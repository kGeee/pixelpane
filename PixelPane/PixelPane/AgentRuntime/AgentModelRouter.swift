//
//  AgentModelRouter.swift
//  PixelPane
//
//  Pure model-routing policy. Given what a run needs (tool-capable vs plain
//  chat), the pool of candidate models with their *measured* conformance tiers,
//  and the user's routing flags, it picks one candidate -- predictively, once,
//  at run start. It performs no I/O and knows nothing about model names: it
//  routes on measured capability + run need + policy, so an unknown downloaded
//  model is just "probe it -> get a tier -> route on the tier".
//
//  The orchestrator/AppState maps installed models + cached conformance profiles
//  into candidates, calls choose(), and builds the chosen backend from the result.
//

import Foundation

nonisolated enum AgentModelRunNeed: String, Codable, Equatable, Sendable {
    /// The run will use local tools / file grants and must drive a tool loop.
    case toolCapable
    /// Plain conversational answer; any chat-capable model will do.
    case plainChat
}

nonisolated enum AgentModelRouteKind: String, Codable, Equatable, Sendable {
    case local
    case cloud
}

nonisolated enum AgentModelRoutePreference: String, Codable, Equatable, Sendable {
    /// Pick the most capable model available (cloud/highest tier first).
    case preferQuality
    /// Stay on-device and fast where the need is still met (avoid swaps/cloud).
    case preferLocalFast
}

/// A routable model, decoupled from the heavy adapter/backend types so the
/// policy stays pure and unit-testable. `id` is the caller's stable key
/// (e.g. a conformance target storage key, or a cloud sentinel).
nonisolated struct AgentModelRouterCandidate: Equatable, Sendable {
    let id: String
    let displayName: String
    let kind: AgentModelRouteKind
    let tier: AgentModelConformanceDerivedTier
    /// True when this model is already warm/loaded, so choosing it incurs no swap.
    let isLoaded: Bool
    /// Optional latency hint (seconds); lower is preferred when tiers tie.
    let latencyHint: Double?

    init(
        id: String,
        displayName: String,
        kind: AgentModelRouteKind,
        tier: AgentModelConformanceDerivedTier,
        isLoaded: Bool = false,
        latencyHint: Double? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.tier = tier
        self.isLoaded = isLoaded
        self.latencyHint = latencyHint
    }
}

nonisolated struct AgentModelRouterInput: Equatable, Sendable {
    let need: AgentModelRunNeed
    let candidates: [AgentModelRouterCandidate]
    let cloudEnabled: Bool
    /// When true, cloud is excluded even if enabled (local-only / privacy lock).
    let privacyLockedToLocal: Bool
    let preference: AgentModelRoutePreference

    init(
        need: AgentModelRunNeed,
        candidates: [AgentModelRouterCandidate],
        cloudEnabled: Bool,
        privacyLockedToLocal: Bool = false,
        preference: AgentModelRoutePreference = .preferQuality
    ) {
        self.need = need
        self.candidates = candidates
        self.cloudEnabled = cloudEnabled
        self.privacyLockedToLocal = privacyLockedToLocal
        self.preference = preference
    }
}

nonisolated enum AgentModelRouterOutcome: Equatable, Sendable {
    /// A candidate that meets the run's need was selected.
    case selected(AgentModelRouterCandidate, reason: String)
    /// No candidate meets the need; the best chat-capable fallback is offered so
    /// the caller can degrade (e.g. answer as plain chat / warn it needs a stronger model).
    case degraded(AgentModelRouterCandidate, reason: String)
    /// Nothing usable at all.
    case unavailable(reason: String)
}

nonisolated struct AgentModelRouter: Sendable {
    init() {}

    func choose(_ input: AgentModelRouterInput) -> AgentModelRouterOutcome {
        let pool = input.candidates.filter { candidate in
            guard candidate.kind == .cloud else { return true }
            return input.cloudEnabled && !input.privacyLockedToLocal
        }
        guard !pool.isEmpty else {
            return .unavailable(reason: "No model is available for this run.")
        }

        let eligible = pool.filter { meetsNeed($0.tier, need: input.need) }
        guard !eligible.isEmpty else {
            // Nothing meets the need. Offer the best chat-capable model so the
            // caller can degrade honestly rather than silently answer ungrounded.
            let chatCapable = pool.filter { $0.tier != .unavailable }
            if let fallback = rank(chatCapable, preference: input.preference).first {
                let reason = input.need == .toolCapable
                    ? "No tool-capable model is available; degrading to \(fallback.displayName) for a plain answer."
                    : "No fully chat-capable model is available; using \(fallback.displayName)."
                return .degraded(fallback, reason: reason)
            }
            return .unavailable(reason: "No model can serve this run.")
        }

        guard let choice = rank(eligible, preference: input.preference).first else {
            return .unavailable(reason: "No model can serve this run.")
        }
        return .selected(choice, reason: selectionReason(for: choice, preference: input.preference))
    }

    // MARK: - Policy

    private func meetsNeed(_ tier: AgentModelConformanceDerivedTier, need: AgentModelRunNeed) -> Bool {
        switch need {
        case .toolCapable:
            // Only tiers that passed tool conformance can drive a tool loop.
            return tier == .tierA || tier == .tierB
        case .plainChat:
            return tier != .unavailable
        }
    }

    /// Ranks candidates best-first for the given preference. Ties always favor an
    /// already-loaded model (avoids an expensive local model swap), then lower latency.
    private func rank(
        _ candidates: [AgentModelRouterCandidate],
        preference: AgentModelRoutePreference
    ) -> [AgentModelRouterCandidate] {
        candidates.sorted { lhs, rhs in
            let lhsKeys = sortKeys(lhs, preference: preference)
            let rhsKeys = sortKeys(rhs, preference: preference)
            return lhsKeys.lexicographicallyPrecedes(rhsKeys) { $0 < $1 }
        }
    }

    /// Lower tuple sorts first (= preferred). Each element is negated/ordered so
    /// that "better" maps to a smaller number.
    private func sortKeys(
        _ candidate: AgentModelRouterCandidate,
        preference: AgentModelRoutePreference
    ) -> [Double] {
        let tierScore = Double(tierRank(candidate.tier))      // higher = more capable
        let cloud: Double = candidate.kind == .cloud ? 1 : 0
        let loaded: Double = candidate.isLoaded ? 1 : 0
        let latency: Double = candidate.latencyHint ?? .greatestFiniteMagnitude

        switch preference {
        case .preferQuality:
            // Most capable first; among equals prefer cloud, then loaded, then faster.
            return [-tierScore, -cloud, -loaded, latency]
        case .preferLocalFast:
            // Local first, then already-loaded, then faster, then more capable.
            return [cloud, -loaded, latency, -tierScore]
        }
    }

    private func tierRank(_ tier: AgentModelConformanceDerivedTier) -> Int {
        switch tier {
        case .tierA: return 3
        case .tierB: return 2
        case .tierC: return 1
        case .unavailable: return 0
        }
    }

    private func selectionReason(
        for candidate: AgentModelRouterCandidate,
        preference: AgentModelRoutePreference
    ) -> String {
        let route = candidate.kind == .cloud ? "cloud" : "local"
        let loaded = candidate.isLoaded ? " (already loaded)" : ""
        return "Routed to \(candidate.displayName) [\(route), \(candidate.tier.rawValue)]\(loaded)."
    }
}
