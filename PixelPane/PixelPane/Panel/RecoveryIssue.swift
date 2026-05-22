import Foundation

enum RecoveryIssue: Identifiable, Equatable {
    case screenRecording
    case hotkeyRegistration(message: String)

    var id: String {
        switch self {
        case .screenRecording:
            "screen-recording"
        case .hotkeyRegistration:
            "hotkey-registration"
        }
    }

    var title: String {
        switch self {
        case .screenRecording:
            "Screen Recording Access Needed"
        case .hotkeyRegistration:
            "Shortcut Not Available"
        }
    }

    var systemImage: String {
        switch self {
        case .screenRecording:
            "rectangle.on.rectangle.slash"
        case .hotkeyRegistration:
            "keyboard.badge.exclamationmark"
        }
    }

    var message: String {
        switch self {
        case .screenRecording:
            "Pixel Pane needs Screen Recording permission to capture the region you select."
        case .hotkeyRegistration(let message):
            "The global capture shortcut could not be registered. \(message)"
        }
    }

    var recoveryText: String {
        switch self {
        case .screenRecording:
            "After enabling Pixel Pane, macOS may ask you to quit and reopen the app."
        case .hotkeyRegistration:
            "Capture from the menu bar still works."
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .screenRecording:
            "Request Access"
        case .hotkeyRegistration:
            "Dismiss"
        }
    }

    var primaryActionSystemImage: String {
        switch self {
        case .screenRecording:
            "lock.open"
        case .hotkeyRegistration:
            "checkmark"
        }
    }

    var secondaryActionTitle: String? {
        switch self {
        case .screenRecording:
            "Open System Settings"
        case .hotkeyRegistration:
            nil
        }
    }
}
