import Foundation

enum AgentSideEffectControllerFixtureHarness {
    struct HarnessError: Error, CustomStringConvertible {
        let description: String
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw HarnessError(description: message)
        }
    }

    static func run() async throws {
        try await testApproveAndExecuteFileWrite()
        try await testDenyAndDuplicateApproval()
        try await testRelaunchWhileWaiting()
        try await testFailedWriteAndRollback()
        try await testCommandApproval()
        try await testProcessStartStopAndRollback()
    }

    private static func testApproveAndExecuteFileWrite() async throws {
        let harness = try await makeHarness()
        let target = harness.workspace.appendingPathComponent("notes.md")
        try Data("old".utf8).write(to: target)

        let stage = try await harness.controller.stage(
            runID: harness.run.runID,
            draft: .fileWrite(
                AgentFileWriteDraft(
                    operation: .replace,
                    targetPath: target.path,
                    content: "new"
                )
            )
        )

        try expect(stage.wait.status == .pending, "stage should create a pending approval wait")
        try expect(stage.sideEffect.status == .proposed, "stage should record proposed side effect")

        let approved = try await harness.controller.resolveApproval(sideEffectID: stage.sideEffect.sideEffectID, decision: .approved)
        try expect(approved.status == .approved, "approval should mark side effect approved")

        let completed = try await harness.controller.executeApproved(sideEffectID: stage.sideEffect.sideEffectID)
        let content = try String(contentsOf: target, encoding: .utf8)
        try expect(content == "new", "approved file write should update target")
        try expect(completed.status == .completed, "executed file write should complete")
        try expect(completed.beforeArtifactID != nil, "file write should have before snapshot")
        try expect(completed.afterArtifactID != nil, "file write should have after snapshot")
        try expect(completed.startedAt != nil && completed.completedAt != nil, "file write should record execution timestamps")
    }

    private static func testDenyAndDuplicateApproval() async throws {
        let harness = try await makeHarness()
        let target = harness.workspace.appendingPathComponent("deny.md")
        let stage = try await harness.controller.stage(
            runID: harness.run.runID,
            draft: .fileWrite(
                AgentFileWriteDraft(
                    operation: .create,
                    targetPath: target.path,
                    content: "denied"
                )
            )
        )

        let denied = try await harness.controller.resolveApproval(sideEffectID: stage.sideEffect.sideEffectID, decision: .denied)
        try expect(denied.status == .denied, "denied approval should mark side effect denied")
        let run = try await harness.store.runRecord(runID: harness.run.runID)
        try expect(run.status == .blocked, "denied wait should block run")

        do {
            _ = try await harness.controller.resolveApproval(sideEffectID: stage.sideEffect.sideEffectID, decision: .approved)
            throw HarnessError(description: "duplicate approval should throw")
        } catch AgentSideEffectError.duplicateApproval {
            // Expected.
        }

        do {
            _ = try await harness.controller.executeApproved(sideEffectID: stage.sideEffect.sideEffectID)
            throw HarnessError(description: "denied side effect should not execute")
        } catch AgentSideEffectError.invalidApprovalState {
            // Expected.
        }
    }

    private static func testRelaunchWhileWaiting() async throws {
        let harness = try await makeHarness()
        let target = harness.workspace.appendingPathComponent("waiting.md")
        let stage = try await harness.controller.stage(
            runID: harness.run.runID,
            draft: .fileWrite(
                AgentFileWriteDraft(
                    operation: .create,
                    targetPath: target.path,
                    content: "waiting"
                )
            )
        )

        let runner = AgentRunner(store: harness.store)
        let recovery = try await runner.recoverOnLaunch()
        try expect(recovery.interruptedRuns.isEmpty, "waiting run should not be interrupted on relaunch")
        try expect(recovery.pendingWaits.map(\.waitID).contains(stage.wait.waitID), "pending approval should recover on launch")
        let run = try await harness.store.runRecord(runID: harness.run.runID)
        try expect(run.status == .waitingForApproval, "run should remain waiting for approval")
    }

    private static func testFailedWriteAndRollback() async throws {
        let harness = try await makeHarness()
        let missingTarget = harness.workspace.appendingPathComponent("missing.md")
        let failedStage = try await harness.controller.stage(
            runID: harness.run.runID,
            draft: .fileWrite(
                AgentFileWriteDraft(
                    operation: .replace,
                    targetPath: missingTarget.path,
                    content: "new"
                )
            )
        )
        _ = try await harness.controller.resolveApproval(sideEffectID: failedStage.sideEffect.sideEffectID, decision: .approved)
        let failed = try await harness.controller.executeApproved(sideEffectID: failedStage.sideEffect.sideEffectID)
        try expect(failed.status == .failed, "replace missing target should fail")
        try expect(failed.errorSummary != nil, "failed write should record error summary")

        let target = harness.workspace.appendingPathComponent("rollback.md")
        try Data("before".utf8).write(to: target)
        let stage = try await harness.controller.stage(
            runID: harness.run.runID,
            draft: .fileWrite(
                AgentFileWriteDraft(
                    operation: .replace,
                    targetPath: target.path,
                    content: "after"
                )
            )
        )
        _ = try await harness.controller.resolveApproval(sideEffectID: stage.sideEffect.sideEffectID, decision: .approved)
        let completed = try await harness.controller.executeApproved(sideEffectID: stage.sideEffect.sideEffectID)
        try expect(completed.status == .completed, "write before rollback should complete")

        let rolledBack = try await harness.controller.rollback(sideEffectID: stage.sideEffect.sideEffectID)
        let restored = try String(contentsOf: target, encoding: .utf8)
        try expect(rolledBack.status == .rolledBack, "rollback should mark side effect rolled back")
        try expect(restored == "before", "rollback should restore original content")
    }

    private static func testCommandApproval() async throws {
        let commandExecutor = FixtureCommandExecutor()
        let harness = try await makeHarness(commandExecutor: commandExecutor)
        let stage = try await harness.controller.stage(
            runID: harness.run.runID,
            draft: .command(
                AgentCommandDraft(
                    command: "echo ok",
                    workingDirectory: harness.workspace.path,
                    timeoutSeconds: 5
                )
            )
        )
        _ = try await harness.controller.resolveApproval(sideEffectID: stage.sideEffect.sideEffectID, decision: .approved)
        let completed = try await harness.controller.executeApproved(sideEffectID: stage.sideEffect.sideEffectID)

        try expect(completed.status == .completed, "approved command should complete")
        try expect(completed.afterArtifactID != nil, "command execution should record output artifact")
        try expect(commandExecutor.commands == ["echo ok"], "command executor should receive approved command")
    }

    private static func testProcessStartStopAndRollback() async throws {
        let processExecutor = FixtureProcessExecutor()
        let harness = try await makeHarness(processExecutor: processExecutor)
        let startStage = try await harness.controller.stage(
            runID: harness.run.runID,
            draft: .processStart(
                AgentProcessStartDraft(
                    command: "npm run dev",
                    workingDirectory: harness.workspace.path,
                    processID: "dev-server"
                )
            )
        )
        _ = try await harness.controller.resolveApproval(sideEffectID: startStage.sideEffect.sideEffectID, decision: .approved)
        let started = try await harness.controller.executeApproved(sideEffectID: startStage.sideEffect.sideEffectID)
        try expect(started.status == .completed, "process start should complete through executor")
        try expect(stringValue(started.metadata["processID"]) == "dev-server", "process ID should be recorded")

        let rolledBack = try await harness.controller.rollback(sideEffectID: startStage.sideEffect.sideEffectID)
        try expect(rolledBack.status == .rolledBack, "process start rollback should stop process")
        try expect(processExecutor.stoppedProcessIDs.contains("dev-server"), "rollback should call process stop")

        let stopStage = try await harness.controller.stage(
            runID: harness.run.runID,
            draft: .processStop(AgentProcessStopDraft(processID: "dev-server"))
        )
        _ = try await harness.controller.resolveApproval(sideEffectID: stopStage.sideEffect.sideEffectID, decision: .approved)
        let stopped = try await harness.controller.executeApproved(sideEffectID: stopStage.sideEffect.sideEffectID)
        try expect(stopped.status == .completed, "process stop should complete through executor")
    }

    private static func makeHarness(
        commandExecutor: any AgentCommandExecuting = FixtureCommandExecutor(),
        processExecutor: any AgentManagedProcessExecuting = FixtureProcessExecutor()
    ) async throws -> Harness {
        let root = try makeTemporaryRoot(prefix: "store")
        let workspace = try makeTemporaryRoot(prefix: "workspace")
        let store = try AgentRunStore(rootDirectory: root)
        let session = try await store.createSession(title: "Side Effects")
        let run = try await store.createRun(sessionID: session.id, status: .queued)
        let controller = AgentSideEffectController(
            store: store,
            commandExecutor: commandExecutor,
            processExecutor: processExecutor
        )
        return Harness(store: store, controller: controller, run: run, workspace: workspace)
    }

    private static func makeTemporaryRoot(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixel-pane-side-effect-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func stringValue(_ value: AgentRunMetadataValue?) -> String? {
        guard case .string(let text) = value else { return nil }
        return text
    }

    struct Harness {
        let store: AgentRunStore
        let controller: AgentSideEffectController
        let run: AgentRunRecord
        let workspace: URL
    }
}

