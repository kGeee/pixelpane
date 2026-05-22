# Architecture: Pixel Pane

> **Status**: Draft — to be filled in by the Architect agent before development begins.

## High-Level Overview

Pixel Pane is a macOS menu-bar app built with SwiftUI + AppKit. Its core pipeline is:

```
Hotkey → Overlay (NSWindow) → Region selection (CGRect)
  → Screenshot (ScreenCaptureKit) → OCR (Vision)
  → Content classification → Action selection
  → Result (Apple Foundation Models / MLX vision / Claude API)
  → Notch-attached result surface (SwiftUI in NSPanel)
```

## Key Technical Decisions

| Decision | Choice | Rationale |
|---|---|---|
| UI framework | SwiftUI + AppKit interop | SwiftUI for panels/settings; AppKit for overlay NSWindow |
| OCR | Apple Vision (VNRecognizeTextRequest) | On-device, fast, no data leaves device |
| Minimum macOS | macOS 15.2+ | Keeps the capture stack aligned with `SCScreenshotManager.captureImage(in:)` |
| Local text and translation AI | Apple Foundation Models | Private, on-device text generation when Apple Intelligence is available |
| Local vision AI | Optional MLX/VLM model setup | Private, on-device image understanding while Apple Foundation Models lacks image prompt input |
| Cloud AI | Claude API (claude-sonnet-4-6) | Best-in-class reasoning for explain/study/menu modes when user opts into Cloud Mode |
| Cloud proxy hosting | Cloudflare Workers | Streaming-friendly edge runtime for the Claude proxy, with secrets kept server-side |
| Screen capture | ScreenCaptureKit | Apple-recommended modern API, permission-gated |
| Global hotkey | Carbon `RegisterEventHotKey` | Enough for the alpha shortcut and avoids Accessibility permission by default |
| Payments | Stripe + RevenueCat | Fits Direct distribution outside the Mac App Store |
| Persistence | UserDefaults (settings) + CoreData (history, glossary) | Appropriate scale for local-first data |

## Module Structure (Proposed)

```
PixelPane/
  App/
    PixelPaneApp.swift         # App entry point, menu bar setup
    AppState.swift             # ObservableObject for global state
  Capture/
    HotkeyManager.swift        # Carbon RegisterEventHotKey global shortcut
    OverlayWindow.swift        # Full-screen NSWindow overlay
    RegionSelector.swift       # Drag-to-select view
    ScreenCapturer.swift       # ScreenCaptureKit wrapper
  OCR/
    OCREngine.swift            # Vision VNRecognizeTextRequest wrapper
    LanguageDetector.swift     # NLLanguageRecognizer wrapper
  Classification/
    ContentClassifier.swift    # Rule-based + lightweight model classifier
  Actions/
    LocalAIBackend.swift       # Shared local backend protocol
    AppleTextBackend.swift     # Foundation Models text-only local backend
    MLXVisionBackend.swift     # Optional local image-aware backend
    TranslateAction.swift      # Local and cloud translation
    ExplainAction.swift        # Claude API explain prompt
    SimplifyAction.swift       # Claude API simplify prompt
    ExtractTextAction.swift    # Pass-through from OCR
    AskAction.swift            # Multi-turn follow-up
    DebugAction.swift          # Code/error-aware prompt
  Panel/
    ResultPanel.swift          # Notch-attached SwiftUI result surface
    ActionRail.swift           # Primary action buttons
    FollowUpInput.swift        # Follow-up text input
  Settings/
    SettingsView.swift         # Preferences window
    PrivacySettings.swift      # Local vs. cloud toggle
    LocalModelSetupView.swift  # MLX model discovery/install setup
    GlossarySettings.swift     # Glossary management
  Persistence/
    HistoryStore.swift         # CoreData history model
    GlossaryStore.swift        # CoreData glossary model
  Onboarding/
    OnboardingFlow.swift       # First-launch permission flow
  Monetization/
    SubscriptionManager.swift  # Stripe + RevenueCat wrapper
    PaywallView.swift          # Upgrade prompt UI
  API/
    ClaudeAPIClient.swift      # Anthropic API client
    PromptBuilder.swift        # Prompt templates per action/mode
```

## Data Flow

