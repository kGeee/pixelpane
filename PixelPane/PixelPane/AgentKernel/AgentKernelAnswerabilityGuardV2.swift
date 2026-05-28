import Foundation

struct AgentKernelAnswerabilityGuardV2: Sendable {
    enum Intervention: Sendable {
        case retryWithObservation(AgentKernelToolResultV2)
        case block(AgentKernelTerminalReasonV2)
    }

    nonisolated init() {}

    nonisolated func intervention(
        finalAnswer: String,
        ledger: AgentKernelSessionLedgerV2,
        availableTools: [AgentKernelToolSchemaV2]
    ) -> Intervention? {
        guard !availableTools.isEmpty,
              defersDespiteTooling(finalAnswer, availableTools: availableTools)
        else {
            return nil
        }

        let latestUserSequence = ledger.latestUserSequenceForAnswerability
        if alreadyRetriedAfterLatestUser(ledger: ledger, latestUserSequence: latestUserSequence) {
            return .block(
                AgentKernelTerminalReasonV2(
                    code: "answerability_deferred_after_retry",
                    summary: AgentKernelBoundedTextV2("The model kept deferring instead of using an available runtime capability or answering from collected evidence."),
                    metadata: ["toolCount": .int(availableTools.count)]
                )
            )
        }

        return .retryWithObservation(
            AgentKernelToolResultV2(
                toolName: "answerability_guard",
                status: .failed,
                summary: AgentKernelBoundedTextV2(retrySummary(availableTools: availableTools)),
                metadata: [
                    "code": .string("answerability_deferred_with_available_tools"),
                    "availableTools": .string(availableTools.map(\.name).sorted().joined(separator: ","))
                ]
            )
        )
    }

    private nonisolated func defersDespiteTooling(
        _ finalAnswer: String,
        availableTools: [AgentKernelToolSchemaV2]
    ) -> Bool {
        let normalized = finalAnswer.normalizedForAnswerabilityGuard
        if asksForPreConfirmation(normalized) {
            return true
        }
        guard soundsLikeMissingEvidence(normalized) else {
            return false
        }
        return mentionsAvailableCapability(normalized, availableTools: availableTools)
    }

    private nonisolated func asksForPreConfirmation(_ text: String) -> Bool {
        [
            "would you like me to",
            "do you want me to",
            "should i",
            "shall i",
            "proceed with",
            "proceed to"
        ].contains { text.contains($0) }
    }

    private nonisolated func soundsLikeMissingEvidence(_ text: String) -> Bool {
        [
            "cannot confirm",
            "can't confirm",
            "cannot determine",
            "can't determine",
            "cannot verify",
            "can't verify",
            "do not have that information",
            "don't have that information",
            "would need to",
            "need to check",
            "need to probe",
            "not currently have"
        ].contains { text.contains($0) }
    }

    private nonisolated func mentionsAvailableCapability(
        _ text: String,
        availableTools: [AgentKernelToolSchemaV2]
    ) -> Bool {
        let vocabulary = capabilityVocabulary(from: availableTools)
        return vocabulary.contains { token in
            token.count >= 4 && text.contains(token)
        }
    }

    private nonisolated func capabilityVocabulary(
        from tools: [AgentKernelToolSchemaV2]
    ) -> Set<String> {
        var tokens: Set<String> = []
        for tool in tools {
            collectTokens(from: tool.name, into: &tokens)
            collectTokens(from: tool.summary, into: &tokens)
            for argument in tool.arguments {
                collectTokens(from: argument.name, into: &tokens)
                collectTokens(from: argument.summary, into: &tokens)
            }
        }
        return tokens.subtracting(Self.noisyCapabilityTokens)
    }

    private nonisolated func collectTokens(from text: String, into tokens: inout Set<String>) {
        let normalized = text.normalizedForAnswerabilityGuard
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        for token in normalized.split(separator: " ") {
            let cleaned = token.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            if cleaned.count >= 4 {
                tokens.insert(cleaned)
            }
        }
    }

    private nonisolated func alreadyRetriedAfterLatestUser(
        ledger: AgentKernelSessionLedgerV2,
        latestUserSequence: Int
    ) -> Bool {
        ledger.events.contains { event in
            guard event.sequence > latestUserSequence,
                  case .toolResult(let result) = event.payload
            else {
                return false
            }
            return result.toolName == "answerability_guard"
        }
    }

    private nonisolated func retrySummary(
        availableTools: [AgentKernelToolSchemaV2]
    ) -> String {
        let names = availableTools.map(\.name).sorted().joined(separator: ", ")
        return "The final answer deferred work even though runtime capabilities are available. Continue by proposing one of the available tools or by answering from existing evidence. Do not ask for pre-confirmation; side-effect tools use the app approval flow. Available tools: \(names)."
    }

    private nonisolated static let noisyCapabilityTokens: Set<String> = [
        "with",
        "that",
        "this",
        "from",
        "into",
        "inside",
        "without",
        "optional",
        "local",
        "runtime",
        "available",
        "evidence",
        "summary",
        "source",
        "record",
        "records"
    ]
}

private extension AgentKernelSessionLedgerV2 {
    nonisolated var latestUserSequenceForAnswerability: Int {
        events.last { event in
            guard case .userMessage = event.payload else { return false }
            return true
        }?.sequence ?? -1
    }
}

private extension String {
    nonisolated var normalizedForAnswerabilityGuard: String {
        lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }
}
