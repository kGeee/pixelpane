import Foundation

enum AgentToolCallingFixtureHarness {
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
        try await testToolLoopListsGrantedFolderAndContinues()
        try await testSearchAndReadToolsRecordEvidence()
        try await testWriteProposalApprovalExecutesAndContinues()
        try await testSpecificGrantBeatsBroadGrantForRandomTests()
        try await testMissingWriteParentIsRejectedBeforeApproval()
        try await testApprovedWriteFailureFailsRun()
        try await testDeniedWriteDoesNotExecute()
    }

    @MainActor
    private static func testToolLoopListsGrantedFolderAndContinues() async throws {
        let harness = try await makeHarness(prefix: "tool-list")
        try "alpha".write(to: harness.workspace.appendingPathComponent("alpha.txt"), atomically: true, encoding: .utf8)
        try "beta".write(to: harness.workspace.appendingPathComponent("beta.txt"), atomically: true, encoding: .utf8)
        let adapter = FixtureAgentKernelAdapterV2(
            responses: [
                .toolCall(name: "list_folder", arguments: ["path": harness.workspace.path], reason: "Need folder contents."),
                .finalAnswer("The folder contains alpha.txt and beta.txt.")
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "what is inside the folder?",
            context: AgentRunViewContext(title: "Tool List", contextID: "tool-list", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        try expect(harness.viewModel.state.activeStatus == .completed, "folder listing run should complete")
        try expect(harness.viewModel.state.messages.map(\.text.text).contains("The folder contains alpha.txt and beta.txt."), "final answer should project")
        let trace = try await harness.store.traceProjection(runID: runID)
        try expect(trace.steps.contains(where: { $0.kind == .toolRequest }), "trace should include tool request step")
        try expect(trace.steps.contains(where: { $0.kind == .toolResult }), "trace should include tool result step")
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.folderList.rawValue }), "folder listing should record evidence")
        let lastRequest = await adapter.lastRequest()
        try expect(lastRequest?.messages.contains(where: { $0.role == .observation && $0.content.contains("alpha.txt") }) == true, "second model request should include tool observation")
    }

    @MainActor
    private static func testSearchAndReadToolsRecordEvidence() async throws {
        let harness = try await makeHarness(prefix: "tool-search")
        let profile = harness.workspace.appendingPathComponent("index.html")
        try """
        <html>
        <body>
        <h1>Snehith Nayak</h1>
        <p>Experience: AI engineering, Swift apps, and agent tooling.</p>
        </body>
        </html>
        """.write(to: profile, atomically: true, encoding: .utf8)
        let adapter = FixtureAgentKernelAdapterV2(
            responses: [
                .toolCall(name: "search_files", arguments: ["query": "experience"], reason: nil),
                .toolCall(name: "read_file", arguments: ["path": "index.html"], reason: nil),
                .finalAnswer("Your website says your experience includes AI engineering, Swift apps, and agent tooling.")
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "what is my experience according to my personal website?",
            context: AgentRunViewContext(title: "Tool Search", contextID: "tool-search", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        try expect(harness.viewModel.state.activeStatus == .completed, "search/read run should complete")
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.fileSearch.rawValue }), "search should record evidence")
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.fileRead.rawValue }), "read should record evidence")
        try expect(harness.viewModel.state.messages.last?.text.text.contains("AI engineering") == true, "final answer should use file evidence")
    }

    @MainActor
    private static func testWriteProposalApprovalExecutesAndContinues() async throws {
        let harness = try await makeHarness(prefix: "tool-write")
        let target = harness.workspace.appendingPathComponent("story.txt")
        let adapter = FixtureAgentKernelAdapterV2(
            responses: [
                .toolCall(
                    name: "stage_write_proposal",
                    arguments: [
                        "operation": "create",
                        "targetPath": target.path,
                        "content": "A short story."
                    ],
                    reason: "Write requested file."
                ),
                .finalAnswer("Done. I created story.txt in the granted folder.")
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .proposalOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "write a short story in txt format within the folder.",
            context: AgentRunViewContext(title: "Tool Write", contextID: "tool-write", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let approval = try expectOne(harness.viewModel.state.pendingApprovals, "write proposal should create one approval")
        try expect(harness.viewModel.state.activeStatus == .waitingForApproval, "write run should wait for approval")

        try await harness.viewModel.approveWait(
            approval.waitID,
            adapter: adapter,
            context: AgentRunViewContext(title: "Tool Write", contextID: "tool-write", contextKind: "assistant"),
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let content = try String(contentsOf: target, encoding: .utf8)
        let trace = try await harness.store.traceProjection(runID: runID)
        try expect(content == "A short story.", "approved write should create file exactly once")
        try expect(harness.viewModel.state.activeStatus == .completed, "approved write should continue to final answer")
        try expect(trace.sideEffects.contains(where: { $0.status == .completed }), "completed side effect should be recorded")
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.sideEffect.rawValue }), "side-effect evidence should be recorded")
    }

    @MainActor
    private static func testSpecificGrantBeatsBroadGrantForRandomTests() async throws {
        let root = try makeTemporaryRoot(prefix: "tool-random-tests")
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        let pixelPane = documents.appendingPathComponent("pixel-pane", isDirectory: true)
        let randomTests = documents.appendingPathComponent("random-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: pixelPane, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: randomTests, withIntermediateDirectories: true)
        let store = try AgentRunStore(rootDirectory: root.appendingPathComponent("store", isDirectory: true))
        let viewModel = AgentRunViewModel(store: store)
        let grants = [
            AgentLocalFileGrant(path: pixelPane.path, isDirectory: true, access: .readWrite),
            AgentLocalFileGrant(path: randomTests.path, isDirectory: true, access: .readWrite)
        ]
        let target = randomTests.appendingPathComponent("short_story.txt")
        let shadowTarget = pixelPane.appendingPathComponent("random-tests/short_story.txt")
        let adapter = FixtureAgentKernelAdapterV2(
            responses: [
                .toolCall(
                    name: "stage_write_proposal",
                    arguments: [
                        "operation": "create",
                        "targetPath": "random-tests/short_story.txt",
                        "content": "The correct folder wins."
                    ],
                    reason: nil
                ),
                .finalAnswer("Done. I created short_story.txt in random-tests.")
            ]
        )
        let config = toolConfig(grants: grants, runMode: .proposalOnly, adapter: adapter)

        _ = try await viewModel.startRun(
            userMessage: "write a short story in a txt file in random-tests",
            context: AgentRunViewContext(title: "Random Tests", contextID: "tool-random-tests", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await viewModel.waitForIdle(timeout: 3)
        await viewModel.refresh()

        let approval = try expectOne(viewModel.state.pendingApprovals, "specific random-tests write should create one approval")
        try expect(approval.primaryText == target.path, "approval target should resolve to the explicit random-tests grant")
        try await viewModel.approveWait(
            approval.waitID,
            adapter: adapter,
            context: AgentRunViewContext(title: "Random Tests", contextID: "tool-random-tests", contextKind: "assistant"),
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await viewModel.waitForIdle(timeout: 3)
        await viewModel.refresh()

        let writtenContent = try String(contentsOf: target, encoding: .utf8)
        try expect(writtenContent == "The correct folder wins.", "write should land in the explicit random-tests grant")
        try expect(!FileManager.default.fileExists(atPath: shadowTarget.path), "write should not create a shadow path under the broad grant")
        try expect(viewModel.state.activeStatus == .completed, "specific grant write should complete")
    }

    @MainActor
    private static func testMissingWriteParentIsRejectedBeforeApproval() async throws {
        let harness = try await makeHarness(prefix: "tool-missing-parent")
        let adapter = FixtureAgentKernelAdapterV2(
            responses: [
                .toolCall(
                    name: "stage_write_proposal",
                    arguments: [
                        "operation": "create",
                        "targetPath": "missing/short_story.txt",
                        "content": "This should not reach approval."
                    ],
                    reason: nil
                ),
                .finalAnswer("I could not stage that write because the parent folder does not exist.")
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .proposalOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "write a story under a missing folder",
            context: AgentRunViewContext(title: "Missing Parent", contextID: "tool-missing-parent", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        try expect(harness.viewModel.state.pendingApprovals.isEmpty, "missing parent write should not create an approval")
        try expect(trace.sideEffects.isEmpty, "missing parent write should not stage a side effect")
        try expect(trace.steps.contains(where: { $0.kind == .toolResult }), "missing parent write should still produce a tool result")
    }

    @MainActor
    private static func testApprovedWriteFailureFailsRun() async throws {
        let harness = try await makeHarness(prefix: "tool-approved-fail")
        let missingTarget = harness.workspace.appendingPathComponent("missing-replace.txt")
        let adapter = FixtureAgentKernelAdapterV2(
            responses: [
                .toolCall(
                    name: "stage_write_proposal",
                    arguments: [
                        "operation": "replace",
                        "targetPath": missingTarget.path,
                        "content": "replace should fail"
                    ],
                    reason: nil
                ),
                .finalAnswer("This response should not be used after failed execution.")
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .proposalOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "replace a missing file",
            context: AgentRunViewContext(title: "Approved Failure", contextID: "tool-approved-fail", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let approval = try expectOne(harness.viewModel.state.pendingApprovals, "replace missing file should still require approval before execution")
        try await harness.viewModel.approveWait(
            approval.waitID,
            adapter: adapter,
            context: AgentRunViewContext(title: "Approved Failure", contextID: "tool-approved-fail", contextKind: "assistant"),
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        let visible = await harness.store.visibleMessages(sessionID: nil).filter { $0.runID == runID }
        let export = AgentRunTraceExporter().export(trace: trace, visibleMessages: visible)

        try expect(harness.viewModel.state.activeStatus == .failed, "failed approved write should fail the run")
        try expect(harness.viewModel.state.messages.last?.text.text.contains("Approved side effect failed") == true, "user-visible message should describe failed side effect")
        try expect(trace.sideEffects.contains(where: { $0.status == .failed && $0.errorSummary != nil }), "failed side effect should record error summary")
        try expect(export.contains("error=Side-effect execution failed"), "trace export should include side-effect error summary")
        try expect(!FileManager.default.fileExists(atPath: missingTarget.path), "failed replace should not create the missing target")
    }

    @MainActor
    private static func testDeniedWriteDoesNotExecute() async throws {
        let harness = try await makeHarness(prefix: "tool-deny")
        let target = harness.workspace.appendingPathComponent("denied.txt")
        let adapter = FixtureAgentKernelAdapterV2(
            responses: [
                .toolCall(
                    name: "stage_write_proposal",
                    arguments: [
                        "operation": "create",
                        "targetPath": target.path,
                        "content": "Should not be written."
                    ],
                    reason: nil
                )
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .proposalOnly, adapter: adapter)

        _ = try await harness.viewModel.startRun(
            userMessage: "write a denied file.",
            context: AgentRunViewContext(title: "Tool Deny", contextID: "tool-deny", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let approval = try expectOne(harness.viewModel.state.pendingApprovals, "denied write should create one approval")
        try await harness.viewModel.denyWait(
            approval.waitID,
            adapter: adapter,
            context: AgentRunViewContext(title: "Tool Deny", contextID: "tool-deny", contextKind: "assistant"),
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        await harness.viewModel.refresh()

        try expect(!FileManager.default.fileExists(atPath: target.path), "denied write should not create file")
        try expect(harness.viewModel.state.activeStatus == .blocked, "denied write should block the run")
    }

    private static func expectOne<T>(_ values: [T], _ message: String) throws -> T {
        guard values.count == 1, let value = values.first else {
            throw HarnessError(description: message)
        }
        return value
    }

    private static func toolConfig(
        grant: AgentLocalFileGrant,
        runMode: AgentRunPermissionMode,
        adapter: any AgentKernelModelAdapterV2
    ) -> (mode: AgentModelGatewayMode, tools: [AgentKernelToolSchemaV2], context: AgentToolRunContext) {
        toolConfig(grants: [grant], runMode: runMode, adapter: adapter)
    }

    private static func toolConfig(
        grants: [AgentLocalFileGrant],
        runMode: AgentRunPermissionMode,
        adapter: any AgentKernelModelAdapterV2
    ) -> (mode: AgentModelGatewayMode, tools: [AgentKernelToolSchemaV2], context: AgentToolRunContext) {
        let tier = AgentModelGateway.tier(for: adapter.capabilities)
        let context = AgentToolRunContext(
            runMode: runMode,
            localGrants: grants,
            deniedScopes: [.network, .processControl, .privileged]
        )
        let tools = AgentToolCatalog().visibleModelSchemas(
            providerTier: tier,
            runMode: runMode,
            localGrants: grants,
            deniedScopes: context.deniedScopes
        )
        let mode: AgentModelGatewayMode = tier == .tierAFullAgent ? .fullAgent : .constrainedStructuredText
        return (mode, tools, context)
    }

    @MainActor
    private static func makeHarness(prefix: String) async throws -> Harness {
        let root = try makeTemporaryRoot(prefix: prefix)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let store = try AgentRunStore(rootDirectory: root.appendingPathComponent("store", isDirectory: true))
        return Harness(
            store: store,
            viewModel: AgentRunViewModel(store: store),
            workspace: workspace,
            grant: AgentLocalFileGrant(path: workspace.path, isDirectory: true, access: .readWrite)
        )
    }

    private static func makeTemporaryRoot(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixel-pane-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    struct Harness {
        let store: AgentRunStore
        let viewModel: AgentRunViewModel
        let workspace: URL
        let grant: AgentLocalFileGrant
    }
}

@main
struct AgentToolCallingFixtureMain {
    static func main() async {
        do {
            try await AgentToolCallingFixtureHarness.run()
            print("Agent tool-calling fixture tests passed")
        } catch {
            fputs("Agent tool-calling fixture tests failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
