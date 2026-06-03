import Foundation

enum AgentRunnerFixtureHarness {
    struct HarnessError: Error, CustomStringConvertible {
        let description: String
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw HarnessError(description: message)
        }
    }

    static func run() async throws {
        try await testCheckpointedSteps()
        try await testTimeoutInterruptsRun()
        try await testCancellationCancelsRun()
        try await testLaunchRecoveryInterruptsUnsafeWork()
        try await testLaunchRecoveryRestoresApprovalWait()
        try await testDuplicateRunPrevention()
    }

    private static func testCheckpointedSteps() async throws {
        let (store, runner, run) = try await makeHarness(status: .queued)
        _ = try await runner.run(
            runID: run.runID,
            steps: [
                AgentRunnerStep(kind: .route) {
                    .progress(AgentRunText("Selected route"))
                },
                AgentRunnerStep(kind: .modelRequest) {
                    .event(kind: .providerDiagnostic, payload: .diagnostic(AgentRunText("model request sent")))
                },
                AgentRunnerStep(kind: .modelResponse) {
                    .event(kind: .assistantMessage, payload: .text(AgentRunText("Done")))
                }
            ]
        )

        let trace = try await store.traceProjection(runID: run.runID)
        try expect(trace.steps.map(\.kind) == [.route, .modelRequest, .modelResponse], "runner should create typed steps")
        try expect(trace.steps.allSatisfy { $0.status == .completed }, "successful runner steps should complete")
        try expect(trace.run.status == .completed, "runner should complete run after steps finish")
        let visibleMessages = await store.visibleMessages().map(\.text.text)
        try expect(visibleMessages == ["Done"], "assistant event should project as visible message")
    }

    private static func testTimeoutInterruptsRun() async throws {
        let (store, runner, run) = try await makeHarness(status: .queued)

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
            throw HarnessError(description: "timeout test should throw")
        } catch AgentRunnerError.stepTimedOut {
            let trace = try await store.traceProjection(runID: run.runID)
            try expect(trace.run.status == .interrupted, "timeout should interrupt run")
            try expect(trace.steps.last?.status == .interrupted, "timeout should interrupt active step")
            try expect(trace.events.contains { $0.kind == .failure }, "timeout should record failure checkpoint")
        }
    }

    private static func testCancellationCancelsRun() async throws {
        let (store, runner, run) = try await makeHarness(status: .queued)
        let task = Task {
            try await runner.run(
                runID: run.runID,
                steps: [
                    AgentRunnerStep(kind: .toolRequest) {
                        try await Task.sleep(nanoseconds: 500_000_000)
                        return .none
                    }
                ]
            )
        }
        task.cancel()

        do {
            _ = try await task.value
            throw HarnessError(description: "cancellation test should throw")
        } catch AgentRunnerError.canceled {
            let trace = try await store.traceProjection(runID: run.runID)
            try expect(trace.run.status == .canceled, "cancellation should cancel run")
        }
    }

    private static func testLaunchRecoveryInterruptsUnsafeWork() async throws {
        let (store, runner, run) = try await makeHarness(status: .running)
        let step = try await store.beginStep(runID: run.runID, kind: .modelRequest)

        let recovery = try await runner.recoverOnLaunch()
        let trace = try await store.traceProjection(runID: run.runID)

        try expect(recovery.interruptedRuns.map(\.runID) == [run.runID], "recovery should report interrupted run")
        try expect(recovery.interruptedSteps.map(\.stepID) == [step.stepID], "recovery should report the interrupted active step")
        try expect(recovery.interruptedSteps.map(\.kind) == [.modelRequest], "recovery should preserve interrupted step kind")
        try expect(trace.run.status == .interrupted, "running run should become interrupted")
        try expect(trace.steps.first { $0.stepID == step.stepID }?.status == .interrupted, "active step should become interrupted")
    }

    private static func testLaunchRecoveryRestoresApprovalWait() async throws {
        let (store, runner, run) = try await makeHarness(status: .waitingForApproval)
        let wait = try await store.createWait(
            runID: run.runID,
            kind: .approval,
            prompt: AgentRunText("Approve write?"),
            risk: "write"
        )

        let recovery = try await runner.recoverOnLaunch()
        try expect(recovery.interruptedRuns.isEmpty, "waiting run should not be marked interrupted")
        try expect(recovery.pendingWaits.map(\.waitID) == [wait.waitID], "pending approval wait should be restored")
        let trace = try await store.traceProjection(runID: run.runID)
        try expect(trace.run.status == .waitingForApproval, "waiting status should be preserved")
    }

    private static func testDuplicateRunPrevention() async throws {
        let (store, runner, run) = try await makeHarness(status: .queued)
        let slowStep = AgentRunnerStep(kind: .toolRequest) {
            try await Task.sleep(nanoseconds: 200_000_000)
            return .none
        }
        let first = Task {
            try await runner.run(runID: run.runID, steps: [slowStep])
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        do {
            _ = try await runner.run(runID: run.runID, steps: [slowStep])
            throw HarnessError(description: "duplicate run should throw")
        } catch AgentRunnerError.runAlreadyActive {
            _ = try await first.value
            let trace = try await store.traceProjection(runID: run.runID)
            try expect(trace.run.status == .completed, "first run should still finish")
        }
    }

    private static func makeHarness(status: AgentRunStatus) async throws -> (AgentRunStore, AgentRunner, AgentRunRecord) {
        let root = try makeTemporaryRoot()
        let store = try AgentRunStore(rootDirectory: root)
        let session = try await store.createSession(title: "Runner")
        let run = try await store.createRun(sessionID: session.id, status: status)
        return (store, AgentRunner(store: store), run)
    }

    private static func makeTemporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixel-pane-agent-runner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@main
struct AgentRunnerFixtureMain {
    static func main() async {
        do {
            try await AgentRunnerFixtureHarness.run()
            print("Agent runner fixture tests passed")
        } catch {
            fputs("Agent runner fixture tests failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
