import Foundation

struct ModelDisplayTextNormalizer: Sendable {
    nonisolated func normalize(_ text: String) -> String {
        var normalized = text
        normalized = normalizeMarkdownBlocks(in: normalized)
        normalized = normalizeMarkdownInline(in: normalized)
        normalized = normalizeMathDelimiters(in: normalized)
        normalized = normalizeMathSyntax(in: normalized, compactsWhitespace: false)
        normalized = normalized.replacingOccurrences(
            of: #"([A-Za-z0-9)\]}])\\([A-Za-z])"#,
            with: "$1 $2",
            options: .regularExpression
        )
        return normalized
    }

    private nonisolated func normalizeMarkdownBlocks(in text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var output: [String] = []
        var index = 0

        while index < lines.count {
            if let table = markdownTable(startingAt: index, in: lines) {
                appendBlock(table.text, to: &output)
                index = table.endIndex
                continue
            }

            let trimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)

            if isMarkdownRule(trimmed) {
                appendBlankLine(to: &output)
                index += 1
                continue
            }

            if let heading = markdownHeading(from: lines[index]) {
                appendBlankLine(to: &output)
                output.append(heading)
                index += 1
                continue
            }

            output.append(lines[index])
            index += 1
        }

        return output
            .joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated func appendBlock(_ block: String, to output: inout [String]) {
        appendBlankLine(to: &output)
        output.append(block)
        appendBlankLine(to: &output)
    }

    private nonisolated func appendBlankLine(to output: inout [String]) {
        if !output.isEmpty, output.last?.isEmpty == false {
            output.append("")
        }
    }

