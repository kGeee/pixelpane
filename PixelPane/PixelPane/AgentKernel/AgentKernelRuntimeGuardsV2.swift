import Foundation

enum AgentKernelToolRiskV2: String, Codable, Equatable, Sendable {
    case readOnly
    case sideEffect
    case privileged
}

struct AgentKernelToolPolicyV2: Codable, Equatable, Sendable {
    let toolName: String
    let risk: AgentKernelToolRiskV2
    let requiresApproval: Bool

    nonisolated init(
        toolName: String,
        risk: AgentKernelToolRiskV2,
        requiresApproval: Bool
    ) {
        self.toolName = toolName
        self.risk = risk
        self.requiresApproval = requiresApproval
    }
}

enum AgentKernelGuardDecisionV2: Equatable, Sendable {
    case proceed
    case requestApproval(AgentKernelApprovalRequestV2)
    case forceSynthesis(AgentKernelTerminalReasonV2)
    case block(AgentKernelTerminalReasonV2)
    case canceled(AgentKernelTerminalReasonV2)
    case resumed
}

struct AgentKernelRuntimeGuardsV2: Sendable {
    let repeatedModelResponseLimit: Int

    nonisolated init(repeatedModelResponseLimit: Int = 2) {
        self.repeatedModelResponseLimit = max(1, repeatedModelResponseLimit)
    }

    nonisolated func approvalDecision(
        for call: AgentKernelToolCallV2,
        policy: AgentKernelToolPolicyV2,
        reason: AgentKernelBoundedTextV2
    ) -> AgentKernelGuardDecisionV2 {
        guard policy.requiresApproval || policy.risk != .readOnly else {
            return .proceed
        }

        return .requestApproval(
            AgentKernelApprovalRequestV2(
                toolCallID: call.id,
                toolName: call.name,
                riskClass: policy.risk.rawValue,
                reason: reason,
                displaySummary: AgentKernelBoundedTextV2(call.signature)
            )
        )
    }

    nonisolated func toolProposalDecision(
        for call: AgentKernelToolCallV2,
        ledger: AgentKernelSessionLedgerV2
    ) -> AgentKernelGuardDecisionV2 {
        if hasRepeatedObservedToolCall(call, in: ledger) {
            return .block(
                AgentKernelTerminalReasonV2(
                    code: "duplicate_tool_call_after_same_result",
                    summary: AgentKernelBoundedTextV2("The model repeated a tool call after the same result was already observed."),
                    metadata: ["tool": .string(call.name)]
                )
            )
        }
        return .proceed
    }

    nonisolated func modelResponseDecision(
        events: [AgentKernelModelEventV2],
        ledger: AgentKernelSessionLedgerV2
    ) -> AgentKernelGuardDecisionV2 {
        if let repeatedCall = events.firstRepeatedObservedToolCall(in: ledger) {
            return .forceSynthesis(
                AgentKernelTerminalReasonV2(
                    code: "repeated_observed_step",
                    summary: AgentKernelBoundedTextV2("The model repeated an already-observed step and should synthesize from available observations."),
                    metadata: ["tool": .string(repeatedCall.name)]
                )
            )
        }

        let signature = events.modelResponseSignature
        guard !signature.isEmpty else {
            return .proceed
        }

        let previousMatches = ledger.events.filter { event in
            guard case .modelResponse(_, let previousEvents) = event.payload else {
                return false
            }
            return previousEvents.modelResponseSignature == signature
        }.count

        if previousMatches + 1 >= repeatedModelResponseLimit {
            return .block(
                AgentKernelTerminalReasonV2(
                    code: "no_progress_model_loop",
                    summary: AgentKernelBoundedTextV2("The model repeated the same response without producing new progress."),
                    metadata: ["signature": .string(signature)]
                )
            )
        }

        return .proceed
    }

    nonisolated func cancel(
        ledger: inout AgentKernelSessionLedgerV2,
        reason: AgentKernelTerminalReasonV2
    ) -> AgentKernelGuardDecisionV2 {
        ledger.append(.taskCanceled(reason))
        return .canceled(reason)
    }

    nonisolated func resume(
        ledger: inout AgentKernelSessionLedgerV2,
        approvalID: UUID,
        decision: AgentKernelApprovalDecisionV2 = .approved
    ) -> AgentKernelGuardDecisionV2 {
        ledger.append(
            .approvalResolved(
                AgentKernelApprovalResolutionV2(
                    approvalID: approvalID,
                    decision: decision
                )
            )
        )
        return .resumed
    }

    private nonisolated func hasRepeatedObservedToolCall(
        _ call: AgentKernelToolCallV2,
        in ledger: AgentKernelSessionLedgerV2
    ) -> Bool {
        var proposalSignaturesByID: [UUID: String] = [:]

        for event in ledger.events {
            switch event.payload {
            case .toolProposal(let previousCall):
                proposalSignaturesByID[previousCall.id] = previousCall.signature
            case .toolResult(let result):
                guard
                    let callID = result.toolCallID,
                    proposalSignaturesByID[callID] == call.signature
                else {
                    continue
                }
                return true
            default:
                continue
            }
        }

        return false
    }
}

private extension Array where Element == AgentKernelModelEventV2 {
    nonisolated var modelResponseSignature: String {
        map(\.stableSignature).joined(separator: "|")
    }

    nonisolated func firstRepeatedObservedToolCall(
        in ledger: AgentKernelSessionLedgerV2
    ) -> AgentKernelToolCallV2? {
        compactMap { event -> AgentKernelToolCallV2? in
            guard case .toolCall(let call) = event else {
                return nil
            }
            if AgentKernelRuntimeGuardsV2().toolProposalDecision(for: call, ledger: ledger).requiresSynthesisOrBlock {
                return call
            }
            return nil
        }.first
    }
}

private extension AgentKernelModelEventV2 {
    nonisolated var stableSignature: String {
        switch self {
        case .finalAnswer(let text):
            "final:\(text)"
        case .toolCall(let call):
            "tool:\(call.signature)"
        case .malformedOutput(let text):
            "malformed:\(text)"
        case .emptyOutput:
            "empty"
        case .timedOut:
            "timeout"
        }
    }
}

private extension AgentKernelToolCallV2 {
    nonisolated var signature: String {
        let sortedArguments = arguments
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        return "\(name)(\(sortedArguments))"
    }
}

private extension AgentKernelGuardDecisionV2 {
    nonisolated var requiresSynthesisOrBlock: Bool {
        switch self {
        case .forceSynthesis, .block:
            true
        case .proceed, .requestApproval, .canceled, .resumed:
            false
        }
    }
}
