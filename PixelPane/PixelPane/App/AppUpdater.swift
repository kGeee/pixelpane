import Foundation
import Sparkle

/// Sparkle auto-updates. Checks run automatically (SUEnableAutomaticChecks in
/// Info.plist) against the appcast published with each GitHub release; the
/// Settings button triggers a manual check. Disabled in DEBUG builds so
/// development runs never prompt about updates.
@MainActor
final class AppUpdater {
    static let shared = AppUpdater()

    private let controller: SPUStandardUpdaterController

    private init() {
        #if DEBUG
        let startsUpdater = false
        #else
        let startsUpdater = true
        #endif
        controller = SPUStandardUpdaterController(
            startingUpdater: startsUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
