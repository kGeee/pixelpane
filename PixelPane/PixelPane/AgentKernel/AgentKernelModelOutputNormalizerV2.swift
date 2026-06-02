import Foundation

enum AgentKernelToolProtocolDecodeResultV2: Equatable, Sendable {
    case event(AgentKernelModelAdapterEventV2)
    case notProtocol
    case failure(AgentKernelTerminalReasonV2)
}

struct AgentKernelToolProtocolDecoderV2: Sendable {
    nonisolated init() {}

    nonisolated func decode(
        _ text: String,
        tools: [AgentKernelToolSchemaV2],
        requiresProtocolEnvelope: Bool
    ) -> AgentKernelToolProtocolDecodeResultV2 {
        let cleaned = protocolPayload(from: text)
        guard !cleaned.isEmpty else {
            return .event(.emptyOutput)
        }
        guard let data = cleaned.data(using: .utf8) else {
            return .failure(reason(code: "text_protocol_not_utf8", summary: "Text protocol output was not valid UTF-8."))
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            return requiresProtocolEnvelope
                ? .failure(reason(code: "text_protocol_malformed_json", summary: error.localizedDescription))
                : .notProtocol
        }
        guard let json = object as? [String: Any] else {
            return requiresProtocolEnvelope
                ? .failure(reason(code: "text_protocol_not_object", summary: "Text protocol output must be a JSON object."))
                : .notProtocol
        }
        guard let type = json["type"] as? String else {
            return requiresProtocolEnvelope
                ? .failure(reason(code: "text_protocol_missing_type", summary: "Text protocol output is missing a type field."))
                : .notProtocol
        }

        switch type {
        case "final_answer":
            return decodeFinalAnswer(json)
        case "tool_call":
            return decodeToolCall(json, tools: tools)
        default:
            return .failure(reason(code: "text_protocol_unknown_type", summary: "Text protocol output type is not supported."))
        }
    }

    private nonisolated func decodeFinalAnswer(_ json: [String: Any]) -> AgentKernelToolProtocolDecodeResultV2 {
        guard let text = json["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(reason(code: "text_protocol_missing_final_text", summary: "Final answer output is missing non-empty text."))
        }
        guard let groundingValue = json["grounding"] else {
            return .event(.finalAnswer(AgentKernelFinalAnswerV2(text: text)))
        }
        guard let groundingObject = groundingValue as? [String: Any] else {
            return .failure(reason(code: "text_protocol_grounding_not_object", summary: "Final answer grounding must be a JSON object."))
        }
        guard let basisValue = groundingObject["basis"] as? String,
              let basis = AgentKernelAnswerGroundingBasisV2(rawValue: basisValue) else {
            return .failure(reason(code: "text_protocol_unknown_grounding_basis", summary: "Final answer grounding basis is not supported."))
        }

        let rawClaims = groundingObject["claims"] as? [[String: Any]] ?? []
        var claims: [AgentKernelAnswerClaimV2] = []
        for rawClaim in rawClaims {
            guard let kindValue = rawClaim["kind"] as? String,
                  let kind = AgentKernelAnswerClaimKindV2(rawValue: kindValue) else {
                return .failure(reason(code: "text_protocol_unknown_grounding_claim", summary: "Final answer grounding claim kind is not supported."))
            }
            claims.append(
                AgentKernelAnswerClaimV2(
                    kind: kind,
                    target: rawClaim["target"] as? String
                )
            )
        }

        return .event(
            .finalAnswer(
                AgentKernelFinalAnswerV2(
                    text: text,
                    grounding: AgentKernelAnswerGroundingV2(
                        basis: basis,
                        claims: claims
                    )
                )
            )
        )
    }

    nonisolated func partialToolCallForValidation(
        _ text: String,
        tools: [AgentKernelToolSchemaV2]
    ) -> AgentKernelToolCallV2? {
        let cleaned = protocolPayload(from: text)
        guard let data = cleaned.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any],
              json["type"] as? String == "tool_call",
              let name = json["name"] as? String,
              let tool = tools.first(where: { $0.name == name })
        else {
            return nil
        }

        let rawArguments: [String: Any]
        if let arguments = json["arguments"] {
            guard let object = arguments as? [String: Any] else {
                return nil
            }
            rawArguments = object
        } else {
            rawArguments = [:]
        }

        let arguments: [String: String]
        do {
            arguments = try AgentToolCallArgumentNormalizer.normalizedArguments(rawArguments: rawArguments, tool: tool)
        } catch {
            return nil
        }

