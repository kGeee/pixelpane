import Foundation

nonisolated enum AgentRunStoreSchema {
    static let currentVersion = 2
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

    var isTerminal: Bool {
        switch self {
        case .completed, .blocked, .failed, .canceled, .interrupted:
            true
        case .draft, .queued, .running, .waitingForApproval, .waitingForUserInput:
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

nonisolated struct AgentToolRunContext: Codable, Equatable, Sendable {
    let runMode: AgentRunPermissionMode
    let localGrants: [AgentLocalFileGrant]
    let grantedScopes: [AgentPermissionScope]
    let deniedScopes: [AgentPermissionScope]
    let supportedOperations: Set<AgentToolOperationKind>

    init(
        runMode: AgentRunPermissionMode,
        localGrants: [AgentLocalFileGrant] = [],
        grantedScopes: [AgentPermissionScope] = [],
        deniedScopes: [AgentPermissionScope] = [],
        supportedOperations: Set<AgentToolOperationKind> = AgentToolExecutionCapabilities.activeLocalRuntimeOperations
    ) {
        self.runMode = runMode
        self.localGrants = localGrants
        self.grantedScopes = grantedScopes
        self.deniedScopes = deniedScopes
        self.supportedOperations = supportedOperations
    }

    static let plainChat = AgentToolRunContext(runMode: .plainChat)
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
    case runConfiguration(AgentRunModelConfigurationRecord)
}

nonisolated enum AgentRunControlRecordKind: String, Codable, Equatable, Sendable {
    case modelRequest
    case modelResponse
    case modelFailure
    case toolCall
    case toolResult
    case preflightObservation
    case toolObservation
    case finalAnswerRepairObservation
    case bestEffortSynthesisObservation
    case structuredOutputRecoveryObservation
    case toolCallInvalidRecoveryObservation
    case contextRepackObservation
    case approvalResultObservation
}

nonisolated struct AgentRunModelResponseRecord: Codable, Equatable, Sendable {
    let requestID: UUID
    let adapterID: String
    let descriptor: AgentKernelModelDescriptorV2
    let tier: AgentModelCapabilityTier
    let responseFormat: AgentKernelToolCallingModeV2
    let events: [AgentKernelModelAdapterEventV2]
    let diagnostics: AgentRunText?

    init(
        requestID: UUID,
        adapterID: String,
        descriptor: AgentKernelModelDescriptorV2,
        tier: AgentModelCapabilityTier,
        responseFormat: AgentKernelToolCallingModeV2,
        events: [AgentKernelModelAdapterEventV2],
        diagnostics: AgentRunText? = nil
    ) {
        self.requestID = requestID
        self.adapterID = adapterID
        self.descriptor = descriptor
        self.tier = tier
        self.responseFormat = responseFormat
        self.events = events
        self.diagnostics = diagnostics
    }

    init(response: AgentModelGatewayResponse) {
        self.init(
            requestID: response.requestID,
            adapterID: response.adapterID,
            descriptor: response.descriptor,
            tier: response.tier,
            responseFormat: response.responseFormat,
            events: response.events,
            diagnostics: response.diagnostics
        )
    }
}

nonisolated struct AgentRunToolResultRecord: Codable, Equatable, Sendable {
    let status: String
    let toolName: String
    let summary: AgentRunText
    let observation: AgentRunText
    let evidenceIDs: [UUID]
    let artifactIDs: [UUID]
    let waitID: UUID?
    let sideEffectID: UUID?
}

nonisolated enum AgentRunControlPayload: Codable, Equatable, Sendable {
    case modelRequest(AgentModelGatewayRequest)
    case modelResponse(AgentRunModelResponseRecord)
    case modelFailure(AgentModelGatewayFailure)
    case modelMessage(AgentKernelMessageV2)
    case toolCall(AgentKernelToolCallV2)
    case toolResult(AgentRunToolResultRecord)
    case metadata([String: AgentRunMetadataValue])
}

nonisolated struct AgentRunControlRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID { recordID }

    let sessionID: UUID
    let runID: UUID
    let stepID: UUID?
    let recordID: UUID
    let sequence: Int
    let kind: AgentRunControlRecordKind
    let payload: AgentRunControlPayload
    let createdAt: Date
    let metadata: [String: AgentRunMetadataValue]

    init(
        sessionID: UUID,
        runID: UUID,
        stepID: UUID? = nil,
        recordID: UUID = UUID(),
        sequence: Int,
        kind: AgentRunControlRecordKind,
        payload: AgentRunControlPayload,
        createdAt: Date = Date(),
        metadata: [String: AgentRunMetadataValue] = [:]
    ) {
        self.sessionID = sessionID
        self.runID = runID
        self.stepID = stepID
        self.recordID = recordID
        self.sequence = sequence
        self.kind = kind
        self.payload = payload
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

nonisolated struct AgentRunModelConfigurationRecord: Codable, Equatable, Sendable {
    let adapterDescriptor: AgentKernelModelDescriptorV2
    let request: AgentModelGatewayRequest
    let toolContext: AgentToolRunContext
    let createdAt: Date

    init(
        adapterDescriptor: AgentKernelModelDescriptorV2,
        request: AgentModelGatewayRequest,
        toolContext: AgentToolRunContext,
        createdAt: Date = Date()
    ) {
        self.adapterDescriptor = adapterDescriptor
        self.request = request
        self.toolContext = toolContext
        self.createdAt = createdAt
    }

    static func == (lhs: AgentRunModelConfigurationRecord, rhs: AgentRunModelConfigurationRecord) -> Bool {
        lhs.adapterDescriptor.id == rhs.adapterDescriptor.id
            && lhs.adapterDescriptor.providerKind == rhs.adapterDescriptor.providerKind
            && lhs.adapterDescriptor.route == rhs.adapterDescriptor.route
            && lhs.adapterDescriptor.displayName == rhs.adapterDescriptor.displayName
            && lhs.adapterDescriptor.modelName == rhs.adapterDescriptor.modelName
            && lhs.request.id == rhs.request.id
            && lhs.request.mode == rhs.request.mode
            && lhs.request.tools.map(\.name) == rhs.request.tools.map(\.name)
            && lhs.request.requestedMaxOutputTokens == rhs.request.requestedMaxOutputTokens
            && lhs.request.timeout == rhs.request.timeout
            && lhs.request.metadata == rhs.request.metadata
            && lhs.toolContext == rhs.toolContext
            && lhs.createdAt == rhs.createdAt
    }
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
    let controlRecords: [AgentRunControlRecord]
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
    var controlRecords: [AgentRunControlRecord]
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
        controlRecords: [AgentRunControlRecord] = [],
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
        self.controlRecords = controlRecords
        self.events = events
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case sessions
        case runs
        case steps
        case waits
        case artifacts
        case evidence
        case sideEffects
        case controlRecords
        case events
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? AgentRunStoreSchema.currentVersion,
            sessions: try container.decodeIfPresent([AgentRunSessionRecord].self, forKey: .sessions) ?? [],
            runs: try container.decodeIfPresent([AgentRunRecord].self, forKey: .runs) ?? [],
            steps: try container.decodeIfPresent([AgentRunStepRecord].self, forKey: .steps) ?? [],
            waits: try container.decodeIfPresent([AgentRunWaitRecord].self, forKey: .waits) ?? [],
            artifacts: try container.decodeIfPresent([AgentRunArtifactRecord].self, forKey: .artifacts) ?? [],
            evidence: try container.decodeIfPresent([AgentRunEvidenceRecord].self, forKey: .evidence) ?? [],
            sideEffects: try container.decodeIfPresent([AgentRunSideEffectRecord].self, forKey: .sideEffects) ?? [],
            controlRecords: try container.decodeIfPresent([AgentRunControlRecord].self, forKey: .controlRecords) ?? [],
            events: try container.decodeIfPresent([AgentRunEventRecord].self, forKey: .events) ?? []
        )
    }
}
