//
//  ResultPanelStatusViews.swift
//  PixelPane
//
//  Recovery, typing, approval, agent-run controls, transcript, thinking, and terminal banners.
//

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Recovery view

struct ActionRecoveryView: View {
    let state: ActionRecoveryState
    let onPrimaryAction: () -> Void
    let onSecondaryAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: state.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26, height: 26)
                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(state.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }

            Text(state.detail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                OverlayPillButton(
                    title: state.primaryTitle,
                    systemImage: state.primarySystemImage,
                    style: .accent,
                    action: onPrimaryAction
                )

                if let secondaryTitle = state.secondaryTitle, let onSecondaryAction {
                    OverlayPillButton(
                        title: secondaryTitle,
                        systemImage: state.secondarySystemImage ?? "arrow.clockwise",
                        style: .primary,
                        action: onSecondaryAction
                    )
                }

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
    }
}

// MARK: - Typing placeholder

struct TypingStatusView: View {
    let title: String

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.35)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate * 3) % 4
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))

                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.primary.opacity(index < phase ? 0.75 : 0.22))
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(width: 20, alignment: .leading)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AgentRunApprovalCard: View {
    let approval: AgentRunProjectedApproval
    let onApprove: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)

                Text(approval.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if let risk = approval.risk {
                    Text(risk)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.16), in: Capsule())
                }
            }

            Text(approval.prompt)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 3) {
                if let secondaryText = approval.secondaryText {
                    Text(displayName(for: secondaryText))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Text(approval.primaryText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 8) {
                OverlayPillButton(
                    title: approval.approveTitle,
                    systemImage: approveIcon,
                    style: .accent,
                    action: onApprove
                )

                OverlayPillButton(
                    title: approval.denyTitle,
                    systemImage: "xmark",
                    style: .secondary,
                    action: onDeny
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.orange.opacity(0.20), lineWidth: 1)
        }
    }

    private var systemImage: String {
        switch approval.kind {
        case .fileWrite:
            return "square.and.pencil"
        case .command:
            return "terminal"
        case .processStart:
            return "play.rectangle"
        case .processStop:
            return "stop.circle"
        case .approval:
            return "checkmark.shield"
        }
    }

    private var approveIcon: String {
        switch approval.kind {
        case .command, .processStart:
            return "play.fill"
        case .processStop:
            return "stop.fill"
        case .fileWrite, .approval:
            return "checkmark"
        }
    }

    private func displayName(for value: String) -> String {
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value).lastPathComponent
        }
        return value
    }
}

struct AgentRunRecoveryControlView: View {
    let summary: String
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)

                Text("Run interrupted")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)
            }

            Text(summary)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                OverlayPillButton(
                    title: "Retry",
                    systemImage: "arrow.clockwise",
                    style: .accent,
                    action: onRetry
                )

                OverlayPillButton(
                    title: "Cancel",
                    systemImage: "xmark",
                    style: .secondary,
                    action: onCancel
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.orange.opacity(0.20), lineWidth: 1)
        }
    }
}

// MARK: - Chat transcript

struct AskTranscriptView: View {
    let turns: [AskConversationTurn]
    let toolState: AssistantToolState
    let emptyText: String
    private let bottomAnchorID = "ask-transcript-bottom"

    private var latestTurnSignature: String {
        guard let lastTurn = turns.last else { return "empty" }
        return "\(turns.count)-\(lastTurn.question.count)-\(lastTurn.answer.count)"
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if turns.isEmpty, !emptyText.isEmpty {
                        Text(emptyText)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    } else {
                        ForEach(Array(turns.enumerated()), id: \.offset) { index, turn in
                            AskTurnView(index: index + 1, turn: turn, toolState: toolState)
                                .id(index)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 4)
                .padding(.bottom, 2)
                .id(bottomAnchorID)
            }
            .scrollIndicators(.automatic)
            .onAppear {
                scrollToBottom(proxy, animated: false)
            }
            .onChange(of: turns.count) { _, newCount in
                guard newCount > 0 else { return }
                scrollToBottom(proxy)
            }
            .onChange(of: latestTurnSignature) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        guard !turns.isEmpty else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
    }
}

