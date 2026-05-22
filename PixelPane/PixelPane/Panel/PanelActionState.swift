import Foundation

enum PanelActionKind: String, CaseIterable, Identifiable {
    case extractText
    case translate
    case explain
    case simplify
    case debug
    case ask

    var id: String { rawValue }

    var title: String {
        switch self {
        case .extractText:
            "Extract"
        case .translate:
            "Translate"
        case .explain:
            "Explain"
        case .simplify:
            "Simplify"
        case .debug:
            "Debug"
        case .ask:
            "Chat"
        }
    }

    var systemImage: String {
        switch self {
        case .extractText:
            "text.viewfinder"
        case .translate:
            "character.book.closed"
        case .explain:
            "lightbulb"
        case .simplify:
            "text.alignleft"
        case .debug:
            "ladybug"
        case .ask:
            "questionmark.bubble"
        }
    }
}

struct PanelActionState: Identifiable {
    let kind: PanelActionKind
    let isSelected: Bool
    let isLoading: Bool
    let disabledReason: String?

    var id: PanelActionKind { kind }
    var isEnabled: Bool { disabledReason == nil }

    static func states(
        selectedAction: PanelActionKind,
        loadingActions: Set<PanelActionKind>,
        hasText: Bool,
        allowsPlainAsk: Bool = false,
        canUseImageInput: (PanelActionKind) -> Bool,
        showsDebug: Bool
    ) -> [PanelActionState] {
        visibleKinds(showsDebug: showsDebug).map { kind in
            PanelActionState(
                kind: kind,
                isSelected: kind == selectedAction,
                isLoading: loadingActions.contains(kind),
                disabledReason: disabledReason(
                    for: kind,
                    hasText: hasText,
                    allowsPlainAsk: allowsPlainAsk,
                    canUseImageInput: canUseImageInput(kind)
                )
            )
        }
    }

    private static func visibleKinds(showsDebug: Bool) -> [PanelActionKind] {
        var kinds: [PanelActionKind] = [.extractText, .translate, .explain, .simplify]
        if showsDebug {
            kinds.append(.debug)
        }
        kinds.append(.ask)
        return kinds
    }

    private static func disabledReason(
        for kind: PanelActionKind,
        hasText: Bool,
        allowsPlainAsk: Bool,
        canUseImageInput: Bool
    ) -> String? {
        switch kind {
        case .extractText:
            return nil
        case .translate:
            return hasText ? nil : "No OCR text was found."
        case .explain:
            return hasText || canUseImageInput ? nil : "No OCR text was found."
        case .simplify:
            return hasText || canUseImageInput ? nil : "No OCR text was found."
        case .debug:
            return hasText || canUseImageInput ? nil : "No OCR text was found."
        case .ask:
            if allowsPlainAsk { return nil }
            return hasText || canUseImageInput ? nil : "No OCR text was found."
        }
    }
}
