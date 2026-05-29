import Foundation

enum AgentRunStoreFixtureHarness {
    struct HarnessError: Error, CustomStringConvertible {
        let description: String
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw HarnessError(description: message)
        }
    }

    static func run() async throws {
        try await testAppendProjectionAndReload()
        try await testWaitEvidenceArtifactAndSideEffectRecords()
        try await testSchemaMigration()
        try await testInterruptedRunDetection()
    }

    private static func testAppendProjectionAndReload() async throws {
        let root = try makeTemporaryRoot()
        let store = try AgentRunStore(rootDirectory: root)
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let session = try await store.createSession(title: "Fixture", contextID: "fixture", contextKind: "assistant", createdAt: createdAt)
        let run = try await store.createRun(sessionID: session.id, status: .queued, createdAt: createdAt)

        let userEvent = try await store.appendEvent(
            runID: run.runID,
            kind: .userMessage,
            payload: .text(AgentRunText("Inspect the project.")),
            createdAt: createdAt.addingTimeInterval(1)
        )
        let progressEvent = try await store.appendEvent(
            runID: run.runID,
            kind: .progress,
            payload: .progress(AgentRunText("Reading granted files")),
            createdAt: createdAt.addingTimeInterval(2)
        )
        let assistantEvent = try await store.appendEvent(
            runID: run.runID,
            kind: .assistantMessage,
            payload: .text(AgentRunText("I found the active backlog.")),
            createdAt: createdAt.addingTimeInterval(3)
        )
        _ = try await store.updateRunStatus(runID: run.runID, status: .completed, createdAt: createdAt.addingTimeInterval(4))

        try expect(userEvent.sequence == 0, "first event sequence should be zero")
        try expect(progressEvent.sequence == 1, "progress event should increment sequence")
        try expect(assistantEvent.sequence == 2, "assistant event should increment sequence")

        let messages = await store.visibleMessages(sessionID: session.id)
        try expect(messages.map(\.role) == [.user, .assistant], "visible projection should include only chat messages")
        let latestProgress = await store.latestProgress(runID: run.runID)
        try expect(latestProgress?.text == "Reading granted files", "latest progress should project from progress events")

        let reloaded = try AgentRunStore(rootDirectory: root)
        let reloadedMessages = await reloaded.visibleMessages(sessionID: session.id)
        try expect(reloadedMessages == messages, "visible projection should survive reload")
        let status = try await reloaded.statusProjection(runID: run.runID)
        try expect(status.status == .completed, "run status should survive reload")
    }

    private static func testWaitEvidenceArtifactAndSideEffectRecords() async throws {
        let root = try makeTemporaryRoot()
        let store = try AgentRunStore(rootDirectory: root)
        let session = try await store.createSession(title: "Artifacts")
        let run = try await store.createRun(sessionID: session.id, status: .running)
        let step = try await store.beginStep(runID: run.runID, kind: .toolRequest)
        let wait = try await store.createWait(
            runID: run.runID,
            stepID: step.stepID,
            kind: .approval,
            prompt: AgentRunText("Approve file write?"),
            risk: "write"
        )

        let pendingWaitIDs = await store.pendingWaits(runID: run.runID).map(\.waitID)
        try expect(pendingWaitIDs == [wait.waitID], "pending wait should be projected")

        let artifactData = Data("hello artifact".utf8)
        let artifact = try await store.recordArtifact(
            runID: run.runID,
            stepID: step.stepID,
            kind: "file-read",
            mimeType: "text/plain",
            fileExtension: "txt",
            data: artifactData,
            summary: AgentRunText("README excerpt")
        )
        let evidence = try await store.recordEvidence(
            runID: run.runID,
            stepID: step.stepID,
            sourceID: "read_file:README.md",
            kind: "file",
            summary: AgentRunText("README.md exists"),
            artifactID: artifact.artifactID,
            metadata: ["path": .string("README.md")]
        )
        let sideEffect = try await store.recordSideEffect(
            runID: run.runID,
            stepID: step.stepID,
            kind: .fileWrite,
            status: .proposed,
            proposalHash: "abc123"
        )
        _ = try await store.resolveWait(waitID: wait.waitID, status: .approved, summary: AgentRunText("Approved"))

        let readArtifactData = try await store.readArtifact(artifact.artifactID)
        try expect(readArtifactData == artifactData, "artifact bytes should be durable")
        let summary = await store.evidenceArtifactSummary(runID: run.runID)
        try expect(summary.artifacts.map(\.artifactID) == [artifact.artifactID], "artifact summary should include artifact")
        try expect(summary.evidence.map(\.evidenceID) == [evidence.evidenceID], "evidence summary should include evidence")
        let trace = try await store.traceProjection(runID: run.runID)
        try expect(trace.sideEffects.map(\.sideEffectID) == [sideEffect.sideEffectID], "trace should include side effects")
        let remainingWaits = await store.pendingWaits(runID: run.runID)
        try expect(remainingWaits.isEmpty, "resolved wait should not remain pending")
    }

    private static func testSchemaMigration() async throws {
        let root = try makeTemporaryRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let oldSnapshot = AgentRunStoreSnapshot(schemaVersion: 0)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(oldSnapshot).write(to: root.appendingPathComponent("store.json"), options: .atomic)

        let store = try AgentRunStore(rootDirectory: root)
        let schemaVersion = await store.schemaVersion()
        try expect(schemaVersion == AgentRunStoreSchema.currentVersion, "old schema should migrate to current version")
    }

    private static func testInterruptedRunDetection() async throws {
        let root = try makeTemporaryRoot()
        let store = try AgentRunStore(rootDirectory: root)
        let session = try await store.createSession(title: "Recovery")
        let queued = try await store.createRun(sessionID: session.id, status: .queued)
        let running = try await store.createRun(sessionID: session.id, status: .running)
        let waiting = try await store.createRun(sessionID: session.id, status: .waitingForApproval)
        let completed = try await store.createRun(sessionID: session.id, status: .completed)
        _ = try await store.createWait(
            runID: waiting.runID,
            kind: .approval,
            prompt: AgentRunText("Approve?"),
            risk: "write"
        )

        let reloaded = try AgentRunStore(rootDirectory: root)
        let recoveryIDs = await Set(reloaded.runsNeedingLaunchRecovery().map(\.runID))
        try expect(recoveryIDs == Set([queued.runID, running.runID]), "only queued/running runs should need launch recovery")
        let pendingWaitRunIDs = await reloaded.pendingWaits().map(\.runID)
        try expect(pendingWaitRunIDs == [waiting.runID], "pending waits should be restored separately")
        try expect(!recoveryIDs.contains(completed.runID), "completed runs should not need recovery")
    }

    private static func makeTemporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixel-pane-agent-run-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@main
struct AgentRunStoreFixtureMain {
    static func main() async {
        do {
            try await AgentRunStoreFixtureHarness.run()
            print("Agent run store fixture tests passed")
        } catch {
            fputs("Agent run store fixture tests failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
