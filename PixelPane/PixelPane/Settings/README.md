# Settings

Settings window and reusable local-model setup components shared with the onboarding flow.

## Files

| File | Purpose |
|---|---|
| `SettingsView.swift` | Tab-based `NSWindow` content. Tabs: Capture (hotkey, screen recording), Permissions, Local AI (model selection, download, runtime), Files (granted folders), Chat History. |
| `LocalModelSetupView.swift` | Three reusable SwiftUI views used in both Settings and Onboarding: `ModelDownloadProgressView` (progress bar / error for an active download), `RuntimeSetupRow` (MLX runtime status + install button), `RecommendedModelDownloadView` (hardware chip, model card, combined download + runtime block). |

## Adding a new settings tab

1. Add a tab identifier and a corresponding `@ViewBuilder` section in `SettingsView`.
2. Bind new preferences to `AppState` properties or introduce a new settings struct (following the pattern in `App/AIRoutingSettings.swift`).

## LocalModelSetupView components

These views are intentionally decoupled from the tab structure so they can be dropped into any context:

- `ModelDownloadProgressView(state:onCancel:onDismissError:)` — renders the current `ModelDownloadState` (preparing / downloading / validating / failed).
- `RuntimeSetupRow(appState:)` — green checkmark when the runtime is present; install + copy-command buttons when it isn't.
- `RecommendedModelDownloadView(appState:onChooseFolder:)` — full hardware-aware recommendation card + download button + runtime row.
