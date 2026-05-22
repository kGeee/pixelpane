import SwiftUI

struct RecoveryPanelView: View {
    let issue: RecoveryIssue
    let onPrimaryAction: @MainActor () -> Void
    let onSecondaryAction: (@MainActor () -> Void)?
    let onClose: () -> Void

    @State private var didAppear = false

    var body: some View {
        GlassOverlayContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: issue.systemImage)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.95),
                                    Color.accentColor.opacity(0.55)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(.white.opacity(0.25), lineWidth: 1)
                                .blendMode(.plusLighter)
                        }
                        .shadow(color: Color.accentColor.opacity(0.4), radius: 8, y: 2)

                    Text(issue.title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))

                    Spacer()

                    OverlayCloseButtonStandalone(action: onClose)
                }

                Text(issue.message)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(issue.recoveryText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                HStack(spacing: 8) {
                    RecoveryPillButton(
                        title: issue.primaryActionTitle,
                        systemImage: issue.primaryActionSystemImage,
                        accent: true,
                        action: { onPrimaryAction() }
                    )

                    if let secondaryActionTitle = issue.secondaryActionTitle, let onSecondaryAction {
                        RecoveryPillButton(
                            title: secondaryActionTitle,
                            systemImage: "gearshape",
                            accent: false,
                            action: { onSecondaryAction() }
                        )
                    }

                    Spacer()
                }
            }
            .padding(20)
            .frame(minWidth: 380, minHeight: 220)
        }
        .scaleEffect(didAppear ? 1 : 0.985)
        .opacity(didAppear ? 1 : 0)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: didAppear)
        .onAppear { didAppear = true }
    }
}

private struct OverlayCloseButtonStandalone: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.white.opacity(hovered ? 0.14 : 0.07))
                Circle()
                    .stroke(.white.opacity(0.10), lineWidth: 1)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovered ? .primary : .secondary)
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .keyboardShortcut(.cancelAction)
        .help("Close (Esc)")
    }
}

private struct RecoveryPillButton: View {
    let title: String
    let systemImage: String
    let accent: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(accent ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .frame(minHeight: 30)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(fill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            }
            .shadow(color: accent ? Color.accentColor.opacity(0.35) : Color.black.opacity(0.10), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    private var fill: AnyShapeStyle {
        if accent {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(hovered ? 1.0 : 0.92),
                        Color.accentColor.opacity(hovered ? 0.78 : 0.7)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        return AnyShapeStyle(.white.opacity(hovered ? 0.14 : 0.09))
    }

    private var stroke: Color {
        accent ? .white.opacity(0.22) : .white.opacity(0.10)
    }
}
