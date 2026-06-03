import Foundation
import SQLite3

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
        try await testControlRecordsReplayAndReload()
        try await testSQLiteSchemaAndLegacyImport()
        try await testSchemaMigration()
        try await testInterruptedRunDetection()
        try await testTerminalStatusGuard()
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
        let trace = try await store.traceProjection(runID: run.runID)
        let reloadedTrace = try await reloaded.traceProjection(runID: run.runID)
        try expect(reloadedTrace == trace, "trace projection should survive SQLite reload")
        try expect(
            FileManager.default.fileExists(atPath: root.appendingPathComponent(AgentRunSQLitePersistenceBackend.databaseFileName).path),
            "run store should create the SQLite database"
        )
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

    private static func testControlRecordsReplayAndReload() async throws {
        let root = try makeTemporaryRoot()
        let store = try AgentRunStore(rootDirectory: root)
        let session = try await store.createSession(title: "Control Records")
        let run = try await store.createRun(sessionID: session.id, status: .running)
        let step = try await store.beginStep(runID: run.runID, kind: .modelRequest)
        let messages = [
            AgentKernelMessage(role: .system, content: "You are Pixel Pane."),
            AgentKernelMessage(role: .user, content: "Inspect the project."),
            AgentKernelMessage(role: .observation, content: "Hidden preflight evidence.")
        ]
        let request = AgentModelGatewayRequest(
            mode: .fullAgent,
            messages: messages,
            tools: [],
            requestedMaxOutputTokens: 512,
            metadata: ["fixture": .string("control-replay")]
        )
        let requestRecord = try await store.recordControl(
            runID: run.runID,
            stepID: step.stepID,
            kind: .modelRequest,
            payload: .modelRequest(request),
            metadata: ["iteration": .int(1)]
        )
        let observation = AgentKernelMessage(
            role: .observation,
            content: "Tool result\nname: list_folder\nstatus: succeeded"
        )
        let observationRecord = try await store.recordControl(
            runID: run.runID,
            kind: .toolObservation,
            payload: .modelMessage(observation),
            metadata: ["toolName": .string("list_folder")]
        )

        try expect(requestRecord.sequence == 0, "first control record sequence should be zero")
        try expect(observationRecord.sequence == 1, "control records should sequence per run")
        let replay = await store.replayMessages(runID: run.runID)
        try expect(replay == messages, "replay messages should come from the latest durable model request")
        let trace = try await store.traceProjection(runID: run.runID)
        try expect(trace.controlRecords.map(\.kind) == [.modelRequest, .toolObservation], "trace should include control records in order")

        let reloaded = try AgentRunStore(rootDirectory: root)
        let reloadedReplay = await reloaded.replayMessages(runID: run.runID)
        try expect(reloadedReplay == messages, "replay messages should survive SQLite reload")
        let reloadedControlKinds = await reloaded.controlRecords(runID: run.runID).map(\.kind)
        try expect(reloadedControlKinds == [.modelRequest, .toolObservation], "control records should survive SQLite reload")
    }

    private static func testSQLiteSchemaAndLegacyImport() async throws {
        let root = try makeTemporaryRoot()
        let createdAt = Date(timeIntervalSince1970: 1_800_100_000)
        let session = AgentRunSessionRecord(
            title: "Legacy",
            contextID: "legacy-context",
            contextKind: "assistant",
            createdAt: createdAt
        )
        let run = AgentRunRecord(
            sessionID: session.id,
            status: .completed,
            createdAt: createdAt,
            lastSequence: 0
        )
        let event = AgentRunEventRecord(
            sessionID: session.id,
            runID: run.runID,
            sequence: 0,
            kind: .assistantMessage,
            payload: .text(AgentRunText("Imported answer")),
            createdAt: createdAt.addingTimeInterval(1)
        )
        let oldSnapshot = AgentRunStoreSnapshot(
            schemaVersion: 0,
            sessions: [session],
            runs: [run],
            events: [event]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(oldSnapshot).write(to: root.appendingPathComponent("store.json"), options: .atomic)

        let store = try AgentRunStore(rootDirectory: root)
        let schemaVersion = await store.schemaVersion()
        try expect(schemaVersion == AgentRunStoreSchema.currentVersion, "legacy JSON import should migrate to the current schema")
        let messages = await store.visibleMessages(sessionID: session.id)
        try expect(messages.map(\.text.text) == ["Imported answer"], "legacy JSON import should preserve visible messages")

        let databasePath = root.appendingPathComponent(AgentRunSQLitePersistenceBackend.databaseFileName).path
        try expect(FileManager.default.fileExists(atPath: databasePath), "legacy JSON import should create the SQLite store")
        let tableNames = try sqliteTableNames(root: root)
        for expectedTable in ["sessions", "runs", "steps", "waits", "artifacts", "evidence", "side_effects", "control_records", "events", "store_metadata"] {
            try expect(tableNames.contains(expectedTable), "SQLite schema should include \(expectedTable)")
        }

        let reloaded = try AgentRunStore(rootDirectory: root)
        let reloadedMessages = await reloaded.visibleMessages(sessionID: session.id)
        try expect(reloadedMessages == messages, "imported SQLite projection should survive reload")
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

    private static func testTerminalStatusGuard() async throws {
        let root = try makeTemporaryRoot()
        let store = try AgentRunStore(rootDirectory: root)
        let session = try await store.createSession(title: "Terminal Guard")
        let run = try await store.createRun(sessionID: session.id, status: .queued)

        try await store.updateRunStatus(runID: run.runID, status: .canceled)
        try await store.updateRunStatus(runID: run.runID, status: .running)
        let guardedRun = try await store.runRecord(runID: run.runID)
        try expect(guardedRun.status == .canceled, "late nonterminal status should not overwrite a terminal run")

        try await store.updateRunStatus(
            runID: run.runID,
            status: .queued,
            allowsTerminalTransition: true
        )
        let retriedRun = try await store.runRecord(runID: run.runID)
        try expect(retriedRun.status == .queued, "explicit terminal transition should support retry/recovery flows")
    }

    private static func makeTemporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixel-pane-agent-run-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func sqliteTableNames(root: URL) throws -> Set<String> {
        let databaseURL = root.appendingPathComponent(AgentRunSQLitePersistenceBackend.databaseFileName, isDirectory: false)
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            throw HarnessError(description: "could not open SQLite store")
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT name FROM sqlite_master WHERE type = 'table';",
            -1,
            &statement,
            nil
        ) == SQLITE_OK,
              let statement else {
            throw HarnessError(description: "could not inspect SQLite schema")
        }
        defer { sqlite3_finalize(statement) }

        var names = Set<String>()
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                guard let text = sqlite3_column_text(statement, 0) else { continue }
                names.insert(String(cString: text))
            } else if result == SQLITE_DONE {
                return names
            } else {
                throw HarnessError(description: "could not read SQLite schema")
            }
        }
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
