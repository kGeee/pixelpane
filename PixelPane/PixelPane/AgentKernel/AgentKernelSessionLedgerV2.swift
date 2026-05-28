import Foundation

enum AgentKernelTaskStateV2: String, Codable, Equatable, Sendable {
    case idle
    case planning
    case compilingContext
    case callingModel
    case validatingTool
    case awaitingApproval
    case runningTool
    case observing
    case verifying
    case repairing
    case completed
    case blocked
    case canceled
    case failed
}

struct AgentKernelBoundedTextV2: Codable, Equatable, Sendable {
    nonisolated static let defaultLimit = 12_000

    let text: String
    let characterLimit: Int
    let isTruncated: Bool

    nonisolated init(_ text: String, characterLimit: Int = Self.defaultLimit) {
        let limit = max(0, characterLimit)
        if text.count > limit {
            self.text = String(text.prefix(limit))
            self.isTruncated = true
        } else {
            self.text = text
            self.isTruncated = false
        }
        self.characterLimit = limit
    }
}

enum AgentKernelMetadataValueV2: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
}

enum AgentKernelToolResultStatusV2: String, Codable, Equatable, Sendable {
    case succeeded
    case failed
    case canceled
}

enum AgentKernelApprovalDecisionV2: String, Codable, Equatable, Sendable {
    case approved
    case denied
    case canceled
}

enum AgentKernelProcessStatusKindV2: String, Codable, Equatable, Sendable {
    case started
    case running
    case exited
    case failed
    case canceled
}

struct AgentKernelToolResultV2: Codable, Equatable, Sendable {
    let toolCallID: UUID?
    let toolName: String
    let status: AgentKernelToolResultStatusV2
    let summary: AgentKernelBoundedTextV2
    let metadata: [String: AgentKernelMetadataValueV2]

    nonisolated init(
        toolCallID: UUID? = nil,
        toolName: String,
        status: AgentKernelToolResultStatusV2,
        summary: AgentKernelBoundedTextV2,
        metadata: [String: AgentKernelMetadataValueV2] = [:]
    ) {
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.status = status
        self.summary = summary
        self.metadata = metadata
    }
}

struct AgentKernelApprovalRequestV2: Codable, Equatable, Sendable {
    let id: UUID
    let toolCallID: UUID
    let toolName: String
    let riskClass: String
    let reason: AgentKernelBoundedTextV2
    let displaySummary: AgentKernelBoundedTextV2
    let operationPreview: AgentKernelBoundedTextV2?

    nonisolated init(
        id: UUID = UUID(),
        toolCallID: UUID,
        toolName: String,
        riskClass: String,
        reason: AgentKernelBoundedTextV2,
        displaySummary: AgentKernelBoundedTextV2,
        operationPreview: AgentKernelBoundedTextV2? = nil
    ) {
        self.id = id
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.riskClass = riskClass
        self.reason = reason
        self.displaySummary = displaySummary
        self.operationPreview = operationPreview
    }
}

struct AgentKernelApprovalResolutionV2: Codable, Equatable, Sendable {
    let approvalID: UUID
    let decision: AgentKernelApprovalDecisionV2
    let reason: AgentKernelBoundedTextV2?

    nonisolated init(
        approvalID: UUID,
        decision: AgentKernelApprovalDecisionV2,
        reason: AgentKernelBoundedTextV2? = nil
    ) {
        self.approvalID = approvalID
        self.decision = decision
        self.reason = reason
    }
}

struct AgentKernelProcessStatusV2: Codable, Equatable, Sendable {
    let processID: String
    let kind: AgentKernelProcessStatusKindV2
    let summary: AgentKernelBoundedTextV2
    let metadata: [String: AgentKernelMetadataValueV2]

    nonisolated init(
        processID: String,
        kind: AgentKernelProcessStatusKindV2,
        summary: AgentKernelBoundedTextV2,
        metadata: [String: AgentKernelMetadataValueV2] = [:]
    ) {
        self.processID = processID
        self.kind = kind
        self.summary = summary
        self.metadata = metadata
    }
}

