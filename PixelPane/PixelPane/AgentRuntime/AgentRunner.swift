import Foundation

nonisolated enum AgentRunnerError: Error, Equatable, CustomStringConvertible {
    case runAlreadyActive(UUID)
    case stepTimedOut(kind: AgentRunStepKind, timeout: TimeInterval)
    case canceled(UUID)

    var description: String {
        switch self {
        case .runAlreadyActive(let runID):
            "Agent run \(runID) is already active."
        case .stepTimedOut(let kind, let timeout):
            "Agent runner step \(kind.rawValue) timed out after \(timeout) seconds."
        case .canceled(let runID):
            "Agent run \(runID) was canceled."
        }
    }
}

nonisolated enum AgentRunnerStepOutput: Sendable {
    case none
    case progress(AgentRunText)
    case event(kind: AgentRunEventKind, payload: AgentRunEventPayload)
    case wait(kind: AgentRunWaitKind, prompt: AgentRunText, risk: String?)
    case sideEffect(kind: AgentRunSideEffectKind, status: AgentRunSideEffectStatus, proposalHash: String?)
    case terminal(status: AgentRunStatus, reason: AgentRunText?)
}

nonisolated struct AgentRunnerStep: Sendable {
    let kind: AgentRunStepKind
    let timeout: TimeInterval?
    let metadata: [String: AgentRunMetadataValue]
    let operation: @Sendable () async throws -> AgentRunnerStepOutput

    init(
        kind: AgentRunStepKind,
        timeout: TimeInterval? = nil,
        metadata: [String: AgentRunMetadataValue] = [:],
        operation: @escaping @Sendable () async throws -> AgentRunnerStepOutput
    ) {
        self.kind = kind
        self.timeout = timeout
        self.metadata = metadata
        self.operation = operation
    }
}

nonisolated struct AgentRunnerLaunchRecoveryResult: Codable, Equatable, Sendable {
    let interruptedRuns: [AgentRunRecord]
    let pendingWaits: [AgentRunWaitRecord]
}

