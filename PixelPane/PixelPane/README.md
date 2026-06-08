# PixelPane — Source Architecture

This document describes how the Swift source is layered and where to look when making changes.

## Layer map

```
User gesture (hotkey / menu)
        │
        ▼
    App/AppState          ← orchestrates everything; start reading here
        │
   ┌────┴────┐
   ▼         ▼
Capture/   Panel/         ← screen selection UI  |  result + chat UI
   │
   ▼
 OCR/ + Classification/   ← text extraction and smart action selection
        │
        ▼
    Actions/              ← AI backend protocol + MLX / Apple FM / Cloud impls
        │
        ▼
  AgentKernel/            ← adapter layer: translates backends → agent protocol
        │
        ▼
  AgentRuntime/           ← stateful agent: tool loop, permissions, storage
        │
        ▼
    API/ (cloud path)     ← Cloudflare Worker client for Cloud Mode
```

## Folder summaries

| Folder | One-line purpose |
|---|---|
| `App/` | Central `AppState`, routing config, hotkeys, permissions |
| `Capture/` | Region selection overlay and `ScreenCaptureKit` capture |
| `OCR/` | Vision-framework OCR and NaturalLanguage detection |
| `Classification/` | Classifies OCR content to pick the smart default action |
| `Actions/` | `AIBackend` protocol, MLX backends, model catalog, downloader |
| `AgentKernel/` | Adapter factory bridging `AIBackend` into the agent model protocol |
| `AgentRuntime/` | Durable agent runner: tool loop, evidence, permissions, SQLite storage |
| `Panel/` | Notch-attached SwiftUI result panel and chat transcript |
| `Onboarding/` | First-launch permissions and local-AI setup flow |
| `Settings/` | Settings window tabs (capture, AI routing, local models, files) |
| `API/` | Cloud backend client and auth token management |

## Key protocols and extension points

### Adding a new AI backend
1. Conform to `AIBackend` (`Actions/AIBackend.swift`).
2. Register it in `HybridLocalAIBackend` (`Actions/HybridLocalAIBackend.swift`).
3. Add an adapter in `AgentKernel/` if the backend needs custom tool-call handling.

### Adding a new panel action
1. Add a case to `PanelActionState` (`Panel/PanelActionState.swift`).
2. Handle it in `ResultPanelView` (`Panel/ResultPanelView.swift`).
3. The action will automatically appear in the action bar.

### Adding a new agent tool
1. Add a spec to `AgentToolCatalog` (`AgentRuntime/AgentToolCatalog.swift`) — name, description, risk level, and which permission modes allow it.
2. Add an executor case in `AgentLocalToolExecutor` (`AgentRuntime/AgentLocalToolExecutor.swift`).
3. Add an evidence type in `AgentEvidencePackets` if the tool produces verifiable output.

## Data flow for a single capture

1. `HotkeyManager` fires → `AppState.startCapture()`
2. `OverlayCoordinator` shows region selector; user drags a rect
3. `ScreenCapturer` grabs a `CGImage` for that rect
4. `OCREngine` extracts text; `TechnicalContentClassifier` scores it
5. `SmartDefaultActionSelector` picks the opening action
6. `ResultPanelController` shows the panel; user picks an action or types a question
7. `AgentRuntime` routes to the right model via `AgentModelRouter`, calls tools as needed, streams back results
8. Panel renders streamed output through `ModelOutputFormatter`