struct AgentKernelEvidenceRecordV2: Codable, Equatable, Sendable {
    let id: UUID
    let sourceID: String
    let kind: String
    let summary: AgentKernelBoundedTextV2
    let body: AgentKernelBoundedTextV2?
    let metadata: [String: AgentKernelMetadataValueV2]
    let privacyClass: String
    let trustClass: String
    let isTruncated: Bool
    let relatedToolCallID: UUID?

    nonisolated init(
        id: UUID = UUID(),
        sourceID: String,
        kind: String,
        summary: AgentKernelBoundedTextV2,
        body: AgentKernelBoundedTextV2? = nil,
        metadata: [String: AgentKernelMetadataValueV2] = [:],
        privacyClass: String,
        trustClass: String,
        isTruncated: Bool = false,
        relatedToolCallID: UUID? = nil
    ) {
        self.id = id
        self.sourceID = sourceID
        self.kind = kind
        self.summary = summary
        self.body = body
        self.metadata = metadata
        self.privacyClass = privacyClass
        self.trustClass = trustClass
        self.isTruncated = isTruncated
        self.relatedToolCallID = relatedToolCallID
    }
}

struct AgentKernelTerminalReasonV2: Codable, Equatable, Sendable {
    let code: String
    let summary: AgentKernelBoundedTextV2
    let metadata: [String: AgentKernelMetadataValueV2]

    nonisolated init(
        code: String,
        summary: AgentKernelBoundedTextV2,
        metadata: [String: AgentKernelMetadataValueV2] = [:]
    ) {
        self.code = code
        self.summary = summary
        self.metadata = metadata
    }
}

enum AgentKernelSessionEventPayloadV2: Codable, Equatable, Sendable {
    case userMessage(AgentKernelBoundedTextV2)
    case assistantMessage(AgentKernelBoundedTextV2)
    case modelCall(modelID: String, messageCount: Int, toolNames: [String])
    case modelResponse(modelID: String, events: [AgentKernelModelEventV2])
    case toolProposal(AgentKernelToolCallV2)
    case toolResult(AgentKernelToolResultV2)
    case approvalRequested(AgentKernelApprovalRequestV2)
    case approvalResolved(AgentKernelApprovalResolutionV2)
    case processStatus(AgentKernelProcessStatusV2)
    case evidenceRecorded(AgentKernelEvidenceRecordV2)
    case taskBlocked(AgentKernelTerminalReasonV2)
    case taskFailed(AgentKernelTerminalReasonV2)
    case taskCanceled(AgentKernelTerminalReasonV2)
    case taskCompleted(AgentKernelTerminalReasonV2)

    nonisolated var isTranscriptMessage: Bool {
        switch self {
        case .userMessage, .assistantMessage:
            true
        default:
            false
        }
    }

    nonisolated func nextState(from current: AgentKernelTaskStateV2) -> AgentKernelTaskStateV2 {
        switch self {
        case .userMessage:
            .planning
        case .assistantMessage:
            current
        case .modelCall:
            .callingModel
        case .modelResponse(_, let events):
            events.contains(where: \.requiresRepair) ? .repairing : .observing
        case .toolProposal:
            .validatingTool
        case .approvalRequested:
            .awaitingApproval
        case .approvalResolved(let resolution):
            switch resolution.decision {
            case .approved:
                .runningTool
            case .denied:
                .blocked
            case .canceled:
                .canceled
            }
        case .toolResult:
            .observing
        case .processStatus(let status):
            status.nextState
        case .evidenceRecorded:
            .verifying
        case .taskBlocked:
            .blocked
        case .taskFailed:
            .failed
        case .taskCanceled:
            .canceled
        case .taskCompleted:
            .completed
        }
    }
}

struct AgentKernelSessionEventV2: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let sessionID: UUID
    let sequence: Int
    let createdAt: Date
    let payload: AgentKernelSessionEventPayloadV2

    nonisolated init(
        id: UUID = UUID(),
        sessionID: UUID,
        sequence: Int,
        createdAt: Date = Date(),
        payload: AgentKernelSessionEventPayloadV2
    ) {
        self.id = id
        self.sessionID = sessionID
        self.sequence = sequence
        self.createdAt = createdAt
        self.payload = payload
    }
}

