import Foundation

enum AgentTraceExportFixtureHarness {
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
        try await testTraceExportRedactsAndSummarizes()
        try await testRefreshKeepsRecentSessionsOutOfRunProjection()
    }

    @MainActor
    private static func testTraceExportRedactsAndSummarizes() async throws {
        let (store, viewModel) = try await makeHarness()
        let session = try await store.createSession(title: "Trace", contextID: "trace", contextKind: "assistant")
        let run = try await store.createRun(sessionID: session.id, status: .queued)
        try await store.appendEvent(runID: run.runID, kind: .userMessage, payload: .text(AgentRunText("What changed?")))
        try await store.appendEvent(runID: run.runID, kind: .assistantMessage, payload: .text(AgentRunText("The trace is ready.")))
        let artifact = try await store.recordArtifact(
            runID: run.runID,
            kind: "command-output",
            mimeType: "text/plain",
            fileExtension: "txt",
            data: Data("SECRET_BODY_SHOULD_NOT_EXPORT".utf8),
            summary: AgentRunText("Command output")
        )
        _ = try await store.recordEvidence(
            runID: run.runID,
            sourceID: "fixture",
            kind: "command",
            summary: AgentRunText("Command succeeded"),
            artifactID: artifact.artifactID,
            metadata: [
                "api_key": .string("sk-secret"),
                "path": .string("/tmp/project")
            ]
        )
        _ = try await store.recordSideEffect(
            runID: run.runID,
            kind: .command,
            status: .completed,
            metadata: [
                "command": .string("echo ok"),
                "authorization": .string("Bearer abc123")
            ]
        )
        _ = try await store.updateRunStatus(runID: run.runID, status: .completed)

        try await viewModel.loadSession(sessionID: session.id)
        guard let export = viewModel.state.traceExport else {
            throw HarnessError(description: "trace export should be available")
        }

        try expect(export.contains("# Pixel Pane Agent Trace"), "export should have trace header")
        try expect(export.contains(run.runID.uuidString), "export should include run ID")
        try expect(export.contains("## Conversation"), "export should include conversation")
        try expect(export.contains("## Evidence"), "export should include evidence")
        try expect(export.contains("## Artifacts"), "export should include artifact records")
        try expect(export.contains("[redacted]"), "export should redact sensitive metadata")
        try expect(!export.contains("sk-secret"), "export should not leak API keys")
        try expect(!export.contains("abc123"), "export should not leak bearer tokens")
        try expect(!export.contains("SECRET_BODY_SHOULD_NOT_EXPORT"), "export should not inline artifact bodies")
    }

    @MainActor
    private static func testRefreshKeepsRecentSessionsOutOfRunProjection() async throws {
        let (store, viewModel) = try await makeHarness()
        for index in 0..<2 {
            let session = try await store.createSession(title: "Session \(index)", contextID: "session-\(index)", contextKind: "assistant")
            let run = try await store.createRun(sessionID: session.id, status: .queued)
            try await store.appendEvent(runID: run.runID, kind: .userMessage, payload: .text(AgentRunText("Question \(index)")))
            _ = try await store.updateRunStatus(runID: run.runID, status: .completed)
        }

        await viewModel.refresh()
        try expect(viewModel.state.recentSessions.isEmpty, "run projection should not expose universal recent sessions")
        try await viewModel.clearHistory()
        let sessionsAfterClear = await store.allSessions()
        try expect(sessionsAfterClear.isEmpty, "clear history should clear store sessions")
    }

    @MainActor
    private static func makeHarness() async throws -> (AgentRunStore, AgentRunViewModel) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixel-pane-agent-trace-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try AgentRunStore(rootDirectory: root)
        return (store, AgentRunViewModel(store: store))
    }
}

@main
struct AgentTraceExportFixtureMain {
    static func main() async {
        do {
            try await AgentTraceExportFixtureHarness.run()
            print("Agent trace export fixture tests passed")
        } catch {
            fputs("Agent trace export fixture tests failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
