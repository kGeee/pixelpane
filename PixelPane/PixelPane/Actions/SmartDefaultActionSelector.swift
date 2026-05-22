import Foundation

struct SmartDefaultActionCandidate {
    let action: PanelActionKind
    let score: Double
    let reason: String
}

protocol SmartDefaultActionRule {
    func candidate(for result: CaptureResult) -> SmartDefaultActionCandidate?
}

struct SmartDefaultActionSelection: Equatable {
    let action: PanelActionKind
    let reason: String
}

struct SmartDefaultActionSelector {
    private let rules: [any SmartDefaultActionRule]

    init(rules: [any SmartDefaultActionRule] = SmartDefaultActionSelector.defaultRules) {
        self.rules = rules
    }

    func selectDefaultAction(for result: CaptureResult) -> SmartDefaultActionSelection {
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !result.isEmptyOCRResult else {
            return SmartDefaultActionSelection(action: .extractText, reason: "empty OCR")
        }

        let bestCandidate = rules
            .compactMap { $0.candidate(for: result) }
            .max { lhs, rhs in lhs.score < rhs.score }

        guard let bestCandidate, bestCandidate.score >= 0.55 else {
            return SmartDefaultActionSelection(action: .extractText, reason: "general text")
        }

        return SmartDefaultActionSelection(
            action: bestCandidate.action,
            reason: bestCandidate.reason
        )
    }

    private static let defaultRules: [any SmartDefaultActionRule] = [
        TechnicalDebugDefaultRule(),
        TranslationDefaultRule(),
        SimplifyDefaultRule(),
        ExplainDefaultRule()
    ]
}

private struct TechnicalDebugDefaultRule: SmartDefaultActionRule {
    func candidate(for result: CaptureResult) -> SmartDefaultActionCandidate? {
        guard result.technicalClassification.shouldShowDebug else { return nil }
        return SmartDefaultActionCandidate(
            action: .debug,
            score: 0.96,
            reason: "technical content"
        )
    }
}

private struct TranslationDefaultRule: SmartDefaultActionRule {
    func candidate(for result: CaptureResult) -> SmartDefaultActionCandidate? {
        guard let code = result.detectedLanguage.code?.lowercased() else { return nil }
        guard !Self.englishLanguageCodes.contains(code) else { return nil }

        return SmartDefaultActionCandidate(
            action: .translate,
            score: min(0.92, max(0.68, result.detectedLanguage.confidence)),
            reason: "non-English text"
        )
    }

    private static let englishLanguageCodes: Set<String> = ["en", "eng"]
}

private struct SimplifyDefaultRule: SmartDefaultActionRule {
    func candidate(for result: CaptureResult) -> SmartDefaultActionCandidate? {
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = text.split { $0.isWhitespace || $0.isNewline }.count
        let sentenceCount = max(
            1,
            text.split { ".!?".contains($0) }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .count
        )
        let averageWordsPerSentence = Double(wordCount) / Double(sentenceCount)

        guard wordCount >= 45 || averageWordsPerSentence >= 24 else { return nil }

        let score = min(0.82, 0.56 + (Double(wordCount) / 500.0) + max(0, averageWordsPerSentence - 24) / 120.0)
        return SmartDefaultActionCandidate(
            action: .simplify,
            score: score,
            reason: "dense text"
        )
    }
}

private struct ExplainDefaultRule: SmartDefaultActionRule {
    func candidate(for result: CaptureResult) -> SmartDefaultActionCandidate? {
        let lowercased = result.text.lowercased()
        let markers = [
            "what is", "why", "how does", "explain", "prove", "solve",
            "therefore", "whereas", "assume", "definition", "theorem"
        ]

        guard markers.contains(where: lowercased.contains) else { return nil }
        return SmartDefaultActionCandidate(
            action: .explain,
            score: 0.62,
            reason: "explanation cue"
        )
    }
}
