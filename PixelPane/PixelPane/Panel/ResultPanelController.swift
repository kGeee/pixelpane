import AppKit
import SwiftUI

@MainActor
final class ResultPanelController {
    private var panel: NSPanel?
    private let resultPresentationStyle: ResultPanelPresentationStyle = .notchAttached
    private var currentResult: CaptureResult?
    private var currentStartsInAssistantMode = false
    private var currentOnTryAgain: (@MainActor () -> Void)?

    func show(
        result: CaptureResult,
        routingSettings: AIRoutingSettings,
        localAICapabilities: AIBackendCapabilities,
        localFileAccess: LocalFileAccessStore,
        startsInAssistantMode: Bool = false,
        startsExpanded: Bool = false,
        showsInitialNotchNotification: Bool = true,
        onTryAgain: @escaping @MainActor () -> Void
    ) {
        currentResult = result
        currentStartsInAssistantMode = startsInAssistantMode
        currentOnTryAgain = onTryAgain
        ensurePanel()

        installContent(
            ResultPanelView(
                result: result,
                routingSettings: routingSettings,
                localAICapabilities: localAICapabilities,
                localFileAccess: localFileAccess,
                presentationStyle: resultPresentationStyle,
                startsInAssistantMode: startsInAssistantMode,
                startsExpanded: startsExpanded,
                showsInitialNotchNotification: showsInitialNotchNotification,
                onPresentationSizeChange: { [weak self] size in
                    self?.resizeNotchPanel(to: size, for: result.selectionFrame)
                },
                onTryAgain: onTryAgain,
                onClose: { [weak self] in
                    self?.close()
                }
            )
        )
        switch resultPresentationStyle {
        case .floatingNearSelection:
            positionPanel(near: result.selectionFrame)
            panel?.makeKeyAndOrderFront(nil)
            NSApp.activate()
        case .notchAttached:
            positionPanelAtNotch(
                on: screen(for: result.selectionFrame),
                size: initialNotchSize(
                    startsExpanded: startsExpanded,
                    showsInitialNotchNotification: showsInitialNotchNotification
                )
            )
            panel?.orderFrontRegardless()
        }
    }

    func refreshRoutingSettings(
        _ routingSettings: AIRoutingSettings,
        localAICapabilities: AIBackendCapabilities,
        localFileAccess: LocalFileAccessStore
    ) {
        guard panel != nil, let currentResult, let currentOnTryAgain else { return }
        let startsExpanded = panel.map { isExpandedNotchSize($0.frame.size) } ?? false
        show(
            result: currentResult,
            routingSettings: routingSettings,
            localAICapabilities: localAICapabilities,
            localFileAccess: localFileAccess,
            startsInAssistantMode: currentStartsInAssistantMode,
            startsExpanded: startsExpanded,
            showsInitialNotchNotification: false,
            onTryAgain: currentOnTryAgain
        )
        if !startsExpanded {
            resizeNotchPanel(to: ResultPanelPresentationStyle.notchHoverTargetSize, for: currentResult.selectionFrame)
        }
    }

