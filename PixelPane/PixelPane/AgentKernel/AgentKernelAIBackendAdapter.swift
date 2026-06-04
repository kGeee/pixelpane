import Foundation

struct AgentKernelAIBackendAdapter: AgentKernelModelAdapter {
    let descriptor: AgentKernelModelDescriptor
    let capabilities: AgentKernelModelAdapterCapabilities
    private let backend: any AIBackend
    private let preferredProvider: AIBackendProvider?
    private let promptBuilder: AgentKernelTextProtocolPromptBuilder
    private let parser: AgentKernelTextProtocolParser
    private let allowsSingleRepairAttempt: Bool

    nonisolated init(
        descriptor: AgentKernelModelDescriptor,
        backend: any AIBackend,
        capabilities: AgentKernelModelAdapterCapabilities,
        preferredProvider: AIBackendProvider? = nil,
        promptBuilder: AgentKernelTextProtocolPromptBuilder = AgentKernelTextProtocolPromptBuilder(),
        parser: AgentKernelTextProtocolParser = AgentKernelTextProtocolParser(),
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
        for request: AgentKernelModelAdapterRequest
    ) async -> AgentKernelModelAdapterResponse {
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
            return AgentKernelModelAdapterResponse(
                requestID: request.id,
                descriptor: descriptor,
                events: trimmed.isEmpty ? [.emptyOutput] : [.finalAnswer(trimmed)]
            )
        } catch is CancellationError {
            return AgentKernelModelAdapterResponse(
                requestID: request.id,
                descriptor: descriptor,
                events: [.timedOut],
                diagnostics: AgentKernelBoundedText("Request was canceled.")
            )
        } catch {
            return AgentKernelModelAdapterResponse(
                requestID: request.id,
                descriptor: descriptor,
                events: [.transportFailure(error.localizedDescription)],
                diagnostics: AgentKernelBoundedText(error.localizedDescription)
            )
        }
    }

    nonisolated func stream(
        for request: AgentKernelModelAdapterRequest
    ) -> AsyncStream<AgentKernelModelAdapterEvent> {
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
                    continuation.yield(.transportFailure(error.localizedDescription))
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
        originalRequest request: AgentKernelModelAdapterRequest
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
            do {
                let repairedText = try await completeText(prompt: repairPrompt, request: request)
                switch parser.parse(repairedText, tools: request.tools) {
                case .success(let event):
                    return response(for: request, events: [event], diagnostics: reason.summary)
                case .failure(let repairReason):
                    return response(for: request, events: [.malformedOutput(repairedText)], diagnostics: repairReason.summary)
                }
            } catch {
                return response(for: request, events: [.transportFailure(error.localizedDescription)], diagnostics: reason.summary)
            }
        }
    }

    private nonisolated func completeText(
        prompt: String,
        request: AgentKernelModelAdapterRequest
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

    private nonisolated func plainPrompt(for messages: [AgentKernelMessage]) -> String {
        messages.map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n")
    }
}

extension AgentKernelModelAdapterCapabilities {
    nonisolated static func aiBackendBridge(
        descriptor: AgentKernelModelDescriptor,
        backendCapabilities: AIBackendCapabilities
    ) -> AgentKernelModelAdapterCapabilities {
        var inputModalities: Set<AgentKernelModelInputModality> = []
        if backendCapabilities.text.isAvailable {
            inputModalities.insert(.text)
        }
        if backendCapabilities.image.isAvailable {
            inputModalities.insert(.image)
        }
        let unavailableReason: AgentKernelBoundedText?
        if inputModalities.isEmpty {
            unavailableReason = AgentKernelBoundedText(backendCapabilities.text.detail)
        } else {
            unavailableReason = nil
        }
        let textProvider: AIBackendProvider?
        if case .available(let provider) = backendCapabilities.text {
            textProvider = provider
        } else {
            textProvider = nil
        }
        return AgentKernelModelAdapterCapabilities(
            descriptor: descriptor,
            inputModalities: inputModalities.isEmpty ? [.text] : inputModalities,
            outputModalities: [.text],
            toolCallingMode: textProvider == .mlxText ? .native : .textProtocol,
            structuredOutputReliability: .bestEffort,
            streamingMode: .snapshots,
            limits: AgentKernelModelLimits(
                contextWindowTokens: backendCapabilities.contextWindowTokens,
                maxPromptCharacters: backendCapabilities.maxPromptCharacters,
                maxOutputTokens: backendCapabilities.maxOutputTokens
            ),
            isAvailable: !inputModalities.isEmpty,
            unavailableReason: unavailableReason
        )
    }
}
