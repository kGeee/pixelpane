import Foundation

enum AgentRunViewModelFixtureHarness {
    struct HarnessError: Error, CustomStringConvertible {
        let description: String
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw HarnessError(description: message)
        }
    }

    @MainActor
    static func run() async throws {
        try await testSendProjectsDurableMessages()
        try await testDetachedRunAutoRefreshesProjection()
        try await testPendingApprovalProjectionAndDecisions()
        try await testApprovalContinuationProjectsImmediately()
        try await testApprovalContinuationRequiresSavedAdapter()
        try await testCancelUpdatesRunStatus()
        try await testCancelDoesNotOverwriteCompletedRun()
        try await testToolCapableRunRejectsConcurrentStart()
        try await testTerminalFailureProjectionDoesNotReuseProgress()
        try await testLaunchRecoveryProjectsInterruptedRun()
        try await testTerminalHandledRecoveryProjectionClears()
        try await testLoadSessionRestoresProjection()
        try await testRefreshDoesNotAutoLoadPreviousSession()
    }

    @MainActor
    private static func testSendProjectsDurableMessages() async throws {
        let (store, viewModel) = try await makeHarness()
        let context = AgentRunViewContext(title: "Assistant", contextID: "ctx-send", contextKind: "assistant")
        let adapter = FixtureAgentModelAdapter(events: [.finalAnswer("Projected answer")])

        _ = try await viewModel.startRun(
            userMessage: "Hello",
            context: context,
            adapter: adapter,
            maxOutputTokens: 128
        )
        try await viewModel.waitForIdle(timeout: 3)

        try expect(viewModel.state.activeStatus == .completed, "send should complete the durable run")
        try expect(viewModel.state.messages.map(\.text.text) == ["Hello", "Projected answer"], "visible messages should project from durable events")
        let sessionCount = await store.allSessions().count
        try expect(sessionCount == 1, "send should create one durable session")
    }

    @MainActor
    private static func testDetachedRunAutoRefreshesProjection() async throws {
        let (_, viewModel) = try await makeHarness()
        let context = AgentRunViewContext(title: "Assistant", contextID: "ctx-auto-refresh", contextKind: "assistant")
        let adapter = FixtureAgentModelAdapter(
            events: [.finalAnswer("Auto-projected answer")],
            delayNanoseconds: 80_000_000
        )

        _ = try await viewModel.startRun(
            userMessage: "Auto refresh",
            context: context,
            adapter: adapter,
            maxOutputTokens: 128
        )
        try expect(viewModel.state.isBusy, "detached run should initially project busy state")

        try await waitUntil(timeout: 3, "detached run should project completion without manual refresh") {
            viewModel.state.activeStatus == .completed
        }
        try expect(
            viewModel.state.messages.map(\.text.text) == ["Auto refresh", "Auto-projected answer"],
            "automatic projection refresh should expose the assistant answer"
        )
    }

    @MainActor
    private static func testPendingApprovalProjectionAndDecisions() async throws {
        let (store, viewModel) = try await makeHarness()
        try await viewModel.loadOrCreateSession(
            context: AgentRunViewContext(title: "Approvals", contextID: "ctx-approval", contextKind: "assistant")
        )
        guard let sessionID = viewModel.state.sessionID else {
            throw HarnessError(description: "session should be loaded")
        }

        let run = try await store.createRun(sessionID: sessionID, status: .queued)
        let wait = try await store.createWait(
            runID: run.runID,
            kind: .approval,
            prompt: AgentRunText("Run command in /tmp: echo ok"),
            risk: "command"
        )
        _ = try await store.recordSideEffect(
            runID: run.runID,
            kind: .command,
            status: .proposed,
            approvalWaitID: wait.waitID,
            metadata: [
                "command": .string("echo ok"),
                "workingDirectory": .string("/tmp")
            ]
        )

        try await viewModel.loadSession(sessionID: sessionID)
        try expect(viewModel.state.activeStatus == .waitingForApproval, "approval wait should project status")
        try expect(viewModel.state.pendingApprovals.count == 1, "approval wait should project one card")
        try expect(viewModel.state.pendingApprovals.first?.kind == .command, "command side effect should project typed approval")
        try expect(viewModel.state.pendingApprovals.first?.primaryText == "echo ok", "approval card should expose command")

        try await viewModel.approveWait(wait.waitID)
        try expect(viewModel.state.pendingApprovals.isEmpty, "approved wait should leave no pending approvals")
        try expect(viewModel.state.activeStatus == .queued, "approved wait should queue the run")

        let wait2 = try await store.createWait(
            runID: run.runID,
            kind: .approval,
            prompt: AgentRunText("Create /tmp/denied.md"),
            risk: "file-write"
        )
        _ = try await store.recordSideEffect(
            runID: run.runID,
            kind: .fileWrite,
            status: .proposed,
            approvalWaitID: wait2.waitID,
            metadata: [
                "operation": .string("create"),
                "targetPath": .string("/tmp/denied.md")
            ]
        )
        await viewModel.refresh()
        try await viewModel.denyWait(wait2.waitID)
        try expect(viewModel.state.activeStatus == .blocked, "denied wait should block the run")
    }

    @MainActor
    private static func testApprovalContinuationProjectsImmediately() async throws {
        let (store, viewModel) = try await makeHarness()
        let context = AgentRunViewContext(title: "Immediate Approval", contextID: "ctx-immediate-approval", contextKind: "assistant")
        try await viewModel.loadOrCreateSession(context: context)
        guard let sessionID = viewModel.state.sessionID else {
            throw HarnessError(description: "session should be loaded")
        }

        let run = try await store.createRun(sessionID: sessionID, status: .queued)
        let sideEffects = AgentSideEffectController(store: store)
        let stage = try await sideEffects.stage(
            runID: run.runID,
            draft: .command(
                AgentCommandDraft(
                    command: "sleep 1; echo ok",
                    workingDirectory: FileManager.default.temporaryDirectory.path,
                    timeoutSeconds: 5
                )
            )
        )

        try await viewModel.loadSession(sessionID: sessionID)
        try expect(viewModel.state.pendingApprovals.count == 1, "command approval should initially project")

        let adapter = FixtureAgentModelAdapter(events: [.finalAnswer("Done.")])
        let approvalTask = Task {
            try await viewModel.approveWait(
                stage.wait.waitID,
                adapter: adapter,
                context: context,
                mode: .plainChat,
                tools: [],
                toolContext: .plainChat,
                timeout: 2
            )
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        try expect(viewModel.state.pendingApprovals.isEmpty, "approved command should immediately leave no pending approval card")
        try expect(viewModel.state.activeStatus == .running, "approved command should immediately project a running state")
        try expect(viewModel.state.latestProgress?.text == "Approved. Running approved action.", "approved command should immediately project progress")

        try await approvalTask.value
        try expect(viewModel.state.activeStatus == .completed, "approved command continuation should still complete")
    }

    @MainActor
    private static func testApprovalContinuationRequiresSavedAdapter() async throws {
        let (store, viewModel) = try await makeHarness()
        let context = AgentRunViewContext(title: "Saved Config", contextID: "ctx-saved-config", contextKind: "assistant")
        try await viewModel.loadOrCreateSession(context: context)
        guard let sessionID = viewModel.state.sessionID else {
            throw HarnessError(description: "session should be loaded")
        }
        let run = try await store.createRun(sessionID: sessionID, status: .waitingForApproval)
        let firstAdapter = FixtureAgentModelAdapter(id: "fixture.first", events: [.finalAnswer("Done.")])
        try await store.appendEvent(
            runID: run.runID,
            kind: .custom,
            payload: .runConfiguration(
                AgentRunModelConfigurationRecord(
                    adapterDescriptor: firstAdapter.descriptor,
                    request: AgentModelGatewayRequest(
                        mode: .plainChat,
                        messages: [AgentKernelMessageV2(role: .user, content: "approve saved config")],
                        metadata: [
                            "sessionID": .string(sessionID.uuidString),
                            "runID": .string(run.runID.uuidString)
                        ]
                    ),
                    toolContext: .plainChat
                )
            )
        )
        let wait = try await store.createWait(
            runID: run.runID,
            kind: .approval,
            prompt: AgentRunText("Approve saved config"),
            risk: "test"
        )
        _ = try await store.recordSideEffect(
            runID: run.runID,
            kind: .fileWrite,
            status: .proposed,
            approvalWaitID: wait.waitID,
            metadata: ["targetPath": .string("/tmp/saved-config.txt")]
        )
        try await viewModel.loadSession(sessionID: sessionID)
        try expect(viewModel.state.pendingApprovals.count == 1, "saved config approval should project")

        let changedAdapter = FixtureAgentModelAdapter(id: "fixture.changed", events: [.finalAnswer("Done.")])
        do {
            try await viewModel.approveWait(wait.waitID, adapter: changedAdapter)
            throw HarnessError(description: "approval continuation should reject an adapter changed after staging")
        } catch AgentRunViewModelError.adapterChanged(_, _) {
            try expect(true, "adapter change should be rejected")
        }
    }

    @MainActor
    private static func testCancelUpdatesRunStatus() async throws {
        let (_, viewModel) = try await makeHarness()
        let adapter = FixtureAgentModelAdapter(events: [.finalAnswer("late")], delayNanoseconds: 500_000_000)
        _ = try await viewModel.startRun(
            userMessage: "Cancel this",
            context: AgentRunViewContext(title: "Cancel", contextID: "ctx-cancel", contextKind: "assistant"),
            adapter: adapter
        )
        try expect(viewModel.state.isBusy, "run should be busy before cancel")

        await viewModel.cancelRun()
        try expect(viewModel.state.activeStatus == .canceled, "cancel should checkpoint canceled status")
    }

    @MainActor
    private static func testCancelDoesNotOverwriteCompletedRun() async throws {
        let (_, viewModel) = try await makeHarness()
        let adapter = FixtureAgentModelAdapter(events: [.finalAnswer("Already done")])
        _ = try await viewModel.startRun(
            userMessage: "Finish before stale cancel",
            context: AgentRunViewContext(title: "Completed Cancel", contextID: "ctx-completed-cancel", contextKind: "assistant"),
            adapter: adapter
        )
        try await waitUntil(timeout: 3, "run should complete before stale cancel") {
            viewModel.state.activeStatus == .completed
        }

        await viewModel.cancelRun()
        try expect(viewModel.state.activeStatus == .completed, "cancel should not overwrite an already completed run")
        try expect(
            viewModel.state.messages.map(\.text.text) == ["Finish before stale cancel", "Already done"],
            "completed answer should remain visible after stale cancel"
        )
    }

    @MainActor
    private static func testToolCapableRunRejectsConcurrentStart() async throws {
        let (_, viewModel) = try await makeHarness()
        let context = AgentRunViewContext(
            title: "Tool Duplicate",
            contextID: "ctx-tool-duplicate",
            contextKind: "assistant"
        )
        let adapter = FixtureAgentModelAdapter(
            events: [.finalAnswer("late")],
            delayNanoseconds: 2_000_000_000,
            toolCallingMode: .native,
            structuredOutputReliability: .strict
        )
        let tools = [
            AgentKernelToolSchemaV2(
                name: "get_current_time",
                summary: "Return the current local time."
            )
        ]
        let toolContext = AgentToolRunContext(runMode: .readOnly)

        let firstRunID = try await viewModel.startRun(
            userMessage: "Use a tool-capable route.",
            context: context,
            adapter: adapter,
            mode: .fullAgent,
            tools: tools,
            toolContext: toolContext,
            timeout: 4
        )
        try expect(viewModel.state.isBusy, "tool-capable run should be busy before duplicate start")

        do {
            _ = try await viewModel.startRun(
                userMessage: "Start another tool-capable route.",
                context: context,
                adapter: adapter,
                mode: .fullAgent,
                tools: tools,
                toolContext: toolContext,
                timeout: 4
            )
            throw HarnessError(description: "runtime should reject a concurrent tool-capable run")
        } catch AgentRunViewModelError.activeRunInProgress(let runID) {
            try expect(runID == firstRunID, "duplicate rejection should identify the active run")
        }

        await viewModel.cancelRun()
        try expect(viewModel.state.activeStatus == .canceled, "duplicate-run cleanup should cancel the active run")
    }

    @MainActor
    private static func testTerminalFailureProjectionDoesNotReuseProgress() async throws {
        let (_, viewModel) = try await makeHarness()
        let adapter = FixtureAgentModelAdapter(events: [.malformedOutput("```json\n{\"type\":\"final_answer\",\"text\":\"Bad wrapper\"}\n```<|im_end|>")])
        _ = try await viewModel.startRun(
            userMessage: "Do not spin forever",
            context: AgentRunViewContext(title: "Failure", contextID: "ctx-failure", contextKind: "assistant"),
            adapter: adapter
        )
        try await viewModel.waitForIdle(timeout: 3)

        try expect(viewModel.state.activeStatus == .failed, "malformed provider output should fail the run")
        try expect(!viewModel.state.isBusy, "failed run should not remain busy")
        try expect(viewModel.state.messages.map(\.role) == [.user], "failed run should not synthesize a fake assistant answer")
        try expect(viewModel.state.statusSummary != "Preparing model route.", "terminal status should not reuse stale progress")
        try expect(viewModel.state.statusSummary.contains("could not use"), "terminal status should project a usable failure reason")
    }

    @MainActor
    private static func testLaunchRecoveryProjectsInterruptedRun() async throws {
        let (store, viewModel) = try await makeHarness()
        let session = try await store.createSession(title: "Recovery", contextID: "ctx-recovery", contextKind: "assistant")
        let run = try await store.createRun(sessionID: session.id, status: .running)
        _ = try await store.beginStep(runID: run.runID, kind: .modelRequest)

        let recovery = try await viewModel.recoverOnLaunch()
        try expect(recovery.interruptedRuns.map(\.runID) == [run.runID], "recovery should interrupt unsafe active run")
        try expect(viewModel.state.activeStatus == .interrupted, "interrupted run should project into UI state")
        try expect(viewModel.state.recovery?.interruptedRunIDs == [run.runID], "recovery projection should include interrupted run")
    }

    @MainActor
    private static func testTerminalHandledRecoveryProjectionClears() async throws {
        let (store, viewModel) = try await makeHarness()
        let session = try await store.createSession(title: "Recovery Clear", contextID: "ctx-recovery-clear", contextKind: "assistant")
        let run = try await store.createRun(sessionID: session.id, status: .running)
        _ = try await store.beginStep(runID: run.runID, kind: .modelRequest)

        _ = try await viewModel.recoverOnLaunch()
        try expect(viewModel.state.recovery?.interruptedRunIDs == [run.runID], "interrupted recovery should initially project")

        await viewModel.cancelRun()
        try expect(viewModel.state.activeStatus == .canceled, "terminal handling should cancel the recovered run")
        try expect(viewModel.state.recovery == nil, "terminally handled recovery should clear stale recovery projection")
    }

    @MainActor
    private static func testLoadSessionRestoresProjection() async throws {
        let (store, viewModel) = try await makeHarness()
        let session = try await store.createSession(title: "Reload", contextID: "ctx-reload", contextKind: "assistant")
        let run = try await store.createRun(sessionID: session.id, status: .queued)
        try await store.appendEvent(runID: run.runID, kind: .userMessage, payload: .text(AgentRunText("Reload question")))
        try await store.appendEvent(runID: run.runID, kind: .assistantMessage, payload: .text(AgentRunText("Reload answer")))
        try await store.updateRunStatus(runID: run.runID, status: .completed)

        try await viewModel.loadOrCreateSession(
            context: AgentRunViewContext(title: "Reload", contextID: "ctx-reload", contextKind: "assistant")
        )
        try expect(viewModel.state.sessionID == session.id, "context load should find existing session")
        try expect(viewModel.state.messages.map(\.text.text) == ["Reload question", "Reload answer"], "reload should project existing messages")
    }

    @MainActor
    private static func testRefreshDoesNotAutoLoadPreviousSession() async throws {
        let (store, viewModel) = try await makeHarness()
        let oldSession = try await store.createSession(title: "Old", contextID: "ctx-old", contextKind: "assistant")
        let oldRun = try await store.createRun(sessionID: oldSession.id, status: .queued)
        try await store.appendEvent(runID: oldRun.runID, kind: .userMessage, payload: .text(AgentRunText("Old question")))
        try await store.appendEvent(runID: oldRun.runID, kind: .assistantMessage, payload: .text(AgentRunText("Old answer")))
        try await store.updateRunStatus(runID: oldRun.runID, status: .completed)

        await viewModel.refresh()

        try expect(viewModel.state.sessionID == nil, "blank view model should not auto-load the latest stored session")
        try expect(viewModel.state.messages.isEmpty, "blank view model should not project previous session messages")
        try expect(viewModel.state.recentSessions.isEmpty, "blank view model should not expose universal recent sessions")
    }

    @MainActor
    private static func makeHarness() async throws -> (AgentRunStore, AgentRunViewModel) {
        let store = try AgentRunStore(rootDirectory: makeTemporaryRoot())
        return (store, AgentRunViewModel(store: store))
    }

    private static func makeTemporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixel-pane-agent-run-view-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    private static func waitUntil(
        timeout: TimeInterval,
        _ message: String,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw HarnessError(description: message)
    }

}

