import Foundation

enum ResponseDetailLevel: Int, CaseIterable, Codable, Identifiable {
    case brief = 0
    case balanced = 1
    case thorough = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .brief: "Brief"
        case .balanced: "Balanced"
        case .thorough: "Thorough"
        }
    }

    var subtitle: String {
        switch self {
        case .brief:
            "Shorter replies when practical. Completeness still wins."
        case .balanced:
            "Default mix of speed and depth. Uses MLX Vision when ready."
        case .thorough:
            "More detail when the question benefits from it."
        }
    }

    var leadingLabel: String { "Quicker, briefer" }
    var trailingLabel: String { "Slower, more thorough" }

    /// Whether image-aware MLX should be used for this action when available.
    /// Brief mode keeps Explain/Simplify/Ask on the fast Apple text model even when
    /// MLX Vision is ready, since vision generation is the slowest path on most Macs.
    /// Debug always prefers vision when available because the visual context is the
    /// point of debugging a screenshot.
    func usesImageInput(for action: PanelActionKind) -> Bool {
        switch action {
        case .debug:
            return true
        case .extractText, .translate:
            return false
        case .explain, .simplify, .ask:
            return self != .brief
        }
    }

    /// Completion budget for the given action. Response style is guidance, not
    /// a truncation mechanism, so every level gets enough room to finish.
    func maxOutputTokens(for action: PanelActionKind) -> Int {
        switch action {
        case .extractText, .translate, .simplify:
            2_048
        case .explain, .debug, .ask:
            AIModelLimits.defaultMaxOutputTokens
        }
    }

    var outputGuidance: String {
        switch self {
        case .brief:
            "Prefer a short, direct answer when practical. Still finish the answer; do not cut off a sentence, list, or required step just to stay brief."
        case .balanced:
            "Use enough detail to answer clearly. Still finish the answer; do not cut off a sentence, list, or required step to fit a target length."
        case .thorough:
            "Include extra detail when it improves the answer. Still keep structure readable and finish the answer completely."
        }
    }
}

enum ResponseDetailDefaults {
    static let levelKey = "ResponseDetailLevel"
}
