import CryptoKit
import Foundation

nonisolated enum AgentSideEffectError: Error, Equatable, CustomStringConvertible {
    case invalidDraft(String)
    case invalidApprovalState(String)
    case duplicateApproval(UUID)
    case missingProposalArtifact(UUID)
    case executionAlreadyCompleted(UUID)
    case duplicateExecution(UUID)
    case verificationFailed(String)
    case rollbackUnsupported(AgentRunSideEffectKind)
    case executionFailed(String)

    var description: String {
        switch self {
        case .invalidDraft(let summary):
            "Invalid side-effect draft: \(summary)"
        case .invalidApprovalState(let summary):
            "Invalid approval state: \(summary)"
        case .duplicateApproval(let waitID):
            "Approval wait \(waitID) has already been resolved."
        case .missingProposalArtifact(let artifactID):
            "Missing side-effect proposal artifact \(artifactID)."
        case .executionAlreadyCompleted(let sideEffectID):
            "Side effect \(sideEffectID) has already completed."
        case .duplicateExecution(let sideEffectID):
            "A matching side effect has already executed as \(sideEffectID)."
        case .verificationFailed(let summary):
            "Side-effect verification failed: \(summary)"
        case .rollbackUnsupported(let kind):
            "Rollback is not supported for \(kind.rawValue)."
        case .executionFailed(let summary):
            "Side-effect execution failed: \(summary)"
        }
    }
}

nonisolated enum AgentFileWriteOperation: String, Codable, Equatable, Sendable {
    case create
    case replace
    case append
}

nonisolated struct AgentFileWriteDraft: Codable, Equatable, Sendable {
    let operation: AgentFileWriteOperation
    let targetPath: String
    let content: String

    init(operation: AgentFileWriteOperation, targetPath: String, content: String) {
        self.operation = operation
        self.targetPath = targetPath
        self.content = content
    }
}

nonisolated struct AgentCommandDraft: Codable, Equatable, Sendable {
    let command: String
    let workingDirectory: String
    let timeoutSeconds: Int

    init(command: String, workingDirectory: String, timeoutSeconds: Int = 30) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.timeoutSeconds = max(1, timeoutSeconds)
    }
}

nonisolated struct AgentProcessStartDraft: Codable, Equatable, Sendable {
    let command: String
    let workingDirectory: String
    let processID: String?

    init(command: String, workingDirectory: String, processID: String? = nil) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.processID = processID
    }
}

nonisolated struct AgentProcessStopDraft: Codable, Equatable, Sendable {
    let processID: String

    init(processID: String) {
        self.processID = processID
    }
}

nonisolated enum AgentSideEffectDraft: Codable, Equatable, Sendable {
    case fileWrite(AgentFileWriteDraft)
    case command(AgentCommandDraft)
    case processStart(AgentProcessStartDraft)
    case processStop(AgentProcessStopDraft)

    var kind: AgentRunSideEffectKind {
        switch self {
        case .fileWrite:
            .fileWrite
        case .command:
            .command
        case .processStart:
            .processStart
        case .processStop:
            .processStop
        }
    }

    var risk: String {
        switch self {
        case .fileWrite:
            "file-write"
        case .command:
            "command"
        case .processStart, .processStop:
            "process-control"
        }
    }

    var approvalPrompt: AgentRunText {
        switch self {
        case .fileWrite(let draft):
            AgentRunText("\(draft.operation.rawValue) \(draft.targetPath)")
        case .command(let draft):
            AgentRunText("Run command in \(draft.workingDirectory): \(draft.command)")
        case .processStart(let draft):
            AgentRunText("Start process in \(draft.workingDirectory): \(draft.command)")
        case .processStop(let draft):
            AgentRunText("Stop process \(draft.processID)")
        }
    }

    var metadata: [String: AgentRunMetadataValue] {
        switch self {
        case .fileWrite(let draft):
            [
                "operation": .string(draft.operation.rawValue),
                "targetPath": .string(draft.targetPath)
            ]
        case .command(let draft):
            [
                "command": .string(draft.command),
                "workingDirectory": .string(draft.workingDirectory),
                "timeoutSeconds": .int(draft.timeoutSeconds)
            ]
        case .processStart(let draft):
            [
                "command": .string(draft.command),
                "workingDirectory": .string(draft.workingDirectory),
                "processID": .string(draft.processID ?? "")
            ]
        case .processStop(let draft):
            [
                "processID": .string(draft.processID)
            ]
        }
    }
}

