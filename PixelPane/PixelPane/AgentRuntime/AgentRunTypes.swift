import Foundation

nonisolated enum AgentRunStoreSchema {
    static let currentVersion = 1
}

nonisolated enum AgentRunStatus: String, Codable, Equatable, Sendable {
    case draft
    case queued
    case running
    case waitingForApproval
    case waitingForUserInput
    case interrupted
    case completed
    case blocked
    case failed
    case canceled

    var requiresLaunchRecovery: Bool {
        switch self {
        case .queued, .running:
            true
        case .draft, .waitingForApproval, .waitingForUserInput, .interrupted, .completed, .blocked, .failed, .canceled:
            false
        }
    }
}

nonisolated enum AgentRunStepKind: String, Codable, Equatable, Sendable {
    case route
    case modelRequest
    case modelResponse
    case toolRequest
    case toolResult
    case wait
    case sideEffect
    case validation
    case terminal
    case evidence
    case artifact
    case projection
    case custom
}

nonisolated enum AgentRunStepStatus: String, Codable, Equatable, Sendable {
    case pending
    case running
    case completed
    case failed
    case canceled
    case interrupted
}

nonisolated enum AgentRunWaitKind: String, Codable, Equatable, Sendable {
    case approval
    case userInput
}

nonisolated enum AgentRunWaitStatus: String, Codable, Equatable, Sendable {
    case pending
    case approved
    case denied
    case canceled
    case resolved
}

nonisolated enum AgentRunSideEffectKind: String, Codable, Equatable, Sendable {
    case fileWrite
    case command
    case processStart
    case processStop
    case custom
}

nonisolated enum AgentRunSideEffectStatus: String, Codable, Equatable, Sendable {
    case proposed
    case approved
    case denied
    case running
    case completed
    case failed
    case rolledBack
    case canceled
}

nonisolated enum AgentRunEventKind: String, Codable, Equatable, Sendable {
    case userMessage
    case assistantMessage
    case progress
    case statusChanged
    case stepStarted
    case stepCompleted
    case waitCreated
    case waitResolved
    case artifactRecorded
    case evidenceRecorded
    case sideEffectRecorded
    case providerDiagnostic
    case failure
    case custom
}

nonisolated enum AgentRunMetadataValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
}

nonisolated struct AgentRunText: Codable, Equatable, Sendable {
    static let defaultLimit = 24_000

    let text: String
    let characterLimit: Int
    let isTruncated: Bool

    init(_ text: String, characterLimit: Int = Self.defaultLimit) {
        let limit = max(0, characterLimit)
        if text.count > limit {
            self.text = String(text.prefix(limit))
            isTruncated = true
        } else {
            self.text = text
            isTruncated = false
        }
        self.characterLimit = limit
    }
}

nonisolated struct AgentRunSessionRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var contextID: String?
    var contextKind: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        contextID: String? = nil,
        contextKind: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.contextID = contextID
        self.contextKind = contextKind
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

nonisolated struct AgentRunRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID { runID }

    let sessionID: UUID
    let runID: UUID
    var status: AgentRunStatus
    var createdAt: Date
    var updatedAt: Date
    var lastSequence: Int
    var activeStepID: UUID?

    init(
        sessionID: UUID,
        runID: UUID = UUID(),
        status: AgentRunStatus = .draft,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        lastSequence: Int = -1,
        activeStepID: UUID? = nil
    ) {
        self.sessionID = sessionID
        self.runID = runID
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.lastSequence = lastSequence
        self.activeStepID = activeStepID
    }
}

nonisolated struct AgentRunStepRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID { stepID }

    let sessionID: UUID
    let runID: UUID
    let stepID: UUID
    let kind: AgentRunStepKind
    var status: AgentRunStepStatus
    var createdAt: Date
    var updatedAt: Date
    var metadata: [String: AgentRunMetadataValue]

    init(
        sessionID: UUID,
        runID: UUID,
        stepID: UUID = UUID(),
        kind: AgentRunStepKind,
        status: AgentRunStepStatus = .pending,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        metadata: [String: AgentRunMetadataValue] = [:]
    ) {
        self.sessionID = sessionID
        self.runID = runID
        self.stepID = stepID
        self.kind = kind
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.metadata = metadata
    }
}

