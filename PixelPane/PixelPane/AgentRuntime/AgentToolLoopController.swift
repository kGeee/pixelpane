//
//  AgentToolLoopController.swift
//  PixelPane
//
//  Pure loop-control decisions for the tool-calling loop: repeated-call
//  tracking, the no-progress guard, and terminal-block reasons. Extracted
//  from AgentToolOrchestrator so the loop's control flow is decided in one
//  testable place. This type performs no I/O; the orchestrator still owns
//  model calls, tool execution, and durable writes.
//

import Foundation

nonisolated struct AgentToolLoopController: Sendable {
    let maxIterations: Int

    private var toolCallHistory: [String: Int] = [:]

    init(maxIterations: Int) {
        self.maxIterations = max(1, maxIterations)
    }

    /// Records a tool-call signature and returns how many times the same
    /// signature was seen *before* this call.
    mutating func registerToolCall(signature: String) -> Int {
        let priorCount = toolCallHistory[signature, default: 0]
        toolCallHistory[signature] = priorCount + 1
        return priorCount
    }

    /// True when the same tool call has already been seen and just failed again.
    func isRepeatedFailingCall(status: AgentToolExecutionStatus, priorCount: Int) -> Bool {
        status == .failed && priorCount >= 1
    }

    /// The same exact tool call (name + arguments) issued this many prior times
    /// is treated as no progress. A repeated deterministic call (e.g. re-reading
    /// the same file) yields no new information, and a repeated failing call is
    /// stuck; either way the loop should stop and synthesize a best-effort answer
    /// from what it already gathered rather than burning the whole budget.
    static let repeatedCallHaltThreshold = 2

    enum NoProgressDecision: Equatable {
        /// Stop looping: attempt a best-effort answer, then block if that fails.
        case halt
        /// Continue the loop, feeding back a tool observation.
        case `continue`(repeatedFailingCall: Bool)
    }

    /// Decides whether the loop should halt for lack of progress after a tool
    /// result. Halts once the same call signature has been issued
    /// `repeatedCallHaltThreshold` times, regardless of whether those calls
    /// succeeded or failed: re-issuing an identical call makes no progress
    /// (RELY-004 / RC-4; chat1/chat2 repeated-read loop).
    func noProgressDecision(status: AgentToolExecutionStatus, priorCount: Int) -> NoProgressDecision {
        if priorCount >= Self.repeatedCallHaltThreshold {
            return .halt
        }
        return .continue(repeatedFailingCall: isRepeatedFailingCall(status: status, priorCount: priorCount))
    }

    // MARK: - Model-facing text

    func repeatedFailingObservation(toolName: String, summary: String) -> String {
        """
        You already called \(toolName) with the same arguments and it failed: \(summary)
        Do not repeat that exact call. Call list_grants to see valid writable targets, choose different arguments or a different tool, or produce your best final answer now.
        """
    }

    func noProgressBlockReason(summary: String) -> String {
        "The agent repeated the same failing action without making progress. \(summary)"
    }

    func maxIterationsBlockReason() -> String {
        AgentToolOrchestratorError.maxIterationsExceeded(maxIterations).description
    }
}
