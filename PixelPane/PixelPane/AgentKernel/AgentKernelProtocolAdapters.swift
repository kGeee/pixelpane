import Foundation

struct AgentKernelNativeToolCallAdapter: AgentKernelModelAdapter {
    let descriptor: AgentKernelModelDescriptor
    let capabilities: AgentKernelModelAdapterCapabilities
    private let upstream: any AgentKernelModelAdapter

    nonisolated init(upstream: any AgentKernelModelAdapter) {
        self.upstream = upstream
        self.descriptor = upstream.descriptor
        self.capabilities = AgentKernelModelAdapterCapabilities(
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
        for request: AgentKernelModelAdapterRequest
    ) async -> AgentKernelModelAdapterResponse {
        await upstream.response(
            for: AgentKernelModelAdapterRequest(
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
        for request: AgentKernelModelAdapterRequest
    ) -> AsyncStream<AgentKernelModelAdapterEvent> {
        upstream.stream(
            for: AgentKernelModelAdapterRequest(
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

enum AgentKernelTextProtocolTransportEvent: Equatable, Sendable {
    case text(String)
    case timedOut
}

protocol AgentKernelTextProtocolTransport: Sendable {
    nonisolated func complete(prompt: String, request: AgentKernelModelAdapterRequest) async -> AgentKernelTextProtocolTransportEvent
}

struct AgentKernelTextProtocolPromptBuilder: Sendable {
    /// Provider-specific context prepended to the protocol prompt, e.g. the
    /// cloud adapter noting that hosted web search may be used. Optional so
    /// local adapters keep the unmodified protocol.
    let providerPreamble: String?

    nonisolated init(providerPreamble: String? = nil) {
        self.providerPreamble = providerPreamble
    }

    nonisolated func prompt(for request: AgentKernelModelAdapterRequest) -> String {
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
                lines.append("  ocrText: \(AgentKernelBoundedText(ocrText, characterLimit: 4_000).text)")
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n")

        let preamble = providerPreamble.map { "\($0)\n" } ?? ""
        return """
        \(preamble)Return exactly one JSON object and no Markdown.
        Valid final answer format (general knowledge):
        {"type":"final_answer","text":"answer text","grounding":{"basis":"general_knowledge","claims":[]}}
        Valid final answer format (grounded in recorded tool observations):
        {"type":"final_answer","text":"answer text","grounding":{"basis":"local_evidence","claims":[{"kind":"file_listing","target":"/path/to/folder"}]}}
        Grounding basis values: general_knowledge, local_evidence, capability_limitation.
        Use local_evidence only with one or more claims, each {"kind":...,"target":...}, backed by recorded tool observations. If current local state is needed and no observation supports it, call an available tool.
        Local evidence claim kind values: file_grants (granted locations), file_listing (folder contents or search results), local_file (file contents you read), process_snapshot, local_listeners, command_output, side_effect, temporal_context, location_context (app-provided approximate location), visual_context.
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

    private nonisolated static func metadataString(_ value: AgentKernelMetadataValue?) -> String? {
        guard case .string(let text) = value else { return nil }
        return text
    }

    nonisolated func repairPrompt(
        malformedOutput: String,
        reason: String,
        originalRequest: AgentKernelModelAdapterRequest
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

struct AgentKernelTextProtocolParser: Sendable {
    private let decoder: AgentKernelToolProtocolDecoder

    nonisolated init(decoder: AgentKernelToolProtocolDecoder = AgentKernelToolProtocolDecoder()) {
        self.decoder = decoder
    }

    nonisolated func parse(
        _ text: String,
        tools: [AgentKernelToolSchema]
    ) -> Result<AgentKernelModelAdapterEvent, AgentKernelTerminalReason> {
        switch decoder.decode(text, tools: tools, requiresProtocolEnvelope: true) {
        case .event(let event):
            return .success(event)
        case .notProtocol:
            return .failure(
                AgentKernelTerminalReason(
                    code: "text_protocol_missing_type",
                    summary: AgentKernelBoundedText("Text protocol output is missing a type field.")
                )
            )
        case .failure(let reason):
            return .failure(reason)
        }
    }

    nonisolated func partialToolCallForValidation(
        _ text: String,
        tools: [AgentKernelToolSchema]
    ) -> AgentKernelToolCall? {
        decoder.partialToolCallForValidation(text, tools: tools)
    }
}

struct AgentKernelTextProtocolAdapter: AgentKernelModelAdapter {
    let descriptor: AgentKernelModelDescriptor
    let capabilities: AgentKernelModelAdapterCapabilities

    private let transport: any AgentKernelTextProtocolTransport
    private let promptBuilder: AgentKernelTextProtocolPromptBuilder
    private let parser: AgentKernelTextProtocolParser
    private let allowsSingleRepairAttempt: Bool

    nonisolated init(
        descriptor: AgentKernelModelDescriptor,
        transport: any AgentKernelTextProtocolTransport,
        limits: AgentKernelModelLimits = AgentKernelModelLimits(),
        promptBuilder: AgentKernelTextProtocolPromptBuilder = AgentKernelTextProtocolPromptBuilder(),
        parser: AgentKernelTextProtocolParser = AgentKernelTextProtocolParser(),
        allowsSingleRepairAttempt: Bool = true
    ) {
        self.descriptor = descriptor
        self.transport = transport
        self.promptBuilder = promptBuilder
        self.parser = parser
        self.allowsSingleRepairAttempt = allowsSingleRepairAttempt
        self.capabilities = AgentKernelModelAdapterCapabilities(
            descriptor: descriptor,
            toolCallingMode: .textProtocol,
            structuredOutputReliability: .bestEffort,
            streamingMode: .unsupported,
            limits: limits
        )
    }

    nonisolated func response(
        for request: AgentKernelModelAdapterRequest
    ) async -> AgentKernelModelAdapterResponse {
        let protocolRequest = AgentKernelModelAdapterRequest(
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
        request: AgentKernelModelAdapterRequest
    ) async -> AgentKernelModelAdapterResponse {
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
        for request: AgentKernelModelAdapterRequest,
        events: [AgentKernelModelAdapterEvent],
        diagnostics: AgentKernelBoundedText? = nil
    ) -> AgentKernelModelAdapterResponse {
        AgentKernelModelAdapterResponse(
            requestID: request.id,
            descriptor: descriptor,
            events: events,
            diagnostics: diagnostics
        )
    }
}

actor FixtureTextProtocolTransport: AgentKernelTextProtocolTransport {
    private var responses: [AgentKernelTextProtocolTransportEvent]
    private(set) var prompts: [String] = []

    init(responses: [AgentKernelTextProtocolTransportEvent]) {
        self.responses = responses
    }

    func complete(
        prompt: String,
        request: AgentKernelModelAdapterRequest
    ) async -> AgentKernelTextProtocolTransportEvent {
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
