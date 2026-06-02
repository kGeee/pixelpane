import Foundation

nonisolated enum AgentRunStoreError: Error, Equatable, CustomStringConvertible {
    case missingSession(UUID)
    case missingRun(UUID)
    case missingStep(UUID)
    case missingWait(UUID)
    case missingArtifact(UUID)
    case missingSideEffect(UUID)
    case unsupportedSchemaVersion(Int)
    case invalidArtifactPath(String)
    case persistence(String)

    var description: String {
        switch self {
        case .missingSession(let id):
            "Missing agent session \(id)."
        case .missingRun(let id):
            "Missing agent run \(id)."
        case .missingStep(let id):
            "Missing agent step \(id)."
        case .missingWait(let id):
            "Missing agent wait \(id)."
        case .missingArtifact(let id):
            "Missing agent artifact \(id)."
        case .missingSideEffect(let id):
            "Missing agent side effect \(id)."
        case .unsupportedSchemaVersion(let version):
            "Unsupported agent run store schema version \(version)."
        case .invalidArtifactPath(let path):
            "Invalid agent artifact path \(path)."
        case .persistence(let summary):
            "Agent run store persistence failed: \(summary)"
        }
    }
}

actor AgentRunStore {
    private let rootDirectory: URL
    private let snapshotURL: URL
    private let artifactsDirectory: URL
    private let persistence: AgentRunStorePersistenceBackend
    private var snapshot: AgentRunStoreSnapshot
    private let decoder: JSONDecoder

    init(rootDirectory: URL? = nil) throws {
        let resolvedRoot = try rootDirectory ?? Self.defaultRootDirectory()
        self.rootDirectory = resolvedRoot
        snapshotURL = resolvedRoot.appendingPathComponent("store.json", isDirectory: false)
        artifactsDirectory = resolvedRoot.appendingPathComponent("Artifacts", isDirectory: true)
        persistence = try AgentRunSQLitePersistenceBackend(rootDirectory: resolvedRoot)

        decoder = JSONDecoder()

        try FileManager.default.createDirectory(at: resolvedRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: artifactsDirectory, withIntermediateDirectories: true)

        if try persistence.hasStoredSnapshot() {
            snapshot = try Self.migratedSnapshot(persistence.loadSnapshot())
        } else if FileManager.default.fileExists(atPath: snapshotURL.path) {
            let data = try Data(contentsOf: snapshotURL)
            let decoded = try decoder.decode(AgentRunStoreSnapshot.self, from: data)
            snapshot = try Self.migratedSnapshot(decoded)
            try persistence.saveSnapshot(snapshot)
        } else {
            snapshot = AgentRunStoreSnapshot()
            try persistence.saveSnapshot(snapshot)
        }
    }

    nonisolated static func defaultRootDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("PixelPane", isDirectory: true)
            .appendingPathComponent("AgentRuns", isDirectory: true)
    }

    func schemaVersion() -> Int {
        snapshot.schemaVersion
    }

    func createSession(
        title: String,
        contextID: String? = nil,
        contextKind: String? = nil,
        createdAt: Date = Date()
    ) throws -> AgentRunSessionRecord {
        let session = AgentRunSessionRecord(
            title: title,
            contextID: contextID,
            contextKind: contextKind,
            createdAt: createdAt
        )
        snapshot.sessions.append(session)
        try persist()
        return session
    }

    func createRun(
        sessionID: UUID,
        status: AgentRunStatus = .draft,
        createdAt: Date = Date()
    ) throws -> AgentRunRecord {
        guard snapshot.sessions.contains(where: { $0.id == sessionID }) else {
            throw AgentRunStoreError.missingSession(sessionID)
        }

        let run = AgentRunRecord(
            sessionID: sessionID,
            status: status,
            createdAt: createdAt
        )
        snapshot.runs.append(run)
        touchSession(sessionID, at: createdAt)
        try persist()
        return run
    }

    func beginStep(
        runID: UUID,
        kind: AgentRunStepKind,
        createdAt: Date = Date(),
        metadata: [String: AgentRunMetadataValue] = [:]
    ) throws -> AgentRunStepRecord {
        guard let runIndex = snapshot.runs.firstIndex(where: { $0.runID == runID }) else {
            throw AgentRunStoreError.missingRun(runID)
        }

        let run = snapshot.runs[runIndex]
        let step = AgentRunStepRecord(
            sessionID: run.sessionID,
            runID: run.runID,
            kind: kind,
            status: .running,
            createdAt: createdAt,
            metadata: metadata
        )
        snapshot.steps.append(step)
        snapshot.runs[runIndex].activeStepID = step.stepID
        snapshot.runs[runIndex].updatedAt = createdAt
        touchSession(run.sessionID, at: createdAt)
        _ = try appendEventWithoutPersisting(
            runID: runID,
            stepID: step.stepID,
            kind: .stepStarted,
            payload: .step(step),
            createdAt: createdAt
        )
        try persist()
        return step
    }

    func finishStep(
        stepID: UUID,
        status: AgentRunStepStatus = .completed,
        finishedAt: Date = Date()
    ) throws -> AgentRunStepRecord {
        guard let stepIndex = snapshot.steps.firstIndex(where: { $0.stepID == stepID }) else {
            throw AgentRunStoreError.missingStep(stepID)
        }

        snapshot.steps[stepIndex].status = status
        snapshot.steps[stepIndex].updatedAt = finishedAt
        let step = snapshot.steps[stepIndex]

        if let runIndex = snapshot.runs.firstIndex(where: { $0.runID == step.runID }) {
            if snapshot.runs[runIndex].activeStepID == stepID {
                snapshot.runs[runIndex].activeStepID = nil
            }
            snapshot.runs[runIndex].updatedAt = finishedAt
            touchSession(snapshot.runs[runIndex].sessionID, at: finishedAt)
        }

        _ = try appendEventWithoutPersisting(
            runID: step.runID,
            stepID: stepID,
            kind: .stepCompleted,
            payload: .step(step),
            createdAt: finishedAt
        )
        try persist()
        return step
    }

    @discardableResult
    func appendEvent(
        runID: UUID,
        stepID: UUID? = nil,
        kind: AgentRunEventKind,
        payload: AgentRunEventPayload,
        createdAt: Date = Date()
    ) throws -> AgentRunEventRecord {
        let event = try appendEventWithoutPersisting(
            runID: runID,
            stepID: stepID,
            kind: kind,
            payload: payload,
            createdAt: createdAt
        )
        try persist()
        return event
    }

    @discardableResult
    func updateRunStatus(
        runID: UUID,
        status: AgentRunStatus,
        reason: AgentRunText? = nil,
        createdAt: Date = Date(),
        allowsTerminalTransition: Bool = false
    ) throws -> AgentRunEventRecord? {
        guard let runIndex = snapshot.runs.firstIndex(where: { $0.runID == runID }) else {
            throw AgentRunStoreError.missingRun(runID)
        }

        let currentStatus = snapshot.runs[runIndex].status
        if currentStatus.isTerminal,
           currentStatus != status,
           !allowsTerminalTransition {
            return nil
        }

        snapshot.runs[runIndex].status = status
        snapshot.runs[runIndex].updatedAt = createdAt
        touchSession(snapshot.runs[runIndex].sessionID, at: createdAt)

        let event = try appendEventWithoutPersisting(
            runID: runID,
            kind: .statusChanged,
            payload: .status(status, reason: reason),
            createdAt: createdAt
        )
        try persist()
        return event
    }

    func createWait(
        runID: UUID,
        stepID: UUID? = nil,
        kind: AgentRunWaitKind,
        prompt: AgentRunText,
        risk: String? = nil,
        createdAt: Date = Date()
    ) throws -> AgentRunWaitRecord {
        guard let runIndex = snapshot.runs.firstIndex(where: { $0.runID == runID }) else {
            throw AgentRunStoreError.missingRun(runID)
        }

        let run = snapshot.runs[runIndex]
        let wait = AgentRunWaitRecord(
            sessionID: run.sessionID,
            runID: run.runID,
            stepID: stepID,
            kind: kind,
            prompt: prompt,
            risk: risk,
            createdAt: createdAt
        )
        snapshot.waits.append(wait)
        snapshot.runs[runIndex].status = kind == .approval ? .waitingForApproval : .waitingForUserInput
        snapshot.runs[runIndex].updatedAt = createdAt
        touchSession(run.sessionID, at: createdAt)
        _ = try appendEventWithoutPersisting(
            runID: runID,
            stepID: stepID,
            kind: .waitCreated,
            payload: .wait(wait),
            createdAt: createdAt
        )
        try persist()
        return wait
    }

    func resolveWait(
        waitID: UUID,
        status: AgentRunWaitStatus,
        summary: AgentRunText? = nil,
        resolvedAt: Date = Date()
    ) throws -> AgentRunWaitRecord {
        guard let waitIndex = snapshot.waits.firstIndex(where: { $0.waitID == waitID }) else {
            throw AgentRunStoreError.missingWait(waitID)
        }

        snapshot.waits[waitIndex].status = status
        snapshot.waits[waitIndex].resolvedAt = resolvedAt
        snapshot.waits[waitIndex].resolutionSummary = summary
        let wait = snapshot.waits[waitIndex]

        if let runIndex = snapshot.runs.firstIndex(where: { $0.runID == wait.runID }) {
            switch status {
            case .approved, .resolved:
                snapshot.runs[runIndex].status = .queued
            case .denied:
                snapshot.runs[runIndex].status = .blocked
            case .canceled:
                snapshot.runs[runIndex].status = .canceled
            case .pending:
                break
            }
            snapshot.runs[runIndex].updatedAt = resolvedAt
            touchSession(snapshot.runs[runIndex].sessionID, at: resolvedAt)
        }

        _ = try appendEventWithoutPersisting(
            runID: wait.runID,
            stepID: wait.stepID,
            kind: .waitResolved,
            payload: .wait(wait),
            createdAt: resolvedAt
        )
        try persist()
        return wait
    }

    func waitRecord(waitID: UUID) throws -> AgentRunWaitRecord {
        guard let wait = snapshot.waits.first(where: { $0.waitID == waitID }) else {
            throw AgentRunStoreError.missingWait(waitID)
        }
        return wait
    }

    func recordArtifact(
        runID: UUID,
        stepID: UUID? = nil,
        kind: String,
        mimeType: String = "application/octet-stream",
        fileExtension: String? = nil,
        data: Data,
        summary: AgentRunText? = nil,
        createdAt: Date = Date()
    ) throws -> AgentRunArtifactRecord {
        guard let run = snapshot.runs.first(where: { $0.runID == runID }) else {
            throw AgentRunStoreError.missingRun(runID)
        }

        let artifactID = UUID()
        let safeExtension = Self.safeArtifactExtension(fileExtension)
        let fileName = safeExtension.map { "\(artifactID.uuidString).\($0)" } ?? artifactID.uuidString
        let relativePath = "Artifacts/\(fileName)"
        let url = artifactsDirectory.appendingPathComponent(fileName, isDirectory: false)
        try data.write(to: url, options: .atomic)

        let artifact = AgentRunArtifactRecord(
            sessionID: run.sessionID,
            runID: run.runID,
            stepID: stepID,
            artifactID: artifactID,
            kind: kind,
            mimeType: mimeType,
            relativePath: relativePath,
            byteCount: data.count,
            createdAt: createdAt,
            summary: summary
        )
        snapshot.artifacts.append(artifact)
        _ = try appendEventWithoutPersisting(
            runID: runID,
            stepID: stepID,
            kind: .artifactRecorded,
            payload: .artifact(artifact),
            createdAt: createdAt
        )
        try persist()
        return artifact
    }

    func readArtifact(_ artifactID: UUID) throws -> Data {
        guard let artifact = snapshot.artifacts.first(where: { $0.artifactID == artifactID }) else {
            throw AgentRunStoreError.missingArtifact(artifactID)
        }

        let url = try artifactURL(relativePath: artifact.relativePath)
        return try Data(contentsOf: url)
    }

    func recordEvidence(
        runID: UUID,
        stepID: UUID? = nil,
        sourceID: String,
        kind: String,
        summary: AgentRunText,
        artifactID: UUID? = nil,
        metadata: [String: AgentRunMetadataValue] = [:],
        createdAt: Date = Date()
    ) throws -> AgentRunEvidenceRecord {
        guard let run = snapshot.runs.first(where: { $0.runID == runID }) else {
            throw AgentRunStoreError.missingRun(runID)
        }
        if let artifactID, !snapshot.artifacts.contains(where: { $0.artifactID == artifactID }) {
            throw AgentRunStoreError.missingArtifact(artifactID)
        }

        let evidence = AgentRunEvidenceRecord(
            sessionID: run.sessionID,
            runID: run.runID,
            stepID: stepID,
            evidenceID: UUID(),
            sourceID: sourceID,
            kind: kind,
            summary: summary,
            artifactID: artifactID,
            createdAt: createdAt,
            metadata: metadata
        )
        snapshot.evidence.append(evidence)
        _ = try appendEventWithoutPersisting(
            runID: runID,
            stepID: stepID,
            kind: .evidenceRecorded,
            payload: .evidence(evidence),
            createdAt: createdAt
        )
        try persist()
        return evidence
    }

    @discardableResult
    func recordControl(
        runID: UUID,
        stepID: UUID? = nil,
        kind: AgentRunControlRecordKind,
        payload: AgentRunControlPayload,
        metadata: [String: AgentRunMetadataValue] = [:],
        createdAt: Date = Date()
    ) throws -> AgentRunControlRecord {
        guard let run = snapshot.runs.first(where: { $0.runID == runID }) else {
            throw AgentRunStoreError.missingRun(runID)
        }
        if let stepID, !snapshot.steps.contains(where: { $0.stepID == stepID }) {
            throw AgentRunStoreError.missingStep(stepID)
        }

        let sequence = (snapshot.controlRecords
            .filter { $0.runID == runID }
            .map(\.sequence)
            .max() ?? -1) + 1
        let record = AgentRunControlRecord(
            sessionID: run.sessionID,
            runID: runID,
            stepID: stepID,
            sequence: sequence,
            kind: kind,
            payload: payload,
            createdAt: createdAt,
            metadata: metadata
        )
        snapshot.controlRecords.append(record)
        touchRun(runID, at: createdAt)
        try persist()
        return record
    }

    func recordSideEffect(
        runID: UUID,
        stepID: UUID? = nil,
        sideEffectID: UUID = UUID(),
        kind: AgentRunSideEffectKind,
        status: AgentRunSideEffectStatus,
        proposalHash: String? = nil,
        proposalArtifactID: UUID? = nil,
        approvalWaitID: UUID? = nil,
        beforeArtifactID: UUID? = nil,
        afterArtifactID: UUID? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        errorSummary: AgentRunText? = nil,
        metadata: [String: AgentRunMetadataValue] = [:],
        createdAt: Date = Date()
    ) throws -> AgentRunSideEffectRecord {
        guard let run = snapshot.runs.first(where: { $0.runID == runID }) else {
            throw AgentRunStoreError.missingRun(runID)
        }

        let sideEffect = AgentRunSideEffectRecord(
            sessionID: run.sessionID,
            runID: run.runID,
            stepID: stepID,
            sideEffectID: sideEffectID,
            kind: kind,
            status: status,
            proposalHash: proposalHash,
            proposalArtifactID: proposalArtifactID,
            approvalWaitID: approvalWaitID,
            beforeArtifactID: beforeArtifactID,
            afterArtifactID: afterArtifactID,
            createdAt: createdAt,
            startedAt: startedAt,
            completedAt: completedAt,
            updatedAt: createdAt,
            errorSummary: errorSummary,
            metadata: metadata
        )
        snapshot.sideEffects.append(sideEffect)
        _ = try appendEventWithoutPersisting(
            runID: runID,
            stepID: stepID,
            kind: .sideEffectRecorded,
            payload: .sideEffect(sideEffect),
            createdAt: createdAt
        )
        try persist()
        return sideEffect
    }

    func updateSideEffect(
        sideEffectID: UUID,
        status: AgentRunSideEffectStatus? = nil,
        beforeArtifactID: UUID? = nil,
        afterArtifactID: UUID? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        errorSummary: AgentRunText? = nil,
        metadata: [String: AgentRunMetadataValue]? = nil,
        updatedAt: Date = Date()
    ) throws -> AgentRunSideEffectRecord {
        guard let index = snapshot.sideEffects.firstIndex(where: { $0.sideEffectID == sideEffectID }) else {
            throw AgentRunStoreError.missingSideEffect(sideEffectID)
        }

        if let status {
            snapshot.sideEffects[index].status = status
        }
        if let beforeArtifactID {
            snapshot.sideEffects[index].beforeArtifactID = beforeArtifactID
        }
        if let afterArtifactID {
            snapshot.sideEffects[index].afterArtifactID = afterArtifactID
        }
        if let startedAt {
            snapshot.sideEffects[index].startedAt = startedAt
        }
        if let completedAt {
            snapshot.sideEffects[index].completedAt = completedAt
        }
        if let errorSummary {
            snapshot.sideEffects[index].errorSummary = errorSummary
        }
        if let metadata {
            snapshot.sideEffects[index].metadata = metadata
        }
        snapshot.sideEffects[index].updatedAt = updatedAt
        let sideEffect = snapshot.sideEffects[index]
        touchRun(sideEffect.runID, at: updatedAt)
        _ = try appendEventWithoutPersisting(
            runID: sideEffect.runID,
            stepID: sideEffect.stepID,
            kind: .sideEffectRecorded,
            payload: .sideEffect(sideEffect),
            createdAt: updatedAt
        )
        try persist()
        return sideEffect
    }

    func sideEffectRecord(sideEffectID: UUID) throws -> AgentRunSideEffectRecord {
        guard let sideEffect = snapshot.sideEffects.first(where: { $0.sideEffectID == sideEffectID }) else {
            throw AgentRunStoreError.missingSideEffect(sideEffectID)
        }
        return sideEffect
    }

    func sideEffects(runID: UUID? = nil) -> [AgentRunSideEffectRecord] {
        snapshot.sideEffects
            .filter { sideEffect in runID == nil || sideEffect.runID == runID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func visibleMessages(sessionID: UUID? = nil) -> [AgentRunVisibleMessage] {
        snapshot.events
            .filter { event in
                sessionID == nil || event.sessionID == sessionID
            }
            .compactMap { event -> AgentRunVisibleMessage? in
                switch (event.kind, event.payload) {
                case (.userMessage, .text(let text)):
                    AgentRunVisibleMessage(
                        id: event.eventID,
                        sessionID: event.sessionID,
                        runID: event.runID,
                        sequence: event.sequence,
                        role: .user,
                        text: text,
                        createdAt: event.createdAt
                    )
                case (.assistantMessage, .text(let text)):
                    AgentRunVisibleMessage(
                        id: event.eventID,
                        sessionID: event.sessionID,
                        runID: event.runID,
                        sequence: event.sequence,
                        role: .assistant,
                        text: text,
                        createdAt: event.createdAt
                    )
                default:
                    nil
                }
            }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    lhs.sequence < rhs.sequence
                } else {
                    lhs.createdAt < rhs.createdAt
                }
            }
    }

    func statusProjection(runID: UUID) throws -> AgentRunStatusProjection {
        guard let run = snapshot.runs.first(where: { $0.runID == runID }) else {
            throw AgentRunStoreError.missingRun(runID)
        }

        return AgentRunStatusProjection(
            sessionID: run.sessionID,
            runID: run.runID,
            status: run.status,
            activeStepID: run.activeStepID,
            updatedAt: run.updatedAt,
            latestProgress: latestProgress(runID: runID),
            pendingWaits: pendingWaits(runID: runID)
        )
    }

    func pendingWaits(runID: UUID? = nil) -> [AgentRunWaitRecord] {
        snapshot.waits
            .filter { wait in
                wait.status == .pending && (runID == nil || wait.runID == runID)
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func latestProgress(runID: UUID) -> AgentRunText? {
        snapshot.events
            .filter { $0.runID == runID && $0.kind == .progress }
            .sorted { $0.sequence < $1.sequence }
            .compactMap { event -> AgentRunText? in
                guard case .progress(let text) = event.payload else { return nil }
                return text
            }
            .last
    }

    func latestTerminalSummary(runID: UUID) -> AgentRunText? {
        let events = snapshot.events
            .filter { $0.runID == runID }
            .sorted { $0.sequence > $1.sequence }

        if let statusReason = events.compactMap({ event -> AgentRunText? in
            guard event.kind == .statusChanged,
                  case .status(let status, let reason) = event.payload,
                  status.isTerminal,
                  let reason,
                  !reason.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return nil
            }
            return reason
        }).first {
            return statusReason
        }

        return events.compactMap { event -> AgentRunText? in
            guard event.kind == .failure,
                  case .diagnostic(let text) = event.payload,
                  !text.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return nil
            }
            return text
        }.first
    }

    func evidenceArtifactSummary(runID: UUID) -> AgentRunEvidenceArtifactSummary {
        AgentRunEvidenceArtifactSummary(
            evidence: snapshot.evidence.filter { $0.runID == runID },
            artifacts: snapshot.artifacts.filter { $0.runID == runID }
        )
    }

    func controlRecords(runID: UUID? = nil) -> [AgentRunControlRecord] {
        snapshot.controlRecords
            .filter { record in runID == nil || record.runID == runID }
            .sorted { lhs, rhs in
                if lhs.runID == rhs.runID {
                    return lhs.sequence < rhs.sequence
                }
                if lhs.createdAt == rhs.createdAt {
                    return lhs.recordID.uuidString < rhs.recordID.uuidString
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    func latestModelRequest(runID: UUID) -> AgentModelGatewayRequest? {
        controlRecords(runID: runID)
            .reversed()
            .compactMap { record -> AgentModelGatewayRequest? in
                guard case .modelRequest(let request) = record.payload else { return nil }
                return request
            }
            .first
    }

    func replayMessages(runID: UUID) -> [AgentKernelMessageV2] {
        latestModelRequest(runID: runID)?.messages ?? []
    }

    func traceProjection(runID: UUID) throws -> AgentRunTraceProjection {
        guard let run = snapshot.runs.first(where: { $0.runID == runID }) else {
            throw AgentRunStoreError.missingRun(runID)
        }

        return AgentRunTraceProjection(
            session: snapshot.sessions.first { $0.id == run.sessionID },
            run: run,
            steps: snapshot.steps.filter { $0.runID == runID }.sorted { $0.createdAt < $1.createdAt },
            waits: snapshot.waits.filter { $0.runID == runID }.sorted { $0.createdAt < $1.createdAt },
            artifacts: snapshot.artifacts.filter { $0.runID == runID }.sorted { $0.createdAt < $1.createdAt },
            evidence: snapshot.evidence.filter { $0.runID == runID }.sorted { $0.createdAt < $1.createdAt },
            sideEffects: snapshot.sideEffects.filter { $0.runID == runID }.sorted { $0.createdAt < $1.createdAt },
            controlRecords: snapshot.controlRecords.filter { $0.runID == runID }.sorted { $0.sequence < $1.sequence },
            events: snapshot.events.filter { $0.runID == runID }.sorted { $0.sequence < $1.sequence }
        )
    }

    func runsNeedingLaunchRecovery() -> [AgentRunRecord] {
        snapshot.runs
            .filter { $0.status.requiresLaunchRecovery }
            .sorted { $0.updatedAt < $1.updatedAt }
    }

    func allRuns() -> [AgentRunRecord] {
        snapshot.runs.sorted { $0.updatedAt > $1.updatedAt }
    }

    func allSessions() -> [AgentRunSessionRecord] {
        snapshot.sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    func sessionRecord(sessionID: UUID) throws -> AgentRunSessionRecord {
        guard let session = snapshot.sessions.first(where: { $0.id == sessionID }) else {
            throw AgentRunStoreError.missingSession(sessionID)
        }
        return session
    }

    func sessions(contextID: String?, contextKind: String? = nil) -> [AgentRunSessionRecord] {
        snapshot.sessions
            .filter { session in
                guard session.contextID == contextID else { return false }
                guard let contextKind else { return true }
                return session.contextKind == contextKind
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func runs(sessionID: UUID) -> [AgentRunRecord] {
        snapshot.runs
            .filter { $0.sessionID == sessionID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func latestRun(sessionID: UUID) -> AgentRunRecord? {
        runs(sessionID: sessionID).first
    }

    func clearAll() throws {
        snapshot = AgentRunStoreSnapshot()
        if FileManager.default.fileExists(atPath: artifactsDirectory.path) {
            try FileManager.default.removeItem(at: artifactsDirectory)
        }
        try FileManager.default.createDirectory(at: artifactsDirectory, withIntermediateDirectories: true)
        try persistence.clearSnapshot()
    }

    func runRecord(runID: UUID) throws -> AgentRunRecord {
        guard let run = snapshot.runs.first(where: { $0.runID == runID }) else {
            throw AgentRunStoreError.missingRun(runID)
        }
        return run
    }

    private func appendEventWithoutPersisting(
        runID: UUID,
        stepID: UUID? = nil,
        kind: AgentRunEventKind,
        payload: AgentRunEventPayload,
        createdAt: Date
    ) throws -> AgentRunEventRecord {
        guard let runIndex = snapshot.runs.firstIndex(where: { $0.runID == runID }) else {
            throw AgentRunStoreError.missingRun(runID)
        }

        if let stepID, !snapshot.steps.contains(where: { $0.stepID == stepID }) {
            throw AgentRunStoreError.missingStep(stepID)
        }

        let sequence = snapshot.runs[runIndex].lastSequence + 1
        let event = AgentRunEventRecord(
            sessionID: snapshot.runs[runIndex].sessionID,
            runID: runID,
            stepID: stepID,
            sequence: sequence,
            kind: kind,
            payload: payload,
            createdAt: createdAt
        )

        snapshot.events.append(event)
        snapshot.runs[runIndex].lastSequence = sequence
        snapshot.runs[runIndex].updatedAt = createdAt
        touchSession(snapshot.runs[runIndex].sessionID, at: createdAt)
        return event
    }

    private func persist() throws {
        snapshot.schemaVersion = AgentRunStoreSchema.currentVersion
        try persistence.saveSnapshot(snapshot)
    }

    private func touchSession(_ sessionID: UUID, at date: Date) {
        guard let index = snapshot.sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }
        snapshot.sessions[index].updatedAt = date
    }

    private func touchRun(_ runID: UUID, at date: Date) {
        guard let index = snapshot.runs.firstIndex(where: { $0.runID == runID }) else {
            return
        }
        snapshot.runs[index].updatedAt = date
        touchSession(snapshot.runs[index].sessionID, at: date)
    }

    private func artifactURL(relativePath: String) throws -> URL {
        guard relativePath.hasPrefix("Artifacts/") else {
            throw AgentRunStoreError.invalidArtifactPath(relativePath)
        }
        let fileName = String(relativePath.dropFirst("Artifacts/".count))
        guard !fileName.contains("/") && !fileName.contains("..") else {
            throw AgentRunStoreError.invalidArtifactPath(relativePath)
        }
        return artifactsDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    private static func safeArtifactExtension(_ fileExtension: String?) -> String? {
        guard let fileExtension else { return nil }
        let allowed = fileExtension.filter { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
        }
        return allowed.isEmpty ? nil : allowed
    }

    private static func migratedSnapshot(_ snapshot: AgentRunStoreSnapshot) throws -> AgentRunStoreSnapshot {
        guard snapshot.schemaVersion <= AgentRunStoreSchema.currentVersion else {
            throw AgentRunStoreError.unsupportedSchemaVersion(snapshot.schemaVersion)
        }

        var migrated = snapshot
        if migrated.schemaVersion < AgentRunStoreSchema.currentVersion {
            migrated.schemaVersion = AgentRunStoreSchema.currentVersion
        }
        return migrated
    }
}
