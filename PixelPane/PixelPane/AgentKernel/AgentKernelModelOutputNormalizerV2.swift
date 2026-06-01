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
            guard let text = json["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(reason(code: "text_protocol_missing_final_text", summary: "Final answer output is missing non-empty text."))
            }
            return .event(.finalAnswer(text))
        case "tool_call":
            return decodeToolCall(json, tools: tools)
        default:
            return .failure(reason(code: "text_protocol_unknown_type", summary: "Text protocol output type is not supported."))
        }
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

        let repairedArguments = repairArguments(rawArguments, for: tool)
        let knownArguments = tool.knownArgumentNames
        guard repairedArguments.keys.allSatisfy({ knownArguments.contains($0) }) else {
            return nil
        }

        var arguments: [String: String] = [:]
        for (key, value) in repairedArguments {
            arguments[key] = stringArgument(from: value)
        }

        for argument in tool.arguments {
            guard let value = arguments[argument.name] else {
                continue
            }
            guard isValid(value: value, for: argument.type) else {
                return nil
            }
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
        let repairedArguments = repairArguments(rawArguments, for: tool)

        let knownArguments = tool.knownArgumentNames
        if let unknown = repairedArguments.keys.filter({ !knownArguments.contains($0) }).sorted().first {
            return .failure(
                reason(
                    code: "text_protocol_unknown_tool_argument",
                    summary: "Tool call output included an argument that is not in the tool schema.",
                    metadata: ["tool": .string(name), "argument": .string(unknown)]
                )
            )
        }

        var arguments: [String: String] = [:]
        for (key, value) in repairedArguments {
            arguments[key] = stringArgument(from: value)
        }

        let missing = tool.requiredArguments.filter { (arguments[$0] ?? "").isEmpty }
        guard missing.isEmpty else {
            return .failure(
                reason(
                    code: "text_protocol_missing_tool_argument",
                    summary: "Tool call output is missing required argument(s).",
                    metadata: ["tool": .string(name), "missing": .string(missing.joined(separator: ","))]
                )
            )
        }

        for argument in tool.arguments {
            guard let value = arguments[argument.name] else {
                continue
            }
            guard isValid(value: value, for: argument.type) else {
                return .failure(
                    reason(
                        code: "text_protocol_malformed_tool_argument",
                        summary: "Tool call output included an argument with the wrong type.",
                        metadata: [
                            "tool": .string(name),
                            "argument": .string(argument.name),
                            "type": .string(argument.type.rawValue)
                        ]
                    )
                )
            }
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

    private nonisolated func repairArguments(
        _ rawArguments: [String: Any],
        for tool: AgentKernelToolSchemaV2
    ) -> [String: Any] {
        guard tool.name == "stage_write_proposal" else {
            return rawArguments
        }

        var repaired = rawArguments
        if (stringValue(repaired["targetPath"]) ?? "").isEmpty,
           let path = stringValue(repaired["path"]),
           !path.isEmpty {
            repaired["targetPath"] = path
            repaired.removeValue(forKey: "path")
        }

        if (stringValue(repaired["operation"]) ?? "").isEmpty,
           !(stringValue(repaired["targetPath"]) ?? "").isEmpty,
           !(stringValue(repaired["content"]) ?? "").isEmpty {
            repaired["operation"] = "create"
        }

        return repaired
    }

    private nonisolated func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        return stringArgument(from: value)
    }

    private nonisolated func stringArgument(from value: Any) -> String {
        if let string = value as? String {
            return string
        }
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }
        if let int = value as? Int {
            return "\(int)"
        }
        if let double = value as? Double {
            return "\(double)"
        }
        if JSONSerialization.isValidJSONObject(value),
           let encoded = try? JSONSerialization.data(withJSONObject: value),
           let encodedString = String(data: encoded, encoding: .utf8) {
            return encodedString
        }
        return "\(value)"
    }

    private nonisolated func isValid(
        value: String,
        for type: AgentKernelToolArgumentTypeV2
    ) -> Bool {
        switch type {
        case .string:
            return true
        case .integer:
            return Int(value) != nil
        case .number:
            return Double(value) != nil
        case .boolean:
            return value == "true" || value == "false"
        case .jsonString:
            guard let data = value.data(using: .utf8) else {
                return false
            }
            return (try? JSONSerialization.jsonObject(with: data)) != nil
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
        guard case .finalAnswer(let text) = event else {
            return event
        }
        return normalizedFinalAnswer(text, tools: tools) ?? event
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
