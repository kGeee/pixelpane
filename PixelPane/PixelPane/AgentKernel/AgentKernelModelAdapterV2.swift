import Foundation

enum AgentKernelModelProviderKindV2: String, Codable, Equatable, Sendable {
    case fixture
    case appleLocal
    case mlxLocal
    case openAICompatible
    case pixelPaneCloud
    case custom
}

enum AgentKernelModelRouteV2: String, Codable, Equatable, Sendable {
    case local
    case cloud
}

enum AgentKernelModelInputModalityV2: String, Codable, Equatable, Hashable, Sendable {
    case text
    case image
}

enum AgentKernelModelOutputModalityV2: String, Codable, Equatable, Hashable, Sendable {
    case text
}

enum AgentKernelToolCallingModeV2: String, Codable, Equatable, Sendable {
    case none
    case native
    case textProtocol
}

enum AgentKernelStructuredOutputReliabilityV2: String, Codable, Equatable, Sendable {
    case unsupported
    case bestEffort
    case strict
}

enum AgentKernelStreamingModeV2: String, Codable, Equatable, Sendable {
    case unsupported
    case snapshots
    case events
}

struct AgentKernelModelLimitsV2: Codable, Equatable, Sendable {
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

struct AgentKernelModelDescriptorV2: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let providerKind: AgentKernelModelProviderKindV2
    let route: AgentKernelModelRouteV2
    let displayName: String
    let modelName: String?

    nonisolated init(
        id: String,
        providerKind: AgentKernelModelProviderKindV2,
        route: AgentKernelModelRouteV2,
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

struct AgentKernelModelAdapterCapabilitiesV2: Codable, Equatable, Sendable {
    let descriptor: AgentKernelModelDescriptorV2
    let inputModalities: Set<AgentKernelModelInputModalityV2>
    let outputModalities: Set<AgentKernelModelOutputModalityV2>
    let toolCallingMode: AgentKernelToolCallingModeV2
    let structuredOutputReliability: AgentKernelStructuredOutputReliabilityV2
    let streamingMode: AgentKernelStreamingModeV2
    let limits: AgentKernelModelLimitsV2
    let isAvailable: Bool
    let unavailableReason: AgentKernelBoundedTextV2?

    nonisolated init(
        descriptor: AgentKernelModelDescriptorV2,
        inputModalities: Set<AgentKernelModelInputModalityV2> = [.text],
        outputModalities: Set<AgentKernelModelOutputModalityV2> = [.text],
        toolCallingMode: AgentKernelToolCallingModeV2,
        structuredOutputReliability: AgentKernelStructuredOutputReliabilityV2,
        streamingMode: AgentKernelStreamingModeV2,
        limits: AgentKernelModelLimitsV2 = AgentKernelModelLimitsV2(),
        isAvailable: Bool = true,
        unavailableReason: AgentKernelBoundedTextV2? = nil
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

    nonisolated var legacyCapabilities: AgentKernelModelCapabilitiesV2 {
        AgentKernelModelCapabilitiesV2(
            supportsNativeToolCalling: toolCallingMode == .native,
            supportsStreaming: streamingMode != .unsupported,
            contextWindowTokens: limits.contextWindowTokens
        )
    }
}

struct AgentKernelModelAttachmentV2: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let modality: AgentKernelModelInputModalityV2
    let label: String
    let transientOnly: Bool
    let metadata: [String: AgentKernelMetadataValueV2]

    nonisolated init(
        id: UUID = UUID(),
        modality: AgentKernelModelInputModalityV2,
        label: String,
        transientOnly: Bool = true,
        metadata: [String: AgentKernelMetadataValueV2] = [:]
    ) {
        self.id = id
        self.modality = modality
        self.label = label
        self.transientOnly = transientOnly
        self.metadata = metadata
    }
}

struct AgentKernelModelAdapterRequestV2: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let messages: [AgentKernelMessageV2]
    let tools: [AgentKernelToolSchemaV2]
    let attachments: [AgentKernelModelAttachmentV2]
    let requestedMaxOutputTokens: Int
    let responseFormat: AgentKernelToolCallingModeV2
    let metadata: [String: AgentKernelMetadataValueV2]

    nonisolated init(
        id: UUID = UUID(),
        messages: [AgentKernelMessageV2],
        tools: [AgentKernelToolSchemaV2] = [],
        attachments: [AgentKernelModelAttachmentV2] = [],
        requestedMaxOutputTokens: Int = 1_024,
        responseFormat: AgentKernelToolCallingModeV2 = .none,
        metadata: [String: AgentKernelMetadataValueV2] = [:]
    ) {
        self.id = id
        self.messages = messages
        self.tools = tools
        self.attachments = attachments
        self.requestedMaxOutputTokens = max(1, requestedMaxOutputTokens)
        self.responseFormat = responseFormat
        self.metadata = metadata
    }

    nonisolated var legacyRequest: AgentKernelModelRequestV2 {
        AgentKernelModelRequestV2(
            messages: messages,
            tools: tools,
            maxOutputTokens: requestedMaxOutputTokens
        )
    }
}

enum AgentKernelModelAdapterEventV2: Codable, Equatable, Sendable {
    case snapshot(String)
    case finalAnswer(String)
    case toolCall(AgentKernelToolCallV2)
    case malformedOutput(String)
    case emptyOutput
    case timedOut

    nonisolated var modelEvent: AgentKernelModelEventV2? {
        switch self {
        case .snapshot:
            nil
        case .finalAnswer(let text):
            .finalAnswer(text)
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

struct AgentKernelModelAdapterResponseV2: Codable, Equatable, Sendable {
    let requestID: UUID
    let descriptor: AgentKernelModelDescriptorV2
    let events: [AgentKernelModelAdapterEventV2]
    let diagnostics: AgentKernelBoundedTextV2?

    nonisolated init(
        requestID: UUID,
        descriptor: AgentKernelModelDescriptorV2,
        events: [AgentKernelModelAdapterEventV2],
        diagnostics: AgentKernelBoundedTextV2? = nil
    ) {
        self.requestID = requestID
        self.descriptor = descriptor
        self.events = events
        self.diagnostics = diagnostics
    }

    nonisolated var modelEvents: [AgentKernelModelEventV2] {
        let converted = events.compactMap(\.modelEvent)
        return converted.isEmpty ? [.emptyOutput] : converted
    }
}

protocol AgentKernelModelAdapterV2: Sendable {
    nonisolated var descriptor: AgentKernelModelDescriptorV2 { get }
    nonisolated var capabilities: AgentKernelModelAdapterCapabilitiesV2 { get }

    nonisolated func response(for request: AgentKernelModelAdapterRequestV2) async -> AgentKernelModelAdapterResponseV2
    nonisolated func stream(for request: AgentKernelModelAdapterRequestV2) -> AsyncStream<AgentKernelModelAdapterEventV2>
}

extension AgentKernelModelAdapterV2 {
    nonisolated func stream(for request: AgentKernelModelAdapterRequestV2) -> AsyncStream<AgentKernelModelAdapterEventV2> {
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
