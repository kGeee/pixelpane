import AppKit
import CoreGraphics
import Foundation

enum ScreenRecordingPermissionStatus: Equatable {
    case granted
    case notGranted

    var isGranted: Bool {
        self == .granted
    }

    var label: String {
        switch self {
        case .granted:
            "Granted"
        case .notGranted:
            "Needs Permission"
        }
    }

    var detail: String {
        switch self {
        case .granted:
            "Pixel Pane can capture selected screen regions."
        case .notGranted:
            "Grant Screen Recording permission before using capture."
        }
    }
}

enum HotkeyRegistrationStatus: Equatable {
    case notRegistered
    case registered(shortcut: String)
    case paused(shortcut: String)
    case failed(message: String)

    var label: String {
        switch self {
        case .notRegistered:
            "Not Registered"
        case .registered:
            "Registered"
        case .paused:
            "Paused"
        case .failed:
            "Failed"
        }
    }

    var detail: String {
        switch self {
        case .notRegistered:
            "Global shortcut registration is not enabled in this build. Menu capture remains available."
        case .registered(let shortcut):
            "\(shortcut) is active system-wide."
        case .paused(let shortcut):
            "\(shortcut) is paused. Capture from the menu bar still works."
        case .failed(let message):
            "Global shortcut registration failed: \(message). Menu capture remains available."
        }
    }
}

struct SystemPermissionManager {
    func screenRecordingStatus() -> ScreenRecordingPermissionStatus {
        CGPreflightScreenCaptureAccess() ? .granted : .notGranted
    }

    @discardableResult
    func requestScreenRecordingAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func openScreenRecordingSettings() {
        let settingsURLs = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy"
        ].compactMap(URL.init(string:))

        for url in settingsURLs where NSWorkspace.shared.open(url) {
            return
        }
    }
}