struct FixtureAgentModelAdapter: AgentKernelModelAdapterV2 {
    let descriptor: AgentKernelModelDescriptorV2
    let capabilities: AgentKernelModelAdapterCapabilitiesV2
    let events: [AgentKernelModelAdapterEventV2]
    let delayNanoseconds: UInt64

    init(
        id: String = "fixture.chat",
        events: [AgentKernelModelAdapterEventV2],
        delayNanoseconds: UInt64 = 0,
        toolCallingMode: AgentKernelToolCallingModeV2 = .none,
        structuredOutputReliability: AgentKernelStructuredOutputReliabilityV2 = .unsupported
    ) {
        descriptor = AgentKernelModelDescriptorV2(
            id: id,
            providerKind: .fixture,
            route: .local,
            displayName: "Fixture"
        )
        capabilities = AgentKernelModelAdapterCapabilitiesV2(
            descriptor: descriptor,
            toolCallingMode: toolCallingMode,
            structuredOutputReliability: structuredOutputReliability,
            streamingMode: .unsupported
        )
        self.events = events
        self.delayNanoseconds = delayNanoseconds
    }

    func response(for request: AgentKernelModelAdapterRequestV2) async -> AgentKernelModelAdapterResponseV2 {
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return AgentKernelModelAdapterResponseV2(
            requestID: request.id,
            descriptor: descriptor,
            events: events
        )
    }
}

@main
struct AgentRunViewModelFixtureMain {
    static func main() async {
        do {
            try await AgentRunViewModelFixtureHarness.run()
            print("Agent run view model fixture tests passed")
        } catch {
            fputs("Agent run view model fixture tests failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
