//
//  PixelPaneApp.swift
//  PixelPane
//
//  Created by Snehith Nayak on 4/28/26.
//

import AppKit
import SwiftUI

final class PixelPaneAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    func applicationWillTerminate(_ notification: Notification) {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await MLXTextServerManager.terminateCurrentProcess()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 1)
    }
}

@main
struct PixelPaneApp: App {
    @Environment(\.openSettings) private var openSettings
    @NSApplicationDelegateAdaptor(PixelPaneAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Pixel Pane", systemImage: "viewfinder") {
            Button("Capture") {
                appState.startCapture()
            }
            .keyboardShortcut(" ", modifiers: [.command, .shift])

            Button("Show Last Result") {
                appState.showLastResult()
            }
            .disabled(appState.lastResult == nil)

            Divider()

            Button(appState.isHotkeyPaused ? "Resume Hotkey" : "Pause Hotkey") {
                appState.togglePauseHotkey()
            }
            .disabled(!appState.canTogglePauseHotkey)

            Button("Settings") {
                openSettings()
                SettingsWindowActivation.request()
            }

            Divider()

            Button("Quit Pixel Pane") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
