import Foundation

struct ModelOutputFormatter: Sendable {
    private let displayTextNormalizer = ModelDisplayTextNormalizer()

    nonisolated func format(_ rawText: String) -> AIModelOutput {
        let assistantText = textAfterLastAssistantMarker(in: rawText)
        let extraction = extractReasoning(from: assistantText)
        let statisticsExtraction = extractStatistics(from: extraction.visible)
        let finalText = cleanVisibleText(statisticsExtraction.visible)
        let reasoningText = cleanReasoningText(extraction.reasoning)

        return AIModelOutput(
            finalText: finalText.isEmpty ? cleanVisibleText(rawText) : finalText,
            reasoningText: reasoningText.isEmpty ? nil : reasoningText,
            statistics: statisticsExtraction.statistics
        )
    }

    private nonisolated func textAfterLastAssistantMarker(in text: String) -> String {
        let markers = [
            "<|im_start|>assistant",
            "<im_start>assistant",
            "<lim_start>assistant",
            "<|assistant|>",
            "<assistant>",
            "Assistant:",
            "\nassistant\n"
        ]

        let ranges = markers.compactMap { marker in
            text.range(of: marker, options: [.caseInsensitive, .backwards])
        }

        guard let markerRange = ranges.max(by: { $0.lowerBound < $1.lowerBound }) else {
            return text
        }

        return String(text[markerRange.upperBound...])
    }

    private nonisolated func extractReasoning(from text: String) -> (visible: String, reasoning: String) {
        var visible = text
        var reasoningBlocks: [String] = []

        for tag in ["think", "thinking", "analysis"] {
            let result = removeTaggedBlocks(named: tag, from: visible)
            visible = result.visible
            reasoningBlocks.append(contentsOf: result.reasoning)
        }

        return (
            visible: visible,
            reasoning: reasoningBlocks.joined(separator: "\n\n")
        )
    }

    private nonisolated func removeTaggedBlocks(named tag: String, from text: String) -> (visible: String, reasoning: [String]) {
        let pattern = "<\\s*\(tag)\\s*>[\\s\\S]*?<\\s*/\\s*\(tag)\\s*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return (text, [])
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange).reversed()
        var visible = text
        var reasoning: [String] = []

        for match in matches {
            guard let range = Range(match.range, in: visible) else { continue }
            let block = String(visible[range])
            reasoning.append(stripReasoningTags(block, tag: tag))
            visible.removeSubrange(range)
        }

        return (visible, reasoning.reversed())
    }

    private nonisolated func stripReasoningTags(_ text: String, tag: String) -> String {
        text
            .replacingOccurrences(
                of: "<\\s*/?\\s*\(tag)\\s*>",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated func cleanVisibleText(_ text: String) -> String {
        var cleaned = text
        cleaned = removeLeadingDiagnostics(from: cleaned)

        let tokens = [
            "<|im_end|>",
            "<|end|>",
            "<|endoftext|>",
            "<|vision_start|>",
            "<|vision_end|>",
            "<|image_pad|>",
            "<vision_start>",
            "<vision_end>",
            "<image_pad>",
            "<|user|>",
            "<|assistant|>",
            "<|im_start|>user",
            "<|im_start|>assistant",
            "<im_start>user",
            "<im_start>assistant",
            "<lim_start>user",
            "<lim_start>assistant",
            "<lim_end>"
        ]

        for token in tokens {
            cleaned = cleaned.replacingOccurrences(of: token, with: "", options: [.caseInsensitive])
        }

        cleaned = cleaned.replacingOccurrences(
            of: #"(?m)^\s*={4,}\s*$"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"(?m)^\s*assistant\s*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )

        return displayTextNormalizer
            .normalize(cleaned)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated func cleanReasoningText(_ text: String) -> String {
        cleanVisibleText(text)
    }

    private nonisolated func extractStatistics(from text: String) -> (visible: String, statistics: [AIModelOutputStatistic]) {
        let lines = text.components(separatedBy: .newlines)
        var visibleLines: [String] = []
        var statistics: [AIModelOutputStatistic] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let statistic = statistic(from: trimmed) {
                statistics.append(statistic)
            } else {
                visibleLines.append(line)
            }
        }

        return (visibleLines.joined(separator: "\n"), statistics)
    }

    private nonisolated func statistic(from line: String) -> AIModelOutputStatistic? {
        if let match = match(
            #"^(Prompt|Generation):\s*([0-9,]+)\s+tokens,\s*([0-9.]+)\s+tokens-per-sec$"#,
            in: line
        ) {
            return AIModelOutputStatistic(
                label: match[0],
                value: "\(match[1]) tokens",
                detail: "\(match[2]) tok/s"
            )
        }

        if let match = match(#"^Peak memory:\s*(.+)$"#, in: line) {
            return AIModelOutputStatistic(
                label: "Peak Memory",
                value: match[0],
                detail: nil
            )
        }

        return nil
    }

    private nonisolated func match(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let result = regex.firstMatch(in: text, range: nsRange) else { return nil }

        return (1..<result.numberOfRanges).compactMap { index in
            guard let range = Range(result.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }

    private nonisolated func removeLeadingDiagnostics(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var firstContentIndex = 0

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("Files:") || trimmed.hasPrefix("Prompt:") || trimmed.allSatisfy({ $0 == "=" }) {
                firstContentIndex = index + 1
                continue
            }
            if firstContentIndex > 0 && trimmed.isEmpty {
                firstContentIndex = index + 1
                continue
            }
            break
        }

        return lines.dropFirst(firstContentIndex).joined(separator: "\n")
    }
}
