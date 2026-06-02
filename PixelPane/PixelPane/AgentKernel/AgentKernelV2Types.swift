import Foundation

nonisolated struct AgentKernelBoundedTextV2: Codable, Equatable, Sendable {
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

nonisolated enum AgentKernelMetadataValueV2: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
}

nonisolated struct AgentKernelTerminalReasonV2: Error, Codable, Equatable, Sendable {
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

nonisolated enum AgentKernelRoleV2: String, Codable, Equatable, Sendable {
    case system
    case user
    case assistant
    case observation
}

nonisolated struct AgentKernelMessageV2: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let role: AgentKernelRoleV2
    let content: String

    nonisolated init(id: UUID = UUID(), role: AgentKernelRoleV2, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

nonisolated enum AgentKernelToolArgumentTypeV2: String, Codable, Equatable, Sendable {
    case string
    case integer
    case number
    case boolean
    case jsonString
}

nonisolated struct AgentKernelToolArgumentSchemaV2: Codable, Equatable, Sendable {
    let name: String
    let type: AgentKernelToolArgumentTypeV2
    let isRequired: Bool
    let summary: String

    nonisolated init(
        name: String,
        type: AgentKernelToolArgumentTypeV2,
        isRequired: Bool = true,
        summary: String
    ) {
        self.name = name
        self.type = type
        self.isRequired = isRequired
        self.summary = summary
    }
}

nonisolated struct AgentKernelToolSchemaV2: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let summary: String
    let arguments: [AgentKernelToolArgumentSchemaV2]
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
        arguments: [AgentKernelToolArgumentSchemaV2]? = nil
    ) {
        let resolvedArguments = arguments ?? requiredArguments.map {
            AgentKernelToolArgumentSchemaV2(
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
        let arguments = try container.decodeIfPresent([AgentKernelToolArgumentSchemaV2].self, forKey: .arguments)
        self.init(name: name, summary: summary, requiredArguments: requiredArguments, arguments: arguments)
    }

    nonisolated var knownArgumentNames: Set<String> {
        Set(arguments.map(\.name))
    }
}

nonisolated struct AgentKernelToolCallV2: Codable, Equatable, Identifiable, Sendable {
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

nonisolated enum AgentKernelAnswerGroundingBasisV2: String, Codable, Equatable, Sendable {
    case generalKnowledge = "general_knowledge"
    case localEvidence = "local_evidence"
    case capabilityLimitation = "capability_limitation"
}

nonisolated enum AgentKernelAnswerClaimKindV2: String, Codable, Equatable, Hashable, Sendable {
    case fileGrants = "file_grants"
    case processSnapshot = "process_snapshot"
    case localListeners = "local_listeners"
    case localFile = "local_file"
    case commandOutput = "command_output"
    case sideEffect = "side_effect"
    case temporalContext = "temporal_context"
    case visualContext = "visual_context"
}

nonisolated struct AgentKernelAnswerClaimV2: Codable, Equatable, Sendable {
    let kind: AgentKernelAnswerClaimKindV2
    let target: String?

    nonisolated init(kind: AgentKernelAnswerClaimKindV2, target: String? = nil) {
        self.kind = kind
        self.target = target
    }
}

nonisolated struct AgentKernelAnswerGroundingV2: Codable, Equatable, Sendable {
    let basis: AgentKernelAnswerGroundingBasisV2
    let claims: [AgentKernelAnswerClaimV2]

    nonisolated init(
        basis: AgentKernelAnswerGroundingBasisV2,
        claims: [AgentKernelAnswerClaimV2] = []
    ) {
        self.basis = basis
        self.claims = claims
    }
}

nonisolated struct AgentKernelFinalAnswerV2: Codable, Equatable, Sendable {
    let text: String
    let grounding: AgentKernelAnswerGroundingV2?

    nonisolated init(
        text: String,
        grounding: AgentKernelAnswerGroundingV2? = nil
    ) {
        self.text = text
        self.grounding = grounding
    }
}

nonisolated enum AgentKernelModelEventV2: Codable, Equatable, Sendable {
    case finalAnswer(AgentKernelFinalAnswerV2)
    case toolCall(AgentKernelToolCallV2)
    case malformedOutput(String)
    case emptyOutput
    case timedOut

    nonisolated static func finalAnswer(_ text: String) -> Self {
        .finalAnswer(AgentKernelFinalAnswerV2(text: text))
    }
}