    func showAssistant(
        routingSettings: AIRoutingSettings,
        localAICapabilities: AIBackendCapabilities,
        localFileAccess: LocalFileAccessStore,
        onTryAgain: @escaping @MainActor () -> Void
    ) {
        let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 700, height: 500)
        let result = CaptureResult(
            image: nil,
            text: "",
            isEmptyOCRResult: true,
            selectionFrame: CGRect(x: screenFrame.midX, y: screenFrame.maxY - 1, width: 1, height: 1),
            createdAt: Date(),
            sourceType: .assistant,
            detectedLanguage: .unknown
        )
        show(
            result: result,
            routingSettings: routingSettings,
            localAICapabilities: localAICapabilities,
            localFileAccess: localFileAccess,
            startsInAssistantMode: true,
            showsInitialNotchNotification: false,
            onTryAgain: onTryAgain
        )
    }

    func show(
        recovery issue: RecoveryIssue,
        near selectionFrame: CGRect? = nil,
        onPrimaryAction: @escaping @MainActor () -> Void,
        onSecondaryAction: (@MainActor () -> Void)? = nil
    ) {
        ensurePanel()

        installContent(
            RecoveryPanelView(
                issue: issue,
                onPrimaryAction: onPrimaryAction,
                onSecondaryAction: onSecondaryAction,
                onClose: { [weak self] in
                    self?.close()
                }
            )
        )

        if let selectionFrame {
            positionPanel(near: selectionFrame)
        } else {
            positionPanelAtCenter()
        }

        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close() {
        panel?.close()
        panel = nil
        currentResult = nil
        currentOnTryAgain = nil
        currentStartsInAssistantMode = false
    }

    private func ensurePanel() {
        if panel == nil {
            panel = makePanel()
        }
    }

    private func installContent<Content: View>(_ root: Content) {
        guard let panel else { return }
        let host = NSHostingView(rootView: root)
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        host.layer?.isOpaque = false
        host.layer?.masksToBounds = true
        host.layer?.cornerCurve = .continuous
        panel.contentView = host
        updateContentCornerMask(for: panel.frame.size)
        panel.invalidateShadow()
    }

    private func makePanel() -> NSPanel {
        let initialSize = resultPresentationStyle.initialSize
        let panel = OverlayPanel(
            contentRect: CGRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = resultPresentationStyle != .notchAttached
        panel.level = resultPresentationStyle == .notchAttached ? .statusBar : .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = resultPresentationStyle.minimumSize
        panel.maxSize = resultPresentationStyle.maximumSize
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = resultPresentationStyle != .notchAttached
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        return panel
    }

    private func positionPanel(near selectionFrame: CGRect) {
        guard let panel else { return }

        let visibleFrame = screen(for: selectionFrame)?.visibleFrame ?? .zero
        let size = panel.frame.size

        let candidateOrigins = [
            CGPoint(x: selectionFrame.maxX + 12, y: selectionFrame.maxY - size.height),
            CGPoint(x: selectionFrame.minX, y: selectionFrame.minY - size.height - 12),
            CGPoint(x: selectionFrame.minX - size.width - 12, y: selectionFrame.maxY - size.height),
            CGPoint(x: selectionFrame.minX, y: selectionFrame.maxY + 12)
        ]

        let origin = candidateOrigins.first { point in
            visibleFrame.contains(CGRect(origin: point, size: size))
        } ?? CGPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2
        )

        panel.setFrameOrigin(clamp(origin: origin, size: size, into: visibleFrame))
    }

    private func screen(for selectionFrame: CGRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(selectionFrame) } ?? NSScreen.main
    }

    private func positionPanelAtNotch(on screen: NSScreen?, size requestedSize: CGSize? = nil) {
        guard let panel else { return }

        let rawSize = requestedSize ?? panel.frame.size
        let isHoverTarget = isHoverTargetSize(rawSize)
        let size = resolvedNotchSize(rawSize, on: screen)
        let origin = notchOrigin(for: size, on: screen, isHoverTarget: isHoverTarget)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        updateContentCornerMask(for: size)
    }

    private func initialNotchSize(startsExpanded: Bool, showsInitialNotchNotification: Bool) -> CGSize {
        if startsExpanded {
            return ResultPanelPresentationStyle.notchExpandedSize
        }
        return showsInitialNotchNotification
            ? ResultPanelPresentationStyle.notchCompactSize
            : ResultPanelPresentationStyle.notchHoverTargetSize
    }

    private func resizeNotchPanel(to size: CGSize, for selectionFrame: CGRect) {
        guard resultPresentationStyle == .notchAttached, let panel else { return }

        let screen = screen(for: selectionFrame)
        let isHoverTarget = isHoverTargetSize(size)
        let size = resolvedNotchSize(size, on: screen)
        let origin = notchOrigin(for: size, on: screen, isHoverTarget: isHoverTarget)
        let targetFrame = CGRect(
            x: origin.x,
            y: origin.y,
            width: size.width,
            height: size.height
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = size.width > panel.frame.width ? 0.36 : 0.12
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.86, 0.24, 1.0)
            panel.animator().setFrame(targetFrame, display: true)
        }
        updateContentCornerMask(for: size)
        panel.invalidateShadow()
    }

    private func updateContentCornerMask(for size: CGSize) {
        guard let layer = panel?.contentView?.layer else { return }
        let roundsAssistantPanel = resultPresentationStyle == .notchAttached
            && currentResult?.sourceType == .assistant
            && isExpandedNotchSize(size)
        layer.cornerRadius = roundsAssistantPanel
            ? ResultPanelPresentationStyle.notchAssistantCornerRadius
            : resultPresentationStyle.cornerRadius
        layer.masksToBounds = true
        layer.cornerCurve = .continuous
    }

    private func notchOrigin(for size: CGSize, on screen: NSScreen?, isHoverTarget: Bool = false) -> CGPoint {
        let resolvedScreen = screen ?? NSScreen.main
        let screenFrame = resolvedScreen?.frame ?? .zero
        guard resultPresentationStyle == .notchAttached else { return .zero }

        if isCompactNotificationSize(size),
           let origin = compactNotificationOrigin(for: size, on: resolvedScreen, in: screenFrame) {
            return origin
        }

        if isHoverTarget,
           let notchBounds = notchBounds(on: resolvedScreen) {
            let x = notchBounds.midX - size.width / 2
            let y = notchBounds.maxY - size.height + notchTopOverscan
            return clampNotch(origin: CGPoint(x: x, y: y), size: size, into: screenFrame)
        }

        return clampNotch(
            origin: CGPoint(
                x: screenFrame.midX - size.width / 2,
                y: screenFrame.maxY - size.height + notchTopOverscan
            ),
            size: size,
            into: screenFrame
        )
    }

    private var notchTopOverscan: CGFloat {
        currentResult?.sourceType == .assistant ? 0 : ResultPanelPresentationStyle.notchTopOverscan
    }

    private func resolvedNotchSize(_ requestedSize: CGSize, on screen: NSScreen?) -> CGSize {
        guard isHoverTargetSize(requestedSize),
              let notchBounds = notchBounds(on: screen) else {
            return requestedSize
        }

        return CGSize(
            width: max(96, notchBounds.width),
            height: max(requestedSize.height, min(notchBounds.height, 44))
        )
    }

    private func compactNotificationOrigin(for size: CGSize, on screen: NSScreen?, in screenFrame: CGRect) -> CGPoint? {
        guard let screen else { return nil }

        if let notchBounds = notchBounds(on: screen) {
            let origin = CGPoint(
                x: notchBounds.maxX - ResultPanelPresentationStyle.notchCompactOverlap,
                y: notchBounds.maxY - size.height
            )
            return clampNotch(origin: origin, size: size, into: screenFrame)
        }

        if let topRightArea = screen.auxiliaryTopRightArea,
           !topRightArea.isEmpty,
           topRightArea.minX > screenFrame.midX {
            let origin = CGPoint(
                x: topRightArea.minX - ResultPanelPresentationStyle.notchCompactOverlap,
                y: topRightArea.maxY - size.height
            )
            return clampNotch(origin: origin, size: size, into: screenFrame)
        }

        let fallbackNotchWidth = min(max(screenFrame.width * 0.12, 160), 280)
        let fallbackNotchRightEdge = screenFrame.midX + fallbackNotchWidth / 2
        return clampNotch(
            origin: CGPoint(
                x: fallbackNotchRightEdge - ResultPanelPresentationStyle.notchCompactOverlap,
                y: screenFrame.maxY - size.height
            ),
            size: size,
            into: screenFrame
        )
    }

    private func isCompactNotificationSize(_ size: CGSize) -> Bool {
        abs(size.width - ResultPanelPresentationStyle.notchCompactSize.width) < 1
            && abs(size.height - ResultPanelPresentationStyle.notchCompactSize.height) < 1
    }

    private func isHoverTargetSize(_ size: CGSize) -> Bool {
        abs(size.width - ResultPanelPresentationStyle.notchHoverTargetSize.width) < 1
            && abs(size.height - ResultPanelPresentationStyle.notchHoverTargetSize.height) < 1
    }

    private func isExpandedNotchSize(_ size: CGSize) -> Bool {
        size.width >= ResultPanelPresentationStyle.notchEmptyAssistantSize.width - 1
            || size.height > ResultPanelPresentationStyle.notchHoverTargetSize.height + 80
    }

    private func notchBounds(on screen: NSScreen?) -> CGRect? {
        guard let screen else {
            return nil
        }

        let frame = screen.frame
        let fallbackWidth = min(max(frame.width * 0.12, 160), 280)
        let fallbackHeight = max(28, frame.maxY - screen.visibleFrame.maxY)
        let topLeftArea = screen.auxiliaryTopLeftArea
        let topRightArea = screen.auxiliaryTopRightArea

        if let topLeftArea,
           let topRightArea,
           !topLeftArea.isEmpty,
           !topRightArea.isEmpty,
           topLeftArea.maxX < topRightArea.minX {
            let bounds = CGRect(
                x: topLeftArea.maxX,
                y: min(topLeftArea.minY, topRightArea.minY),
                width: topRightArea.minX - topLeftArea.maxX,
                height: max(topLeftArea.height, topRightArea.height)
            )
            if isReasonableNotchBounds(bounds, in: frame) {
                return bounds
            }
        }

        if let topRightArea, !topRightArea.isEmpty, topRightArea.minX > frame.midX {
            let bounds = CGRect(
                x: topRightArea.minX - fallbackWidth,
                y: topRightArea.minY,
                width: fallbackWidth,
                height: max(topRightArea.height, fallbackHeight)
            )
            if isReasonableNotchBounds(bounds, in: frame) {
                return bounds
            }
        }

        if let topLeftArea, !topLeftArea.isEmpty, topLeftArea.maxX < frame.midX {
            let bounds = CGRect(
                x: topLeftArea.maxX,
                y: topLeftArea.minY,
                width: fallbackWidth,
                height: max(topLeftArea.height, fallbackHeight)
            )
            if isReasonableNotchBounds(bounds, in: frame) {
                return bounds
            }
        }

        return nil
    }

    private func isReasonableNotchBounds(_ bounds: CGRect, in frame: CGRect) -> Bool {
        bounds.width >= 80
            && bounds.width <= min(520, frame.width * 0.34)
            && bounds.height >= 20
            && bounds.height <= 96
            && abs(bounds.midX - frame.midX) <= frame.width * 0.18
    }

    private func clampNotch(origin: CGPoint, size: CGSize, into frame: CGRect) -> CGPoint {
        guard frame != .zero else { return origin }
        let maxX = max(frame.minX, frame.maxX - size.width)
        return CGPoint(
            x: min(max(origin.x, frame.minX), maxX),
            y: origin.y
        )
    }

    private func clamp(origin: CGPoint, size: CGSize, into frame: CGRect) -> CGPoint {
        guard frame != .zero else { return origin }
        let maxX = max(frame.minX, frame.maxX - size.width)
        let maxY = max(frame.minY, frame.maxY - size.height)
        return CGPoint(
            x: min(max(origin.x, frame.minX), maxX),
            y: min(max(origin.y, frame.minY), maxY)
        )
    }

    private func positionPanelAtCenter() {
        guard let panel else { return }

        let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
        let size = panel.frame.size
        panel.setFrameOrigin(
            CGPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2
            )
        )
    }
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

