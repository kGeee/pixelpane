import Foundation

enum AgentRearchitectureRegressionFixtureHarness {
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
        try await testFC001SearchEvidenceCarriesExactPath()
        try await testFC002SupportedAnswerDoesNotDependOnModelVerifier()
        try await testFC003TimeoutAndContextPressureHaveRecoveryState()
        try await testFC004ProtocolJSONIsNormalizedOrRejected()
        try await testFC005ProviderFailureDoesNotLeaveThinkingState()
        try await testFC006MalformedWriteProtocolDoesNotSurfaceAsAnswer()
        try await testFC007DeferralClaimsNeedEvidence()
        try await testFC008StaleEvidenceDoesNotLeakIntoCurrentRun()
        try await testFC009ApprovalWaitAndWriteExecutionAreDurable()
        try await testFC010LocalhostEvidenceIsPortSpecific()
        try await testFC011GeneratedScriptArtifactsAreRejectedBeforeApproval()
        try await testFC012TraceExportExplainsFailureAndRedactsSecrets()
        try await testProviderTierConformance()
        try await testLaunchRecoveryMatrix()
    }

    private static func testFC001SearchEvidenceCarriesExactPath() async throws {
        let harness = try await makeHarness(title: "FC001")
        let targetPath = "/Users/nayak/Documents/random-tests/counter.py"
        let evidence = try await harness.recorder.recordFileSearch(
            runID: harness.run.runID,
            query: "counter.py",
            matches: [
                AgentFileSearchMatch(path: targetPath, preview: AgentRunText("print(count)"), score: 100)
            ]
        )

        let records = await harness.store.evidenceArtifactSummary(runID: harness.run.runID).evidence
        let support = harness.controller.verify(.fileSearchFound(targetPath), evidence: records)
        let packet = harness.controller.contextPackets(from: records, query: "counter.py").first

        try expect(support.status == .supported, "FC-001 search result should support exact path claim")
        try expect(support.evidenceIDs == [evidence.evidenceID], "FC-001 support should cite search evidence")
        try expect(packet?.keyFields["topPath"] == .string(targetPath), "FC-001 context packet should expose the answer-critical path")
        try expect(packet?.artifactID != nil, "FC-001 search details should be artifact-backed")
    }

    private static func testFC002SupportedAnswerDoesNotDependOnModelVerifier() async throws {
        let harness = try await makeHarness(title: "FC002")
        _ = try await harness.recorder.recordLocalServer(
            runID: harness.run.runID,
            server: AgentLocalServerEvidence(
                url: "http://localhost:59620",
                port: 59620,
                isListening: true,
                httpStatusCode: 200,
                processID: "site",
                workingDirectory: "/Users/nayak/Documents/site"
            )
        )

        let finalSupport = AgentFinalAnswerSupportRecorder(
            store: harness.store,
            evidenceRecorder: harness.recorder,
            controller: harness.controller
        )
        let support = try await finalSupport.recordSupport(
            runID: harness.run.runID,
            answer: AgentRunText("The site is responding on http://localhost:59620."),
            claims: [.portListening(59620), .urlResponds("http://localhost:59620")]
        )

        try expect(support.canAnswer, "FC-002 supported local answer should not require a model verifier")
        try expect(support.supportEvidenceID != nil, "FC-002 final answer support should be durable evidence")
    }

    private static func testFC003TimeoutAndContextPressureHaveRecoveryState() async throws {
        let root = try makeTemporaryRoot(prefix: "fc003")
        let store = try AgentRunStore(rootDirectory: root)
        let runner = AgentRunner(store: store)
        let session = try await store.createSession(title: "FC003")
        let run = try await store.createRun(sessionID: session.id, status: .queued)

        do {
            _ = try await runner.run(
                runID: run.runID,
                steps: [
                    AgentRunnerStep(kind: .modelRequest, timeout: 0.02) {
                        try await Task.sleep(nanoseconds: 500_000_000)
                        return .none
                    }
                ]
            )
            throw HarnessError(description: "FC-003 timeout should throw")
        } catch AgentRunnerError.stepTimedOut {
            let trace = try await store.traceProjection(runID: run.runID)
            try expect(trace.run.status == .interrupted, "FC-003 timeout should interrupt run")
            try expect(trace.events.contains { $0.kind == .failure }, "FC-003 timeout should record recovery failure event")
        }

        let adapter = fixtureAdapter(
            id: "fc003.small-context",
            limits: AgentKernelModelLimits(maxPromptCharacters: 4),
            responses: [.finalAnswer("unused")]
        )
        let gateway = AgentModelGateway(adapters: [adapter])
        let result = await gateway.response(
            adapterID: adapter.descriptor.id,
            request: AgentModelGatewayRequest(
                mode: .plainChat,
                messages: [AgentKernelMessage(role: .user, content: "too long")]
            )
        )
        try expect(result.failure?.kind == .contextTooLarge, "FC-003 oversized local prompts should fail before provider call")
    }

    private static func testFC004ProtocolJSONIsNormalizedOrRejected() async throws {
        let adapter = fixtureAdapter(
            id: "fc004.protocol-json",
            toolCallingMode: .none,
            structured: .unsupported,
            responses: [.finalAnswer(#"{"type":"final_answer","text":"Clean answer"}"#)]
        )
        let gateway = AgentModelGateway(adapters: [adapter])
        let result = await gateway.response(
            adapterID: adapter.descriptor.id,
            request: AgentModelGatewayRequest(
                mode: .plainChat,
                messages: [AgentKernelMessage(role: .user, content: "answer")]
            )
        )

        try expect(result.response?.events == [.finalAnswer("Clean answer")], "FC-004 protocol final-answer JSON should normalize before projection")
        try expect(result.response?.events.description.contains(#""type""#) == false, "FC-004 raw protocol JSON should not leak as assistant prose")

        let toolLeak = fixtureAdapter(
            id: "fc004.tool-json",
            toolCallingMode: .none,
            structured: .unsupported,
            responses: [.finalAnswer(#"{"type":"tool_call","name":"read_file","arguments":{"path":"README.md"}}"#)]
        )
        let toolGateway = AgentModelGateway(adapters: [toolLeak])
        let toolResult = await toolGateway.response(
            adapterID: toolLeak.descriptor.id,
            request: AgentModelGatewayRequest(
                mode: .plainChat,
                messages: [AgentKernelMessage(role: .user, content: "read")]
            )
        )
        try expect(toolResult.failure?.kind == .transportError, "FC-004 protocol tool-call JSON in plain chat should fail instead of becoming prose")
    }

    @MainActor
    private static func testFC005ProviderFailureDoesNotLeaveThinkingState() async throws {
        let store = try AgentRunStore(rootDirectory: makeTemporaryRoot(prefix: "fc005"))
        let viewModel = AgentRunViewModel(store: store)
        let adapter = fixtureAdapter(id: "fc005.empty", responses: [.emptyOutput])

        _ = try await viewModel.startRun(
            userMessage: "Do not hang",
            context: AgentRunViewContext(title: "FC005", contextID: "fc005", contextKind: "assistant"),
            adapter: adapter,
            timeout: 1
        )
        try await viewModel.waitForIdle(timeout: 3)
        await viewModel.refresh()

        try expect(viewModel.state.activeStatus == .failed, "FC-005 empty provider output should finish as failed")
        try expect(!viewModel.state.isBusy, "FC-005 failed run should not remain in thinking state")
        try expect(viewModel.state.messages.map(\.role) == [.user], "FC-005 should not project a fake empty assistant answer")
    }

    private static func testFC006MalformedWriteProtocolDoesNotSurfaceAsAnswer() async throws {
        let stageTool = stageWriteTool()
        let repairable = fixtureAdapter(
            id: "fc006.repairable",
            toolCallingMode: .textProtocol,
            structured: .bestEffort,
            responses: [.finalAnswer(#"{"type":"tool_call","name":"stage_write_proposal","arguments":{"path":"/tmp/a.py","content":"print(1)"}}"#)]
        )
        let gateway = AgentModelGateway(adapters: [repairable])
        let repaired = await gateway.response(
            adapterID: repairable.descriptor.id,
            request: AgentModelGatewayRequest(
                mode: .constrainedStructuredText,
                messages: [AgentKernelMessage(role: .user, content: "write")],
                tools: [stageTool]
            )
        )
        guard case .toolCall(let call)? = repaired.response?.events.first else {
            throw HarnessError(description: "FC-006 repairable write call should become a typed tool call")
        }
        try expect(call.arguments["targetPath"] == "/tmp/a.py", "FC-006 path alias should repair to targetPath")
        try expect(call.arguments["operation"] == "create", "FC-006 missing create operation should be repaired when content is present")

        let malformed = fixtureAdapter(
            id: "fc006.malformed",
            toolCallingMode: .textProtocol,
            structured: .bestEffort,
            responses: [.finalAnswer(#"{"type":"tool_call","name":"stage_write_proposal","arguments":{"path":"/tmp/a.py"}}"#)]
        )
        let malformedGateway = AgentModelGateway(adapters: [malformed])
        let result = await malformedGateway.response(
            adapterID: malformed.descriptor.id,
            request: AgentModelGatewayRequest(
                mode: .constrainedStructuredText,
                messages: [AgentKernelMessage(role: .user, content: "write")],
                tools: [stageTool]
            )
        )
        try expect(result.failure?.kind == .structuredOutputInvalid, "FC-006 incomplete write protocol should fail as structured output, not user prose")
    }

    private static func testFC007DeferralClaimsNeedEvidence() async throws {
        let harness = try await makeHarness(title: "FC007")
        let finalSupport = AgentFinalAnswerSupportRecorder(
            store: harness.store,
            evidenceRecorder: harness.recorder,
            controller: harness.controller
        )
        let support = try await finalSupport.recordSupport(
            runID: harness.run.runID,
            answer: AgentRunText("I cannot confirm whether the server is running."),
            claims: [AgentEvidenceClaim(type: .unsupported, target: "deferral")]
        )

        try expect(!support.canAnswer, "FC-007 deferral should not be accepted as supported evidence")
        try expect(support.decisions.first?.status == .unsupported, "FC-007 unsupported claim should stay explicit")
    }

    private static func testFC008StaleEvidenceDoesNotLeakIntoCurrentRun() async throws {
        let root = try makeTemporaryRoot(prefix: "fc008")
        let store = try AgentRunStore(rootDirectory: root)
        let recorder = AgentEvidenceRecorder(store: store)
        let controller = AgentEvidenceController()
        let session = try await store.createSession(title: "FC008")
        let oldRun = try await store.createRun(sessionID: session.id, status: .completed)
        let currentRun = try await store.createRun(sessionID: session.id, status: .queued)

        _ = try await recorder.recordFileSearch(
            runID: oldRun.runID,
            query: "counter.py",
            matches: [AgentFileSearchMatch(path: "/old/counter.py", preview: AgentRunText("old"), score: 100)]
        )
        _ = try await recorder.recordFileSearch(
            runID: currentRun.runID,
            query: "counter.py",
            matches: [AgentFileSearchMatch(path: "/current/counter.py", preview: AgentRunText("current"), score: 100)]
        )

        let currentEvidence = await store.evidenceArtifactSummary(runID: currentRun.runID).evidence
        let packets = controller.contextPackets(from: currentEvidence, query: "counter.py")
        let packetText = packets.map { packet in "\(packet.keyFields)" }.joined(separator: "\n")

        try expect(packetText.contains("/current/counter.py"), "FC-008 current evidence should be present")
        try expect(!packetText.contains("/old/counter.py"), "FC-008 old evidence should not leak into current context packets")
    }

    private static func testFC009ApprovalWaitAndWriteExecutionAreDurable() async throws {
        let harness = try await makeHarness(title: "FC009")
        let target = harness.workspace.appendingPathComponent("approved.txt")
        let controller = AgentSideEffectController(store: harness.store)

        let stage = try await controller.stage(
            runID: harness.run.runID,
            draft: .fileWrite(
                AgentFileWriteDraft(
                    operation: .create,
                    targetPath: target.path,
                    content: "approved"
                )
            )
        )
        let waitingRun = try await harness.store.runRecord(runID: harness.run.runID)
        let pendingWaitIDs = await harness.store.pendingWaits(runID: harness.run.runID).map(\.waitID)
        try expect(waitingRun.status == .waitingForApproval, "FC-009 staged write should create durable approval wait")
        try expect(pendingWaitIDs == [stage.wait.waitID], "FC-009 wait should be reloadable from store")

        _ = try await controller.resolveApproval(sideEffectID: stage.sideEffect.sideEffectID, decision: .approved)
        let completed = try await controller.executeApproved(sideEffectID: stage.sideEffect.sideEffectID)
        let content = try String(contentsOf: target, encoding: .utf8)

        try expect(content == "approved", "FC-009 approved side effect should write file")
        try expect(completed.status == .completed, "FC-009 side effect should complete in store")
        do {
            _ = try await controller.executeApproved(sideEffectID: stage.sideEffect.sideEffectID)
            throw HarnessError(description: "FC-009 duplicate side-effect execution should throw")
        } catch AgentSideEffectError.executionAlreadyCompleted {
            // Expected.
        }
    }

    private static func testFC010LocalhostEvidenceIsPortSpecific() async throws {
        let harness = try await makeHarness(title: "FC010")
        _ = try await harness.recorder.recordLocalServer(
            runID: harness.run.runID,
            server: AgentLocalServerEvidence(url: "http://localhost:59620", port: 59620, isListening: true, httpStatusCode: 200)
        )

        let evidence = await harness.store.evidenceArtifactSummary(runID: harness.run.runID).evidence
        let actualPort = harness.controller.verify(.portListening(59620), evidence: evidence)
        let defaultPort = harness.controller.verify(.portListening(80), evidence: evidence)

        try expect(actualPort.status == .supported, "FC-010 observed localhost port should be supported")
        try expect(defaultPort.status == .needsEvidence, "FC-010 localhost evidence must not generalize to port 80")
    }

    private static func testFC011GeneratedScriptArtifactsAreRejectedBeforeApproval() async throws {
        let harness = try await makeHarness(title: "FC011")
        let target = harness.workspace.appendingPathComponent("bad.py")
        let controller = AgentSideEffectController(store: harness.store)

        do {
            _ = try await controller.stage(
                runID: harness.run.runID,
                draft: .fileWrite(
                    AgentFileWriteDraft(
                        operation: .create,
                        targetPath: target.path,
                        content: "nimport os\nndir_path = os.path.dirname(os.path.abspath(file))\nprint(ndir_path)"
                    )
                )
            )
            throw HarnessError(description: "FC-011 generated script artifact should fail validation")
        } catch AgentSideEffectError.invalidDraft(let summary) {
            try expect(summary.contains("newline marker"), "FC-011 invalid draft should explain generated marker artifacts")
        }

        let pendingWaits = await harness.store.pendingWaits(runID: harness.run.runID)
        try expect(pendingWaits.isEmpty, "FC-011 invalid script should not create an approval wait")
    }

    private static func testFC012TraceExportExplainsFailureAndRedactsSecrets() async throws {
        let harness = try await makeHarness(title: "FC012")
        try await harness.store.appendEvent(
            runID: harness.run.runID,
            kind: .providerDiagnostic,
            payload: .diagnostic(AgentRunText("api_key=abc123 Bearer SECRET456"))
        )
        try await harness.store.appendEvent(
            runID: harness.run.runID,
            kind: .failure,
            payload: .metadata([
                "reason": .string("provider_error"),
                "authToken": .string("topsecret")
            ])
        )
        try await harness.store.updateRunStatus(
            runID: harness.run.runID,
            status: .failed,
            reason: AgentRunText("Provider failed with token=abc123")
        )

        let trace = try await harness.store.traceProjection(runID: harness.run.runID)
        let export = AgentRunTraceExporter().export(trace: trace, visibleMessages: [])

        try expect(export.contains("Private reasoning: omitted"), "FC-012 trace should explicitly omit private reasoning")
        try expect(export.contains("Status: failed"), "FC-012 trace should include terminal status")
        try expect(export.contains("failure"), "FC-012 trace should include failure event")
        try expect(!export.contains("abc123"), "FC-012 trace should redact free-text secrets")
        try expect(!export.contains("SECRET456"), "FC-012 trace should redact bearer secrets")
        try expect(!export.contains("topsecret"), "FC-012 trace should redact secret metadata")
    }

    private static func testProviderTierConformance() async throws {
        let tierA = fixtureAdapter(id: "tier-a", responses: [.toolCall(name: "read_file", arguments: ["path": "README.md"], reason: nil)])
        let tierB = fixtureAdapter(id: "tier-b", toolCallingMode: .textProtocol, structured: .bestEffort, responses: [.finalAnswer("ok")])
        let tierC = fixtureAdapter(id: "tier-c", toolCallingMode: .none, structured: .unsupported, responses: [.finalAnswer("ok")])
        let gateway = AgentModelGateway(adapters: [tierA, tierB, tierC])
        let tierAValue = await gateway.tier(adapterID: tierA.descriptor.id)
        let tierBValue = await gateway.tier(adapterID: tierB.descriptor.id)
        let tierCValue = await gateway.tier(adapterID: tierC.descriptor.id)

        try expect(tierAValue == .tierAFullAgent, "Tier A should support full agent mode")
        try expect(tierBValue == .tierBConstrainedStructuredText, "Tier B should be constrained structured text")
        try expect(tierCValue == .tierCPlainChat, "Tier C should be plain chat")

        let tierBFullAgent = await gateway.response(
            adapterID: tierB.descriptor.id,
            request: AgentModelGatewayRequest(
                mode: .fullAgent,
                messages: [AgentKernelMessage(role: .user, content: "read")],
                tools: [readFileTool()]
            )
        )
        try expect(tierBFullAgent.failure?.kind == .unsupportedToolMode, "Tier B should not enter full-agent tool loop")

        let tierCPlain = await gateway.response(
            adapterID: tierC.descriptor.id,
            request: AgentModelGatewayRequest(
                mode: .plainChat,
                messages: [AgentKernelMessage(role: .user, content: "hello")],
                tools: [readFileTool()]
            )
        )
        let tierCLastRequest = await tierC.lastRequest()
        try expect(tierCPlain.response?.events == [.finalAnswer("ok")], "Tier C should synthesize plain answers")
        try expect(tierCLastRequest?.tools.isEmpty == true, "Tier C plain chat should not receive tool schemas")
    }

    private static func testLaunchRecoveryMatrix() async throws {
        let root = try makeTemporaryRoot(prefix: "recovery")
        let store = try AgentRunStore(rootDirectory: root)
        let runner = AgentRunner(store: store)
        let session = try await store.createSession(title: "Recovery Matrix")

        let modelRun = try await store.createRun(sessionID: session.id, status: .running)
        _ = try await store.beginStep(runID: modelRun.runID, kind: .modelRequest)

        let toolRun = try await store.createRun(sessionID: session.id, status: .running)
        _ = try await store.beginStep(runID: toolRun.runID, kind: .toolRequest)

        let sideEffectRun = try await store.createRun(sessionID: session.id, status: .running)
        let sideEffectStep = try await store.beginStep(runID: sideEffectRun.runID, kind: .sideEffect)
        let sideEffect = try await store.recordSideEffect(
            runID: sideEffectRun.runID,
            stepID: sideEffectStep.stepID,
            kind: .processStart,
            status: .running,
            metadata: [
                "processID": .string("site-server"),
                "command": .string("python3 -m http.server")
            ]
        )

        let waitingRun = try await store.createRun(sessionID: session.id, status: .waitingForApproval)
        let wait = try await store.createWait(
            runID: waitingRun.runID,
            kind: .approval,
            prompt: AgentRunText("Start process?"),
            risk: "process-control"
        )

        let recovery = try await runner.recoverOnLaunch()
        let interrupted = Set(recovery.interruptedRuns.map(\.runID))
        let interruptedStepKinds = Set(recovery.interruptedSteps.map(\.kind))

        try expect(interrupted == Set([modelRun.runID, toolRun.runID, sideEffectRun.runID]), "Recovery should interrupt unsafe active model/tool/side-effect steps")
        try expect(interruptedStepKinds == Set([.modelRequest, .toolRequest, .sideEffect]), "Recovery should preserve interrupted active step kinds")
        try expect(recovery.pendingWaits.map(\.waitID) == [wait.waitID], "Recovery should restore pending approval waits")
        let recoveredSideEffects = await store.sideEffects(runID: sideEffectRun.runID)
        try expect(recoveredSideEffects.map(\.sideEffectID).contains(sideEffect.sideEffectID), "Recovery should preserve managed process ownership records")
    }

    private static func makeHarness(title: String) async throws -> Harness {
        let root = try makeTemporaryRoot(prefix: title.lowercased())
        let workspace = try makeTemporaryRoot(prefix: "\(title.lowercased())-workspace")
        let store = try AgentRunStore(rootDirectory: root)
        let session = try await store.createSession(title: title)
        let run = try await store.createRun(sessionID: session.id, status: .queued)
        return Harness(
            store: store,
            recorder: AgentEvidenceRecorder(store: store),
            controller: AgentEvidenceController(),
            run: run,
            workspace: workspace
        )
    }

    private static func fixtureAdapter(
        id: String,
        toolCallingMode: AgentKernelToolCallingMode = .native,
        structured: AgentKernelStructuredOutputReliability = .strict,
        limits: AgentKernelModelLimits = AgentKernelModelLimits(contextWindowTokens: 8_192),
        responses: [FixtureAgentKernelAdapter.ScriptedResponse]
    ) -> FixtureAgentKernelAdapter {
        let descriptor = AgentKernelModelDescriptor(
            id: id,
            providerKind: .fixture,
            route: .local,
            displayName: id
        )
        let capabilities = AgentKernelModelAdapterCapabilities(
            descriptor: descriptor,
            toolCallingMode: toolCallingMode,
            structuredOutputReliability: structured,
            streamingMode: .events,
            limits: limits
        )
        return FixtureAgentKernelAdapter(
            descriptor: descriptor,
            capabilities: capabilities,
            responses: responses
        )
    }

    private static func readFileTool() -> AgentKernelToolSchema {
        AgentKernelToolSchema(
            name: "read_file",
            summary: "Read a granted local file.",
            requiredArguments: ["path"]
        )
    }

    private static func stageWriteTool() -> AgentKernelToolSchema {
        AgentKernelToolSchema(
            name: "stage_write_proposal",
            summary: "Stage a file write proposal.",
            arguments: [
                AgentKernelToolArgumentSchema(name: "operation", type: .string, summary: "create, replace, or append"),
                AgentKernelToolArgumentSchema(name: "targetPath", type: .string, summary: "Absolute target path"),
                AgentKernelToolArgumentSchema(name: "content", type: .string, summary: "Full file content")
            ]
        )
    }

    private static func makeTemporaryRoot(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixel-pane-agent-regression-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    struct Harness {
        let store: AgentRunStore
        let recorder: AgentEvidenceRecorder
        let controller: AgentEvidenceController
        let run: AgentRunRecord
        let workspace: URL
    }
}

@main
struct AgentRearchitectureRegressionFixtureMain {
    static func main() async {
        do {
            try await AgentRearchitectureRegressionFixtureHarness.run()
            print("Agent rearchitecture regression fixture tests passed")
        } catch {
            fputs("Agent rearchitecture regression fixture tests failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