nonisolated struct AgentRunWaitRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID { waitID }

    let sessionID: UUID
    let runID: UUID
    let stepID: UUID?
    let waitID: UUID
    let kind: AgentRunWaitKind
    var status: AgentRunWaitStatus
    let prompt: AgentRunText
    let risk: String?
    var createdAt: Date
    var resolvedAt: Date?
    var resolutionSummary: AgentRunText?

    init(
        sessionID: UUID,
        runID: UUID,
        stepID: UUID? = nil,
        waitID: UUID = UUID(),
        kind: AgentRunWaitKind,
        status: AgentRunWaitStatus = .pending,
        prompt: AgentRunText,
        risk: String? = nil,
        createdAt: Date = Date(),
        resolvedAt: Date? = nil,
        resolutionSummary: AgentRunText? = nil
    ) {
        self.sessionID = sessionID
        self.runID = runID
        self.stepID = stepID
        self.waitID = waitID
        self.kind = kind
        self.status = status
        self.prompt = prompt
        self.risk = risk
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.resolutionSummary = resolutionSummary
    }
}

nonisolated struct AgentRunArtifactRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID { artifactID }

    let sessionID: UUID
    let runID: UUID
    let stepID: UUID?
    let artifactID: UUID
    let kind: String
    let mimeType: String
    let relativePath: String
    let byteCount: Int
    let createdAt: Date
    let summary: AgentRunText?
}

nonisolated struct AgentRunEvidenceRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID { evidenceID }

    let sessionID: UUID
    let runID: UUID
    let stepID: UUID?
    let evidenceID: UUID
    let sourceID: String
    let kind: String
    let summary: AgentRunText
    let artifactID: UUID?
    let createdAt: Date
    let metadata: [String: AgentRunMetadataValue]
}

nonisolated struct AgentRunSideEffectRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID { sideEffectID }

    let sessionID: UUID
    let runID: UUID
    let stepID: UUID?
    let sideEffectID: UUID
    let kind: AgentRunSideEffectKind
    var status: AgentRunSideEffectStatus
    let proposalHash: String?
    let proposalArtifactID: UUID?
    let approvalWaitID: UUID?
    var beforeArtifactID: UUID?
    var afterArtifactID: UUID?
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var updatedAt: Date
    var errorSummary: AgentRunText?
    var metadata: [String: AgentRunMetadataValue]

    init(
        sessionID: UUID,
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
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        updatedAt: Date? = nil,
        errorSummary: AgentRunText? = nil,
        metadata: [String: AgentRunMetadataValue] = [:]
    ) {
        self.sessionID = sessionID
        self.runID = runID
        self.stepID = stepID
        self.sideEffectID = sideEffectID
        self.kind = kind
        self.status = status
        self.proposalHash = proposalHash
        self.proposalArtifactID = proposalArtifactID
        self.approvalWaitID = approvalWaitID
        self.beforeArtifactID = beforeArtifactID
        self.afterArtifactID = afterArtifactID
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.updatedAt = updatedAt ?? createdAt
        self.errorSummary = errorSummary
        self.metadata = metadata
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case runID
        case stepID
        case sideEffectID
        case kind
        case status
        case proposalHash
        case proposalArtifactID
        case approvalWaitID
        case beforeArtifactID
        case afterArtifactID
        case createdAt
        case startedAt
        case completedAt
        case updatedAt
        case errorSummary
        case metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.init(
            sessionID: try container.decode(UUID.self, forKey: .sessionID),
            runID: try container.decode(UUID.self, forKey: .runID),
            stepID: try container.decodeIfPresent(UUID.self, forKey: .stepID),
            sideEffectID: try container.decode(UUID.self, forKey: .sideEffectID),
            kind: try container.decode(AgentRunSideEffectKind.self, forKey: .kind),
            status: try container.decode(AgentRunSideEffectStatus.self, forKey: .status),
            proposalHash: try container.decodeIfPresent(String.self, forKey: .proposalHash),
            proposalArtifactID: try container.decodeIfPresent(UUID.self, forKey: .proposalArtifactID),
            approvalWaitID: try container.decodeIfPresent(UUID.self, forKey: .approvalWaitID),
            beforeArtifactID: try container.decodeIfPresent(UUID.self, forKey: .beforeArtifactID),
            afterArtifactID: try container.decodeIfPresent(UUID.self, forKey: .afterArtifactID),
            createdAt: createdAt,
            startedAt: try container.decodeIfPresent(Date.self, forKey: .startedAt),
            completedAt: try container.decodeIfPresent(Date.self, forKey: .completedAt),
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt,
            errorSummary: try container.decodeIfPresent(AgentRunText.self, forKey: .errorSummary),
            metadata: try container.decodeIfPresent([String: AgentRunMetadataValue].self, forKey: .metadata) ?? [:]
        )
    }
}