struct AgentKernelContextSnapshotV2: Codable, Equatable, Sendable {
    let transcriptMessages: [AgentKernelMessageV2]
    let observationMessages: [AgentKernelMessageV2]

    nonisolated init(
        transcriptMessages: [AgentKernelMessageV2],
        observationMessages: [AgentKernelMessageV2]
    ) {
        self.transcriptMessages = transcriptMessages
        self.observationMessages = observationMessages
    }

    nonisolated var modelMessages: [AgentKernelMessageV2] {
        transcriptMessages + observationMessages
    }
}

struct AgentKernelTranscriptTurnV2: Codable, Equatable, Sendable {
    let question: AgentKernelBoundedTextV2
    let answer: AgentKernelBoundedTextV2?
}

struct AgentKernelControlEventExportRecordV2: Codable, Equatable, Sendable {
    let kind: String
    let summary: AgentKernelBoundedTextV2
}

struct AgentKernelExportProjectionV2: Sendable {
    nonisolated init() {}

    nonisolated func conversationTurns(
        from ledger: AgentKernelSessionLedgerV2
    ) -> [AgentKernelTranscriptTurnV2] {
        var turns: [AgentKernelTranscriptTurnV2] = []
        var pendingQuestion: AgentKernelBoundedTextV2?

        for message in ledger.transcriptMessages {
            switch message.role {
            case .user:
                if let question = pendingQuestion {
                    turns.append(AgentKernelTranscriptTurnV2(question: question, answer: nil))
                }
                pendingQuestion = ledger.boundedText(message.content)
            case .assistant:
                let answer = ledger.boundedText(message.content)
                if let question = pendingQuestion {
                    turns.append(AgentKernelTranscriptTurnV2(question: question, answer: answer))
                    pendingQuestion = nil
                } else {
                    turns.append(
                        AgentKernelTranscriptTurnV2(
                            question: ledger.boundedText("Continue"),
                            answer: answer
                        )
                    )
                }
            case .system, .observation:
                continue
            }
        }

        if let question = pendingQuestion {
            turns.append(AgentKernelTranscriptTurnV2(question: question, answer: nil))
        }
        return turns
    }

    nonisolated func controlEventRecords(
        from ledger: AgentKernelSessionLedgerV2
    ) -> [AgentKernelControlEventExportRecordV2] {
        ledger.controlEvents.compactMap { event in
            switch event.payload {
            case .modelCall(let modelID, _, let toolNames):
                let tools = toolNames.isEmpty ? "none" : toolNames.joined(separator: ", ")
                return record("model_call", "Model call to \(modelID). Tools: \(tools).", ledger: ledger)
            case .modelResponse(let modelID, let events):
                return record("model_response", "Model response from \(modelID): \(events.count) typed event(s).", ledger: ledger)
            case .toolProposal(let call):
                let arguments = call.arguments.keys.sorted().joined(separator: ", ")
                return record("tool_proposal", "Tool proposed: \(call.name). Arguments: \(arguments.isEmpty ? "none" : arguments).", ledger: ledger)
            case .toolResult(let result):
                return record("tool_result", "Tool result \(result.toolName) \(result.status.rawValue): \(result.summary.text)", ledger: ledger)
            case .approvalRequested(let request):
                return record("approval_requested", "Approval requested for \(request.toolName): \(request.displaySummary.text)", ledger: ledger)
            case .approvalResolved(let resolution):
                return record("approval_resolved", "Approval \(resolution.decision.rawValue).", ledger: ledger)
            case .processStatus(let status):
                return record("process_status", "Process \(status.processID) \(status.kind.rawValue): \(status.summary.text)", ledger: ledger)
            case .evidenceRecorded(let evidence):
                return record("evidence_recorded", "Evidence \(evidence.kind) \(evidence.sourceID): \(evidence.summary.text)", ledger: ledger)
            case .taskBlocked(let reason):
                return record("task_blocked", "\(reason.code): \(reason.summary.text)", ledger: ledger)
            case .taskFailed(let reason):
                return record("task_failed", "\(reason.code): \(reason.summary.text)", ledger: ledger)
            case .taskCanceled(let reason):
                return record("task_canceled", "\(reason.code): \(reason.summary.text)", ledger: ledger)
            case .taskCompleted(let reason):
                return record("task_completed", "\(reason.code): \(reason.summary.text)", ledger: ledger)
            case .userMessage, .assistantMessage:
                return nil
            }
        }
    }

