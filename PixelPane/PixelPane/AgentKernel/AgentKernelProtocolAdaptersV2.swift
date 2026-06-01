import Foundation

struct AgentKernelNativeToolCallAdapterV2: AgentKernelModelAdapterV2 {
    let descriptor: AgentKernelModelDescriptorV2
    let capabilities: AgentKernelModelAdapterCapabilitiesV2
    private let upstream: any AgentKernelModelAdapterV2

    nonisolated init(upstream: any AgentKernelModelAdapterV2) {
        self.upstream = upstream
        self.descriptor = upstream.descriptor
        self.capabilities = AgentKernelModelAdapterCapabilitiesV2(
            descriptor: upstream.capabilities.descriptor,
            inputModalities: upstream.capabilities.inputModalities,
            outputModalities: upstream.capabilities.outputModalities,
            toolCallingMode: .native,
            structuredOutputReliability: upstream.capabilities.structuredOutputReliability,
            streamingMode: upstream.capabilities.streamingMode,
            limits: upstream.capabilities.limits,
            isAvailable: upstream.capabilities.isAvailable,
            unavailableReason: upstream.capabilities.unavailableReason
        )
    }

    nonisolated func response(
        for request: AgentKernelModelAdapterRequestV2
    ) async -> AgentKernelModelAdapterResponseV2 {
        await upstream.response(
            for: AgentKernelModelAdapterRequestV2(
                id: request.id,
                messages: request.messages,
                tools: request.tools,
                attachments: request.attachments,
                requestedMaxOutputTokens: request.requestedMaxOutputTokens,
                responseFormat: .native,
                metadata: request.metadata
            )
        )
    }

    nonisolated func stream(
        for request: AgentKernelModelAdapterRequestV2
    ) -> AsyncStream<AgentKernelModelAdapterEventV2> {
        upstream.stream(
            for: AgentKernelModelAdapterRequestV2(
                id: request.id,
                messages: request.messages,
                tools: request.tools,
                attachments: request.attachments,
                requestedMaxOutputTokens: request.requestedMaxOutputTokens,
                responseFormat: .native,
                metadata: request.metadata
            )
        )
    }
}

enum AgentKernelTextProtocolTransportEventV2: Equatable, Sendable {
    case text(String)
    case timedOut
}

protocol AgentKernelTextProtocolTransportV2: Sendable {
    nonisolated func complete(prompt: String, request: AgentKernelModelAdapterRequestV2) async -> AgentKernelTextProtocolTransportEventV2
}

struct AgentKernelTextProtocolPromptBuilderV2: Sendable {
    nonisolated init() {}