final class FixtureCommandExecutor: AgentCommandExecuting, @unchecked Sendable {
    private nonisolated(unsafe) var recordedCommands: [String] = []

    var commands: [String] {
        recordedCommands
    }

    func run(command: String, workingDirectory: String, timeoutSeconds: Int) async throws -> AgentCommandExecutionOutput {
        recordedCommands.append(command)
        return AgentCommandExecutionOutput(
            command: command,
            workingDirectory: workingDirectory,
            exitCode: 0,
            stdout: AgentRunText("ok"),
            stderr: AgentRunText(""),
            durationSeconds: 0.01,
            didTimeOut: false
        )
    }
}

final class FixtureProcessExecutor: AgentManagedProcessExecuting, @unchecked Sendable {
    private nonisolated(unsafe) var started: [String] = []
    private nonisolated(unsafe) var stopped: [String] = []

    var stoppedProcessIDs: [String] {
        stopped
    }

    func start(command: String, workingDirectory: String, processID: String?) async throws -> AgentProcessExecutionOutput {
        let resolvedID = processID ?? "process-\(UUID().uuidString)"
        started.append(resolvedID)
        return AgentProcessExecutionOutput(
            processID: resolvedID,
            command: command,
            status: "running",
            summary: AgentRunText("Process \(resolvedID) started.")
        )
    }

    func stop(processID: String) async throws -> AgentProcessExecutionOutput {
        stopped.append(processID)
        return AgentProcessExecutionOutput(
            processID: processID,
            command: nil,
            status: "stopped",
            summary: AgentRunText("Process \(processID) stopped.")
        )
    }
}

@main
struct AgentSideEffectControllerFixtureMain {
    static func main() async {
        do {
            try await AgentSideEffectControllerFixtureHarness.run()
            print("Agent side-effect controller fixture tests passed")
        } catch {
            fputs("Agent side-effect controller fixture tests failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
