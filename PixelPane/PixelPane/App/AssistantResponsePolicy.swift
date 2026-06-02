import Foundation

enum AssistantResponsePolicy {
    static func usesImageInput(for action: PanelActionKind) -> Bool {
        switch action {
        case .debug:
            true
        case .extractText, .translate:
            false
        case .explain, .simplify, .ask:
            true
        }
    }

    static func maxOutputTokens(for action: PanelActionKind) -> Int {
        switch action {
        case .extractText, .translate, .simplify:
            2_048
        case .explain, .debug, .ask:
            AIModelLimits.defaultMaxOutputTokens
        }
    }

    static let outputGuidance = "Use enough detail to answer clearly. Do not show reasoning, analysis, scratchpad, or <think> text. Still finish the answer."
}
