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
        try await testPendingApprovalProjectionAndDecisions()
        try await testCancelUpdatesRunStatus()
        try await testLaunchRecoveryProjectsInterruptedRun()
        try await testLoadSessionRestoresProjection()
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

}

struct FixtureAgentModelAdapter: AgentKernelModelAdapterV2 {
    let descriptor: AgentKernelModelDescriptorV2
    let capabilities: AgentKernelModelAdapterCapabilitiesV2
    let events: [AgentKernelModelAdapterEventV2]
    let delayNanoseconds: UInt64

    init(
        id: String = "fixture.chat",
        events: [AgentKernelModelAdapterEventV2],
        delayNanoseconds: UInt64 = 0
    ) {
        descriptor = AgentKernelModelDescriptorV2(
            id: id,
            providerKind: .fixture,
            route: .local,
            displayName: "Fixture"
        )
        capabilities = AgentKernelModelAdapterCapabilitiesV2(
            descriptor: descriptor,
            toolCallingMode: .none,
            structuredOutputReliability: .unsupported,
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