nonisolated struct AgentSideEffectProposal: Codable, Equatable, Sendable {
    let sideEffectID: UUID
    let draft: AgentSideEffectDraft
    let proposalHash: String
    let createdAt: Date
}

nonisolated struct AgentSideEffectStageResult: Codable, Equatable, Sendable {
    let sideEffect: AgentRunSideEffectRecord
    let wait: AgentRunWaitRecord
    let proposalArtifact: AgentRunArtifactRecord
}

nonisolated enum AgentSideEffectApprovalDecision: String, Codable, Equatable, Sendable {
    case approved
    case denied
    case canceled
}

nonisolated struct AgentFileSnapshot: Codable, Equatable, Sendable {
    let path: String
    let exists: Bool
    let isDirectory: Bool
    let content: Data?
    let byteCount: Int
    let contentHash: String?

    init(path: String, exists: Bool, isDirectory: Bool, content: Data?) {
        self.path = path
        self.exists = exists
        self.isDirectory = isDirectory
        self.content = content
        self.byteCount = content?.count ?? 0
        self.contentHash = content.map { AgentSideEffectHasher.sha256Hex($0) }
    }
}

nonisolated struct AgentCommandExecutionOutput: Codable, Equatable, Sendable {
    let command: String
    let workingDirectory: String
    let exitCode: Int32?
    let stdout: AgentRunText
    let stderr: AgentRunText
    let durationSeconds: Double
    let didTimeOut: Bool

    var succeeded: Bool {
        !didTimeOut && exitCode == 0
    }

    var summary: AgentRunText {
        if didTimeOut {
            return AgentRunText("Command timed out.")
        }
        return AgentRunText("Command exited with \(exitCode.map(String.init) ?? "unknown").")
    }

    var failureSummary: AgentRunText? {
        if didTimeOut {
            return AgentRunText("Command timed out.")
        }
        guard exitCode != 0 else { return nil }
        return AgentRunText("Command exited with non-zero status \(exitCode.map(String.init) ?? "unknown").")
    }
}

nonisolated struct AgentProcessExecutionOutput: Codable, Equatable, Sendable {
    let processID: String
    let command: String?
    let status: String
    let summary: AgentRunText
}

