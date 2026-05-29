import Foundation

nonisolated enum AgentModelCapabilityTier: String, Codable, Equatable, Sendable {
    case tierAFullAgent
    case tierBConstrainedStructuredText
    case tierCPlainChat
}

nonisolated enum AgentModelGatewayMode: String, Codable, Equatable, Sendable {
    case fullAgent
    case constrainedStructuredText
    case plainChat
}

nonisolated enum AgentModelGatewayFailureKind: String, Codable, Equatable, Error, Sendable {
    case unavailable
    case auth
    case rateLimited
    case contextTooLarge
    case timeout
    case canceled
    case emptyOutput
    case structuredOutputInvalid
    case toolCallInvalid
    case transportError
    case providerRefusal
    case unsupportedToolMode
    case unknown
}

nonisolated struct AgentModelGatewayFailure: Error, Codable, Equatable, Sendable, CustomStringConvertible {
    let kind: AgentModelGatewayFailureKind
    let adapterID: String
    let message: AgentRunText
    let metadata: [String: AgentRunMetadataValue]

    init(
        kind: AgentModelGatewayFailureKind,
        adapterID: String,
        message: AgentRunText,
        metadata: [String: AgentRunMetadataValue] = [:]
    ) {
        self.kind = kind
        self.adapterID = adapterID
        self.message = message
        self.metadata = metadata
    }

    var description: String {
        "\(kind.rawValue): \(message.text)"
    }
}

nonisolated struct AgentModelGatewayRequest: Identifiable, Sendable {
    let id: UUID
    let mode: AgentModelGatewayMode
    let messages: [AgentKernelMessageV2]
    let tools: [AgentKernelToolSchemaV2]
    let attachments: [AgentKernelModelAttachmentV2]
    let requestedMaxOutputTokens: Int
    let timeout: TimeInterval?
    let metadata: [String: AgentRunMetadataValue]

    init(
        id: UUID = UUID(),
        mode: AgentModelGatewayMode,
        messages: [AgentKernelMessageV2],
        tools: [AgentKernelToolSchemaV2] = [],
        attachments: [AgentKernelModelAttachmentV2] = [],
        requestedMaxOutputTokens: Int = 1_024,
        timeout: TimeInterval? = nil,
        metadata: [String: AgentRunMetadataValue] = [:]
    ) {
        self.id = id
        self.mode = mode
        self.messages = messages
        self.tools = tools
        self.attachments = attachments
        self.requestedMaxOutputTokens = max(1, requestedMaxOutputTokens)
        self.timeout = timeout
        self.metadata = metadata
    }
}

nonisolated struct AgentModelGatewayResponse: Sendable {
    let requestID: UUID
    let adapterID: String
    let descriptor: AgentKernelModelDescriptorV2
    let tier: AgentModelCapabilityTier
    let events: [AgentKernelModelAdapterEventV2]
    let diagnostics: AgentRunText?
}

nonisolated enum AgentModelGatewayResult: Sendable {
    case success(AgentModelGatewayResponse)
    case failure(AgentModelGatewayFailure)

    var failure: AgentModelGatewayFailure? {
        guard case .failure(let failure) = self else { return nil }
        return failure
    }

    var response: AgentModelGatewayResponse? {
        guard case .success(let response) = self else { return nil }
        return response
    }
}

