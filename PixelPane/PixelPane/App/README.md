# App

Central application state, configuration, and integration glue. Most subsystems are created here and wired together through `AppState`.

## Files

| File | Purpose |
|---|---|
| `PixelPaneApp.swift` | App entry point. Owns the menu bar item, registers the global hotkey, launches the capture flow, and opens the settings window. |
| `AppState.swift` | The single `ObservableObject` driving the whole app. Holds live state for capture, permissions, model setup, active downloads, and onboarding. All SwiftUI views observe this. |
| `AIRoutingSettings.swift` | Persisted user preferences for local vs. cloud mode, image context consent, location sharing, and which local model is pinned. |
| `AssistantResponsePolicy.swift` | Declares which actions accept image input and what the output token limit is per action. Change this to add/adjust limits for new actions. |
| `HotkeyManager.swift` | Registers and handles the global Cmd+Shift+Space shortcut via `Carbon`. |
| `LocalFileAccess.swift` | Models and `UserDefaults`-backed store for user-granted file and folder access. The agent runtime checks these grants before accessing the filesystem. |
| `LocationContextProvider.swift` | Resolves a city-level location string (no exact coordinates) to attach as context to cloud requests when the user opts in. |
| `PixelPaneBrand.swift` | Shared `Color` constants (beige, ink) used across all views. |
| `SystemStatus.swift` | Enums for screen recording and hotkey permission states, with human-readable labels and recovery guidance. |
| `AppUpdater.swift` | Sparkle-based update checker. Fires on launch (release builds only) and exposes a manual refresh action. |

## Extension points

- **New persisted setting** — add a property to `AIRoutingSettings` and expose it through `AppState`.
- **New permission type** — add a case to the relevant enum in `SystemStatus.swift` and surface recovery guidance in `Panel/RecoveryPanelView.swift`.
- **New global shortcut** — extend `HotkeyManager` with an additional `EventHotKey` registration.