nonisolated enum AgentSideEffectHasher {
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

protocol AgentCommandExecuting: Sendable {
    nonisolated func run(command: String, workingDirectory: String, timeoutSeconds: Int) async throws -> AgentCommandExecutionOutput
}

protocol AgentManagedProcessExecuting: Sendable {
    nonisolated func start(command: String, workingDirectory: String, processID: String?) async throws -> AgentProcessExecutionOutput
    nonisolated func stop(processID: String) async throws -> AgentProcessExecutionOutput
}

nonisolated struct AgentShellCommandExecutor: AgentCommandExecuting {
    let maxOutputBytes: Int

    init(maxOutputBytes: Int = 48_000) {
        self.maxOutputBytes = max(1, maxOutputBytes)
    }

    func run(command: String, workingDirectory: String, timeoutSeconds: Int) async throws -> AgentCommandExecutionOutput {
        try await Task.detached(priority: .utility) {
            try runBlocking(command: command, workingDirectory: workingDirectory, timeoutSeconds: timeoutSeconds)
        }.value
    }

    private func runBlocking(command: String, workingDirectory: String, timeoutSeconds: Int) throws -> AgentCommandExecutionOutput {
        let startedAt = Date()
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let collector = AgentSideEffectCommandOutputCollector(maxBytes: maxOutputBytes)

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", Self.shellScript(for: command)]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory).standardizedFileURL
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            collector.appendStdout(handle.availableData)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            collector.appendStderr(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw AgentSideEffectError.executionFailed(error.localizedDescription)
        }

        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            finished.signal()
        }

        let didTimeOut = finished.wait(timeout: .now() + .seconds(max(1, timeoutSeconds))) == .timedOut
        if didTimeOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + .milliseconds(750))
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        collector.appendStdout((try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data())
        collector.appendStderr((try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data())

        return AgentCommandExecutionOutput(
            command: command,
            workingDirectory: workingDirectory,
            exitCode: didTimeOut ? nil : process.terminationStatus,
            stdout: AgentRunText(collector.stdoutText),
            stderr: AgentRunText(collector.stderrText),
            durationSeconds: Date().timeIntervalSince(startedAt),
            didTimeOut: didTimeOut
        )
    }

    private static func shellScript(for command: String) -> String {
        """
        set -o pipefail
        \(command)
        """
    }
}

nonisolated struct AgentUnconfiguredProcessExecutor: AgentManagedProcessExecuting {
    init() {}

    func start(command: String, workingDirectory: String, processID: String?) async throws -> AgentProcessExecutionOutput {
        throw AgentSideEffectError.executionFailed("No managed process executor is configured.")
    }

    func stop(processID: String) async throws -> AgentProcessExecutionOutput {
        throw AgentSideEffectError.executionFailed("No managed process executor is configured.")
    }
}

actor AgentSideEffectController {
    private let store: AgentRunStore
    private let commandExecutor: any AgentCommandExecuting
    private let processExecutor: any AgentManagedProcessExecuting
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        store: AgentRunStore,
        commandExecutor: any AgentCommandExecuting = AgentShellCommandExecutor(),
        processExecutor: any AgentManagedProcessExecuting = AgentUnconfiguredProcessExecutor()
    ) {
        self.store = store
        self.commandExecutor = commandExecutor
        self.processExecutor = processExecutor
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        decoder = JSONDecoder()
    }

    func stage(
        runID: UUID,
        stepID: UUID? = nil,
        draft: AgentSideEffectDraft,
        createdAt: Date = Date()
    ) async throws -> AgentSideEffectStageResult {
        try validate(draft)

        let sideEffectID = UUID()
        let proposalHash = try proposalHash(for: draft)
        let proposal = AgentSideEffectProposal(
            sideEffectID: sideEffectID,
            draft: draft,
            proposalHash: proposalHash,
            createdAt: createdAt
        )
        let proposalData = try encoder.encode(proposal)
        let proposalArtifact = try await store.recordArtifact(
            runID: runID,
            stepID: stepID,
            kind: "side-effect-proposal",
            mimeType: "application/json",
            fileExtension: "json",
            data: proposalData,
            summary: AgentRunText("Side-effect proposal \(proposalHash.prefix(12))"),
            createdAt: createdAt
        )
        let wait = try await store.createWait(
            runID: runID,
            stepID: stepID,
            kind: .approval,
            prompt: draft.approvalPrompt,
            risk: draft.risk,
            createdAt: createdAt
        )
        let sideEffect = try await store.recordSideEffect(
            runID: runID,
            stepID: stepID,
            sideEffectID: sideEffectID,
            kind: draft.kind,
            status: .proposed,
            proposalHash: proposalHash,
            proposalArtifactID: proposalArtifact.artifactID,
            approvalWaitID: wait.waitID,
            metadata: draft.metadata,
            createdAt: createdAt
        )

        return AgentSideEffectStageResult(
            sideEffect: sideEffect,
            wait: wait,
            proposalArtifact: proposalArtifact
        )
    }

    func resolveApproval(
        sideEffectID: UUID,
        decision: AgentSideEffectApprovalDecision,
        summary: AgentRunText? = nil,
        resolvedAt: Date = Date()
    ) async throws -> AgentRunSideEffectRecord {
        let sideEffect = try await store.sideEffectRecord(sideEffectID: sideEffectID)
        guard let waitID = sideEffect.approvalWaitID else {
            throw AgentSideEffectError.invalidApprovalState("Side effect has no approval wait.")
        }
        let wait = try await store.waitRecord(waitID: waitID)
        guard wait.status == .pending else {
            if decision == .approved, wait.status == .approved, sideEffect.status == .approved {
                return sideEffect
            }
            if decision == .denied, wait.status == .denied, sideEffect.status == .denied {
                return sideEffect
            }
            throw AgentSideEffectError.duplicateApproval(waitID)
        }

        switch decision {
        case .approved:
            _ = try await store.resolveWait(
                waitID: waitID,
                status: .approved,
                summary: summary ?? AgentRunText("Approved."),
                resolvedAt: resolvedAt
            )
            return try await store.updateSideEffect(
                sideEffectID: sideEffectID,
                status: .approved,
                updatedAt: resolvedAt
            )
        case .denied:
            _ = try await store.resolveWait(
                waitID: waitID,
                status: .denied,
                summary: summary ?? AgentRunText("Denied."),
                resolvedAt: resolvedAt
            )
            return try await store.updateSideEffect(
                sideEffectID: sideEffectID,
                status: .denied,
                completedAt: resolvedAt,
                updatedAt: resolvedAt
            )
        case .canceled:
            _ = try await store.resolveWait(
                waitID: waitID,
                status: .canceled,
                summary: summary ?? AgentRunText("Canceled."),
                resolvedAt: resolvedAt
            )
            return try await store.updateSideEffect(
                sideEffectID: sideEffectID,
                status: .canceled,
                completedAt: resolvedAt,
                updatedAt: resolvedAt
            )
        }
    }

    func executeApproved(sideEffectID: UUID, startedAt: Date = Date()) async throws -> AgentRunSideEffectRecord {
        let sideEffect = try await store.sideEffectRecord(sideEffectID: sideEffectID)
        if sideEffect.status == .completed {
            throw AgentSideEffectError.executionAlreadyCompleted(sideEffectID)
        }
        guard sideEffect.status == .approved else {
            throw AgentSideEffectError.invalidApprovalState("Side effect must be approved before execution.")
        }
        if let duplicate = await duplicateCompletedSideEffect(for: sideEffect) {
            throw AgentSideEffectError.duplicateExecution(duplicate.sideEffectID)
        }

        let proposal = try await proposal(for: sideEffect)
        switch proposal.draft {
        case .fileWrite(let draft):
            return try await executeFileWrite(sideEffect: sideEffect, draft: draft, startedAt: startedAt)
        case .command(let draft):
            return try await executeCommand(sideEffect: sideEffect, draft: draft, startedAt: startedAt)
        case .processStart(let draft):
            return try await executeProcessStart(sideEffect: sideEffect, draft: draft, startedAt: startedAt)
        case .processStop(let draft):
            return try await executeProcessStop(sideEffect: sideEffect, draft: draft, startedAt: startedAt)
        }
    }

    func rollback(sideEffectID: UUID, rolledBackAt: Date = Date()) async throws -> AgentRunSideEffectRecord {
        let sideEffect = try await store.sideEffectRecord(sideEffectID: sideEffectID)
        guard sideEffect.status == .completed || sideEffect.status == .failed else {
            throw AgentSideEffectError.invalidApprovalState("Only completed or failed side effects can be rolled back.")
        }
        let proposal = try await proposal(for: sideEffect)

        switch proposal.draft {
        case .fileWrite:
            guard let beforeArtifactID = sideEffect.beforeArtifactID else {
                throw AgentSideEffectError.rollbackUnsupported(.fileWrite)
            }
            let snapshot = try decoder.decode(AgentFileSnapshot.self, from: try await store.readArtifact(beforeArtifactID))
            try restore(snapshot)
            let rollbackSnapshot = try fileSnapshot(path: snapshot.path)
            let rollbackArtifact = try await store.recordArtifact(
                runID: sideEffect.runID,
                stepID: sideEffect.stepID,
                kind: "side-effect-rollback",
                mimeType: "application/json",
                fileExtension: "json",
                data: try encoder.encode(rollbackSnapshot),
                summary: AgentRunText("Rollback snapshot for \(snapshot.path)"),
                createdAt: rolledBackAt
            )
            return try await store.updateSideEffect(
                sideEffectID: sideEffectID,
                status: .rolledBack,
                afterArtifactID: rollbackArtifact.artifactID,
                completedAt: rolledBackAt,
                updatedAt: rolledBackAt
            )
        case .processStart:
            let processID = sideEffect.metadata["processID"]?.stringValue
            guard let processID, !processID.isEmpty else {
                throw AgentSideEffectError.rollbackUnsupported(.processStart)
            }
            _ = try await processExecutor.stop(processID: processID)
            return try await store.updateSideEffect(
                sideEffectID: sideEffectID,
                status: .rolledBack,
                completedAt: rolledBackAt,
                updatedAt: rolledBackAt
            )
        case .command, .processStop:
            throw AgentSideEffectError.rollbackUnsupported(sideEffect.kind)
        }
    }

    private func executeFileWrite(
        sideEffect: AgentRunSideEffectRecord,
        draft: AgentFileWriteDraft,
        startedAt: Date
    ) async throws -> AgentRunSideEffectRecord {
        let beforeSnapshot = try fileSnapshot(path: draft.targetPath)
        let beforeArtifact = try await store.recordArtifact(
            runID: sideEffect.runID,
            stepID: sideEffect.stepID,
            kind: "side-effect-before",
            mimeType: "application/json",
            fileExtension: "json",
            data: try encoder.encode(beforeSnapshot),
            summary: AgentRunText("Before snapshot for \(draft.targetPath)"),
            createdAt: startedAt
        )
        _ = try await store.updateSideEffect(
            sideEffectID: sideEffect.sideEffectID,
            status: .running,
            beforeArtifactID: beforeArtifact.artifactID,
            startedAt: startedAt,
            updatedAt: startedAt
        )

        do {
            try apply(draft)
            try verify(draft: draft, beforeSnapshot: beforeSnapshot)
            let afterSnapshot = try fileSnapshot(path: draft.targetPath)
            let afterArtifact = try await store.recordArtifact(
                runID: sideEffect.runID,
                stepID: sideEffect.stepID,
                kind: "side-effect-after",
                mimeType: "application/json",
                fileExtension: "json",
                data: try encoder.encode(afterSnapshot),
                summary: AgentRunText("After snapshot for \(draft.targetPath)")
            )
            return try await store.updateSideEffect(
                sideEffectID: sideEffect.sideEffectID,
                status: .completed,
                afterArtifactID: afterArtifact.artifactID,
                completedAt: Date(),
                updatedAt: Date()
            )
        } catch {
            return try await markExecutionFailed(sideEffect, error: error)
        }
    }

    private func executeCommand(
        sideEffect: AgentRunSideEffectRecord,
        draft: AgentCommandDraft,
        startedAt: Date
    ) async throws -> AgentRunSideEffectRecord {
        _ = try await store.updateSideEffect(
            sideEffectID: sideEffect.sideEffectID,
            status: .running,
            startedAt: startedAt,
            updatedAt: startedAt
        )

        do {
            let output = try await commandExecutor.run(
                command: draft.command,
                workingDirectory: draft.workingDirectory,
                timeoutSeconds: draft.timeoutSeconds
            )
            let outputData = try encoder.encode(output)
            let artifact = try await store.recordArtifact(
                runID: sideEffect.runID,
                stepID: sideEffect.stepID,
                kind: "side-effect-command-output",
                mimeType: "application/json",
                fileExtension: "json",
                data: outputData,
                summary: output.summary
            )
            return try await store.updateSideEffect(
                sideEffectID: sideEffect.sideEffectID,
                status: output.succeeded ? .completed : .failed,
                afterArtifactID: artifact.artifactID,
                completedAt: Date(),
                errorSummary: output.failureSummary,
                updatedAt: Date()
            )
        } catch {
            return try await markExecutionFailed(sideEffect, error: error)
        }
    }

    private func executeProcessStart(
        sideEffect: AgentRunSideEffectRecord,
        draft: AgentProcessStartDraft,
        startedAt: Date
    ) async throws -> AgentRunSideEffectRecord {
        _ = try await store.updateSideEffect(
            sideEffectID: sideEffect.sideEffectID,
            status: .running,
            startedAt: startedAt,
            updatedAt: startedAt
        )

        do {
            let output = try await processExecutor.start(
                command: draft.command,
                workingDirectory: draft.workingDirectory,
                processID: draft.processID
            )
            let artifact = try await store.recordArtifact(
                runID: sideEffect.runID,
                stepID: sideEffect.stepID,
                kind: "side-effect-process-start",
                mimeType: "application/json",
                fileExtension: "json",
                data: try encoder.encode(output),
                summary: output.summary
            )
            var metadata = sideEffect.metadata
            metadata["processID"] = .string(output.processID)
            return try await store.updateSideEffect(
                sideEffectID: sideEffect.sideEffectID,
                status: .completed,
                afterArtifactID: artifact.artifactID,
                completedAt: Date(),
                metadata: metadata,
                updatedAt: Date()
            )
        } catch {
            return try await markExecutionFailed(sideEffect, error: error)
        }
    }

    private func executeProcessStop(
        sideEffect: AgentRunSideEffectRecord,
        draft: AgentProcessStopDraft,
        startedAt: Date
    ) async throws -> AgentRunSideEffectRecord {
        _ = try await store.updateSideEffect(
            sideEffectID: sideEffect.sideEffectID,
            status: .running,
            startedAt: startedAt,
            updatedAt: startedAt
        )

        do {
            let output = try await processExecutor.stop(processID: draft.processID)
            let artifact = try await store.recordArtifact(
                runID: sideEffect.runID,
                stepID: sideEffect.stepID,
                kind: "side-effect-process-stop",
                mimeType: "application/json",
                fileExtension: "json",
                data: try encoder.encode(output),
                summary: output.summary
            )
            return try await store.updateSideEffect(
                sideEffectID: sideEffect.sideEffectID,
                status: .completed,
                afterArtifactID: artifact.artifactID,
                completedAt: Date(),
                updatedAt: Date()
            )
        } catch {
            return try await markExecutionFailed(sideEffect, error: error)
        }
    }

    private func markExecutionFailed(
        _ sideEffect: AgentRunSideEffectRecord,
        error: Error
    ) async throws -> AgentRunSideEffectRecord {
        try await store.updateSideEffect(
            sideEffectID: sideEffect.sideEffectID,
            status: .failed,
            completedAt: Date(),
            errorSummary: AgentRunText(String(describing: error)),
            updatedAt: Date()
        )
    }

    private func proposal(for sideEffect: AgentRunSideEffectRecord) async throws -> AgentSideEffectProposal {
        guard let artifactID = sideEffect.proposalArtifactID else {
            throw AgentSideEffectError.invalidApprovalState("Side effect has no proposal artifact.")
        }
        do {
            return try decoder.decode(AgentSideEffectProposal.self, from: try await store.readArtifact(artifactID))
        } catch AgentRunStoreError.missingArtifact {
            throw AgentSideEffectError.missingProposalArtifact(artifactID)
        }
    }

    private func duplicateCompletedSideEffect(for sideEffect: AgentRunSideEffectRecord) async -> AgentRunSideEffectRecord? {
        guard let proposalHash = sideEffect.proposalHash else { return nil }
        let candidates = await store.sideEffects(runID: sideEffect.runID)
        return candidates.first { candidate in
            candidate.sideEffectID != sideEffect.sideEffectID
                && candidate.proposalHash == proposalHash
                && candidate.status == .completed
        }
    }

    private func validate(_ draft: AgentSideEffectDraft) throws {
        switch draft {
        case .fileWrite(let draft):
            let path = draft.targetPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard path.hasPrefix("/") else {
                throw AgentSideEffectError.invalidDraft("File write target must be an absolute path.")
            }
            guard !draft.content.isEmpty else {
                throw AgentSideEffectError.invalidDraft("File write content cannot be empty.")
            }
            guard draft.content.utf8.count <= 200_000 else {
                throw AgentSideEffectError.invalidDraft("File write content is too large for a single approved side effect.")
            }
            try validateCheapSyntax(path: path, content: draft.content)
        case .command(let draft):
            guard !draft.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AgentSideEffectError.invalidDraft("Command cannot be empty.")
            }
            try validateDirectory(draft.workingDirectory)
        case .processStart(let draft):
            guard !draft.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AgentSideEffectError.invalidDraft("Process command cannot be empty.")
            }
            try validateDirectory(draft.workingDirectory)
        case .processStop(let draft):
            guard !draft.processID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AgentSideEffectError.invalidDraft("Process ID cannot be empty.")
            }
        }
    }

    private func validateDirectory(_ path: String) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw AgentSideEffectError.invalidDraft("Working directory does not exist.")
        }
    }

    private func validateCheapSyntax(path: String, content: String) throws {
        if path.hasSuffix(".json") {
            guard let data = content.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: data)) != nil else {
                throw AgentSideEffectError.invalidDraft("JSON content does not parse.")
            }
        }
        if path.hasSuffix(".plist") {
            guard let data = content.data(using: .utf8),
                  (try? PropertyListSerialization.propertyList(from: data, format: nil)) != nil else {
                throw AgentSideEffectError.invalidDraft("Property list content does not parse.")
            }
        }
        if path.hasSuffix(".py") {
            let suspiciousMarkers = [
                "\nnimport ",
                "\nnfrom ",
                "\nndef ",
                "\nnclass ",
                "\nndir_path",
                "\nnfile_path",
                "nimport os",
                "ndir_path =",
                "nfile_path ="
            ]
            if suspiciousMarkers.contains(where: { content.contains($0) }) {
                throw AgentSideEffectError.invalidDraft("Python content contains generated newline marker artifacts.")
            }
        }
        if content.contains("\u{0000}") {
            throw AgentSideEffectError.invalidDraft("File content cannot contain null bytes.")
        }
    }

    private func proposalHash(for draft: AgentSideEffectDraft) throws -> String {
        try AgentSideEffectHasher.sha256Hex(encoder.encode(draft))
    }

    private func fileSnapshot(path: String) throws -> AgentFileSnapshot {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists else {
            return AgentFileSnapshot(path: url.path, exists: false, isDirectory: false, content: nil)
        }
        guard !isDirectory.boolValue else {
            return AgentFileSnapshot(path: url.path, exists: true, isDirectory: true, content: nil)
        }
        return AgentFileSnapshot(
            path: url.path,
            exists: true,
            isDirectory: false,
            content: try Data(contentsOf: url)
        )
    }

    private func apply(_ draft: AgentFileWriteDraft) throws {
        let url = URL(fileURLWithPath: draft.targetPath).standardizedFileURL
        let contentData = Data(draft.content.utf8)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            throw AgentSideEffectError.executionFailed("Target path is a directory.")
        }

        switch draft.operation {
        case .create:
            guard !exists else {
                throw AgentSideEffectError.executionFailed("Create target already exists.")
            }
            guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) else {
                throw AgentSideEffectError.executionFailed("Create target parent directory does not exist.")
            }
            try contentData.write(to: url, options: .atomic)
        case .replace:
            guard exists else {
                throw AgentSideEffectError.executionFailed("Replace target does not exist.")
            }
            try contentData.write(to: url, options: .atomic)
        case .append:
            guard exists else {
                throw AgentSideEffectError.executionFailed("Append target does not exist.")
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: contentData)
        }
    }

    private func verify(draft: AgentFileWriteDraft, beforeSnapshot: AgentFileSnapshot) throws {
        let url = URL(fileURLWithPath: draft.targetPath).standardizedFileURL
        let afterData = try Data(contentsOf: url)
        let expectedData = Data(draft.content.utf8)

        switch draft.operation {
        case .create, .replace:
            guard afterData == expectedData else {
                throw AgentSideEffectError.verificationFailed("Written file content does not match the approved proposal.")
            }
        case .append:
            guard Data(afterData.suffix(expectedData.count)) == expectedData else {
                throw AgentSideEffectError.verificationFailed("Appended file content is not present at the end of the target.")
            }
            if let before = beforeSnapshot.content {
                guard afterData.prefix(before.count) == before else {
                    throw AgentSideEffectError.verificationFailed("Append modified existing content before the appended bytes.")
                }
            }
        }
    }

    private func restore(_ snapshot: AgentFileSnapshot) throws {
        let url = URL(fileURLWithPath: snapshot.path).standardizedFileURL
        if !snapshot.exists {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return
        }
        guard !snapshot.isDirectory else {
            throw AgentSideEffectError.rollbackUnsupported(.fileWrite)
        }
        guard let content = snapshot.content else {
            throw AgentSideEffectError.rollbackUnsupported(.fileWrite)
        }
        try content.write(to: url, options: .atomic)
    }
}

private final class AgentSideEffectCommandOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let maxBytes: Int
    private nonisolated(unsafe) var stdoutData = Data()
    private nonisolated(unsafe) var stderrData = Data()

    nonisolated init(maxBytes: Int) {
        self.maxBytes = max(1, maxBytes)
    }

    nonisolated func appendStdout(_ data: Data) {
        append(data, to: &stdoutData)
    }

    nonisolated func appendStderr(_ data: Data) {
        append(data, to: &stderrData)
    }

    nonisolated var stdoutText: String {
        text(from: stdoutData)
    }

    nonisolated var stderrText: String {
        text(from: stderrData)
    }

    private nonisolated func append(_ data: Data, to target: inout Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        let remaining = max(0, maxBytes - target.count)
        target.append(data.prefix(remaining))
    }

    private nonisolated func text(from data: Data) -> String {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii)
            ?? String(decoding: data, as: UTF8.self)
    }
}