struct AssistantThinkingIndicator: View {
    let summary: String?
    /// Earlier compact activity labels (oldest first) shown as a faint breadcrumb so
    /// fast steps remain visible instead of flashing by.
    var history: [String] = []
    @State private var phase = false
    private let accent = Color(red: 0.72, green: 0.82, blue: 1.0)

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .stroke(accent.opacity(phase ? 0.18 : 0.34), lineWidth: 1.2)
                    .frame(width: 18, height: 18)
                    .scaleEffect(phase ? 1.22 : 0.78)
                    .blur(radius: phase ? 0.6 : 0)

                Circle()
                    .fill(accent.opacity(0.24))
                    .frame(width: 16, height: 16)
                    .blur(radius: 5)
                    .scaleEffect(phase ? 1.15 : 0.85)

                Circle()
                    .fill(accent.opacity(0.82))
                    .frame(width: 4.5, height: 4.5)
                    .shadow(color: accent.opacity(0.7), radius: phase ? 5 : 2)
            }
            .frame(width: 22, height: 22)

            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(accent.opacity(phase ? 0.95 : 0.38))
                        .frame(width: 4, height: phase ? 15 : 7)
                        .shadow(color: accent.opacity(0.35), radius: phase ? 4 : 1)
                        .animation(
                            .easeInOut(duration: 0.64)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.13),
                            value: phase
                        )
                }
            }
            .frame(width: 23, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(summary?.isEmpty == false ? summary! : "Thinking")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !history.isEmpty {
                    Text(history.joined(separator: "  ·  "))
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
        }
        .padding(.vertical, 2)
        .onAppear {
            phase = true
        }
    }
}

struct RunningTerminalBanner: View {
    let command: String
    let continuation: String?

    @State private var pulse = false

    private static let pattern = try? NSRegularExpression(
        pattern: #"^Running `([^`]+)`\.\.\.(?:\n+(.+))?$"#,
        options: [.dotMatchesLineSeparators]
    )

    static func parse(from text: String) -> (command: String, continuation: String?)? {
        guard let regex = pattern else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range),
              match.numberOfRanges >= 2,
              let commandRange = Range(match.range(at: 1), in: trimmed) else {
            return nil
        }
        let command = String(trimmed[commandRange])

        var continuation: String? = nil
        if match.numberOfRanges >= 3,
           let contRange = Range(match.range(at: 2), in: trimmed) {
            let candidate = String(trimmed[contRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty { continuation = candidate }
        }

        return (command, continuation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(pulse ? 0.10 : 0.22), lineWidth: 1)
                        .frame(width: 16, height: 16)
                        .scaleEffect(pulse ? 1.35 : 0.85)
                        .opacity(pulse ? 0 : 1)
                    Circle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 5, height: 5)
                }
                .frame(width: 18, height: 18)
                .animation(
                    .easeInOut(duration: 1.0).repeatForever(autoreverses: false),
                    value: pulse
                )

                Text("Running")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }

            Text(command)
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.92))
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                }

            if let continuation {
                Text(continuation)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear { pulse = true }
    }
}

struct FileWriteContinuationBanner: View {
    let detail: String
    let baseDirectoryPaths: [String]

    @State private var pulse = false

    private static let pattern = try? NSRegularExpression(
        pattern: #"^Done\. (.+?)(?:\n+)Continuing the task\.\.\.$"#,
        options: [.dotMatchesLineSeparators]
    )

    static func parse(from text: String) -> String? {
        guard let regex = pattern else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range),
              match.numberOfRanges >= 2,
              let detailRange = Range(match.range(at: 1), in: trimmed) else {
            return nil
        }
        let detail = String(trimmed[detailRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? nil : detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.green.opacity(0.82))

                Text("File updated")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }

            FileLinkedAnswerText(text: detail, baseDirectoryPaths: baseDirectoryPaths)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                }

            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(pulse ? 0.08 : 0.20), lineWidth: 1)
                        .frame(width: 14, height: 14)
                        .scaleEffect(pulse ? 1.35 : 0.85)
                        .opacity(pulse ? 0 : 1)
                    Circle()
                        .fill(Color.white.opacity(0.70))
                        .frame(width: 4.5, height: 4.5)
                }
                .frame(width: 16, height: 16)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false), value: pulse)

                Text("Continuing")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear { pulse = true }
    }
}

