import Foundation

enum AgentEvidencePacketsFixtureHarness {
    struct HarnessError: Error, CustomStringConvertible {
        let description: String
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw HarnessError(description: message)
        }
    }

    static func run() async throws {
        try await testFileSearchEvidenceSupportsExactPath()
        try await testLocalServerEvidenceSupportsFinalAnswerWithoutModelVerifier()
        try await testCommandAndTerminalSupport()
        try await testSideEffectEvidenceSupportsWriteClaims()
        try await testContextSelectionAvoidsStaleRuns()
        try await testUnsupportedAndMissingEvidence()
    }

    private static func testFileSearchEvidenceSupportsExactPath() async throws {
        let harness = try await makeHarness()
        let targetPath = "/Users/nayak/Documents/random-tests/counter.py"
        let evidence = try await harness.recorder.recordFileSearch(
            runID: harness.run.runID,
            query: "counter.py",
            matches: [
                AgentFileSearchMatch(
                    path: targetPath,
                    preview: AgentRunText("print(count)"),
                    score: 42
                )
            ]
        )

        let records = await harness.store.evidenceArtifactSummary(runID: harness.run.runID).evidence
        let decision = harness.controller.verify(.fileSearchFound(targetPath), evidence: records)
        let packets = harness.controller.contextPackets(from: records, query: "counter.py")

        try expect(decision.status == .supported, "file search claim should be supported by exact path evidence")
        try expect(decision.evidenceIDs == [evidence.evidenceID], "support should point to search evidence")
        try expect(packets.first?.keyFields["topPath"] == .string(targetPath), "context packet should expose answer-critical path")
        try expect(packets.first?.artifactID != nil, "search detail should be artifact-backed")
    }

    private static func testLocalServerEvidenceSupportsFinalAnswerWithoutModelVerifier() async throws {
        let harness = try await makeHarness()
        let server = AgentLocalServerEvidence(
            url: "http://localhost:59620",
            port: 59620,
            isListening: true,
            httpStatusCode: 200,
            processID: "python-site",
            workingDirectory: "/Users/nayak/Documents/snehithnayak.github.io"
        )
        _ = try await harness.recorder.recordLocalServer(runID: harness.run.runID, server: server)

        let records = await harness.store.evidenceArtifactSummary(runID: harness.run.runID).evidence
        let portDecision = harness.controller.verify(.portListening(59620), evidence: records)
        let urlDecision = harness.controller.verify(.urlResponds("http://localhost:59620"), evidence: records)
        let final = try await harness.finalSupport.recordSupport(
            runID: harness.run.runID,
            answer: AgentRunText("Your site is responding on http://localhost:59620."),
            claims: [.portListening(59620), .urlResponds("http://localhost:59620")]
        )

        try expect(portDecision.status == .supported, "port-listening claim should be deterministic")
        try expect(urlDecision.status == .supported, "URL response claim should be deterministic")
        try expect(final.canAnswer, "final answer should be accepted from deterministic evidence")
        try expect(final.supportEvidenceID != nil, "final answer support should be recorded as evidence")
    }

    private static func testCommandAndTerminalSupport() async throws {
        let harness = try await makeHarness()
        let output = AgentCommandExecutionOutput(
            command: "swift test",
            workingDirectory: "/tmp/project",
            exitCode: 0,
            stdout: AgentRunText("ok"),
            stderr: AgentRunText(""),
            durationSeconds: 1.2,
            didTimeOut: false
        )
        _ = try await harness.recorder.recordCommandOutput(runID: harness.run.runID, output: output)
        _ = try await harness.recorder.recordTerminalState(runID: harness.run.runID, status: .completed)

        let records = await harness.store.evidenceArtifactSummary(runID: harness.run.runID).evidence
        let commandDecision = harness.controller.verify(.commandSucceeded("swift test"), evidence: records)
        let terminalDecision = harness.controller.verify(AgentEvidenceClaim(type: .taskCompleted), evidence: records)

        try expect(commandDecision.status == .supported, "command success should be supported by exit code 0")
        try expect(terminalDecision.status == .supported, "task completion should be supported by terminal evidence")
    }

    private static func testSideEffectEvidenceSupportsWriteClaims() async throws {
        let harness = try await makeHarness()
        let target = harness.workspace.appendingPathComponent("result.txt")
        try Data("old".utf8).write(to: target)

        let stage = try await harness.sideEffects.stage(
            runID: harness.run.runID,
            draft: .fileWrite(
                AgentFileWriteDraft(
                    operation: .replace,
                    targetPath: target.path,
                    content: "new"
                )
            )
        )
        _ = try await harness.sideEffects.resolveApproval(sideEffectID: stage.sideEffect.sideEffectID, decision: .approved)
        let completed = try await harness.sideEffects.executeApproved(sideEffectID: stage.sideEffect.sideEffectID)
        let sideEffectEvidence = try await harness.recorder.recordSideEffect(runID: harness.run.runID, sideEffect: completed)

        let records = await harness.store.evidenceArtifactSummary(runID: harness.run.runID).evidence
        let changedDecision = harness.controller.verify(.fileChanged(target.path), evidence: records)
        let effectDecision = harness.controller.verify(
            AgentEvidenceClaim(type: .sideEffectCompleted, target: completed.sideEffectID.uuidString),
            evidence: records
        )

        try expect(sideEffectEvidence.artifactID != nil, "side-effect evidence should keep full record as artifact")
        try expect(changedDecision.status == .supported, "file changed claim should be supported by completed side effect")
        try expect(effectDecision.status == .supported, "side-effect completion should be supported by side-effect evidence")
    }

    private static func testContextSelectionAvoidsStaleRuns() async throws {
        let root = try makeTemporaryRoot(prefix: "store")
        let store = try AgentRunStore(rootDirectory: root)
        let recorder = AgentEvidenceRecorder(store: store)
        let controller = AgentEvidenceController()
        let session = try await store.createSession(title: "Stale Context")
        let oldRun = try await store.createRun(sessionID: session.id, status: .completed)
        let currentRun = try await store.createRun(sessionID: session.id, status: .queued)

        _ = try await recorder.recordFileSearch(
            runID: oldRun.runID,
            query: "counter.py",
            matches: [
                AgentFileSearchMatch(
                    path: "/Users/nayak/Documents/old/counter.py",
                    preview: AgentRunText("old"),
                    score: 99
                )
            ]
        )
        _ = try await recorder.recordFileSearch(
            runID: currentRun.runID,
            query: "counter.py",
            matches: [
                AgentFileSearchMatch(
                    path: "/Users/nayak/Documents/current/counter.py",
                    preview: AgentRunText("current"),
                    score: 10
                )
            ]
        )

        let currentEvidence = await store.evidenceArtifactSummary(runID: currentRun.runID).evidence
        let packets = controller.contextPackets(from: currentEvidence, query: "counter.py")
        let pathFields = packets.compactMap { packet -> String? in
            guard case .string(let paths) = packet.keyFields["paths"] else { return nil }
            return paths
        }.joined(separator: "\n")

        try expect(pathFields.contains("/Users/nayak/Documents/current/counter.py"), "current run evidence should be selected")
        try expect(!pathFields.contains("/Users/nayak/Documents/old/counter.py"), "old run evidence should not leak into current context")
    }

    private static func testUnsupportedAndMissingEvidence() async throws {
        let harness = try await makeHarness()
        let missing = harness.controller.verify(.fileExists("/tmp/missing.txt"), evidence: [])
        let unsupported = harness.controller.verify(
            AgentEvidenceClaim(type: .unsupported, target: "unverifiable prose"),
            evidence: []
        )

        try expect(missing.status == .needsEvidence, "missing deterministic evidence should request evidence")
        try expect(unsupported.status == .unsupported, "unsupported claims should not be treated as supported")
    }

    private static func makeHarness() async throws -> Harness {
        let root = try makeTemporaryRoot(prefix: "store")
        let workspace = try makeTemporaryRoot(prefix: "workspace")
        let store = try AgentRunStore(rootDirectory: root)
        let session = try await store.createSession(title: "Evidence")
        let run = try await store.createRun(sessionID: session.id, status: .queued)
        let recorder = AgentEvidenceRecorder(store: store)
        let controller = AgentEvidenceController()
        let finalSupport = AgentFinalAnswerSupportRecorder(
            store: store,
            evidenceRecorder: recorder,
            controller: controller
        )
        let sideEffects = AgentSideEffectController(store: store)
        return Harness(
            store: store,
            recorder: recorder,
            controller: controller,
            finalSupport: finalSupport,
            sideEffects: sideEffects,
            run: run,
            workspace: workspace
        )
    }

    private static func makeTemporaryRoot(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixel-pane-evidence-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    struct Harness {
        let store: AgentRunStore
        let recorder: AgentEvidenceRecorder
        let controller: AgentEvidenceController
        let finalSupport: AgentFinalAnswerSupportRecorder
        let sideEffects: AgentSideEffectController
        let run: AgentRunRecord
        let workspace: URL
    }
}

@main
struct AgentEvidencePacketsFixtureMain {
    static func main() async {
        do {
            try await AgentEvidencePacketsFixtureHarness.run()
            print("Agent evidence packet fixture tests passed")
        } catch {
            fputs("Agent evidence packet fixture tests failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
