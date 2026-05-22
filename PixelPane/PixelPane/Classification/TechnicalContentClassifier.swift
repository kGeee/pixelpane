import Foundation

struct TechnicalContentClassification: Equatable {
    static let debugThreshold = 0.8

    let score: Double
    let reasons: [String]

    var shouldShowDebug: Bool {
        score >= Self.debugThreshold
    }
}

struct TechnicalContentClassifier {
    func classify(_ text: String) -> TechnicalContentClassification {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return TechnicalContentClassification(score: 0, reasons: [])
        }

        let lines = trimmed.components(separatedBy: .newlines)
        let lowercased = trimmed.lowercased()
        var score = 0.0
        var reasons: [String] = []

        addKeywordEvidence(
            in: lowercased,
            keywords: [
                "error", "exception", "traceback", "stack trace", "failed",
                "fatal", "panic", "crash", "segmentation fault", "undefined",
                "cannot find", "permission denied", "timed out", "timeout"
            ],
            score: 0.42,
            reason: "error keyword",
            to: &score,
            reasons: &reasons
        )

        addKeywordEvidence(
            in: lowercased,
            keywords: [
                "swift", "xcode", "python", "javascript", "typescript",
                "node", "npm", "git", "docker", "kubernetes", "sql"
            ],
            score: 0.2,
            reason: "developer tool keyword",
            to: &score,
            reasons: &reasons
        )

        if lines.contains(where: looksLikeStackFrame) {
            score += 0.28
            reasons.append("stack frame")
        }

        if lines.contains(where: looksLikeLogLine) {
            score += 0.24
            reasons.append("log line")
        }

        if lines.contains(where: looksLikeCodeLine) {
            score += 0.28
            reasons.append("code syntax")
        }

        if lines.contains(where: looksLikeTerminalLine) {
            score += 0.18
            reasons.append("terminal prompt")
        }

        let symbolDensity = technicalSymbolDensity(in: trimmed)
        if symbolDensity >= 0.08 {
            score += min(0.22, symbolDensity)
            reasons.append("technical symbols")
        }

        return TechnicalContentClassification(
            score: min(score, 1.0),
            reasons: Array(reasons.prefix(4))
        )
    }

    private func addKeywordEvidence(
        in text: String,
        keywords: [String],
        score evidenceScore: Double,
        reason: String,
        to score: inout Double,
        reasons: inout [String]
    ) {
        guard keywords.contains(where: text.contains) else { return }
        score += evidenceScore
        reasons.append(reason)
    }

    private func looksLikeStackFrame(_ line: String) -> Bool {
        line.contains(" at ")
            || line.contains("File \"")
            || line.range(of: #"^\s*#\d+\s+0x[0-9a-fA-F]+"#, options: .regularExpression) != nil
            || line.range(of: #"\w+\.\w+:\d+"#, options: .regularExpression) != nil
    }

    private func looksLikeLogLine(_ line: String) -> Bool {
        line.range(of: #"\b(ERROR|WARN|WARNING|INFO|DEBUG|TRACE|FATAL)\b"#, options: .regularExpression) != nil
            || line.range(of: #"\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}"#, options: .regularExpression) != nil
    }

    private func looksLikeCodeLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }

        let codePrefixes = [
            "func ", "let ", "var ", "class ", "struct ", "enum ", "import ",
            "if ", "for ", "while ", "return ", "const ", "function ", "def ",
            "public ", "private ", "guard ", "case ", "switch "
        ]

        return codePrefixes.contains { trimmed.hasPrefix($0) }
            || trimmed.contains("->")
            || trimmed.contains("=>")
            || trimmed.contains("==")
            || trimmed.contains("!=")
            || (trimmed.contains("{") && trimmed.contains("}"))
            || (trimmed.hasSuffix(";") && trimmed.contains("("))
    }

    private func looksLikeTerminalLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("$ ")
            || trimmed.hasPrefix("% ")
            || trimmed.hasPrefix("> ")
    }

    private func technicalSymbolDensity(in text: String) -> Double {
        let symbols = Set("{}[]();<>=$|`\\")
        let symbolCount = text.reduce(0) { count, character in
            count + (symbols.contains(character) ? 1 : 0)
        }

        return Double(symbolCount) / Double(max(text.count, 1))
    }
}
