import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var onUserClose: (() -> Void)?

    func show(
        appState: AppState,
        screenRecordingStatus: ScreenRecordingPermissionStatus,
        onStartCapture: @escaping () -> Void,
        onOpenAssistant: @escaping () -> Void,
        onRequestScreenRecordingAccess: @escaping () -> ScreenRecordingPermissionStatus,
        onOpenScreenRecordingSettings: @escaping () -> ScreenRecordingPermissionStatus,
        onUserClose: @escaping () -> Void
    ) {
        self.onUserClose = onUserClose
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        let view = OnboardingView(
            appState: appState,
            initialScreenRecordingStatus: screenRecordingStatus,
            onStartCapture: onStartCapture,
            onOpenAssistant: onOpenAssistant,
            onRequestScreenRecordingAccess: onRequestScreenRecordingAccess,
            onOpenScreenRecordingSettings: onOpenScreenRecordingSettings
        )
        let hostingView = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Pixel Pane"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self
        self.window = window

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func close() {
        window?.delegate = nil
        window?.close()
        window = nil
    }

    // Closing the window with the title-bar button must still finish
    // onboarding: the assistant surface only arms after completion, so a
    // bare close would otherwise leave the app with no way in.
    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
        onUserClose?()
    }
}

private struct OnboardingPage {
    let title: String
    let rows: [(systemImage: String, title: String, detail: String)]
}

private struct OnboardingView: View {
    @ObservedObject var appState: AppState
    let onStartCapture: () -> Void
    let onOpenAssistant: () -> Void
    let onRequestScreenRecordingAccess: () -> ScreenRecordingPermissionStatus
    let onOpenScreenRecordingSettings: () -> ScreenRecordingPermissionStatus

    @State private var screenRecordingStatus: ScreenRecordingPermissionStatus
    @State private var pageIndex = 0

    init(
        appState: AppState,
        initialScreenRecordingStatus: ScreenRecordingPermissionStatus,
        onStartCapture: @escaping () -> Void,
        onOpenAssistant: @escaping () -> Void,
        onRequestScreenRecordingAccess: @escaping () -> ScreenRecordingPermissionStatus,
        onOpenScreenRecordingSettings: @escaping () -> ScreenRecordingPermissionStatus
    ) {
        self.appState = appState
        self.onStartCapture = onStartCapture
        self.onOpenAssistant = onOpenAssistant
        self.onRequestScreenRecordingAccess = onRequestScreenRecordingAccess
        self.onOpenScreenRecordingSettings = onOpenScreenRecordingSettings
        _screenRecordingStatus = State(initialValue: initialScreenRecordingStatus)
    }

    private static let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Capture on your terms",
            rows: [
                (
                    "selection.pin.in.out",
                    "Capture only what you choose",
                    "Capture starts only from the hotkey or menu, and reads just the region you drag. No background recording; screenshots stay in memory and are not saved."
                ),
                (
                    "network.slash",
                    "Local Mode is the default",
                    "Questions, file reading, and answers run on this Mac with your own models. Nothing leaves your computer unless you turn on Cloud Mode."
                )
            ]
        ),
        OnboardingPage(
            title: "Your data stays yours",
            rows: [
                (
                    "folder.badge.person.crop",
                    "Your files, your grants",
                    "The assistant sees only folders you grant, every read is recorded in the run trace, and any change to a file is proposed to you for approval first."
                ),
                (
                    "clock.arrow.circlepath",
                    "Chats stay on this Mac",
                    "Conversation history is stored locally. Review or delete any chat from Settings → History at any time."
                )
            ]
        ),
        OnboardingPage(
            title: "Going online is opt-in",
            rows: [
                (
                    "cloud",
                    "Cloud Mode is explicit — and transparent",
                    "When you enable it, your question and the local context the assistant gathers are sent to Pixel Pane Cloud to answer, and web search may fetch current public information. The free tier includes a daily allowance."
                ),
                (
                    "location.slash",
                    "Location stays off until you turn it on",
                    "Approximate, city-level location is shared only in Cloud Mode, and only after you grant macOS access and enable sharing in Settings — two explicit switches."
                )
            ]
        )
    ]

    /// The pages of static rows, followed by the local-AI setup page and the
    /// permission/launch page.
    private var pageCount: Int { Self.pages.count + 2 }
    private var localAIPageIndex: Int { Self.pages.count }
    private var isLastPage: Bool { pageIndex == pageCount - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Group {
                if pageIndex < Self.pages.count {
                    rowsPage(Self.pages[pageIndex])
                } else if pageIndex == localAIPageIndex {
                    localAIPage
                } else {
                    readyPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            navigationBar
        }
        .padding(24)
        .frame(width: 560, height: 500)
    }

    private var header: some View {
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
    }

    private func rowsPage(_ page: OnboardingPage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(page.title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            ForEach(page.rows, id: \.title) { row in
                OnboardingPrivacyRow(
                    systemImage: row.systemImage,
                    title: row.title,
                    detail: row.detail
                )
            }
        }
    }

    private var readyPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("You're set")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            PermissionReadinessRow(
                status: screenRecordingStatus,
                onRequestAccess: {
                    screenRecordingStatus = onRequestScreenRecordingAccess()
                },
                onOpenSettings: {
                    screenRecordingStatus = onOpenScreenRecordingSettings()
                }
            )

            OnboardingPrivacyRow(
                systemImage: "moon.fill",
                title: "The assistant lives in your notch",
                detail: "Hover the notch or press the hotkey to ask anything. Start with a capture, or open the assistant and just type."
            )
        }
    }

    private var localAIPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set up local AI")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            Text("Pixel Pane runs on your Mac with an open model. We picked one that fits your hardware — download it now, or skip and use Cloud Mode.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            RecommendedModelDownloadView(
                appState: appState,
                onChooseFolder: { appState.chooseMLXModelFolder() }
            )
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 10) {
            if pageIndex > 0 {
                Button("Back") {
                    pageIndex -= 1
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())
            }

            Spacer()

            HStack(spacing: 6) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Circle()
                        .fill(index == pageIndex ? PixelPaneBrand.beige : Color.primary.opacity(0.18))
                        .frame(width: 6, height: 6)
                }
            }

            Spacer()

            if isLastPage {
                Button {
                    onOpenAssistant()
                } label: {
                    Text("Open Assistant")
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())

                Button {
                    onStartCapture()
                } label: {
                    Label("Start First Capture", systemImage: "viewfinder")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    pageIndex += 1
                } label: {
                    Text("Continue")
                        .frame(minWidth: 90)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: pageIndex)
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.blue.opacity(0.18), lineWidth: 1)
        )
    }
}