    private nonisolated func record(
        _ kind: String,
        _ summary: String,
        ledger: AgentKernelSessionLedgerV2
    ) -> AgentKernelControlEventExportRecordV2 {
        AgentKernelControlEventExportRecordV2(kind: kind, summary: ledger.boundedText(summary))
    }
}

struct AgentKernelSessionLedgerV2: Codable, Equatable, Sendable {
    let sessionID: UUID
    private(set) var state: AgentKernelTaskStateV2
    private(set) var events: [AgentKernelSessionEventV2]

    private let maxTextCharacters: Int
    private var nextSequence: Int

    nonisolated init(
        sessionID: UUID = UUID(),
        state: AgentKernelTaskStateV2 = .idle,
        maxTextCharacters: Int = AgentKernelBoundedTextV2.defaultLimit
    ) {
        self.sessionID = sessionID
        self.state = state
        self.events = []
        self.maxTextCharacters = maxTextCharacters
        self.nextSequence = 0
    }

    @discardableResult
    nonisolated mutating func append(
        _ payload: AgentKernelSessionEventPayloadV2,
        createdAt: Date = Date()
    ) -> AgentKernelSessionEventV2 {
        let event = AgentKernelSessionEventV2(
            sessionID: sessionID,
            sequence: nextSequence,
            createdAt: createdAt,
            payload: payload
        )
        nextSequence += 1
        events.append(event)
        state = payload.nextState(from: state)
        return event
    }

    nonisolated func boundedText(_ text: String) -> AgentKernelBoundedTextV2 {
        AgentKernelBoundedTextV2(text, characterLimit: maxTextCharacters)
    }

    nonisolated var transcriptMessages: [AgentKernelMessageV2] {
        events.compactMap { event in
            switch event.payload {
            case .userMessage(let text):
                AgentKernelMessageV2(id: event.id, role: .user, content: text.text)
            case .assistantMessage(let text):
                AgentKernelMessageV2(id: event.id, role: .assistant, content: text.text)
            default:
                nil
            }
        }
    }

    nonisolated var controlEvents: [AgentKernelSessionEventV2] {
        events.filter { !$0.payload.isTranscriptMessage }
    }

    nonisolated func contextSnapshot() -> AgentKernelContextSnapshotV2 {
        AgentKernelContextSnapshotV2(
            transcriptMessages: transcriptMessages,
            observationMessages: events.compactMap(\.observationMessage)
        )
    }

    nonisolated func packedContextSnapshot(
        maxTranscriptMessages: Int = 8,
        maxObservationMessages: Int = 16,
        maxObservationCharacters: Int = 24_000
    ) -> AgentKernelContextSnapshotV2 {
        let latestUserSequence = events.last { event in
            guard case .userMessage = event.payload else { return false }
            return true
        }?.sequence ?? -1

        let recentTranscript = Array(transcriptMessages.suffix(max(1, maxTranscriptMessages)))
        let currentTurnObservations = events
            .filter { $0.sequence > latestUserSequence }
            .compactMap(\.observationMessage)
        let packedObservations = Self.packMessages(
            currentTurnObservations,
            maxMessages: maxObservationMessages,
            maxCharacters: maxObservationCharacters
        )

        return AgentKernelContextSnapshotV2(
            transcriptMessages: recentTranscript,
            observationMessages: packedObservations
        )
    }