nonisolated enum AgentRunEventPayload: Codable, Equatable, Sendable {
    case text(AgentRunText)
    case progress(AgentRunText)
    case status(AgentRunStatus, reason: AgentRunText?)
    case step(AgentRunStepRecord)
    case wait(AgentRunWaitRecord)
    case artifact(AgentRunArtifactRecord)
    case evidence(AgentRunEvidenceRecord)
    case sideEffect(AgentRunSideEffectRecord)
    case diagnostic(AgentRunText)
    case metadata([String: AgentRunMetadataValue])
}

nonisolated struct AgentRunEventRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID { eventID }

    let sessionID: UUID
    let runID: UUID
    let stepID: UUID?
    let eventID: UUID
    let sequence: Int
    let kind: AgentRunEventKind
    let payload: AgentRunEventPayload
    let createdAt: Date

    init(
        sessionID: UUID,
        runID: UUID,
        stepID: UUID? = nil,
        eventID: UUID = UUID(),
        sequence: Int,
        kind: AgentRunEventKind,
        payload: AgentRunEventPayload,
        createdAt: Date = Date()
    ) {
        self.sessionID = sessionID
        self.runID = runID
        self.stepID = stepID
        self.eventID = eventID
        self.sequence = sequence
        self.kind = kind
        self.payload = payload
        self.createdAt = createdAt
    }
}

nonisolated struct AgentRunVisibleMessage: Codable, Equatable, Identifiable, Sendable {
    enum Role: String, Codable, Equatable, Sendable {
        case user
        case assistant
    }

    let id: UUID
    let sessionID: UUID
    let runID: UUID
    let sequence: Int
    let role: Role
    let text: AgentRunText
    let createdAt: Date
}

nonisolated struct AgentRunStatusProjection: Codable, Equatable, Sendable {
    let sessionID: UUID
    let runID: UUID
    let status: AgentRunStatus
    let activeStepID: UUID?
    let updatedAt: Date
    let latestProgress: AgentRunText?
    let pendingWaits: [AgentRunWaitRecord]
}

nonisolated struct AgentRunEvidenceArtifactSummary: Codable, Equatable, Sendable {
    let evidence: [AgentRunEvidenceRecord]
    let artifacts: [AgentRunArtifactRecord]
}

nonisolated struct AgentRunTraceProjection: Codable, Equatable, Sendable {
    let session: AgentRunSessionRecord?
    let run: AgentRunRecord
    let steps: [AgentRunStepRecord]
    let waits: [AgentRunWaitRecord]
    let artifacts: [AgentRunArtifactRecord]
    let evidence: [AgentRunEvidenceRecord]
    let sideEffects: [AgentRunSideEffectRecord]
    let events: [AgentRunEventRecord]
}

nonisolated struct AgentRunStoreSnapshot: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var sessions: [AgentRunSessionRecord]
    var runs: [AgentRunRecord]
    var steps: [AgentRunStepRecord]
    var waits: [AgentRunWaitRecord]
    var artifacts: [AgentRunArtifactRecord]
    var evidence: [AgentRunEvidenceRecord]
    var sideEffects: [AgentRunSideEffectRecord]
    var events: [AgentRunEventRecord]

    init(
        schemaVersion: Int = AgentRunStoreSchema.currentVersion,
        sessions: [AgentRunSessionRecord] = [],
        runs: [AgentRunRecord] = [],
        steps: [AgentRunStepRecord] = [],
        waits: [AgentRunWaitRecord] = [],
        artifacts: [AgentRunArtifactRecord] = [],
        evidence: [AgentRunEvidenceRecord] = [],
        sideEffects: [AgentRunSideEffectRecord] = [],
        events: [AgentRunEventRecord] = []
    ) {
        self.schemaVersion = schemaVersion
        self.sessions = sessions
        self.runs = runs
        self.steps = steps
        self.waits = waits
        self.artifacts = artifacts
        self.evidence = evidence
        self.sideEffects = sideEffects
        self.events = events
    }
}