actor AgentModelGateway {
    private var adapters: [String: any AgentKernelModelAdapterV2]
    private let outputNormalizer = AgentKernelModelOutputNormalizerV2()

    init(adapters: [any AgentKernelModelAdapterV2] = []) {
        self.adapters = Dictionary(uniqueKeysWithValues: adapters.map { ($0.descriptor.id, $0) })
    }

    func register(_ adapter: any AgentKernelModelAdapterV2) {
        adapters[adapter.descriptor.id] = adapter
    }

    func adapterIDs() -> [String] {
        adapters.keys.sorted()
    }

    func tier(adapterID: String) -> AgentModelCapabilityTier? {
        guard let adapter = adapters[adapterID] else { return nil }
        return Self.tier(for: adapter.capabilities)
    }

    func response(
        adapterID: String,
        request gatewayRequest: AgentModelGatewayRequest
    ) async -> AgentModelGatewayResult {
        if Task.isCancelled {
            return .failure(
                AgentModelGatewayFailure(
                    kind: .canceled,
                    adapterID: adapterID,
                    message: AgentRunText("Model request was canceled.")
                )
            )
        }

        guard let adapter = adapters[adapterID] else {
            return .failure(
                AgentModelGatewayFailure(
                    kind: .unavailable,
                    adapterID: adapterID,
                    message: AgentRunText("No registered model adapter has id \(adapterID).")
                )
            )
        }

        let capabilities = adapter.capabilities
        guard capabilities.isAvailable else {
            return .failure(
                AgentModelGatewayFailure(
                    kind: .unavailable,
                    adapterID: adapterID,
                    message: AgentRunText(capabilities.unavailableReason?.text ?? "Model adapter is unavailable.")
                )
            )
        }

        let tier = Self.tier(for: capabilities)
        if let failure = validate(gatewayRequest, adapterID: adapterID, capabilities: capabilities, tier: tier) {
            return .failure(failure)
        }

        let adapterRequest = makeAdapterRequest(gatewayRequest, capabilities: capabilities, tier: tier)

        do {
            let rawAdapterResponse = try await execute(adapter: adapter, request: adapterRequest, timeout: gatewayRequest.timeout)
            let adapterResponse = outputNormalizer.normalize(response: rawAdapterResponse, tools: gatewayRequest.tools)
            try Task.checkCancellation()
            if let failure = validate(adapterResponse, gatewayRequest: gatewayRequest, adapterID: adapterID) {
                return .failure(failure)
            }
            return .success(
                AgentModelGatewayResponse(
                    requestID: gatewayRequest.id,
                    adapterID: adapterID,
                    descriptor: adapter.descriptor,
                    tier: tier,
                    events: adapterResponse.events,
                    diagnostics: adapterResponse.diagnostics.map { AgentRunText($0.text) }
                )
            )
        } catch is CancellationError {
            return .failure(
                AgentModelGatewayFailure(
                    kind: .canceled,
                    adapterID: adapterID,
                    message: AgentRunText("Model request was canceled.")
                )
            )
        } catch AgentModelGatewayFailureKind.timeout {
            return .failure(
                AgentModelGatewayFailure(
                    kind: .timeout,
                    adapterID: adapterID,
                    message: AgentRunText("Model request timed out.")
                )
            )
        } catch {
            return .failure(
                AgentModelGatewayFailure(
                    kind: .transportError,
                    adapterID: adapterID,
                    message: AgentRunText(String(describing: error))
                )
            )
        }
    }

    nonisolated static func tier(for capabilities: AgentKernelModelAdapterCapabilitiesV2) -> AgentModelCapabilityTier {
        if capabilities.toolCallingMode == .native || capabilities.structuredOutputReliability == .strict {
            return .tierAFullAgent
        }
        if capabilities.toolCallingMode == .textProtocol || capabilities.structuredOutputReliability == .bestEffort {
            return .tierBConstrainedStructuredText
        }
        return .tierCPlainChat
    }

    private nonisolated func validate(
        _ request: AgentModelGatewayRequest,
        adapterID: String,
        capabilities: AgentKernelModelAdapterCapabilitiesV2,
        tier: AgentModelCapabilityTier
    ) -> AgentModelGatewayFailure? {
        let promptCharacters = request.messages.reduce(0) { $0 + $1.content.count }
        if promptCharacters > capabilities.limits.maxPromptCharacters {
            return AgentModelGatewayFailure(
                kind: .contextTooLarge,
                adapterID: adapterID,
                message: AgentRunText("Prompt has \(promptCharacters) characters; maximum is \(capabilities.limits.maxPromptCharacters)."),
                metadata: [
                    "promptCharacters": .int(promptCharacters),
                    "maxPromptCharacters": .int(capabilities.limits.maxPromptCharacters)
                ]
            )
        }

        switch request.mode {
        case .fullAgent:
            guard tier == .tierAFullAgent else {
                return unsupportedModeFailure(request: request, adapterID: adapterID, tier: tier)
            }
        case .constrainedStructuredText:
            guard tier == .tierAFullAgent || tier == .tierBConstrainedStructuredText else {
                return unsupportedModeFailure(request: request, adapterID: adapterID, tier: tier)
            }
        case .plainChat:
            break
        }

        if !request.tools.isEmpty && tier == .tierCPlainChat && request.mode != .plainChat {
            return unsupportedModeFailure(request: request, adapterID: adapterID, tier: tier)
        }

        return nil
    }

    private nonisolated func validate(
        _ response: AgentKernelModelAdapterResponseV2,
        gatewayRequest: AgentModelGatewayRequest,
        adapterID: String
    ) -> AgentModelGatewayFailure? {
        guard !response.events.isEmpty else {
            return AgentModelGatewayFailure(
                kind: .emptyOutput,
                adapterID: adapterID,
                message: AgentRunText("Model adapter returned no events.")
            )
        }

        if response.events.contains(.timedOut) {
            return AgentModelGatewayFailure(
                kind: .timeout,
                adapterID: adapterID,
                message: AgentRunText("Model adapter reported a timeout.")
            )
        }

        if isSingleEmptyOutput(response.events) {
            return AgentModelGatewayFailure(
                kind: .emptyOutput,
                adapterID: adapterID,
                message: AgentRunText("Model adapter returned empty output.")
            )
        }

        if let malformed = firstMalformedOutput(in: response.events) {
            let kind: AgentModelGatewayFailureKind = gatewayRequest.mode == .plainChat
                ? .transportError
                : .structuredOutputInvalid
            return AgentModelGatewayFailure(
                kind: kind,
                adapterID: adapterID,
                message: AgentRunText(malformed)
            )
        }

        for event in response.events {
            guard case .toolCall(let call) = event else { continue }
            if gatewayRequest.mode == .plainChat {
                return AgentModelGatewayFailure(
                    kind: .toolCallInvalid,
                    adapterID: adapterID,
                    message: AgentRunText("Plain chat mode cannot return tool calls.")
                )
            }
            guard let schema = gatewayRequest.tools.first(where: { $0.name == call.name }) else {
                return AgentModelGatewayFailure(
                    kind: .toolCallInvalid,
                    adapterID: adapterID,
                    message: AgentRunText("Model called unknown tool \(call.name).")
                )
            }
            let missing = schema.requiredArguments.filter { call.arguments[$0]?.isEmpty ?? true }
            if !missing.isEmpty {
                return AgentModelGatewayFailure(
                    kind: .toolCallInvalid,
                    adapterID: adapterID,
                    message: AgentRunText("Tool call \(call.name) is missing required arguments: \(missing.joined(separator: ", "))."),
                    metadata: ["toolName": .string(call.name)]
                )
            }
        }

        return nil
    }

    private nonisolated func makeAdapterRequest(
        _ request: AgentModelGatewayRequest,
        capabilities: AgentKernelModelAdapterCapabilitiesV2,
        tier: AgentModelCapabilityTier
    ) -> AgentKernelModelAdapterRequestV2 {
        let tools: [AgentKernelToolSchemaV2]
        let responseFormat: AgentKernelToolCallingModeV2

        switch request.mode {
        case .plainChat:
            tools = []
            responseFormat = .none
        case .fullAgent, .constrainedStructuredText:
            tools = request.tools
            if request.tools.isEmpty {
                responseFormat = .none
            } else if capabilities.toolCallingMode == .native && tier == .tierAFullAgent {
                responseFormat = .native
            } else {
                responseFormat = .textProtocol
            }
        }

        return AgentKernelModelAdapterRequestV2(
            id: request.id,
            messages: request.messages,
            tools: tools,
            attachments: request.attachments,
            requestedMaxOutputTokens: min(request.requestedMaxOutputTokens, capabilities.limits.maxOutputTokens),
            responseFormat: responseFormat,
            metadata: request.metadata.reduce(into: [:]) { partial, item in
                partial[item.key] = kernelMetadataValue(from: item.value)
            }
        )
    }

    private nonisolated func execute(
        adapter: any AgentKernelModelAdapterV2,
        request: AgentKernelModelAdapterRequestV2,
        timeout: TimeInterval?
    ) async throws -> AgentKernelModelAdapterResponseV2 {
        guard let timeout, timeout > 0 else {
            return await adapter.response(for: request)
        }

        return try await withThrowingTaskGroup(of: AgentKernelModelAdapterResponseV2.self) { group in
            group.addTask {
                await adapter.response(for: request)
            }
            group.addTask {
                let nanoseconds = UInt64((timeout * 1_000_000_000).rounded(.up))
                try await Task.sleep(nanoseconds: nanoseconds)
                throw AgentModelGatewayFailureKind.timeout
            }
            guard let result = try await group.next() else {
                throw AgentModelGatewayFailureKind.timeout
            }
            group.cancelAll()
            return result
        }
    }

    private nonisolated func unsupportedModeFailure(
        request: AgentModelGatewayRequest,
        adapterID: String,
        tier: AgentModelCapabilityTier
    ) -> AgentModelGatewayFailure {
        AgentModelGatewayFailure(
            kind: .unsupportedToolMode,
            adapterID: adapterID,
            message: AgentRunText("Mode \(request.mode.rawValue) is not supported by \(tier.rawValue)."),
            metadata: [
                "mode": .string(request.mode.rawValue),
                "tier": .string(tier.rawValue)
            ]
        )
    }

    private nonisolated func isSingleEmptyOutput(_ events: [AgentKernelModelAdapterEventV2]) -> Bool {
        guard events.count == 1 else { return false }
        guard case .emptyOutput = events[0] else { return false }
        return true
    }

    private nonisolated func firstMalformedOutput(in events: [AgentKernelModelAdapterEventV2]) -> String? {
        for event in events {
            if case .malformedOutput(let text) = event {
                return text
            }
        }
        return nil
    }

    private nonisolated func kernelMetadataValue(from value: AgentRunMetadataValue) -> AgentKernelMetadataValueV2 {
        switch value {
        case .string(let value):
            .string(value)
        case .int(let value):
            .int(value)
        case .double(let value):
            .double(value)
        case .bool(let value):
            .bool(value)
        }
    }
}