        return AgentKernelToolCallV2(
            name: name,
            arguments: arguments,
            reason: json["reason"] as? String
        )
    }

    private nonisolated func decodeToolCall(
        _ json: [String: Any],
        tools: [AgentKernelToolSchemaV2]
    ) -> AgentKernelToolProtocolDecodeResultV2 {
        guard let name = json["name"] as? String, !name.isEmpty else {
            return .failure(reason(code: "text_protocol_missing_tool_name", summary: "Tool call output is missing tool name."))
        }
        guard let tool = tools.first(where: { $0.name == name }) else {
            return .failure(reason(code: "text_protocol_unknown_tool", summary: "Tool call output referenced an unknown tool."))
        }
        let rawArguments: [String: Any]
        if let arguments = json["arguments"] {
            guard let object = arguments as? [String: Any] else {
                return .failure(reason(code: "text_protocol_arguments_not_object", summary: "Tool call arguments must be a JSON object."))
            }
            rawArguments = object
        } else {
            rawArguments = [:]
        }
        let arguments: [String: String]
        do {
            arguments = try AgentToolCallArgumentNormalizer.normalizedArguments(rawArguments: rawArguments, tool: tool)
        } catch let error as AgentToolContractError {
            return .failure(toolArgumentFailure(error, toolName: name))
        } catch {
            return .failure(reason(code: "text_protocol_malformed_tool_argument", summary: "Tool call output included malformed arguments."))
        }

        return .event(
            .toolCall(
                AgentKernelToolCallV2(
                    name: name,
                    arguments: arguments,
                    reason: json["reason"] as? String
                )
            )
        )
    }

    private nonisolated func toolArgumentFailure(
        _ error: AgentToolContractError,
        toolName: String
    ) -> AgentKernelTerminalReasonV2 {
        switch error {
        case .unknownTool(let name):
            return reason(
                code: "text_protocol_unknown_tool",
                summary: "Tool call output requested a tool that is not available.",
                metadata: ["tool": .string(name)]
            )
        case .unknownArgument(let argument):
            return reason(
                code: "text_protocol_unknown_tool_argument",
                summary: "Tool call output included an argument that is not in the tool schema.",
                metadata: ["tool": .string(toolName), "argument": .string(argument)]
            )
        case .missingRequiredArgument(let argument):
            return reason(
                code: "text_protocol_missing_tool_argument",
                summary: "Tool call output is missing required argument(s).",
                metadata: ["tool": .string(toolName), "missing": .string(argument)]
            )
        case .malformedArgument(let argument, let type, _):
            return reason(
                code: "text_protocol_malformed_tool_argument",
                summary: "Tool call output included an argument with the wrong type.",
                metadata: [
                    "tool": .string(toolName),
                    "argument": .string(argument),
                    "type": .string(type.rawValue)
                ]
            )
        case .constraintViolation(let argument, let summary):
            return reason(
                code: "text_protocol_malformed_tool_argument",
                summary: summary,
                metadata: ["tool": .string(toolName), "argument": .string(argument)]
            )
        }
    }

    private nonisolated func reason(
        code: String,
        summary: String,
        metadata: [String: AgentKernelMetadataValueV2] = [:]
    ) -> AgentKernelTerminalReasonV2 {
        AgentKernelTerminalReasonV2(
            code: code,
            summary: AgentKernelBoundedTextV2(summary),
            metadata: metadata
        )
    }

    private nonisolated func protocolPayload(from text: String) -> String {
        var cleaned = stripBoundaryProtocolMarkers(from: text)
        if let fenced = markdownFencePayload(from: cleaned) {
            cleaned = stripBoundaryProtocolMarkers(from: fenced)
        }
        return cleaned
    }

    private nonisolated func stripBoundaryProtocolMarkers(from text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let leadingMarkers = [
            "<|im_start|>assistant",
            "<im_start>assistant",
            "<lim_start>assistant",
            "<|assistant|>",
            "<assistant>",
            "Assistant:"
        ]
        let trailingMarkers = [
            "<|im_end|>",
            "<|end|>",
            "<|endoftext|>",
            "<lim_end>"
        ]

        var changed = true
        while changed {
            changed = false
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

            for marker in leadingMarkers {
                if cleaned.range(of: marker, options: [.caseInsensitive, .anchored]) != nil {
                    cleaned.removeFirst(marker.count)
                    changed = true
                    break
                }
            }
            if changed {
                continue
            }

            for marker in trailingMarkers {
                if cleaned.range(of: marker, options: [.caseInsensitive, .backwards, .anchored]) != nil {
                    cleaned.removeLast(marker.count)
                    changed = true
                    break
                }
            }
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated func markdownFencePayload(from text: String) -> String? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.hasPrefix("```") else {
            return nil
        }
        let afterOpeningFence = cleaned.dropFirst(3)
        guard let firstLineBreak = afterOpeningFence.firstIndex(where: { $0.isNewline }) else {
            return nil
        }
        let bodyStart = afterOpeningFence.index(after: firstLineBreak)
        let body = String(afterOpeningFence[bodyStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard body.hasSuffix("```") else {
            return nil
        }
        return String(body.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AgentKernelModelOutputNormalizerV2: Sendable {
    private let decoder: AgentKernelToolProtocolDecoderV2

    nonisolated init(decoder: AgentKernelToolProtocolDecoderV2 = AgentKernelToolProtocolDecoderV2()) {
        self.decoder = decoder
    }

    nonisolated func normalize(
        response: AgentKernelModelAdapterResponseV2,
        tools: [AgentKernelToolSchemaV2]
    ) -> AgentKernelModelAdapterResponseV2 {
        let normalizedEvents = response.events.map { normalize(event: $0, tools: tools) }
        guard normalizedEvents != response.events else {
            return response
        }
        return AgentKernelModelAdapterResponseV2(
            requestID: response.requestID,
            descriptor: response.descriptor,
            events: normalizedEvents,
            diagnostics: response.diagnostics
        )
    }

    nonisolated func normalize(
        event: AgentKernelModelAdapterEventV2,
        tools: [AgentKernelToolSchemaV2]
    ) -> AgentKernelModelAdapterEventV2 {
        guard case .finalAnswer(let answer) = event else {
            return event
        }
        return normalizedFinalAnswer(answer.text, tools: tools) ?? event
    }

    nonisolated func normalizedFinalAnswer(
        _ text: String,
        tools: [AgentKernelToolSchemaV2]
    ) -> AgentKernelModelAdapterEventV2? {
        switch decoder.decode(text, tools: tools, requiresProtocolEnvelope: false) {
        case .event(let event):
            return event
        case .notProtocol:
            return nil
        case .failure(let reason):
            return .malformedOutput(reason.summary.text)
        }
    }
}
