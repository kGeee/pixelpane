import Foundation
import NaturalLanguage

struct DetectedLanguage: Equatable {
    let code: String?
    let displayName: String
    let confidence: Double

    static let unknown = DetectedLanguage(code: nil, displayName: "Unknown", confidence: 0)

    var isKnown: Bool { code != nil }
}

struct LanguageDetector {
    static let minimumConfidence: Double = 0.5

    func detect(in text: String) -> DetectedLanguage {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)

        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        guard let best = hypotheses.max(by: { $0.value < $1.value }) else {
            return .unknown
        }

        guard best.value >= LanguageDetector.minimumConfidence else {
            return .unknown
        }

        let code = best.key.rawValue
        let displayName = Locale.current.localizedString(forLanguageCode: code) ?? code
        return DetectedLanguage(
            code: code,
            displayName: displayName.capitalized,
            confidence: best.value
        )
    }
}