    private nonisolated func markdownHeading(from line: String) -> String? {
        guard let match = firstMatch(pattern: #"^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$"#, in: line) else {
            return nil
        }
        return normalizeMarkdownInline(in: match[0]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated func isMarkdownRule(_ line: String) -> Bool {
        line.range(of: #"^([-*_])(?:\s*\1){2,}\s*$"#, options: .regularExpression) != nil
    }

    private nonisolated func markdownTable(
        startingAt index: Int,
        in lines: [String]
    ) -> (text: String, endIndex: Int)? {
        guard index + 1 < lines.count else { return nil }
        let header = tableCells(from: lines[index])
        guard header.count >= 2, isMarkdownTableSeparator(lines[index + 1]) else { return nil }

        var rows: [[String]] = []
        var cursor = index + 2

        while cursor < lines.count {
            let cells = tableCells(from: lines[cursor])
            guard cells.count >= 2 else { break }
            rows.append(cells)
            cursor += 1
        }

        guard !rows.isEmpty else { return nil }

        let renderedRows = rows.map { row in
            renderTableRow(headers: header, row: row)
        }

        return (renderedRows.joined(separator: "\n\n"), cursor)
    }

    private nonisolated func isMarkdownTableSeparator(_ line: String) -> Bool {
        let cells = tableCells(from: line)
        guard cells.count >= 2 else { return false }
        return cells.allSatisfy { cell in
            cell.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
        }
    }

    private nonisolated func tableCells(from line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("|") else { return [] }

        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }

        return trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { normalizeMarkdownInline(in: String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private nonisolated func renderTableRow(headers: [String], row: [String]) -> String {
        let columnCount = min(headers.count, row.count)
        return (0..<columnCount)
            .map { column in
                let label = headers[column].trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
                let value = row[column].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !label.isEmpty else { return value }
                return "\(label): \(value)"
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    private nonisolated func normalizeMarkdownInline(in text: String) -> String {
        var normalized = text

        normalized = normalized.replacingOccurrences(
            of: #"`([^`\n]+)`"#,
            with: "$1",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"\*\*([^*\n]+)\*\*"#,
            with: "$1",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"__([^_\n]+)__"#,
            with: "$1",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#,
            with: "$1",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"(?<![A-Za-z0-9_])_([^_\n]+)_(?![A-Za-z0-9_])"#,
            with: "$1",
            options: .regularExpression
        )

        return normalized
    }

    private nonisolated func normalizeMathDelimiters(in text: String) -> String {
        var normalized = text
        normalized = replaceMatches(pattern: #"\\\(([\s\S]*?)\\\)"#, in: normalized) { match in
            normalizeMathSyntax(in: match[0], compactsWhitespace: true)
        }
        normalized = replaceMatches(pattern: #"\\\[([\s\S]*?)\\\]"#, in: normalized) { match in
            normalizeMathSyntax(in: match[0], compactsWhitespace: true)
        }
        normalized = replaceMatches(pattern: #"\$([^$\n]+)\$"#, in: normalized) { match in
            normalizeMathSyntax(in: match[0], compactsWhitespace: true)
        }
        return normalized
    }

    private nonisolated func normalizeMathSyntax(in text: String, compactsWhitespace: Bool) -> String {
        var normalized = text

        normalized = replaceMatches(pattern: #"\\mathbb\{([A-Za-z])\}"#, in: normalized) { match in
            blackboardLetter(match[0])
        }
        normalized = replaceMatches(
            pattern: #"\\(?:mathrm|mathbf|mathit|text|operatorname)\{([^{}]*)\}"#,
            in: normalized
        ) { match in
            match[0]
        }

        for (command, replacement) in commandReplacements {
            normalized = normalized.replacingOccurrences(
                of: #"\\\#(command)\b"#,
                with: replacement,
                options: .regularExpression
            )
        }

        normalized = normalized.replacingOccurrences(
            of: #"\\(?:left|right)\b"#,
            with: "",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"\\[,;:!]"#,
            with: " ",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"\\([{}])"#,
            with: "$1",
            options: .regularExpression
        )

        if compactsWhitespace {
            normalized = normalized
                .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return normalized
    }

    private nonisolated func replaceMatches(
        pattern: String,
        in text: String,
        transform: ([String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        var output = text
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: nsRange).reversed()

        for match in matches {
            guard let fullRange = Range(match.range, in: output) else { continue }
            let captures = (1..<match.numberOfRanges).compactMap { index -> String? in
                guard let range = Range(match.range(at: index), in: output) else { return nil }
                return String(output[range])
            }
            output.replaceSubrange(fullRange, with: transform(captures))
        }

        return output
    }

    private nonisolated func firstMatch(pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let result = regex.firstMatch(in: text, range: nsRange) else { return nil }

        return (1..<result.numberOfRanges).compactMap { index in
            guard let range = Range(result.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }

    private nonisolated func blackboardLetter(_ letter: String) -> String {
        switch letter {
        case "C": "\u{2102}"
        case "H": "\u{210D}"
        case "N": "\u{2115}"
        case "P": "\u{2119}"
        case "Q": "\u{211A}"
        case "R": "\u{211D}"
        case "Z": "\u{2124}"
        default: letter
        }
    }

    private nonisolated var commandReplacements: [(String, String)] {
        [
            ("alpha", "\u{03B1}"),
            ("beta", "\u{03B2}"),
            ("gamma", "\u{03B3}"),
            ("delta", "\u{03B4}"),
            ("epsilon", "\u{03B5}"),
            ("lambda", "\u{03BB}"),
            ("mu", "\u{03BC}"),
            ("pi", "\u{03C0}"),
            ("theta", "\u{03B8}"),
            ("sigma", "\u{03C3}"),
            ("omega", "\u{03C9}"),
            ("Delta", "\u{0394}"),
            ("Theta", "\u{0398}"),
            ("Sigma", "\u{03A3}"),
            ("Omega", "\u{03A9}"),
            ("in", "\u{2208}"),
            ("notin", "\u{2209}"),
            ("subset", "\u{2282}"),
            ("subseteq", "\u{2286}"),
            ("cup", "\u{222A}"),
            ("cap", "\u{2229}"),
            ("leq", "\u{2264}"),
            ("geq", "\u{2265}"),
            ("neq", "\u{2260}"),
            ("times", "\u{00D7}"),
            ("cdot", "\u{00B7}"),
            ("to", "\u{2192}"),
            ("rightarrow", "\u{2192}"),
            ("leftarrow", "\u{2190}"),
            ("forall", "\u{2200}"),
            ("exists", "\u{2203}")
        ]
    }
}
