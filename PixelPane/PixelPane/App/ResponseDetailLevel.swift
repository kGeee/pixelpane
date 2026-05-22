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
            "Quickest replies. Stays on the fast on-device text model and shortens output."
        case .balanced:
            "Default mix of speed and depth. Uses MLX Vision when ready."
        case .thorough:
            "Longest replies. Lets the local model think more before answering."
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

    /// Token cap for the given action. Returns the multiplied value rounded to a
    /// model-friendly chunk size, never going below a small floor for legibility.
    func maxOutputTokens(for action: PanelActionKind) -> Int {
        let base = baseMaxOutputTokens(for: action)
        let scaled = Double(base) * tokenScale
        let rounded = Int((scaled / 10).rounded()) * 10
        return max(60, rounded)
    }

    private var tokenScale: Double {
        switch self {
        case .brief: 0.5
        case .balanced: 1.0
        case .thorough: 1.6
        }
    }

    private func baseMaxOutputTokens(for action: PanelActionKind) -> Int {
        switch action {
        case .extractText:
            return AIModelLimits.defaultMaxOutputTokens
        case .translate:
            return AIModelLimits.defaultMaxOutputTokens
        case .simplify:
            return 140
        case .explain:
            return 320
        case .debug:
            return AIModelLimits.defaultMaxOutputTokens
        case .ask:
            return 520
        }
    }
}

enum ResponseDetailDefaults {
    static let levelKey = "ResponseDetailLevel"
}