    nonisolated func prompt(for request: AgentKernelModelAdapterRequestV2) -> String {
        let tools = request.tools.map { tool in
            let arguments: String
            if tool.arguments.isEmpty {
                arguments = "none"
            } else {
                arguments = tool.arguments.map { argument in
                    let requirement = argument.isRequired ? "required" : "optional"
                    return "\(argument.name): \(argument.type.rawValue), \(requirement), \(argument.summary)"
                }.joined(separator: "; ")
            }
            return "- \(tool.name): \(tool.summary) Arguments: \(arguments)"
        }.joined(separator: "\n")
        let messages = request.messages.map { message in
            "\(message.role.rawValue): \(message.content)"
        }.joined(separator: "\n")
        let attachments = request.attachments.map { attachment in
            var lines = [
                "- \(attachment.label) (\(attachment.modality.rawValue))"
            ]
            if let source = Self.metadataString(attachment.metadata["source"]), !source.isEmpty {
                lines.append("  source: \(source)")
            }
            if let ocrText = Self.metadataString(attachment.metadata["ocrText"]), !ocrText.isEmpty {
                lines.append("  ocrText: \(AgentKernelBoundedTextV2(ocrText, characterLimit: 4_000).text)")
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n")

        return """
        Return exactly one JSON object and no Markdown.
        Valid final answer format:
        {"type":"final_answer","text":"answer text"}
        Valid tool call format:
        {"type":"tool_call","name":"tool_name","arguments":{"argument":"value"},"reason":"optional reason"}
        Tool schemas:
        \(tools.isEmpty ? "- none" : tools)
        Attachments:
        \(attachments.isEmpty ? "- none" : attachments)
        Messages:
        \(messages)
        """
    }

    private nonisolated static func metadataString(_ value: AgentKernelMetadataValueV2?) -> String? {
        guard case .string(let text) = value else { return nil }
        return text
    }

    nonisolated func repairPrompt(
        malformedOutput: String,
        reason: String,
        originalRequest: AgentKernelModelAdapterRequestV2
    ) -> String {
        """
        The previous response did not match the required JSON protocol.
        Reason: \(reason)
        Previous response:
        \(malformedOutput)

        \(prompt(for: originalRequest))
        """
    }
}

struct AgentKernelTextProtocolParserV2: Sendable {
    private let decoder: AgentKernelToolProtocolDecoderV2

    nonisolated init(decoder: AgentKernelToolProtocolDecoderV2 = AgentKernelToolProtocolDecoderV2()) {
        self.decoder = decoder
    }

    nonisolated func parse(
        _ text: String,
        tools: [AgentKernelToolSchemaV2]
    ) -> Result<AgentKernelModelAdapterEventV2, AgentKernelTerminalReasonV2> {
        switch decoder.decode(text, tools: tools, requiresProtocolEnvelope: true) {
        case .event(let event):
            return .success(event)
        case .notProtocol:
            return .failure(
                AgentKernelTerminalReasonV2(
                    code: "text_protocol_missing_type",
                    summary: AgentKernelBoundedTextV2("Text protocol output is missing a type field.")
                )
            )
        case .failure(let reason):
            return .failure(reason)
        }
    }

    nonisolated func partialToolCallForValidation(
        _ text: String,
        tools: [AgentKernelToolSchemaV2]
    ) -> AgentKernelToolCallV2? {
        decoder.partialToolCallForValidation(text, tools: tools)
    }
}

struct AgentKernelTextProtocolAdapterV2: AgentKernelModelAdapterV2 {
    let descriptor: AgentKernelModelDescriptorV2
    let capabilities: AgentKernelModelAdapterCapabilitiesV2

    private let transport: any AgentKernelTextProtocolTransportV2
    private let promptBuilder: AgentKernelTextProtocolPromptBuilderV2
    private let parser: AgentKernelTextProtocolParserV2
    private let allowsSingleRepairAttempt: Bool

    nonisolated init(
        descriptor: AgentKernelModelDescriptorV2,
        transport: any AgentKernelTextProtocolTransportV2,
        limits: AgentKernelModelLimitsV2 = AgentKernelModelLimitsV2(),
        promptBuilder: AgentKernelTextProtocolPromptBuilderV2 = AgentKernelTextProtocolPromptBuilderV2(),
        parser: AgentKernelTextProtocolParserV2 = AgentKernelTextProtocolParserV2(),
        allowsSingleRepairAttempt: Bool = true
    ) {
        self.descriptor = descriptor
        self.transport = transport
        self.promptBuilder = promptBuilder
        self.parser = parser
        self.allowsSingleRepairAttempt = allowsSingleRepairAttempt
        self.capabilities = AgentKernelModelAdapterCapabilitiesV2(
            descriptor: descriptor,
            toolCallingMode: .textProtocol,
            structuredOutputReliability: .bestEffort,
            streamingMode: .unsupported,
            limits: limits
        )
    }

    nonisolated func response(
        for request: AgentKernelModelAdapterRequestV2
    ) async -> AgentKernelModelAdapterResponseV2 {
        let protocolRequest = AgentKernelModelAdapterRequestV2(
            id: request.id,
            messages: request.messages,
            tools: request.tools,
            attachments: request.attachments,
            requestedMaxOutputTokens: request.requestedMaxOutputTokens,
            responseFormat: .textProtocol,
            metadata: request.metadata
        )
        let prompt = promptBuilder.prompt(for: protocolRequest)
        let firstEvent = await transport.complete(prompt: prompt, request: protocolRequest)
        switch firstEvent {
        case .timedOut:
            return response(for: protocolRequest, events: [.timedOut])
        case .text(let text):
            return await parseOrRepair(text, request: protocolRequest)
        }
    }

    private nonisolated func parseOrRepair(
        _ text: String,
        request: AgentKernelModelAdapterRequestV2
    ) async -> AgentKernelModelAdapterResponseV2 {
        switch parser.parse(text, tools: request.tools) {
        case .success(let event):
            return response(for: request, events: [event])
        case .failure(let reason):
            if reason.code == "text_protocol_missing_tool_argument",
               let partialCall = parser.partialToolCallForValidation(text, tools: request.tools) {
                return response(for: request, events: [.toolCall(partialCall)], diagnostics: reason.summary)
            }
            guard allowsSingleRepairAttempt else {
                return response(for: request, events: [.malformedOutput(text)], diagnostics: reason.summary)
            }
            let repairPrompt = promptBuilder.repairPrompt(
                malformedOutput: text,
                reason: reason.summary.text,
                originalRequest: request
            )
            let repairEvent = await transport.complete(prompt: repairPrompt, request: request)
            switch repairEvent {
            case .timedOut:
                return response(for: request, events: [.timedOut], diagnostics: reason.summary)
            case .text(let repairedText):
                switch parser.parse(repairedText, tools: request.tools) {
                case .success(let event):
                    return response(for: request, events: [event], diagnostics: reason.summary)
                case .failure(let repairReason):
                    return response(for: request, events: [.malformedOutput(repairedText)], diagnostics: repairReason.summary)
                }
            }
        }
    }

    private nonisolated func response(
        for request: AgentKernelModelAdapterRequestV2,
        events: [AgentKernelModelAdapterEventV2],
        diagnostics: AgentKernelBoundedTextV2? = nil
    ) -> AgentKernelModelAdapterResponseV2 {
        AgentKernelModelAdapterResponseV2(
            requestID: request.id,
            descriptor: descriptor,
            events: events,
            diagnostics: diagnostics
        )
    }
}

actor FixtureTextProtocolTransportV2: AgentKernelTextProtocolTransportV2 {
    private var responses: [AgentKernelTextProtocolTransportEventV2]
    private(set) var prompts: [String] = []

    init(responses: [AgentKernelTextProtocolTransportEventV2]) {
        self.responses = responses
    }

    func complete(
        prompt: String,
        request: AgentKernelModelAdapterRequestV2
    ) async -> AgentKernelTextProtocolTransportEventV2 {
        prompts.append(prompt)
        guard !responses.isEmpty else {
            return .text("")
        }
        return responses.removeFirst()
    }

    func receivedPrompts() -> [String] {
        prompts
    }
}
