import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    func show(
        screenRecordingStatus: ScreenRecordingPermissionStatus,
        onStartCapture: @escaping () -> Void,
        onOpenAssistant: @escaping () -> Void,
        onRequestScreenRecordingAccess: @escaping () -> ScreenRecordingPermissionStatus,
        onOpenScreenRecordingSettings: @escaping () -> ScreenRecordingPermissionStatus
    ) {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        let view = OnboardingView(
            initialScreenRecordingStatus: screenRecordingStatus,
            onStartCapture: onStartCapture,
            onOpenAssistant: onOpenAssistant,
            onRequestScreenRecordingAccess: onRequestScreenRecordingAccess,
            onOpenScreenRecordingSettings: onOpenScreenRecordingSettings
        )
        let hostingView = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 700),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Pixel Pane"
        window.contentView = hostingView
        window.minSize = NSSize(width: 560, height: 700)
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        self.window = window

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func close() {
        window?.close()
        window = nil
    }
}

private struct OnboardingView: View {
    let onStartCapture: () -> Void
    let onOpenAssistant: () -> Void
    let onRequestScreenRecordingAccess: () -> ScreenRecordingPermissionStatus
    let onOpenScreenRecordingSettings: () -> ScreenRecordingPermissionStatus

    @State private var screenRecordingStatus: ScreenRecordingPermissionStatus

    init(
        initialScreenRecordingStatus: ScreenRecordingPermissionStatus,
        onStartCapture: @escaping () -> Void,
        onOpenAssistant: @escaping () -> Void,
        onRequestScreenRecordingAccess: @escaping () -> ScreenRecordingPermissionStatus,
        onOpenScreenRecordingSettings: @escaping () -> ScreenRecordingPermissionStatus
    ) {
        self.onStartCapture = onStartCapture
        self.onOpenAssistant = onOpenAssistant
        self.onRequestScreenRecordingAccess = onRequestScreenRecordingAccess
        self.onOpenScreenRecordingSettings = onOpenScreenRecordingSettings
        _screenRecordingStatus = State(initialValue: initialScreenRecordingStatus)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "moon.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(PixelPaneBrand.beige)
                    .frame(width: 44, height: 44)
                    .background(PixelPaneBrand.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Pixel Pane")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Local-first help for your screen and files — only when you ask.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                OnboardingPrivacyRow(
                    systemImage: "selection.pin.in.out",
                    title: "Capture only what you choose",
                    detail: "Capture starts only from the hotkey or menu, and reads just the region you drag. No background recording, no screen timeline; screenshots stay in memory and are not saved."
                )
                OnboardingPrivacyRow(
                    systemImage: "network.slash",
                    title: "Local Mode is the default",
                    detail: "Questions, file reading, and answers run on this Mac with your own models. Nothing leaves your computer unless you turn on Cloud Mode."
                )
                OnboardingPrivacyRow(
                    systemImage: "folder.badge.person.crop",
                    title: "Your files, your grants",
                    detail: "The assistant sees only folders you grant, every read is recorded in the run trace, and any change to a file is proposed to you for approval first."
                )
                OnboardingPrivacyRow(
                    systemImage: "cloud",
                    title: "Cloud Mode is explicit — and transparent",
                    detail: "When you enable it, your question and the local context the assistant gathers (such as text it reads from granted files or captures) are sent to Pixel Pane Cloud to answer, and web search may fetch current public information. The free tier includes a daily allowance."
                )
                OnboardingPrivacyRow(
                    systemImage: "location.slash",
                    title: "Location stays off until you turn it on",
                    detail: "Approximate, city-level location is shared only in Cloud Mode, and only after you grant macOS access and enable sharing in Settings — two explicit switches."
                )
                OnboardingPrivacyRow(
                    systemImage: "clock.arrow.circlepath",
                    title: "Chats stay on this Mac",
                    detail: "Conversation history is stored locally. Review or delete any chat from Settings → History at any time."
                )
            }

            PermissionReadinessRow(
                status: screenRecordingStatus,
                onRequestAccess: {
                    screenRecordingStatus = onRequestScreenRecordingAccess()
                },
                onOpenSettings: {
                    screenRecordingStatus = onOpenScreenRecordingSettings()
                }
            )

            Spacer()

            HStack(spacing: 10) {
                Button {
                    onOpenAssistant()
                } label: {
                    Text("Open Assistant")
                        .frame(minWidth: 120)
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())

                Spacer()

                Button {
                    onStartCapture()
                } label: {
                    Label("Start First Capture", systemImage: "viewfinder")
                        .frame(minWidth: 150)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 560)
        .frame(minHeight: 700)
    }
}

private struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(configuration.isPressed ? 0.12 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(configuration.isPressed ? 0.28 : 0.16), lineWidth: 1)
            )
    }
}

private struct OnboardingPrivacyRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PermissionReadinessRow: View {
    let status: ScreenRecordingPermissionStatus
    let onRequestAccess: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: status.isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(status.isGranted ? .green : .yellow)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Screen Recording: \(status.label)")
                        .font(.system(size: 14, weight: .semibold))
                    Text(status.isGranted
                        ? "Pixel Pane is ready to capture selected regions."
                        : "macOS requires this permission before Pixel Pane can read pixels from a selected region."
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !status.isGranted {
                HStack(spacing: 8) {
                    Button {
                        onRequestAccess()
                    } label: {
                        Label("Request Access", systemImage: "lock.open")
                    }

                    Button {
                        onOpenSettings()
                    } label: {
                        Label("Open Settings", systemImage: "gearshape")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.blue.opacity(0.18), lineWidth: 1)
        )
    }
}
