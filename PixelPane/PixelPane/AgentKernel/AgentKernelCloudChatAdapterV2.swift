import Foundation

struct AgentKernelCloudChatAdapterV2: AgentKernelModelAdapterV2 {
    let descriptor: AgentKernelModelDescriptorV2
    let capabilities: AgentKernelModelAdapterCapabilitiesV2

    private let backend: any AIBackend
    private let preferredProvider: AIBackendProvider?
    private let supportsLocalToolProtocol: Bool
    private let promptBuilder: AgentKernelTextProtocolPromptBuilderV2
    private let parser: AgentKernelTextProtocolParserV2
    private let allowsSingleRepairAttempt: Bool

    nonisolated init(
        descriptor: AgentKernelModelDescriptorV2,
        backend: any AIBackend,
        backendCapabilities: AIBackendCapabilities,
        preferredProvider: AIBackendProvider? = .pixelPaneCloud,
        supportsLocalToolProtocol: Bool = false,
        promptBuilder: AgentKernelTextProtocolPromptBuilderV2 = AgentKernelTextProtocolPromptBuilderV2(),
        parser: AgentKernelTextProtocolParserV2 = AgentKernelTextProtocolParserV2(),
        allowsSingleRepairAttempt: Bool = true
    ) {
        self.descriptor = descriptor
        self.backend = backend
        self.preferredProvider = preferredProvider
        self.supportsLocalToolProtocol = supportsLocalToolProtocol
        self.promptBuilder = promptBuilder
        self.parser = parser
        self.allowsSingleRepairAttempt = allowsSingleRepairAttempt
        self.capabilities = AgentKernelModelAdapterCapabilitiesV2.cloudChat(
            descriptor: descriptor,
            backendCapabilities: backendCapabilities,
            supportsLocalToolProtocol: supportsLocalToolProtocol
        )
    }

    nonisolated func response(
        for request: AgentKernelModelAdapterRequestV2
    ) async -> AgentKernelModelAdapterResponseV2 {
        let shouldUseProtocol = !request.tools.isEmpty || request.responseFormat == .textProtocol
        if shouldUseProtocol {
            guard supportsLocalToolProtocol, request.responseFormat == .textProtocol else {
                return AgentKernelModelAdapterResponseV2(
                    requestID: request.id,
                    descriptor: descriptor,
                    events: [.malformedOutput("Cloud chat adapter does not support local tools or structured tool protocol.")],
                    diagnostics: AgentKernelBoundedTextV2("Cloud chat adapter received an unsupported tool-mode request.")
                )
            }

            let prompt = promptBuilder.prompt(for: request)
            do {
                let text = try await completeCloudQuestion(prompt, request: request)
                return await parseOrRepair(text, originalRequest: request)
            } catch is CancellationError {
                return AgentKernelModelAdapterResponseV2(
                    requestID: request.id,
                    descriptor: descriptor,
                    events: [.timedOut],
                    diagnostics: AgentKernelBoundedTextV2("Cloud chat request was canceled.")
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

        guard request.responseFormat == .none else {
            return AgentKernelModelAdapterResponseV2(
                requestID: request.id,
                descriptor: descriptor,
                events: [.malformedOutput("Cloud chat adapter does not support local tools or structured tool protocol.")],
                diagnostics: AgentKernelBoundedTextV2("Cloud chat adapter received an unsupported tool-mode request.")
            )
        }

        let input = Self.cloudChatInput(from: request.messages)
        guard !input.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AgentKernelModelAdapterResponseV2(
                requestID: request.id,
                descriptor: descriptor,
                events: [.emptyOutput],
                diagnostics: AgentKernelBoundedTextV2("Cloud chat request did not contain a user question.")
            )
        }

        do {
            let backendRequest = AIBackendRequest(
                actionKind: .chat,
                prompt: input.question,
                maxOutputTokens: request.requestedMaxOutputTokens,
                preferredProvider: preferredProvider,
                cloudQuestion: input.question,
                cloudConversation: input.conversation
            )
            var finalText = ""
            for try await event in backend.streamResponse(for: backendRequest) {
                switch event {
                case .metadata:
                    continue
                case .snapshot(let text):
                    finalText = text
                case .output(let output):
                    finalText = output.finalText
                case .completed:
                    break
                }
            }

            let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
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
                diagnostics: AgentKernelBoundedTextV2("Cloud chat request was canceled.")
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
                let repairedText = try await completeCloudQuestion(repairPrompt, request: request)
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

    private nonisolated func completeCloudQuestion(
        _ prompt: String,
        request: AgentKernelModelAdapterRequestV2
    ) async throws -> String {
        let backendRequest = AIBackendRequest(
            actionKind: .chat,
            prompt: prompt,
            maxOutputTokens: request.requestedMaxOutputTokens,
            preferredProvider: preferredProvider,
            cloudQuestion: prompt,
            cloudConversation: []
        )
        var finalText = ""
        for try await event in backend.streamResponse(for: backendRequest) {
            try Task.checkCancellation()
            switch event {
            case .metadata:
                continue
            case .snapshot(let text):
                finalText = text
            case .output(let output):
                finalText = output.rawText ?? output.finalText
            case .completed:
                break
            }
        }
        return finalText
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

    private nonisolated static func cloudChatInput(
        from messages: [AgentKernelMessageV2]
    ) -> (question: String, conversation: [AIBackendConversationTurn]) {
        let latestUserIndex = messages.lastIndex { $0.role == .user }
        let question = latestUserIndex.map { messages[$0].content }
            ?? messages.map(\.content).joined(separator: "\n")
        let priorMessages = latestUserIndex.map { messages[..<$0] } ?? messages[...]
        let conversation = priorMessages.compactMap { message -> AIBackendConversationTurn? in
            let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            switch message.role {
            case .user:
                return AIBackendConversationTurn(role: .user, content: trimmed)
            case .assistant:
                return AIBackendConversationTurn(role: .assistant, content: trimmed)
            case .system, .observation:
                return nil
            }
        }
        return (question, conversation)
    }
}

extension AgentKernelModelAdapterCapabilitiesV2 {
    nonisolated static func cloudChat(
        descriptor: AgentKernelModelDescriptorV2,
        backendCapabilities: AIBackendCapabilities,
        supportsLocalToolProtocol: Bool = false
    ) -> AgentKernelModelAdapterCapabilitiesV2 {
        let isAvailable = backendCapabilities.text.isAvailable
        return AgentKernelModelAdapterCapabilitiesV2(
            descriptor: descriptor,
            inputModalities: [.text],
            outputModalities: [.text],
            toolCallingMode: supportsLocalToolProtocol ? .textProtocol : .none,
            structuredOutputReliability: supportsLocalToolProtocol ? .bestEffort : .unsupported,
            streamingMode: .snapshots,
            limits: AgentKernelModelLimitsV2(
                contextWindowTokens: backendCapabilities.contextWindowTokens,
                maxPromptCharacters: backendCapabilities.maxPromptCharacters,
                maxOutputTokens: backendCapabilities.maxOutputTokens
            ),
            isAvailable: isAvailable,
            unavailableReason: isAvailable ? nil : AgentKernelBoundedTextV2(backendCapabilities.text.detail)
        )
    }
}
