# Pixel Pane

Pixel Pane is a local-first, notch-native assistant for macOS. Press a hotkey, select a screen region, and ask anything about what you captured — text extraction, translation, code explanation, file operations, and multi-turn chat, all routed to a local MLX model or Pixel Pane Cloud depending on your settings.

## Architecture at a glance

```
PixelPane/PixelPane/   Swift source
├── App/               Central state, hotkeys, routing settings
├── Capture/           Screen region selection and ScreenCaptureKit
├── OCR/               On-device text and language detection
├── Classification/    Smart default action selection
├── Actions/           AI backends (MLX, Apple FM, Cloud) + model catalog
├── AgentKernel/       Adapter layer between backends and the agent protocol
├── AgentRuntime/      Durable agent execution, tool calls, permissions, storage
├── Panel/             Notch-attached result and chat UI
├── Onboarding/        First-launch setup flow
├── Settings/          Settings window
└── API/               Pixel Pane Cloud backend client

PixelPane/Backend/     Cloudflare Worker (Cloud Mode proxy)
PixelPane/Scripts/     Build verification and fixture test runners
```

Each folder has its own `README.md` with a file-by-file breakdown and contributor guidance.

## Build

```bash
PixelPane/Scripts/verify-debug-build.sh
```

Open `PixelPane/PixelPane.xcodeproj` in Xcode, select the **PixelPane** scheme, and run. No external dependencies beyond the Swift packages already in the project.

## Contributing

Good first areas:
- **New actions** — add an entry to `PanelActionState` in `Panel/` and wire a handler in `ResultPanelView`
- **New AI backend** — conform to `AIBackend` in `Actions/` and register it in `HybridLocalAIBackend`
- **New agent tools** — add a spec to `AgentToolCatalog` and an executor case in `AgentLocalToolExecutor`
- **UI polish** — the Panel and Settings folders contain self-contained SwiftUI views

See `PixelPane/PixelPane/README.md` for a deeper architecture walkthrough.
