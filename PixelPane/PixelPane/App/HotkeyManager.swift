import AppKit
import Carbon.HIToolbox

enum HotkeyRegistrationError: Error, CustomStringConvertible {
    case osStatus(OSStatus)
    case unsupportedModifier

    var description: String {
        switch self {
        case .osStatus(let status):
            return "macOS rejected the shortcut (code \(status))."
        case .unsupportedModifier:
            return "macOS Sequoia rejects shortcuts that do not include Command or Control."
        }
    }
}

nonisolated private func pixelPaneHotkeyEventHandler(
    callRef: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let err = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard err == noErr else { return err }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        manager.handleHotkeyEvent(hotKeyID: hotKeyID)
    }
    return noErr
}

@MainActor
final class HotkeyManager {
    static let defaultDisplayShortcut = "Command + Shift + Space"

    fileprivate static let signatureCode: OSType = {
        let bytes: [UInt8] = [0x50, 0x49, 0x58, 0x50] // "PIXP"
        return (OSType(bytes[0]) << 24) | (OSType(bytes[1]) << 16) | (OSType(bytes[2]) << 8) | OSType(bytes[3])
    }()
    fileprivate static let hotkeyID: UInt32 = 1
    private static let defaultKeyCode: UInt32 = UInt32(kVK_Space)
    private static let defaultModifiers: UInt32 = UInt32(cmdKey | shiftKey)

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var isPaused = false
    private var action: (() -> Void)?

    func register(action: @escaping () -> Void) -> Result<String, HotkeyRegistrationError> {
        if hotKeyRef != nil {
            return .success(HotkeyManager.defaultDisplayShortcut)
        }

        let modifiers = HotkeyManager.defaultModifiers
        let requiresCmdOrControl = (modifiers & UInt32(cmdKey)) != 0
            || (modifiers & UInt32(controlKey)) != 0
        guard requiresCmdOrControl else {
            return .failure(.unsupportedModifier)
        }

        self.action = action

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        var handlerRef: EventHandlerRef?
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            pixelPaneHotkeyEventHandler,
            1,
            &spec,
            userData,
            &handlerRef
        )

        guard installStatus == noErr else {
            self.action = nil
            return .failure(.osStatus(installStatus))
        }
        self.eventHandler = handlerRef

        let hotKeyID = EventHotKeyID(
            signature: HotkeyManager.signatureCode,
            id: HotkeyManager.hotkeyID
        )
        var ref: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            HotkeyManager.defaultKeyCode,
            HotkeyManager.defaultModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard registerStatus == noErr, let ref else {
            if let handlerRef {
                RemoveEventHandler(handlerRef)
                self.eventHandler = nil
            }
            self.action = nil
            return .failure(.osStatus(registerStatus))
        }

        self.hotKeyRef = ref
        return .success(HotkeyManager.defaultDisplayShortcut)
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
    }

    func handleHotkeyEvent(hotKeyID: EventHotKeyID) {
        guard hotKeyID.signature == HotkeyManager.signatureCode,
              hotKeyID.id == HotkeyManager.hotkeyID else { return }
        guard !isPaused, let action else { return }
        action()
    }
}
