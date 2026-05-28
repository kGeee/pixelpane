import Foundation

enum AgentKernelRoleV2: String, Codable, Equatable, Sendable {
    case system
    case user
    case assistant
    case observation
}

struct AgentKernelMessageV2: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let role: AgentKernelRoleV2
    let content: String

    nonisolated init(id: UUID = UUID(), role: AgentKernelRoleV2, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

struct AgentKernelToolSchemaV2: Codable, Equatable, Identifiable, Sendable {
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

struct AgentKernelToolCallV2: Codable, Equatable, Identifiable, Sendable {
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

struct AgentKernelModelCapabilitiesV2: Codable, Equatable, Sendable {
    let supportsNativeToolCalling: Bool
    let supportsStreaming: Bool
    let contextWindowTokens: Int?

    nonisolated init(
        supportsNativeToolCalling: Bool,
        supportsStreaming: Bool,
        contextWindowTokens: Int? = nil
    ) {
        self.supportsNativeToolCalling = supportsNativeToolCalling
        self.supportsStreaming = supportsStreaming
        self.contextWindowTokens = contextWindowTokens
    }
}

struct AgentKernelModelRequestV2: Codable, Equatable, Sendable {
    let messages: [AgentKernelMessageV2]
    let tools: [AgentKernelToolSchemaV2]
    let maxOutputTokens: Int

    nonisolated init(
        messages: [AgentKernelMessageV2],
        tools: [AgentKernelToolSchemaV2] = [],
        maxOutputTokens: Int = 1_024
    ) {
        self.messages = messages
        self.tools = tools
        self.maxOutputTokens = maxOutputTokens
    }
}

enum AgentKernelModelEventV2: Codable, Equatable, Sendable {
    case finalAnswer(String)
    case toolCall(AgentKernelToolCallV2)
    case malformedOutput(String)
    case emptyOutput
    case timedOut
}

protocol AgentKernelModelClientV2: Sendable {
    nonisolated var id: String { get }
    nonisolated var capabilities: AgentKernelModelCapabilitiesV2 { get }

    nonisolated func events(for request: AgentKernelModelRequestV2) async -> [AgentKernelModelEventV2]
}
