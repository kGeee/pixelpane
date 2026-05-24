import AppKit
import SwiftUI

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
final class OverlayCoordinator {
    private var windows: [NSWindow] = []

    func beginSelection(
        showFirstUseTip: Bool = false,
        onComplete: @escaping (CaptureSelection) -> Void,
        onCancel: @escaping () -> Void
    ) {
        closeWindows()

        for screen in NSScreen.screens {
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            let view = RegionSelectorView(
                screen: screen,
                showFirstUseTip: showFirstUseTip,
                onComplete: { [weak self] selection in
                    self?.endOverlay { onComplete(selection) }
                },
                onCancel: { [weak self] in
                    self?.endOverlay { onCancel() }
                }
            )

            let hosting = FirstMouseHostingView(rootView: view)
            hosting.autoresizingMask = [.width, .height]
            hosting.frame = NSRect(origin: .zero, size: screen.frame.size)
            window.contentView = hosting
            window.setFrame(screen.frame, display: true)

            windows.append(window)
            window.orderFrontRegardless()
            window.makeKey()
        }
    }

    private func endOverlay(_ continuation: @escaping () -> Void) {
        let inFlight = windows
        windows.removeAll()
        inFlight.forEach { $0.orderOut(nil) }
        continuation()
        DispatchQueue.main.async {
            _ = inFlight
        }
    }

    private func closeWindows() {
        let inFlight = windows
        windows.removeAll()
        inFlight.forEach { $0.orderOut(nil) }
    }
}