enum OverlayPanelMetrics {
    static let cornerRadius: CGFloat = 16
}

enum ResultPanelPresentationStyle {
    case floatingNearSelection
    case notchAttached

    var initialSize: CGSize {
        switch self {
        case .floatingNearSelection:
            CGSize(width: 880, height: 540)
        case .notchAttached:
            Self.notchCompactSize
        }
    }

    var minimumSize: CGSize {
        switch self {
        case .floatingNearSelection:
            CGSize(width: 720, height: 460)
        case .notchAttached:
            Self.notchCompactSize
        }
    }

    var maximumSize: CGSize {
        switch self {
        case .floatingNearSelection:
            CGSize(width: 1200, height: 900)
        case .notchAttached:
            Self.notchExpandedSize
        }
    }

    static let notchCompactSize = CGSize(width: 52, height: 32)
    static let notchHoverTargetSize = CGSize(width: 180, height: 32)
    static let notchEmptyAssistantSize = CGSize(width: 640, height: 220)
    static let notchExpandedSize = CGSize(width: 820, height: 680)
    static let notchAssistantCornerRadius: CGFloat = 30
    static let notchCompactOverlap: CGFloat = 18
    static let notchTopOverscan: CGFloat = 3

    var cornerRadius: CGFloat {
        switch self {
        case .floatingNearSelection:
            OverlayPanelMetrics.cornerRadius
        case .notchAttached:
            0
        }
    }
}