    private nonisolated static func packMessages(
        _ messages: [AgentKernelMessageV2],
        maxMessages: Int,
        maxCharacters: Int
    ) -> [AgentKernelMessageV2] {
        let messageLimit = max(0, maxMessages)
        let characterLimit = max(0, maxCharacters)
        guard messageLimit > 0, characterLimit > 0 else {
            return []
        }

        var remainingCharacters = characterLimit
        var packed: [AgentKernelMessageV2] = []
        for message in messages.reversed() {
            guard packed.count < messageLimit, remainingCharacters > 0 else {
                break
            }
            let content: String
            if message.content.count > remainingCharacters {
                content = String(message.content.prefix(remainingCharacters))
            } else {
                content = message.content
            }
            remainingCharacters -= content.count
            packed.append(
                AgentKernelMessageV2(
                    id: message.id,
                    role: message.role,
                    content: content
                )
            )
        }
        return packed.reversed()
    }
}

private extension AgentKernelSessionEventV2 {
    nonisolated var observationMessage: AgentKernelMessageV2? {
        switch payload {
        case .toolResult(let result):
            return AgentKernelMessageV2(
                id: id,
                role: .observation,
                content: "tool_result \(result.toolName) \(result.status.rawValue): \(result.summary.text)"
            )
        case .approvalResolved(let resolution):
            return AgentKernelMessageV2(
                id: id,
                role: .observation,
                content: "approval \(resolution.decision.rawValue): \(resolution.reason?.text ?? "")"
            )
        case .processStatus(let status):
            return AgentKernelMessageV2(
                id: id,
                role: .observation,
                content: "process_status \(status.processID) \(status.kind.rawValue): \(status.summary.text)"
            )
        case .evidenceRecorded(let evidence):
            var content = "evidence \(evidence.kind) \(evidence.sourceID): \(evidence.summary.text)"
            let metadata = evidence.observationMetadataSummary
            if !metadata.isEmpty {
                content += " metadata: \(metadata)"
            }
            if let body = evidence.body?.text, !body.isEmpty {
                content += "\n\(body)"
            }
            return AgentKernelMessageV2(
                id: id,
                role: .observation,
                content: content
            )
        case .taskBlocked(let reason):
            return AgentKernelMessageV2(
                id: id,
                role: .observation,
                content: "task_blocked \(reason.code): \(reason.summary.text)"
            )
        case .taskFailed(let reason):
            return AgentKernelMessageV2(
                id: id,
                role: .observation,
                content: "task_failed \(reason.code): \(reason.summary.text)"
            )
        case .taskCanceled(let reason):
            return AgentKernelMessageV2(
                id: id,
                role: .observation,
                content: "task_canceled \(reason.code): \(reason.summary.text)"
            )
        case .taskCompleted(let reason):
            return AgentKernelMessageV2(
                id: id,
                role: .observation,
                content: "task_completed \(reason.code): \(reason.summary.text)"
            )
        case .userMessage,
             .assistantMessage,
             .modelCall,
             .modelResponse,
             .toolProposal,
             .approvalRequested:
            return nil
        }
    }
}

private extension AgentKernelEvidenceRecordV2 {
    nonisolated var observationMetadataSummary: String {
        metadata.keys.sorted().map { key in
            "\(key)=\(metadata[key]?.observationValue ?? "")"
        }
        .joined(separator: ", ")
    }
}

private extension AgentKernelMetadataValueV2 {
    nonisolated var observationValue: String {
        switch self {
        case .string(let text):
            text
        case .int(let number):
            "\(number)"
        case .double(let number):
            "\(number)"
        case .bool(let bool):
            bool ? "true" : "false"
        }
    }
}

private extension AgentKernelModelEventV2 {
    nonisolated var requiresRepair: Bool {
        switch self {
        case .malformedOutput, .emptyOutput, .timedOut:
            true
        case .finalAnswer, .toolCall:
            false
        }
    }
}

private extension AgentKernelProcessStatusV2 {
    nonisolated var nextState: AgentKernelTaskStateV2 {
        switch kind {
        case .started, .running:
            .runningTool
        case .exited:
            .observing
        case .failed:
            .failed
        case .canceled:
            .canceled
        }
    }
}