1. `HotkeyManager` fires → `AppState.startCapture()`
2. `OverlayWindow` shown → user selects `CGRect`
3. `ScreenCapturer.capture(rect:)` → `CGImage`
4. `OCREngine.recognize(image:)` → `[String]` (ordered text lines)
5. `LanguageDetector.detect(text:)` → `NLLanguage`
6. `ContentClassifier.classify(text:)` → `ContentMode` (message/study/menu/technical/general)
7. User taps action in `ActionRail` → appropriate `*Action` called
8. Result returned → `ResultPanel` updated

## Privacy Architecture

- OCR runs entirely in-process using Vision from an in-memory `CGImage`; the normal capture pipeline does not write screenshots to disk.
- If an error state needs retry support, the capture may remain in memory only until the user dismisses the panel or retries the action.
- In local mode, `ClaudeAPIClient` is never called. Text-only local actions may use Apple frameworks. Image-aware local actions require an installed MLX/VLM model selected through setup; until setup passes a smoke test, image-aware actions must be disabled or fall back to OCR-text-only behavior with clear labeling.
- No analytics data is sent without explicit opt-in from the user.

## Local Model Setup

- Pixel Pane should discover compatible Hugging Face/MLX models already present under `~/.cache/huggingface/hub`.
- If a compatible model is present, setup should offer to use it before recommending a download.
- Current recommended local vision model: `mlx-community/Qwen3.6-35B-A3B-6bit`.
- The setup UI must show model source, approximate disk size, license, destination path, and a hardware/RAM warning before downloading.
- Downloads require an explicit user click. Large models are never fetched silently.
- The MLX backend should be isolated behind a helper process or local server boundary, not embedded directly into Swift UI code.

## API Keys & Secrets

- Claude API keys are stored only in the backend proxy environment/secrets store and are never shipped in the macOS app.
- The client stores only anonymous device IDs, user auth tokens, and subscription credentials in Keychain.
- Cloud action endpoints, request schemas, SSE events, auth headers, rate-limit behavior, error codes, and no-content-logging rules are defined in `docs/backend-api.md`.

## Open Questions (for Architect to resolve)

- [x] **Multi-display**: per-display overlay windows (one `NSWindow` per `NSScreen`).
- [ ] Content classifier: pure rule-based sufficient for v1, or integrate a CoreML model? (Recommend rule-based for v1; revisit with telemetry data.)
- [x] **History storage**: CoreData (with full-text-search via NSPredicate + tokenized text column).
- [x] **Result surface**: separate `NSPanel` with `.nonactivatingPanel` style mask. Normal post-capture results are positioned top-center as a notch-attached surface; recovery panels may still use centered or selection-near placement when that is clearer.
- [x] **Minimum macOS**: macOS 15.2+ for alpha and v1. No macOS 14/15.0 compatibility mode is planned.
- [x] **Distribution**: Direct (Developer ID + Sparkle). Drives non-sandboxed app, Sparkle updates, and Stripe + RevenueCat payments. The alpha hotkey uses Carbon `RegisterEventHotKey`; `CGEventTap` is deferred unless Carbon fails QA.
- [x] **Backend hosting**: Cloudflare Workers for the first Claude proxy. Revisit only if Worker limits or provider SDK constraints block streaming or auth requirements.

## Distribution & Sandbox Notes

This app is **not sandboxed**. That is a deliberate choice driven by:
- Direct distribution gives the app a simpler permission and release path for ScreenCaptureKit, future global-input fallbacks, Sparkle, and non-App-Store payments.
- ScreenCaptureKit on a sandboxed app needs a specific entitlement and degraded permission UX.
- Mac App Store rules conflict with several core requirements.

Trade-offs:
- We must self-distribute via signed/notarized DMG with Sparkle for updates.
- Payments handled by Stripe + RevenueCat (no StoreKit).
- First-launch Gatekeeper prompt is manageable with proper notarization and a clear install page.

The current signing and entitlement baseline is documented in `docs/release.md`.

## Cost Model (for Backend Sizing)

Rough per-user-per-day token usage on free tier (10 cloud actions):
- Translate (Haiku): avg 300 input + 200 output = 500 tokens × 6 = 3000
- Explain (Sonnet): avg 400 input + 400 output = 800 tokens × 4 = 3200

Per free user per month (Haiku $0.80/$4 per MTok, Sonnet $3/$15 per MTok, blended estimate):
- Haiku spend: ~$0.05
- Sonnet spend: ~$0.15
- **Total: ~$0.20/free user/month at the cap**

If 5% of free users hit the cap and the rest use a fraction, expected blended cost is ~$0.05/free user/month. Pro users ($8–12/mo) easily cover their own cost (estimated $0.50–$2/mo at heavy usage).
