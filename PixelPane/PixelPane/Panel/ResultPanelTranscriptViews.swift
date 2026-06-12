//
//  ResultPanelTranscriptViews.swift
//  PixelPane
//
//  Ask-turn rendering, file-linked answer text, flow layouts, model stats, and capture preview.
//

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct AskTurnView: View {
    let index: Int
    let turn: AskConversationTurn
    let toolState: AssistantToolState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Spacer(minLength: 80)

                Text(turn.question)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineSpacing(1)
                    .textSelection(.enabled)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.white.opacity(0.07), lineWidth: 1)
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                metadataLine

                if turn.answer.isEmpty {
                    AssistantThinkingIndicator(
                        summary: turn.runtimeProgressSummary,
                        history: Array(turn.runtimeActivityLog.dropLast())
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Thinking")
                } else if let fileWriteDetail = FileWriteContinuationBanner.parse(from: turn.answer) {
                    FileWriteContinuationBanner(
                        detail: fileWriteDetail,
                        baseDirectoryPaths: Self.baseDirectoryPaths(from: toolState)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let running = RunningTerminalBanner.parse(from: turn.answer) {
                    RunningTerminalBanner(command: running.command, continuation: running.continuation)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    FileLinkedAnswerText(
                        text: turn.answer,
                        baseDirectoryPaths: Self.baseDirectoryPaths(from: toolState)
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var metadataLine: some View {
        Text(metadataText)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactBackendLabel: String {
        // Routed labels carry the model name ("MLX Text: Qwen3.6-35B-A3B-6bit");
        // show the compact model so the chip names what actually ran.
        if turn.backendLabel.hasPrefix("MLX Text: ") {
            let model = String(turn.backendLabel.dropFirst("MLX Text: ".count))
            return ResultPanelView.compactModelName(model)
        }
        switch turn.backendLabel {
        case "Pixel Pane Cloud":
            return "Cloud"
        case "MLX Text":
            return "MLX Text"
        case "MLX Vision":
            return "MLX Vision"
        case "Local Files":
            return "Files"
        default:
            return "Local"
        }
    }

    private var metadataText: String {
        let values = turn.statistics.reduce(into: [String: AIModelOutputStatistic]()) { result, statistic in
            result[statistic.label] = statistic
        }
        let model = values["Cloud model"]?.value
        let peakMemory = values["Peak Memory"]?.value
        let actions = Int(values["Actions left"]?.value ?? values["Cloud actions left"]?.value ?? "")
        let reset = values["Actions left"]?.detail ?? values["Cloud actions left"]?.detail
        let usageText: String? = shouldShowCloudUsage(actions) ? actions.map { count in
            if let reset {
                return "\(count) left, \(reset)"
            }
            return "\(count) left"
        } : nil
        let memoryText = shouldShowPeakMemory ? peakMemory.map { "Peak \($0)" } : nil

        return [compactBackendLabel, model, memoryText, usageText]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " - ")
    }

    private func shouldShowCloudUsage(_ remainingActions: Int?) -> Bool {
        guard compactBackendLabel == "Cloud", let remainingActions else { return false }
        return remainingActions <= 10
    }

    private var shouldShowPeakMemory: Bool {
        compactBackendLabel == "MLX Text" || compactBackendLabel == "MLX Vision"
    }

    private static func baseDirectoryPaths(from toolState: AssistantToolState) -> [String] {
        var paths: [String] = []
        if let lastListedFolder = toolState.lastListedFolder {
            paths.append(lastListedFolder.path)
        }
        paths.append(contentsOf: toolState.grantedSourcesUsed.filter { $0.kindLabel == "Folder" }.map(\.path))
        paths.append(contentsOf: toolState.lastFileSources.map { URL(fileURLWithPath: $0.path).deletingLastPathComponent().path })

        var seen: Set<String> = []
        return paths.filter { path in
            guard !path.isEmpty, !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
    }
}

struct FileLinkedAnswerText: View {
    private enum Segment: Identifiable {
        case text(String, UUID)
        case path(display: String, path: String, UUID)

        var id: UUID {
            switch self {
            case .text(_, let id), .path(_, _, let id):
                return id
            }
        }
    }

    let text: String
    let baseDirectoryPaths: [String]

    var body: some View {
        let lineSegments = Self.lineSegments(in: text, baseDirectoryPaths: baseDirectoryPaths)
        let hasLinkedPath = lineSegments.contains { line in
            line.contains { if case .path = $0 { true } else { false } }
        }
        // Without file-path chips there's nothing to tokenize for, so render the
        // whole answer as one Text. A single Text is fully selectable/copyable
        // and wraps naturally — per-word Texts (needed only for path chips) can't
        // be selected across, which is why long answers couldn't be copied.
        if !hasLinkedPath {
            Text(text)
                .font(.system(size: 12.5))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            pathLinkedBody(lineSegments: lineSegments)
        }
    }

    private func pathLinkedBody(lineSegments: [[Segment]]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(lineSegments.indices, id: \.self) { index in
                InlineFlowLayout(horizontalSpacing: 3, verticalSpacing: 4) {
                    ForEach(Self.inlineSegments(from: lineSegments[index])) { segment in
                        switch segment {
                        case .text(let value, _):
                            Text(value)
                                .font(.system(size: 12.5))
                                .lineLimit(1)
                                .textSelection(.enabled)

                        case .path(let display, let path, _):
                            FilePathChip(display: display, path: path)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private static func inlineSegments(from segments: [Segment]) -> [Segment] {
        segments.flatMap { segment -> [Segment] in
            switch segment {
            case .path:
                return [segment]
            case .text(let value, _):
                return textTokens(from: value).map { .text($0, UUID()) }
            }
        }
    }

    private static func textTokens(from value: String) -> [String] {
        guard !value.isEmpty else { return [] }

        var tokens: [String] = []
        var cursor = value.startIndex
        while cursor < value.endIndex {
            let tokenStart = cursor

            if value[cursor].isWhitespace {
                while cursor < value.endIndex, value[cursor].isWhitespace {
                    cursor = value.index(after: cursor)
                }
            } else {
                while cursor < value.endIndex, !value[cursor].isWhitespace {
                    cursor = value.index(after: cursor)
                }
                while cursor < value.endIndex, value[cursor].isWhitespace {
                    cursor = value.index(after: cursor)
                }
            }

            tokens.append(String(value[tokenStart..<cursor]))
        }

        return tokens
    }

    private static func lineSegments(in text: String, baseDirectoryPaths: [String]) -> [[Segment]] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { segments(in: String($0), baseDirectoryPaths: baseDirectoryPaths) }
    }

    private static func segments(in line: String, baseDirectoryPaths: [String]) -> [Segment] {
        guard let regex = try? NSRegularExpression(
            pattern: #"(/Users/[^\s,\)\]\}\"']+)"#,
            options: []
        ) else {
            return [.text(line, UUID())]
        }

        let nsLine = line as NSString
        let matches = regex.matches(
            in: line,
            range: NSRange(location: 0, length: nsLine.length)
        )
        guard !matches.isEmpty else {
            return relativeListingSegments(in: line, baseDirectoryPaths: baseDirectoryPaths)
        }

        var result: [Segment] = []
        var cursor = 0
        for match in matches {
            let range = match.range(at: 1)
            if range.location > cursor {
                result.append(.text(nsLine.substring(with: NSRange(location: cursor, length: range.location - cursor)), UUID()))
            }
            let rawPath = nsLine.substring(with: range)
            let split = splitPathCandidate(rawPath)
            if !split.path.isEmpty {
                result.append(.path(display: displayName(for: split.path), path: split.path, UUID()))
            }
            if !split.trailingText.isEmpty {
                result.append(.text(split.trailingText, UUID()))
            }
            cursor = range.location + range.length
        }

        if cursor < nsLine.length {
            result.append(.text(nsLine.substring(from: cursor), UUID()))
        }

        return result
    }

    private static func relativeListingSegments(in line: String, baseDirectoryPaths: [String]) -> [Segment] {
        guard !baseDirectoryPaths.isEmpty else { return [.text(line, UUID())] }
        let prefixes = ["- File: ", "- Folder: "]
        guard let prefix = prefixes.first(where: { line.hasPrefix($0) }) else {
            return [.text(line, UUID())]
        }
        let name = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/") else { return [.text(line, UUID())] }

        let resolvedPath = baseDirectoryPaths
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name).path }
            .first { FileManager.default.fileExists(atPath: $0) }
            ?? URL(fileURLWithPath: baseDirectoryPaths[0]).appendingPathComponent(name).path

        return [
            .text(prefix, UUID()),
            .path(display: displayName(for: resolvedPath), path: resolvedPath, UUID())
        ]
    }

    private static func splitPathCandidate(_ candidate: String) -> (path: String, trailingText: String) {
        var path = candidate
        var trailing = ""
        while let last = path.last, ".,;:".contains(last) {
            trailing.insert(last, at: trailing.startIndex)
            path.removeLast()
        }
        return (path, trailing)
    }

    private static func displayName(for path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        if !name.isEmpty {
            return name
        }
        return path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }

}

struct FilePathChip: View {
    let display: String
    let path: String

    var body: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } label: {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 9.5, weight: .semibold))

                Text(display)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(Color(red: 0.72, green: 0.82, blue: 1.0))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .frame(height: 20)
            .frame(maxWidth: 220, alignment: .leading)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(path)
    }

    private var iconName: String {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
            return isDirectory.boolValue ? "folder" : "doc.text"
        }
        return URL(fileURLWithPath: path).pathExtension.isEmpty ? "folder" : "doc.text"
    }
}

struct InlineFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    init(horizontalSpacing: CGFloat, verticalSpacing: CGFloat) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        layout(subviews: subviews, maxWidth: proposal.width ?? .greatestFiniteMagnitude).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(subviews: subviews, maxWidth: bounds.width)
        for item in result.items {
            subviews[item.index].place(
                at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                proposal: ProposedViewSize(item.size)
            )
        }
    }

    private func layout(subviews: Subviews, maxWidth: CGFloat) -> (items: [Item], size: CGSize) {
        var items: [Item] = []
        var cursor = CGPoint.zero
        var lineHeight: CGFloat = 0
        var width: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > maxWidth {
                cursor.x = 0
                cursor.y += lineHeight + verticalSpacing
                lineHeight = 0
            }

            items.append(Item(index: index, origin: cursor, size: size))
            cursor.x += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
            width = max(width, cursor.x - horizontalSpacing)
        }

        return (items, CGSize(width: width, height: cursor.y + lineHeight))
    }

    private struct Item {
        let index: Int
        let origin: CGPoint
        let size: CGSize
    }
}

// MARK: - Stats

struct ModelStatisticsView: View {
    let statistics: [AIModelOutputStatistic]

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(statistics) { statistic in
                VStack(alignment: .leading, spacing: 2) {
                    Text(statistic.label)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .textCase(.uppercase)
                        .tracking(0.35)
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 4) {
                        Text(statistic.value)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                        if let detail = statistic.detail {
                            Text(detail)
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(.white.opacity(0.04), lineWidth: 1)
                }
            }
        }
    }
}

struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        HStack(spacing: spacing) {
            content
        }
    }
}

// MARK: - Capture preview

struct CapturePreviewPane: View {
    let image: CGImage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentColor.opacity(0.85))
                Text("Capture")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(image.width)×\(image.height)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.black.opacity(0.30))

                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .padding(8)
            }
            .frame(height: 220)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }

            Text("Selected region")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }
}