actor AgentRunner {
    private let store: AgentRunStore
    private var activeRunIDs: Set<UUID> = []

    init(store: AgentRunStore) {
        self.store = store
    }

    @discardableResult
    func run(runID: UUID, steps: [AgentRunnerStep], startedAt: Date = Date()) async throws -> AgentRunRecord {
        guard !activeRunIDs.contains(runID) else {
            throw AgentRunnerError.runAlreadyActive(runID)
        }

        activeRunIDs.insert(runID)
        defer { activeRunIDs.remove(runID) }

        try await store.updateRunStatus(
            runID: runID,
            status: .running,
            reason: AgentRunText("Runner started."),
            createdAt: startedAt
        )

        do {
            for step in steps {
                try Task.checkCancellation()
                try await runStep(runID: runID, request: step)
            }

            let current = try await store.runRecord(runID: runID)
            if current.status == .running || current.status == .queued {
                try await store.updateRunStatus(
                    runID: runID,
                    status: .completed,
                    reason: AgentRunText("Runner completed all queued steps.")
                )
            }
            return try await store.runRecord(runID: runID)
        } catch is CancellationError {
            try await markRunCanceled(runID: runID)
            throw AgentRunnerError.canceled(runID)
        } catch {
            throw error
        }
    }

    func recoverOnLaunch(recoveredAt: Date = Date()) async throws -> AgentRunnerLaunchRecoveryResult {
        let interruptedCandidates = await store.runsNeedingLaunchRecovery()
        var interruptedRuns: [AgentRunRecord] = []

        for run in interruptedCandidates {
            if let activeStepID = run.activeStepID {
                _ = try await store.finishStep(
                    stepID: activeStepID,
                    status: .interrupted,
                    finishedAt: recoveredAt
                )
            }
            try await store.updateRunStatus(
                runID: run.runID,
                status: .interrupted,
                reason: AgentRunText("Interrupted by app relaunch. Retry or cancel this run."),
                createdAt: recoveredAt
            )
            try await store.appendEvent(
                runID: run.runID,
                kind: .failure,
                payload: .metadata([
                    "reason": .string("app_relaunch"),
                    "recovery": .string("retry_or_cancel")
                ]),
                createdAt: recoveredAt
            )
            interruptedRuns.append(try await store.runRecord(runID: run.runID))
        }

        return AgentRunnerLaunchRecoveryResult(
            interruptedRuns: interruptedRuns,
            pendingWaits: await store.pendingWaits()
        )
    }

    private func runStep(runID: UUID, request: AgentRunnerStep) async throws {
        let step = try await store.beginStep(
            runID: runID,
            kind: request.kind,
            metadata: request.metadata
        )

        do {
            let output = try await executeWithDeadline(request)
            try await checkpoint(output, runID: runID, stepID: step.stepID)
            _ = try await store.finishStep(stepID: step.stepID, status: .completed)
        } catch is CancellationError {
            _ = try await store.finishStep(stepID: step.stepID, status: .canceled)
            try await markRunCanceled(runID: runID)
            throw AgentRunnerError.canceled(runID)
        } catch AgentRunnerError.stepTimedOut(let kind, let timeout) {
            _ = try await store.finishStep(stepID: step.stepID, status: .interrupted)
            try await markRunInterrupted(
                runID: runID,
                reason: AgentRunText("Step \(kind.rawValue) timed out after \(timeout) seconds. Retry or cancel this run."),
                metadata: [
                    "reason": .string("timeout"),
                    "stepKind": .string(kind.rawValue),
                    "timeoutSeconds": .double(timeout),
                    "recovery": .string("retry_or_cancel")
                ]
            )
            throw AgentRunnerError.stepTimedOut(kind: kind, timeout: timeout)
        } catch {
            _ = try await store.finishStep(stepID: step.stepID, status: .failed)
            try await store.updateRunStatus(
                runID: runID,
                status: .failed,
                reason: AgentRunText(String(describing: error))
            )
            try await store.appendEvent(
                runID: runID,
                stepID: step.stepID,
                kind: .failure,
                payload: .diagnostic(AgentRunText(String(describing: error)))
            )
            throw error
        }
    }

    private func checkpoint(_ output: AgentRunnerStepOutput, runID: UUID, stepID: UUID) async throws {
        switch output {
        case .none:
            break
        case .progress(let text):
            try await store.appendEvent(
                runID: runID,
                stepID: stepID,
                kind: .progress,
                payload: .progress(text)
            )
        case .event(let kind, let payload):
            try await store.appendEvent(
                runID: runID,
                stepID: stepID,
                kind: kind,
                payload: payload
            )
        case .wait(let kind, let prompt, let risk):
            _ = try await store.createWait(
                runID: runID,
                stepID: stepID,
                kind: kind,
                prompt: prompt,
                risk: risk
            )
        case .sideEffect(let kind, let status, let proposalHash):
            _ = try await store.recordSideEffect(
                runID: runID,
                stepID: stepID,
                kind: kind,
                status: status,
                proposalHash: proposalHash
            )
        case .terminal(let status, let reason):
            try await store.updateRunStatus(
                runID: runID,
                status: status,
                reason: reason
            )
        }
    }

    private func executeWithDeadline(_ request: AgentRunnerStep) async throws -> AgentRunnerStepOutput {
        guard let timeout = request.timeout, timeout > 0 else {
            return try await request.operation()
        }

        return try await withThrowingTaskGroup(of: AgentRunnerStepOutput.self) { group in
            group.addTask {
                try await request.operation()
            }
            group.addTask {
                let nanoseconds = UInt64((timeout * 1_000_000_000).rounded(.up))
                try await Task.sleep(nanoseconds: nanoseconds)
                throw AgentRunnerError.stepTimedOut(kind: request.kind, timeout: timeout)
            }

            guard let result = try await group.next() else {
                throw AgentRunnerError.stepTimedOut(kind: request.kind, timeout: timeout)
            }
            group.cancelAll()
            return result
        }
    }

    private func markRunCanceled(runID: UUID) async throws {
        try await store.updateRunStatus(
            runID: runID,
            status: .canceled,
            reason: AgentRunText("Runner canceled.")
        )
        try await store.appendEvent(
            runID: runID,
            kind: .failure,
            payload: .metadata([
                "reason": .string("canceled")
            ])
        )
    }

    private func markRunInterrupted(
        runID: UUID,
        reason: AgentRunText,
        metadata: [String: AgentRunMetadataValue]
    ) async throws {
        try await store.updateRunStatus(
            runID: runID,
            status: .interrupted,
            reason: reason
        )
        try await store.appendEvent(
            runID: runID,
            kind: .failure,
            payload: .metadata(metadata)
        )
    }
}
