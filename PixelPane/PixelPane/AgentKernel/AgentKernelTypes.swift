import Foundation

nonisolated struct AgentKernelBoundedText: Codable, Equatable, Sendable {
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

nonisolated enum AgentKernelMetadataValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
}

nonisolated struct AgentKernelTerminalReason: Error, Codable, Equatable, Sendable {
    let code: String
    let summary: AgentKernelBoundedText
    let metadata: [String: AgentKernelMetadataValue]

    nonisolated init(
        code: String,
        summary: AgentKernelBoundedText,
        metadata: [String: AgentKernelMetadataValue] = [:]
    ) {
        self.code = code
        self.summary = summary
        self.metadata = metadata
    }
}

nonisolated enum AgentKernelRole: String, Codable, Equatable, Sendable {
    case system
    case user
    case assistant
    case observation
}

nonisolated struct AgentKernelMessage: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let role: AgentKernelRole
    let content: String

    nonisolated init(id: UUID = UUID(), role: AgentKernelRole, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

nonisolated enum AgentKernelToolArgumentType: String, Codable, Equatable, Sendable {
    case string
    case integer
    case number
    case boolean
    case jsonString
}

nonisolated struct AgentKernelToolArgumentSchema: Codable, Equatable, Sendable {
    let name: String
    let type: AgentKernelToolArgumentType
    let isRequired: Bool
    let summary: String

    nonisolated init(
        name: String,
        type: AgentKernelToolArgumentType,
        isRequired: Bool = true,
        summary: String
    ) {
        self.name = name
        self.type = type
        self.isRequired = isRequired
        self.summary = summary
    }
}

nonisolated struct AgentKernelToolSchema: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let summary: String
    let arguments: [AgentKernelToolArgumentSchema]
    let requiredArguments: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case summary
        case arguments
        case requiredArguments
    }

    nonisolated init(
        name: String,
        summary: String,
        requiredArguments: [String] = [],
        arguments: [AgentKernelToolArgumentSchema]? = nil
    ) {
        let resolvedArguments = arguments ?? requiredArguments.map {
            AgentKernelToolArgumentSchema(
                name: $0,
                type: .string,
                summary: "Required argument."
            )
        }
        self.id = name
        self.name = name
        self.summary = summary
        self.arguments = resolvedArguments
        self.requiredArguments = resolvedArguments
            .filter(\.isRequired)
            .map(\.name)
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let summary = try container.decode(String.self, forKey: .summary)
        let requiredArguments = try container.decodeIfPresent([String].self, forKey: .requiredArguments) ?? []
        let arguments = try container.decodeIfPresent([AgentKernelToolArgumentSchema].self, forKey: .arguments)
        self.init(name: name, summary: summary, requiredArguments: requiredArguments, arguments: arguments)
    }

    nonisolated var knownArgumentNames: Set<String> {
        Set(arguments.map(\.name))
    }
}

nonisolated struct AgentKernelToolCall: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let arguments: [String: String]
    let reason: String?

    nonisolated init(
        id: UUID = UUID(),
        name: String,
        arguments: [String: String] = [:],
        reason: String? = nil
    ) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.reason = reason
    }
}

nonisolated enum AgentKernelAnswerGroundingBasis: String, Codable, Equatable, Sendable {
    case generalKnowledge = "general_knowledge"
    case localEvidence = "local_evidence"
    case capabilityLimitation = "capability_limitation"
}

nonisolated enum AgentKernelAnswerClaimKind: String, Codable, Equatable, Hashable, Sendable {
    case fileGrants = "file_grants"
    case processSnapshot = "process_snapshot"
    case localListeners = "local_listeners"
    case localFile = "local_file"
    case commandOutput = "command_output"
    case sideEffect = "side_effect"
    case temporalContext = "temporal_context"
    case visualContext = "visual_context"
}

nonisolated struct AgentKernelAnswerClaim: Codable, Equatable, Sendable {
    let kind: AgentKernelAnswerClaimKind
    let target: String?

    nonisolated init(kind: AgentKernelAnswerClaimKind, target: String? = nil) {
        self.kind = kind
        self.target = target
    }
}

nonisolated struct AgentKernelAnswerGrounding: Codable, Equatable, Sendable {
    let basis: AgentKernelAnswerGroundingBasis
    let claims: [AgentKernelAnswerClaim]

    nonisolated init(
        basis: AgentKernelAnswerGroundingBasis,
        claims: [AgentKernelAnswerClaim] = []
    ) {
        self.basis = basis
        self.claims = claims
    }
}

nonisolated struct AgentKernelFinalAnswer: Codable, Equatable, Sendable {
    let text: String
    let grounding: AgentKernelAnswerGrounding?

    nonisolated init(
        text: String,
        grounding: AgentKernelAnswerGrounding? = nil
    ) {
        self.text = text
        self.grounding = grounding
    }
}

nonisolated enum AgentKernelModelEvent: Codable, Equatable, Sendable {
    case finalAnswer(AgentKernelFinalAnswer)
    case toolCall(AgentKernelToolCall)
    case malformedOutput(String)
    case emptyOutput
    case timedOut

    nonisolated static func finalAnswer(_ text: String) -> Self {
        .finalAnswer(AgentKernelFinalAnswer(text: text))
    }
}
