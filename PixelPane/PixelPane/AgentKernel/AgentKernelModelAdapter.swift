import Foundation

enum AgentKernelModelProviderKind: String, Codable, Equatable, Sendable {
    case fixture
    case appleLocal
    case mlxLocal
    case openAICompatible
    case pixelPaneCloud
    case custom
}

enum AgentKernelModelRoute: String, Codable, Equatable, Sendable {
    case local
    case cloud
}

enum AgentKernelModelInputModality: String, Codable, Equatable, Hashable, Sendable {
    case text
    case image
}

enum AgentKernelModelOutputModality: String, Codable, Equatable, Hashable, Sendable {
    case text
}

enum AgentKernelToolCallingMode: String, Codable, Equatable, Sendable {
    case none
    case native
    case textProtocol
}

enum AgentKernelStructuredOutputReliability: String, Codable, Equatable, Sendable {
    case unsupported
    case bestEffort
    case strict
}

enum AgentKernelStreamingMode: String, Codable, Equatable, Sendable {
    case unsupported
    case snapshots
    case events
}

struct AgentKernelModelLimits: Codable, Equatable, Sendable {
    let contextWindowTokens: Int?
    let maxPromptCharacters: Int
    let maxOutputTokens: Int

    nonisolated init(
        contextWindowTokens: Int? = nil,
        maxPromptCharacters: Int = 80_000,
        maxOutputTokens: Int = 1_024
    ) {
        self.contextWindowTokens = contextWindowTokens
        self.maxPromptCharacters = max(1, maxPromptCharacters)
        self.maxOutputTokens = max(1, maxOutputTokens)
    }
}

nonisolated struct AgentKernelModelDescriptor: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let providerKind: AgentKernelModelProviderKind
    let route: AgentKernelModelRoute
    let displayName: String
    let modelName: String?

    nonisolated init(
        id: String,
        providerKind: AgentKernelModelProviderKind,
        route: AgentKernelModelRoute,
        displayName: String,
        modelName: String? = nil
    ) {
        self.id = id
        self.providerKind = providerKind
        self.route = route
        self.displayName = displayName
        self.modelName = modelName
    }
}

struct AgentKernelModelAdapterCapabilities: Codable, Equatable, Sendable {
    let descriptor: AgentKernelModelDescriptor
    let inputModalities: Set<AgentKernelModelInputModality>
    let outputModalities: Set<AgentKernelModelOutputModality>
    let toolCallingMode: AgentKernelToolCallingMode
    let structuredOutputReliability: AgentKernelStructuredOutputReliability
    let streamingMode: AgentKernelStreamingMode
    let limits: AgentKernelModelLimits
    let isAvailable: Bool
    let unavailableReason: AgentKernelBoundedText?

    nonisolated init(
        descriptor: AgentKernelModelDescriptor,
        inputModalities: Set<AgentKernelModelInputModality> = [.text],
        outputModalities: Set<AgentKernelModelOutputModality> = [.text],
        toolCallingMode: AgentKernelToolCallingMode,
        structuredOutputReliability: AgentKernelStructuredOutputReliability,
        streamingMode: AgentKernelStreamingMode,
        limits: AgentKernelModelLimits = AgentKernelModelLimits(),
        isAvailable: Bool = true,
        unavailableReason: AgentKernelBoundedText? = nil
    ) {
        self.descriptor = descriptor
        self.inputModalities = inputModalities
        self.outputModalities = outputModalities
        self.toolCallingMode = toolCallingMode
        self.structuredOutputReliability = structuredOutputReliability
        self.streamingMode = streamingMode
        self.limits = limits
        self.isAvailable = isAvailable
        self.unavailableReason = unavailableReason
    }

}

nonisolated struct AgentKernelModelAttachment: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let modality: AgentKernelModelInputModality
    let label: String
    let transientOnly: Bool
    let metadata: [String: AgentKernelMetadataValue]

    nonisolated init(
        id: UUID = UUID(),
        modality: AgentKernelModelInputModality,
        label: String,
        transientOnly: Bool = true,
        metadata: [String: AgentKernelMetadataValue] = [:]
    ) {
        self.id = id
        self.modality = modality
        self.label = label
        self.transientOnly = transientOnly
        self.metadata = metadata
    }
}

struct AgentKernelModelAdapterRequest: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let messages: [AgentKernelMessage]
    let tools: [AgentKernelToolSchema]
    let attachments: [AgentKernelModelAttachment]
    let requestedMaxOutputTokens: Int
    let responseFormat: AgentKernelToolCallingMode
    let metadata: [String: AgentKernelMetadataValue]

    nonisolated init(
        id: UUID = UUID(),
        messages: [AgentKernelMessage],
        tools: [AgentKernelToolSchema] = [],
        attachments: [AgentKernelModelAttachment] = [],
        requestedMaxOutputTokens: Int = 1_024,
        responseFormat: AgentKernelToolCallingMode = .none,
        metadata: [String: AgentKernelMetadataValue] = [:]
    ) {
        self.id = id
        self.messages = messages
        self.tools = tools
        self.attachments = attachments
        self.requestedMaxOutputTokens = max(1, requestedMaxOutputTokens)
        self.responseFormat = responseFormat
        self.metadata = metadata
    }

}

nonisolated enum AgentKernelModelAdapterEvent: Codable, Equatable, Sendable {
    case snapshot(String)
    case finalAnswer(AgentKernelFinalAnswer)
    case toolCall(AgentKernelToolCall)
    case malformedOutput(String)
    case emptyOutput
    case timedOut

    nonisolated static func finalAnswer(_ text: String) -> Self {
        .finalAnswer(AgentKernelFinalAnswer(text: text))
    }

    nonisolated var modelEvent: AgentKernelModelEvent? {
        switch self {
        case .snapshot:
            nil
        case .finalAnswer(let answer):
            .finalAnswer(answer)
        case .toolCall(let call):
            .toolCall(call)
        case .malformedOutput(let text):
            .malformedOutput(text)
        case .emptyOutput:
            .emptyOutput
        case .timedOut:
            .timedOut
        }
    }
}

struct AgentKernelModelAdapterResponse: Codable, Equatable, Sendable {
    let requestID: UUID
    let descriptor: AgentKernelModelDescriptor
    let events: [AgentKernelModelAdapterEvent]
    let diagnostics: AgentKernelBoundedText?

    nonisolated init(
        requestID: UUID,
        descriptor: AgentKernelModelDescriptor,
        events: [AgentKernelModelAdapterEvent],
        diagnostics: AgentKernelBoundedText? = nil
    ) {
        self.requestID = requestID
        self.descriptor = descriptor
        self.events = events
        self.diagnostics = diagnostics
    }

    nonisolated var modelEvents: [AgentKernelModelEvent] {
        let converted = events.compactMap(\.modelEvent)
        return converted.isEmpty ? [.emptyOutput] : converted
    }
}

protocol AgentKernelModelAdapter: Sendable {
    nonisolated var descriptor: AgentKernelModelDescriptor { get }
    nonisolated var capabilities: AgentKernelModelAdapterCapabilities { get }

    nonisolated func response(for request: AgentKernelModelAdapterRequest) async -> AgentKernelModelAdapterResponse
    nonisolated func stream(for request: AgentKernelModelAdapterRequest) -> AsyncStream<AgentKernelModelAdapterEvent>
}

extension AgentKernelModelAdapter {
    nonisolated func stream(for request: AgentKernelModelAdapterRequest) -> AsyncStream<AgentKernelModelAdapterEvent> {
        AsyncStream { continuation in
            let task = Task {
                let response = await self.response(for: request)
                for event in response.events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
