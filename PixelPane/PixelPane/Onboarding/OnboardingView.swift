import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    func show(onStartCapture: @escaping () -> Void, onContinue: @escaping () -> Void) {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        let view = OnboardingView(
            onStartCapture: onStartCapture,
            onContinue: onContinue
        )
        let hostingView = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Pixel Pane"
        window.contentView = hostingView
        window.minSize = NSSize(width: 520, height: 460)
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
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Pixel Pane")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Private screen capture, only when you ask.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                OnboardingPrivacyRow(
                    systemImage: "selection.pin.in.out",
                    title: "Selected regions only",
                    detail: "Capture starts from the hotkey or menu. You drag over the exact screen region Pixel Pane should read."
                )
                OnboardingPrivacyRow(
                    systemImage: "record.circle",
                    title: "No continuous recording",
                    detail: "Pixel Pane does not watch your screen in the background or keep a screen timeline."
                )
                OnboardingPrivacyRow(
                    systemImage: "memorychip",
                    title: "Captures stay ephemeral",
                    detail: "OCR starts from an in-memory image. Screenshots are not saved to chat history by default."
                )
            }

            Text("macOS will ask for Screen Recording permission before the first capture can read pixels. Granting it lets Pixel Pane process only the regions you explicitly select.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack(spacing: 10) {
                Button {
                    onContinue()
                } label: {
                    Text("Continue")
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
        .frame(width: 520)
        .frame(minHeight: 460)
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
