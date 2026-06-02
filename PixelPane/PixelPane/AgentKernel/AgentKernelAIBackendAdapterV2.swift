import Foundation

struct AgentKernelAIBackendAdapterV2: AgentKernelModelAdapterV2 {
    let descriptor: AgentKernelModelDescriptorV2
    let capabilities: AgentKernelModelAdapterCapabilitiesV2
    private let backend: any AIBackend
    private let preferredProvider: AIBackendProvider?
    private let promptBuilder: AgentKernelTextProtocolPromptBuilderV2
    private let parser: AgentKernelTextProtocolParserV2
    private let allowsSingleRepairAttempt: Bool

    nonisolated init(
        descriptor: AgentKernelModelDescriptorV2,
        backend: any AIBackend,
        capabilities: AgentKernelModelAdapterCapabilitiesV2,
        preferredProvider: AIBackendProvider? = nil,
        promptBuilder: AgentKernelTextProtocolPromptBuilderV2 = AgentKernelTextProtocolPromptBuilderV2(),
        parser: AgentKernelTextProtocolParserV2 = AgentKernelTextProtocolParserV2(),
        allowsSingleRepairAttempt: Bool = true
    ) {
        self.descriptor = descriptor
        self.capabilities = capabilities
        self.backend = backend
        self.preferredProvider = preferredProvider
        self.promptBuilder = promptBuilder
        self.parser = parser
        self.allowsSingleRepairAttempt = allowsSingleRepairAttempt
    }

    nonisolated func response(
        for request: AgentKernelModelAdapterRequestV2
    ) async -> AgentKernelModelAdapterResponseV2 {
        let shouldUseProtocol = !request.tools.isEmpty || request.responseFormat == .textProtocol
        let prompt = shouldUseProtocol
            ? promptBuilder.prompt(for: request)
            : plainPrompt(for: request.messages)

        do {
            let text = try await completeText(prompt: prompt, request: request)
            if shouldUseProtocol {
                return await parseOrRepair(text, originalRequest: request)
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return AgentKernelModelAdapterResponseV2(
                requestID: request.id,
                descriptor: descriptor,
                events: trimmed.isEmpty ? [.emptyOutput] : [.finalAnswer(trimmed)]
            )
        } catch is CancellationError {
            return AgentKernelModelAdapterResponseV2(
                requestID: request.id,
                descriptor: descriptor,
                events: [.timedOut],
                diagnostics: AgentKernelBoundedTextV2("Request was canceled.")
            )
        } catch {
            return AgentKernelModelAdapterResponseV2(
                requestID: request.id,
                descriptor: descriptor,
                events: [.malformedOutput(error.localizedDescription)],
                diagnostics: AgentKernelBoundedTextV2(error.localizedDescription)
            )
        }
    }

    nonisolated func stream(
        for request: AgentKernelModelAdapterRequestV2
    ) -> AsyncStream<AgentKernelModelAdapterEventV2> {
        AsyncStream { continuation in
            let task = Task {
                let shouldUseProtocol = !request.tools.isEmpty || request.responseFormat == .textProtocol
                let prompt = shouldUseProtocol
                    ? promptBuilder.prompt(for: request)
                    : plainPrompt(for: request.messages)
                do {
                    let backendRequest = AIBackendRequest(
                        actionKind: .chat,
                        prompt: prompt,
                        maxOutputTokens: request.requestedMaxOutputTokens,
                        preferredProvider: preferredProvider
                    )
                    var finalText = ""
                    for try await event in backend.streamResponse(for: backendRequest) {
                        switch event {
                        case .snapshot(let text):
                            finalText = text
                            if !shouldUseProtocol {
                                continuation.yield(.snapshot(text))
                            }
                        case .output(let output):
                            finalText = shouldUseProtocol ? (output.rawText ?? output.finalText) : output.finalText
                        case .metadata:
                            continue
                        case .completed:
                            break
                        }
                    }
                    if shouldUseProtocol {
                        for event in await parseOrRepair(finalText, originalRequest: request).events {
                            continuation.yield(event)
                        }
                    } else if !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        continuation.yield(.finalAnswer(finalText))
                    } else {
                        continuation.yield(.emptyOutput)
                    }
                    continuation.finish()
                } catch {
                    continuation.yield(.malformedOutput(error.localizedDescription))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private nonisolated func parseOrRepair(
        _ text: String,
        originalRequest request: AgentKernelModelAdapterRequestV2
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
            do {
                let repairedText = try await completeText(prompt: repairPrompt, request: request)
                switch parser.parse(repairedText, tools: request.tools) {
                case .success(let event):
                    return response(for: request, events: [event], diagnostics: reason.summary)
                case .failure(let repairReason):
                    return response(for: request, events: [.malformedOutput(repairedText)], diagnostics: repairReason.summary)
                }
            } catch {
                return response(for: request, events: [.malformedOutput(error.localizedDescription)], diagnostics: reason.summary)
            }
        }
    }

    private nonisolated func completeText(
        prompt: String,
        request: AgentKernelModelAdapterRequestV2
    ) async throws -> String {
        let backendRequest = AIBackendRequest(
            actionKind: .chat,
            prompt: prompt,
            maxOutputTokens: request.requestedMaxOutputTokens,
            preferredProvider: preferredProvider
        )
        var latestSnapshot = ""
        var finalOutput: String?
        let shouldUseProtocol = !request.tools.isEmpty || request.responseFormat == .textProtocol
        for try await event in backend.streamResponse(for: backendRequest) {
            try Task.checkCancellation()
            switch event {
            case .metadata:
                continue
            case .snapshot(let text):
                latestSnapshot = text
            case .output(let output):
                finalOutput = shouldUseProtocol ? (output.rawText ?? output.finalText) : output.finalText
            case .completed:
                break
            }
        }
        return finalOutput ?? latestSnapshot
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

    private nonisolated func plainPrompt(for messages: [AgentKernelMessageV2]) -> String {
        messages.map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n")
    }
}

extension AgentKernelModelAdapterCapabilitiesV2 {
    nonisolated static func aiBackendBridge(
        descriptor: AgentKernelModelDescriptorV2,
        backendCapabilities: AIBackendCapabilities
    ) -> AgentKernelModelAdapterCapabilitiesV2 {
        var inputModalities: Set<AgentKernelModelInputModalityV2> = []
        if backendCapabilities.text.isAvailable {
            inputModalities.insert(.text)
        }
        if backendCapabilities.image.isAvailable {
            inputModalities.insert(.image)
        }
        let unavailableReason: AgentKernelBoundedTextV2?
        if inputModalities.isEmpty {
            unavailableReason = AgentKernelBoundedTextV2(backendCapabilities.text.detail)
        } else {
            unavailableReason = nil
        }
        let textProvider: AIBackendProvider?
        if case .available(let provider) = backendCapabilities.text {
            textProvider = provider
        } else {
            textProvider = nil
        }
        return AgentKernelModelAdapterCapabilitiesV2(
            descriptor: descriptor,
            inputModalities: inputModalities.isEmpty ? [.text] : inputModalities,
            outputModalities: [.text],
            toolCallingMode: textProvider == .mlxText ? .native : .textProtocol,
            structuredOutputReliability: .bestEffort,
            streamingMode: .snapshots,
            limits: AgentKernelModelLimitsV2(
                contextWindowTokens: backendCapabilities.contextWindowTokens,
                maxPromptCharacters: backendCapabilities.maxPromptCharacters,
                maxOutputTokens: backendCapabilities.maxOutputTokens
            ),
            isAvailable: !inputModalities.isEmpty,
            unavailableReason: unavailableReason
        )
    }
}
