# Implementation References

Last updated: 2026-04-29

Use this file when stories need platform/service-specific details. Prefer primary sources over blog posts.

## macOS Capture

- ScreenCaptureKit is the canonical framework for modern macOS screen capture.
- Current alpha code uses `SCScreenshotManager.captureImage(in:)`, which is simple for rectangle capture but requires macOS 15.2+.
- Product decision: alpha and v1 target macOS 15.2+. If the product later needs macOS 14/15.0 support, create a compatibility story using `SCContentFilter` and `SCStreamConfiguration.sourceRect`.

Primary references:

- Apple ScreenCaptureKit sample/docs: https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos
- Apple WWDC22 ScreenCaptureKit overview: https://developer.apple.com/videos/play/wwdc2022/10156/
- Apple WWDC23 ScreenCaptureKit screenshot capabilities: https://developer.apple.com/videos/play/wwdc2023/10136/

## OCR

- Use Vision `VNRecognizeTextRequest` for local OCR.
- Use accurate mode for normal captures unless performance requires a fast-mode option.
- Keep image data in memory by default.

Primary reference:

- Apple Vision text recognition API: https://developer.apple.com/documentation/vision/vnrecognizetextrequest

## Apple Foundation Models

- Use `FoundationModels.LanguageModelSession` for on-device text generation when Local Mode AI actions are enabled.
- Use `SystemLanguageModel.default.availability` before starting a local action so Pixel Pane can distinguish available, device-not-eligible, Apple Intelligence disabled, and model-not-ready states.
- Use `streamResponse(to:options:)` for partial result updates; the stream emits snapshots, not deltas, so UI state should replace the active response text with the latest snapshot content.
- Keep prompts concise. The current SDK exposes `SystemLanguageModel.contextSize` and token-count APIs on macOS 26.4, and Apple documents context-window errors through `LanguageModelSession.GenerationError.exceededContextWindowSize`.
- Do not call `logFeedbackAttachment` from normal app flows because it serializes session information intended for explicit Feedback Assistant reports.
- As of Xcode 26.4 / macOS SDK 26.4, the `FoundationModels` Swift interface exposes text prompts, guided generation, tools, streaming, availability, and token counting, but no `CGImage`, `NSImage`, image attachment, or other prompt image input surface. Treat true local image understanding as blocked until the product chooses a path.

Primary references:

- Apple Foundation Models framework: https://developer.apple.com/documentation/FoundationModels
- Apple `LanguageModelSession`: https://developer.apple.com/documentation/foundationmodels/languagemodelsession
- Apple `SystemLanguageModel`: https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel
- Apple `Prompt`: https://developer.apple.com/documentation/FoundationModels/Prompt
- Apple prompting guidance: https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model

## MLX Local Vision Runtime

- Use MLX/VLM as the optional local image-understanding runtime for Explain, Ask, and Debug when the user installs or selects a compatible local model.
- Current development-machine discovery:
  - `mlx_vlm.generate` exists at `/opt/homebrew/bin/mlx_vlm.generate`.
  - `mlx-run35` was not found on PATH during the 2026-04-29 check.
  - Hugging Face cache includes `mlx-community/Qwen3.6-35B-A3B-6bit`.
- Recommended default model for the setup flow:
  - `mlx-community/Qwen3.6-35B-A3B-6bit`
  - Hugging Face tags it as `Image-Text-to-Text`, `MLX`, `Safetensors`, `qwen3_5_moe`, and `6-bit`.
  - Model card usage shows `python -m mlx_vlm.generate --model mlx-community/Qwen3.6-35B-A3B-6bit --prompt "Describe this image." --image <path_to_image>`.
  - Approximate model size shown by Hugging Face: 29.1 GB.
- Setup should also detect already-downloaded compatible models under `~/.cache/huggingface/hub/models--*` and prefer an installed compatible model over downloading a new one.
- Never auto-download large models. Show source repo, approximate disk size, license, local storage path, and a cancellation path before starting.
- Prefer invoking a small helper process or local server boundary for MLX inference rather than embedding Python directly in Swift. The helper should accept an image path or temporary in-memory export, prompt text, selected model ID/path, token budget, and return streamed or chunked text. Temporary image files, if needed for MLX tooling, must be deleted after the request.

Primary references:

- MLX-VLM GitHub: https://github.com/Blaizzy/mlx-vlm
- Hugging Face MLX docs: https://huggingface.co/docs/hub/en/mlx
- Recommended model card: https://huggingface.co/mlx-community/Qwen3.6-35B-A3B-6bit

## Global Hotkey

- Product decision: alpha uses Carbon `RegisterEventHotKey` for the default `Command + Shift + Space` capture shortcut.
- The Carbon path should not require Accessibility permission for the default alpha shortcut.
- `CGEventTap` is deferred unless Carbon fails full-screen or foreground-app QA. If added later, treat Accessibility permission as required for the `CGEventTap` path.
- On macOS Sequoia, `RegisterEventHotKey` registrations using only Shift/Option are restricted; keep the default shortcut on Command + Shift + Space and reject unsupported combinations.

Primary references:

- Apple Developer Forums `RegisterEventHotKey` Sequoia modifier restriction: https://developer.apple.com/forums/thread/763878
- Apple `CGEvent.tapCreate`: https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)
- Apple `AXIsProcessTrustedWithOptions`: https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions

## Updates

- Direct distribution should use Developer ID signing, notarization, Sparkle, EdDSA update signing, and an appcast feed.
- Sparkle expects an appcast URL in app metadata and incrementing bundle versions.

Primary reference:

- Sparkle documentation: https://sparkle-project.org/documentation/

## Cloud AI Proxy

- The app must not ship Anthropic API keys.
- Backend should stream responses to the client using SSE or an equivalent streaming bridge.
- Anthropic Messages streaming uses server-sent events such as `message_start`, `content_block_delta`, `message_delta`, and `message_stop`.

Primary references:

- Anthropic streaming docs: https://platform.claude.com/docs/en/build-with-claude/streaming
- Cloudflare Workers streaming docs: https://developers.cloudflare.com/workers/runtime-apis/streams/

## Subscriptions

- RevenueCat should be entitlement-based.
- The app should check CustomerInfo entitlements to decide whether Pro/Student features are active.
- For Direct distribution, Stripe + RevenueCat is the current product direction; do not add StoreKit unless the distribution decision changes.

Primary references:

- RevenueCat docs: https://www.revenuecat.com/docs/
- RevenueCat SDK quickstart / entitlements: https://www.revenuecat.com/docs/getting-started/quickstart
