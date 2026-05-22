# Pixel Pane Story Backlog

Last updated: 2026-05-22 (ASSIST-007 through ASSIST-011 local chat speed stories added)

This is the story-level source of truth. Claude/Codex should use this file when you say:

- "Where am I?"
- "What should I do next?"
- "Complete STORY-ID"
- "Complete the next story in Epic N"

## Status Values

- `Not Started`
- `In Progress`
- `Blocked`
- `In Review`
- `Done`

## Current Execution Rule

When asked to complete an epic, do not attempt the whole epic in one pass. Complete the next incomplete story in that epic, update this backlog, update `workflow/status.md`, and report the next story.

## Current Recommended Story

`PRIV-004` - Ephemeral capture audit is the current recommended story.

Reason: The local Qwen prompt/speed slice is complete. The next privacy slice is verifying the ephemeral screenshot handling promise at the implementation and QA level.

---

## Epic 0 - Foundations

| ID | Story | Status | Depends On |
|---|---|---|---|
| `FOUND-001` | Decide minimum macOS and capture compatibility strategy | Done | User decision |
| `FOUND-002` | Finalize signing, entitlements, and Direct distribution baseline | Done | `FOUND-001` |
| `FOUND-003` | Define backend proxy API contract | Done | None |
| `FOUND-004` | Implement backend proxy MVP | Done | `FOUND-003` |
| `FOUND-005` | Add anonymous device identity and auth-token flow | Done | `FOUND-003` |
| `FOUND-006` | Add secret-management rules for app and backend | Done | `FOUND-003` |
| `FOUND-007` | Define Sparkle update/release process | Done | `FOUND-002` |
| `FOUND-008` | Decide telemetry vendor or defer telemetry | Blocked | Product decision before beta |
| `FOUND-009` | Add CI build verification | Done | Stable Xcode project |

### `FOUND-001` - Decide Minimum macOS And Capture Compatibility Strategy

Goal: Record that alpha/v1 targets macOS 15.2+ and does not include a macOS 14/15.0 compatibility path.

Acceptance:

- [x] Decision recorded in `workflow/decisions.md`.
- [x] `docs/prd.md`, `docs/architecture.md`, and `workflow/status.md` agree.
- [x] If supporting macOS earlier than 15.2, create a story for `SCContentFilter` + `SCStreamConfiguration` capture. Not applicable: alpha/v1 keep macOS 15.2+.

Notes:

- Current code uses `SCScreenshotManager.captureImage(in:)`, which is the cleanest rectangle capture path but requires macOS 15.2+.
- Decision: keep macOS 15.2+ for alpha and v1; no macOS 14/15.0 compatibility path is planned.

### `FOUND-002` - Finalize Signing, Entitlements, And Direct Distribution Baseline

Goal: Prepare the app for Developer ID distribution without blocking local development.

Acceptance:

- [x] App sandbox setting matches Direct distribution decision.
- [x] Hardened runtime remains enabled.
- [x] Entitlements are documented.
- [x] Manual release checklist exists for signed/notarized DMG.

Notes:

- Completed 2026-05-10. Confirmed the Pixel Pane target has `ENABLE_APP_SANDBOX = NO`, `ENABLE_HARDENED_RUNTIME = YES`, generated Info.plist metadata, `INFOPLIST_KEY_LSUIElement = YES`, bundle identifier `pane.PixelPane`, and no checked-in app entitlements file. The Debug app's generated signing entitlements include user-selected read-only file access and debug `get-task-allow`, but no App Sandbox entitlement. Added `docs/release.md` with the current signing/entitlement baseline and a manual Developer ID/notarized DMG release checklist. Debug build verification succeeded.

### `FOUND-003` - Define Backend Proxy API Contract

Goal: Make cloud calls implementable without shipping provider keys in the app.

Acceptance:

- [x] Document endpoints for translate, explain, simplify, ask, study, menu, debug.
- [x] Document request/response schemas.
- [x] Document SSE streaming format to the app.
- [x] Document auth header, rate-limit response, error codes, and retention policy.
- [x] Explicitly state that prompt content, screenshots, and OCR text are not logged by default.

Notes:

- Completed 2026-04-29. Added `docs/backend-api.md` with the `/v1` Cloudflare Workers proxy contract, normalized Pixel Pane SSE events, auth/rate-limit/error schemas, image-consent rules, and no-content-logging retention policy. Recorded the Cloudflare Workers hosting decision in `workflow/decisions.md` and linked the contract from `docs/architecture.md`.

### `FOUND-004` - Implement Backend Proxy MVP

Goal: Build the first deployable proxy for Claude calls.

Acceptance:

- [x] API key is server-side only.
- [x] Requests require an app auth token.
- [x] Responses stream to the client.
- [x] Daily free limit can be enforced per anonymous device ID.
- [x] Logs exclude prompt content by default.

Notes:

- Completed 2026-04-29. Added a Cloudflare Worker under `PixelPane/Backend` with TypeScript/Wrangler setup, HMAC bearer-token validation plus dev-token support, request/schema validation for the `/v1` action endpoints, KV-backed free daily quota enforcement, Anthropic Messages streaming, and normalized Pixel Pane SSE `meta`/`snapshot`/`done`/`error` events. Added backend README deployment notes and `.env.example`; provider keys remain Worker secrets only. On 2026-05-06, the user created production and preview Cloudflare KV namespaces and `wrangler.toml` was updated with their IDs, then set `ANTHROPIC_API_KEY` and `APP_AUTH_SECRET` as Worker secrets. After the user registered the account-level `workers.dev` subdomain, `npx wrangler deploy` published the Worker at `https://pixel-pane-api.snehithn5.workers.dev`. Smoke tests verified `/v1/auth/token` bearer-token issuance and `/v1/explain` Anthropic SSE streaming through the deployed Worker. App wiring for the `FOUND-005` client token flow was later added under `ACT-015`.

### `FOUND-005` - Add Anonymous Device Identity And Auth-Token Flow

Goal: Let free users start without account creation while enabling server-side rate limits.

Acceptance:

- [x] Anonymous device ID is generated once and stored in Keychain.
- [x] Client can request/refresh backend JWT.
- [x] Sign in with Apple is deferred until upgrade/account work.

Notes:

- Completed 2026-04-29. Added `CloudAuthTokenProvider` with Keychain-backed anonymous device ID and cached short-lived bearer token storage. Added `/v1/auth/token` to the Worker so anonymous device IDs can receive HMAC-signed Pixel Pane tokens for backend auth and quota. Updated `docs/backend-api.md` to document the token endpoint. Sign in with Apple remains deferred.

### `FOUND-006` - Add Secret-Management Rules For App And Backend

Goal: Prevent accidental leakage of Anthropic, Stripe, RevenueCat, or signing secrets.

Acceptance:

- [x] App stores only device/user/session tokens locally.
- [x] Provider API keys exist only in backend environment/secrets.
- [x] `.env*` is ignored except `.env.example`.
- [x] `workflow/decisions.md` records secret ownership.

Notes:

- Completed 2026-04-29. Added the "Secret Ownership For Cloud Backend" decision. App-side cloud auth stores only an anonymous device ID and short-lived Pixel Pane bearer token in Keychain. The Worker expects `ANTHROPIC_API_KEY` and `APP_AUTH_SECRET` as Cloudflare secrets. `.gitignore` excludes `.env`, `.env.*`, `node_modules/`, and `.wrangler/` while allowing checked-in `.env.example`.

### `FOUND-007` - Define Sparkle Update/Release Process

Goal: Make direct distribution update-ready.

Acceptance:

- [x] Sparkle appcast URL plan is documented.
- [x] EdDSA signing key handling is documented.
- [x] Release checklist includes archive, Developer ID signing, notarization, DMG, appcast generation.

Notes:

- Completed 2026-05-21. Updated `docs/release.md` with the planned production Sparkle appcast URL (`https://pixelpane.app/appcast.xml`), a temporary beta appcast option under the release-site host, release-channel guidance, Sparkle integration prerequisites, EdDSA private-key custody rules, and appcast-generation/verification steps in the Developer ID release checklist. Recorded the Sparkle release update process decision in `workflow/decisions.md`.

### `FOUND-008` - Decide Telemetry Vendor Or Defer Telemetry

Goal: Avoid vague analytics work.

Acceptance:

- [x] Decision recorded: PostHog, Plausible/custom, or defer.
- [ ] Event schema excludes screenshots, OCR text, prompts, and result text.
- [ ] Telemetry is opt-in.

Notes:

- User decision on 2026-05-18: defer telemetry for now. Telemetry is not a requirement for the app. Keep this story open/blocked as a visible beta-planning decision rather than implementing analytics during alpha distribution work.

### `FOUND-009` - Add CI Build Verification

Goal: Ensure future agents do not leave the project unbuildable.

Acceptance:

- [x] CI or local script runs the Debug build command.
- [x] Documentation explains how to run the same check locally.

Notes:

- Completed 2026-05-21. Added `PixelPane/Scripts/verify-debug-build.sh`, an executable local verification wrapper around the Debug `xcodebuild` command. Documented the wrapper in `workflow/README.md`. Running the wrapper succeeded.

---

## Epic 1 - Core Capture Loop

| ID | Story | Status | Depends On |
|---|---|---|---|
| `CORE-001` | Menu-bar app shell | Done | None |
| `CORE-002` | Overlay and region selection | Done | `CORE-001` |
| `CORE-003` | Selected-region screen capture | Done | `CORE-002`, `FOUND-001` |
| `CORE-004` | Local Vision OCR pipeline | Done | `CORE-003` |
| `CORE-005` | Floating result panel with copy | Done | `CORE-004` |
| `CORE-006` | Permission detection and recovery UX | Done | `CORE-003` |
| `CORE-007` | Global hotkey activation | Done | `CORE-006` |
| `CORE-008` | Language detection and result metadata | Done | `CORE-004` |
| `CORE-009` | Panel placement and keyboard behavior hardening | Done | `CORE-005` |
| `CORE-010` | Multi-display QA and capture-loop smoke checklist | Done | `CORE-001`-`CORE-009` |
| `CORE-011` | Fix selected-region capture coordinate alignment | Done | `CORE-003` |

### `CORE-001` - Menu-Bar App Shell

Goal: Pixel Pane runs as a menu-bar utility with no Dock icon.

Acceptance:

- [ ] `LSUIElement` is enabled.
- [ ] Menu bar item exposes Capture, Settings, Show Last Result when available, and Quit.
- [ ] App builds successfully.
- [ ] Manual QA confirms no Dock icon.

Current state: implemented, needs manual QA.

### `CORE-002` - Overlay And Region Selection

Goal: Show a dimmed overlay on all displays and let the user drag-select a region.

Acceptance:

- [ ] One overlay window per `NSScreen`.
- [ ] Selection rectangle follows drag accurately.
- [ ] Escape/cancel closes all overlay windows.
- [ ] Small selections are rejected with clear feedback.
- [ ] No files are written during cancel.

Current state: implemented, but small-selection feedback and manual multi-display QA remain.

### `CORE-003` - Selected-Region Screen Capture

Goal: Capture the selected rectangle as an in-memory `CGImage`.

Acceptance:

- [ ] Uses ScreenCaptureKit.
- [ ] Captures only selected rect.
- [ ] Keeps capture in memory in the normal flow.
- [ ] Reports missing permission clearly.
- [ ] App builds successfully.

Current state: implemented using `SCScreenshotManager.captureImage(in:)`; permission UX added in `CORE-006`, but real capture QA remains.

### `CORE-004` - Local Vision OCR Pipeline

Goal: Convert captured image to ordered text locally.

Acceptance:

- [ ] Uses `VNRecognizeTextRequest`.
- [ ] Uses accurate recognition for normal captures.
- [ ] Returns ordered line text.
- [ ] Empty OCR is handled without crashing.
- [ ] Processing does not block the UI.

Current state: implemented, needs real capture testing and possible sorting/bounding boxes later.

### `CORE-005` - Floating Result Panel With Copy

Goal: Show OCR output near the selection without turning the app into a full chat window.

Acceptance:

- [ ] Panel appears near selected region.
- [ ] Panel stays visible across spaces where appropriate.
- [ ] Result text is selectable.
- [ ] Copy button copies result text.
- [ ] Panel can be closed.

Current state: implemented, needs placement and keyboard hardening.

### `CORE-006` - Permission Detection And Recovery UX

Goal: Give clear recovery when screen capture permission or global hotkey registration blocks capture.

Acceptance:

- [x] Detect Screen Recording permission failure.
- [x] Document that Accessibility permission is not required for the alpha Carbon hotkey path; only check/prompt for Accessibility if a future `CGEventTap` path is enabled.
- [x] Settings includes Screen Recording and hotkey registration status.
- [x] Error UI has a button/deep link guidance to System Settings.
- [x] Denied permissions or failed hotkey registration do not crash capture flow.

Current state: implemented, builds successfully, needs manual permission-denied QA on a fresh or reset Screen Recording permission state.

### `CORE-007` - Global Hotkey Activation

Goal: Start capture from outside the app with the configured shortcut.

Acceptance:

- [x] Uses Carbon `RegisterEventHotKey` for the alpha implementation.
- [x] Default shortcut is Command + Shift + Space unless it conflicts.
- [x] Hotkey works while another app is active. (Implementation registers globally via Carbon; manual QA against full-screen/foreground apps still needed.)
- [x] Hotkey can be paused from menu bar.
- [x] Hotkey registration failure/conflict is handled with clear recovery.
- [x] Shortcut implementation is documented in `workflow/decisions.md`.

Notes:

- Decision: use Carbon `RegisterEventHotKey` for alpha. `CGEventTap` is deferred unless Carbon fails full-screen or foreground-app QA.
- The default Command + Shift + Space includes Command, avoiding macOS Sequoia restrictions on Shift/Option-only hotkey registrations.
- `HotkeyManager` keeps the Carbon code behind an abstraction so a future `CGEventTap` swap touches only one file.
- Pause/resume preserves OS-level registration; only the Swift handler short-circuits when paused, so resume is instant.

### `CORE-008` - Language Detection And Result Metadata

Goal: Detect source language and show useful capture metadata.

Acceptance:

- [x] Uses NaturalLanguage framework after OCR.
- [x] Stores detected language on capture result.
- [x] Result panel shows source type and language.
- [x] Low confidence displays Unknown/manual fallback.

Notes:

- `LanguageDetector` uses `NLLanguageRecognizer` and a 0.5 confidence floor; below the floor, `DetectedLanguage.unknown` is stored and the panel renders an "Unknown" pill.
- `CaptureSourceType` is currently a single-case enum (`.ocr`); future PDF/manual-paste sources should add cases here rather than overloading the existing one.

### `CORE-009` - Panel Placement And Keyboard Behavior Hardening

Goal: Make the result panel feel native and predictable.

Acceptance:

- [x] Placement tries right, below, left, above, then center.
- [x] Panel stays within visible screen frame.
- [x] Escape closes panel.
- [x] Command-C copies result when panel is focused.
- [x] Command-W closes panel.

Notes:

- Center fallback is now clamped into the screen's visible frame so the panel never lands off-screen on small displays.
- Shortcuts are bound on SwiftUI buttons; Cmd-W uses a zero-size hidden button so it can coexist with the visible Close button bound to Escape.

### `CORE-010` - Multi-Display QA And Capture-Loop Smoke Checklist

Goal: Finish Epic 1 with repeatable manual verification.

Acceptance:

- [ ] `workflow/qa-checklist.md` has a Core Capture Loop section with checked/unchecked results.
- [ ] Primary display capture passes.
- [ ] Secondary display capture passes.
- [ ] Full-screen app capture behavior is tested.
- [ ] Known issues are written in `workflow/status.md`.

### `CORE-011` - Fix Selected-Region Capture Coordinate Alignment

Auto-created during user-reported capture regression on 2026-04-29.

Goal: Ensure the OCR image matches the visible highlighted selection, including captures over Xcode windows and Retina/scaled displays.

Acceptance:

- [x] Keep AppKit selection coordinates for panel placement.
- [x] Send ScreenCaptureKit a separate upper-left-origin capture rectangle.
- [x] Preserve selected-region capture in memory.
- [x] App builds successfully.

Notes:

- `CaptureSelection` now carries both `screenRect` for UI placement and `captureRect` for `SCScreenshotManager.captureImage(in:)`.
- The noisy console lines mentioning Apple Intelligence and task-name port rights appear to be system/Xcode logging around capture/debugging, not application-level OCR parsing. Re-test Xcode captures with the rebuilt app to confirm the coordinate fix resolves the visible mismatch.

---

## Epic 2 - Action Rail And Result Formats

| ID | Story | Status | Depends On |
|---|---|---|---|
| `ACT-001` | Action rail UI and action state model | Done | `CORE-005` |
| `ACT-002` | Extract Text action | Done | `ACT-001` |
| `ACT-011` | Hybrid local action backend protocol | Done | `CORE-005` |
| `ACT-012` | MLX local vision model discovery and setup | Done | `ACT-011` |
| `ACT-013` | MLX vision backend adapter | Done | `ACT-011`, `ACT-012` |
| `ACT-003` | Cloud API client shell with streaming support | Done | `FOUND-003`, `ACT-011` |
| `ACT-004` | Translate action with local/cloud routing | Done | `ACT-001`, `ACT-011` |
| `ACT-005` | Explain action | Done | `ACT-001`, `ACT-011`, `ACT-013` for image context |
| `ACT-006` | Simplify action | Done | `ACT-001`, `ACT-011` |
| `ACT-007` | Ask follow-up conversation | Done | `ACT-001`, `ACT-011`, `ACT-013` for first-turn image context |
| `ACT-008` | Contextual Debug action | Done | `ACT-001`, `ACT-011`, `ACT-013` for image context |
| `ACT-009` | Copy/export result controls | Done | `ACT-001` |
| `ACT-010` | Error and empty states | Done | `ACT-001`, `ACT-011` |
| `ACT-014` | Smart default action selection | Done | `ACT-001`, `ACT-004`, `ACT-005`, `ACT-006`, `ACT-008` |
| `ACT-015` | Enable Cloud Mode app wiring | Done | `ACT-003`, `PRIV-005`, `FOUND-004`, `FOUND-005` |

### `ACT-001` - Action Rail UI And Action State Model

Goal: Add a compact action rail to the result panel.

Acceptance:

- [x] Actions are represented by a typed enum/model.
- [x] UI shows Extract, Translate, Explain, Simplify, Ask.
- [x] Disabled actions explain why.
- [x] Selection state and loading state are visible.

Notes:

- Completed 2026-04-29. Added `PanelActionKind` / `PanelActionState` and an action rail in the result panel. Extract is selected by default; future AI actions are visible but disabled with hover help until their implementation stories wire behavior.
- Updated 2026-04-29 after visual QA. The result panel now uses a material background and compact custom action/control buttons instead of oversized default bordered controls.

### `ACT-002` - Extract Text Action

Goal: Make OCR text extraction a polished local action.

Acceptance:

- [x] Uses OCR output only.
- [x] Never calls network.
- [x] Preserves line breaks.
- [x] One-click copy works.

Notes:

- Completed 2026-04-29. Added `ExtractTextAction` as a local-only pass-through over the OCR result. The panel now stores active action text and copies that active output, preserving OCR line breaks.

### `ACT-003` - Cloud API Client Shell With Streaming Support

Goal: Add the cloud-upgrade backend for AI actions when the user has opted into Cloud Mode (`PRIV-005`).

Acceptance:

- [x] Conforms to the shared backend protocol defined by `ACT-011` so action code can swap local <-> cloud at runtime.
- [x] Only invoked when Cloud Mode is on; default Local Mode never instantiates this client.
- [x] Supports streaming text updates.
- [x] Does not store provider API keys.
- [x] Handles auth, rate-limit, and network errors; on failure surfaces a "Cloud unreachable" state and lets `ACT-010` route the action back to the local backend.

Notes:

- Completed 2026-04-29. Added `CloudAIBackend` under `PixelPane/PixelPane/API`, conforming to `AIBackend` and the `docs/backend-api.md` `/v1` contract. It builds request envelopes, requires Cloud Mode configuration before use, rejects image payloads without explicit consent, reads Pixel Pane SSE `snapshot`/`done`/`error` events, maps 429/network/auth/cloud-disabled failures into structured errors, and keeps provider keys out of the app. `ACT-015` later instantiated it from the result panel routing path.

### `ACT-004` - Translate Action With Local/Cloud Routing

Goal: Translate captured text to the default target language, local-first.

Acceptance:

- [x] Uses detected source language from `CORE-008` when available.
- [x] Default path: local Apple model through the shared local backend from `ACT-011`.
- [x] Apple Translation framework path removed after user QA showed it stalls on unavailable language assets.
- [x] Cloud routing is deferred until `ACT-003` and `PRIV-005`; Local Mode never invokes cloud in the current alpha.
- [x] Shows source and target languages plus which backend produced the translation (Local Apple Model, MLX Vision, or Cloud when later enabled).

Notes:

- Completed 2026-04-29. Translate is enabled from the result-panel action rail and routes directly through the shared local backend. It explicitly targets English until a target-language setting exists. Apple Translation was removed from the app path after user QA showed it could stall instead of producing a result.

### `ACT-005` - Explain Action

Goal: Explain captured content in plain English, using both OCR text and the captured image so diagrams, charts, and visual layout are interpreted alongside the text.

Acceptance:

- [x] Default backend is the local backend from `ACT-011`; it sends OCR text to Apple Foundation Models when text-only mode is active, or OCR text plus captured image to MLX after `ACT-012`/`ACT-013` setup passes.
- [x] Cloud routing is deferred until `ACT-003` and `PRIV-005`; Local Mode never invokes cloud in the current alpha.
- [x] Output is concise and context-aware; references visual content when image input is available (e.g., "the diagram shows…").
- [x] Follow-up input is deferred to `ACT-007`; the explanation output remains the active panel result for the future Ask flow.

Notes:

- Completed 2026-04-29. Explain is enabled from the action rail and uses MLX Vision only when Settings reports image-aware local AI ready; otherwise it runs a text-only local explanation.

### `ACT-006` - Simplify Action

Goal: Rewrite dense text into simpler language.

Acceptance:

- [x] Default backend is the local client from `ACT-011`.
- [x] Cloud routing is deferred until `ACT-003` and `PRIV-005`; Local Mode never invokes cloud in the current alpha.
- [x] Output is shorter than input when practical.
- [x] Preserves core meaning.

Notes:

- Completed 2026-04-29. Simplify is enabled from the action rail and streams through the shared local backend with a bounded rewrite prompt.

### `ACT-007` - Ask Follow-Up Conversation

Goal: Let users ask follow-up questions about a capture.

Acceptance:

- [x] Default backend is the local client from `ACT-011`; first turn may include the captured image through MLX after `ACT-012`/`ACT-013` setup passes.
- [x] Cloud Mode (per `PRIV-005`) routes to the backend proxy; sending the image to the cloud still requires the per-action opt-in. Deferred until `ACT-003`/`PRIV-005`; current alpha never invokes cloud.
- [x] Subsequent turns never resend image data regardless of backend, to keep token cost and latency bounded.
- [x] Conversation is cleared when panel closes.

Notes:

- Completed 2026-04-29. Ask is enabled in the action rail with an inline question field and local streaming transcript. The first turn includes the captured image only when MLX Vision is ready; subsequent turns always send OCR text plus prior transcript only. Closing the panel discards the SwiftUI conversation state.
- Updated 2026-04-29 after user feedback. Removed the fixed five-question cap and changed the Ask empty-state copy to allow unlimited follow-up questions for a capture.

### `ACT-008` - Contextual Debug Action

Goal: Show Debug only when capture looks technical, and use the captured image alongside OCR text so terminal screenshots, IDE error overlays, and stack-trace UI are interpreted with their visual context.

Acceptance:

- [x] Rule-based classifier detects code/log/error patterns.
- [x] Debug appears only above a documented confidence threshold.
- [x] Default backend is the local client from `ACT-011`; it receives OCR text plus captured image through MLX after `ACT-012`/`ACT-013` setup passes.
- [x] When Cloud Mode is on, routes to the backend proxy; sending the captured image to the cloud requires the per-action image opt-in defined in `PRIV-005`. If the user has not granted that opt-in, the cloud call sends OCR text only. Deferred until `ACT-003`/`PRIV-005`; current alpha never invokes cloud.
- [x] Debug output explains likely issue and next steps; references visual content when image input is available (e.g., "the highlighted line in the screenshot…").

Notes:

- Completed 2026-04-29. Added `TechnicalContentClassifier` with documented threshold `0.8`, stored classification on `CaptureResult`, and only shows the Debug rail item when that threshold is met. Debug routes through the shared local backend and includes image input only when MLX Vision is ready; otherwise it uses OCR text only.

### `ACT-009` - Copy/Export Result Controls

Goal: Let users reuse results outside Pixel Pane.

Acceptance:

- [x] Copy copies active result.
- [x] Export saves plain text to user-selected location or Downloads.
- [x] Confirmation appears after copy/export.

Notes:

- Completed 2026-04-29. Copy now confirms the active result was copied, and Export saves the active result as a plain-text file via `NSSavePanel`.

### `ACT-010` - Error And Empty States

Goal: Make failure states actionable and non-destructive.

Acceptance:

- [x] No-text OCR has Try Again.
- [x] Local model unavailable (Apple Intelligence not enabled, Apple model still downloading, MLX runtime missing, MLX model missing/installing, model too large, or hardware unsupported) shows a recovery panel with the right setup/recovery action.
- [x] Cloud Mode network failure silently falls back to the local backend with a "Cloud unreachable, used local" inline note; no destructive retries. Deferred until `ACT-003`/`PRIV-005` because Cloud Mode does not exist yet.
- [x] Cloud rate limit (only when Cloud Mode is on) shows an upgrade path and a one-tap "Run locally instead" affordance. Deferred until `ACT-003`/monetization because cloud limits do not exist yet.
- [x] Missing local translation pack handling removed because the Apple Translation framework path was removed.

Notes:

- Updated 2026-04-29 to match the local-first AI default decision: network failures and rate limits are no longer hard errors because the local backend is always available.
- Completed 2026-04-29. Empty OCR results now preserve the capture and show a Try Again recovery control. Local AI failures are mapped into inline recovery panels with retry, Apple Intelligence Settings, or Pixel Pane Settings actions depending on the unavailable reason. Cloud-only criteria are explicitly deferred until the cloud client and Cloud Mode stories are implemented.

### `ACT-014` - Smart Default Action Selection

Auto-created during user-requested smart default action work on 2026-04-29.

Goal: Pick and immediately start the most useful default action after capture without adding meaningful latency.

Acceptance:

- [x] Uses already-available OCR text, language detection, and technical classification only; no model call is required to choose the default.
- [x] Falls back to Extract when OCR is empty or confidence is low.
- [x] Defaults technical captures to Debug, non-English captures to Translate, dense text to Simplify, and explanation-like text to Explain.
- [x] Selector is rule/candidate based so future built-in or user-created actions can add their own fast scoring rule.
- [x] App builds successfully.

Notes:

- Completed 2026-04-29. Added `SmartDefaultActionSelector`, a rule-based scorer that runs synchronously before the result panel appears. The result panel now initializes on the selected action and starts it on appear when the selected default is not Extract. Background Explain prewarm now stays off when another smart default action is active, keeping initial work focused on the chosen action.
- Updated 2026-05-06 after user feedback: removed all background tab precomputation. The panel now starts only the smart default action chosen from capture signals, or the tab the user explicitly selects.

### `ACT-015` - Enable Cloud Mode App Wiring

Auto-created during Cloud Mode planning on 2026-05-06.

Goal: Enable real opted-in Cloud Mode actions now that the Worker backend, app auth token flow, and guarded settings UI exist.

Acceptance:

- [x] Instantiate `CloudAIBackend` against `https://pixel-pane-api.snehithn5.workers.dev` through the shared `AIBackend` routing path.
- [x] Use `CloudAuthTokenProvider` to request, cache, and refresh Pixel Pane bearer tokens before cloud action calls.
- [x] Enable `AIRoutingSettings.cloudBackendAvailable` only when the app is configured with the deployed backend endpoint.
- [x] Settings lets the user opt into Cloud Mode with a single toggle; Cloud Mode covers OCR text and captured image context for cloud-capable actions.
- [x] Local Mode remains the default and never invokes cloud.
- [x] Translate, Explain, Simplify, Ask, and Debug route to cloud only when Cloud Mode is enabled; image payloads are sent only while Cloud Mode is enabled.
- [x] Cloud network/auth/rate-limit failures surface actionable recovery without losing the active panel state. Cloud Mode no longer performs automatic local fallback.
- [x] Result panel labels cloud output with a clear Cloud backend badge and quota metadata when returned by the backend.
- [x] App builds successfully.
- [x] Manual QA verifies at least one text-only cloud action and one image-consent-disabled cloud action against the deployed Worker.

Notes:

- The deployed backend is `https://pixel-pane-api.snehithn5.workers.dev`.
- The Worker already verified `/v1/auth/token` and `/v1/explain` via smoke tests on 2026-05-06.
- Do not send captured images to the cloud unless the user has explicitly enabled Cloud Mode.
- Local-first behavior must remain the default when Cloud Mode is off.
- Implemented 2026-05-06. Added a deployed Worker base URL, enabled Cloud Mode settings, instantiated `CloudAIBackend` in the result panel with `CloudAuthTokenProvider`, added structured cloud request metadata so the proxy receives clean OCR/question/conversation fields, routed actions through cloud only when Cloud Mode is enabled, gated image upload behind Cloud Mode, surfaced cloud model/quota metadata, and surfaced cloud failures in-panel. Build succeeded; manual UI QA remains.
- Updated 2026-05-06 after manual QA: collapsed Cloud Mode settings into a single "Use Cloud Mode" toggle per product decision. Cloud Mode now enables OCR and image context together for cloud-capable actions, while Local Mode remains the default. Removed automatic local fallback while Cloud Mode is on so cloud failures stay visible and the action remains labeled as Pixel Pane Cloud.
- Updated 2026-05-06 after Cloud Mode QA: direct curl confirmed the deployed Worker emits a terminal `done` event for `/v1/simplify`. Fixed the app-side SSE parser to flush a pending final event at EOF so `done` is not dropped and misreported as "Cloud stream ended before completion."
- Updated 2026-05-06 after Cloud Mode QA: fixed cloud output getting stuck on loading placeholders by bypassing the local prompt-echo suppression filter for cloud snapshots and accepting whitespace-only SSE delimiter lines.
- Updated 2026-05-06 after Cloud Mode QA: guarded against cloud streams that complete without any displayable text. The cloud backend now raises an empty-response error when `done` arrives before a non-empty snapshot, and the result panel replaces stale "Explaining..."/"Simplifying" placeholders with the Retry Cloud recovery card. Direct curl smoke tests verified deployed text-only Explain and normal-sized image Explain both stream `meta`/`snapshot`/`done`.
- Updated 2026-05-06 after Cloud Mode QA: raised the deployed Worker alpha quota from 10 to 100 cloud actions per anonymous device per UTC day and replaced the invalid cloud recovery SF Symbol `cloud.slash` with `cloud`. Deployed Worker version `04020fda-06ae-40af-81b0-e28d45db4f77`; curl smoke test confirmed `/v1/simplify` returns `remaining_cloud_actions: 94` and streams successfully.
- Updated 2026-05-06 after Cloud Mode QA: fixed a Worker upstream SSE parsing gap that could emit Pixel Pane `done` with no snapshots. The Worker now handles LF and CRLF Anthropic event delimiters, parses CRLF data lines, and flushes the final buffered event before closing. Deployed Worker version `17abf03e-904e-49d6-8b12-64d93c0319b6`; curl smoke tests confirmed deployed `/v1/simplify` and `/v1/explain` stream `meta`/`snapshot`/`done`.
- Updated 2026-05-10 after Cloud Mode QA screenshot: fixed empty-OCR captures disabling the full action rail. Extract stays available for the empty OCR recovery state, while image-capable actions can run when a real image backend path exists, such as Cloud Mode with image consent or Local Mode with MLX Vision ready. Build succeeded; manual QA should confirm an empty-text screenshot can still run an image-aware cloud action when image consent is enabled.
- Updated 2026-05-10 after follow-up QA screenshot: empty-OCR captures now default to Explain when an image-aware route exists, and Cloud Mode image upload/routing follows the single visible "Use Cloud Mode" setting instead of the legacy hidden image-consent flag. Build succeeded and the rebuilt Debug app was launched.
- Completed 2026-05-10 after user manual QA confirmed Cloud Mode works for text captures, image-only/no-text captures, and Ask on image-only captures.

### `ACT-011` - Hybrid Local Action Backend Protocol

Goal: Define the shared local AI interface used by every action so Local Mode can route text-only work to Apple Foundation Models and image-aware work to an installed MLX vision backend.

Acceptance:

- [x] Define a backend-agnostic local protocol for text prompts, optional captured image input, streaming updates, cancellation, and structured errors.
- [x] Add an Apple Foundation Models implementation for text-only prompts using `FoundationModels.LanguageModelSession` where available.
- [x] Add capability reporting: text-only local available, image-aware local unavailable, image-aware local available through MLX, model installing, model missing, hardware unsupported.
- [x] Streams partial responses to the result panel using the same interface the future cloud client will expose, so action stories can be backend-agnostic.
- [x] Detects Apple model unavailability (Apple Intelligence not enabled, model not downloaded, hardware unsupported) and MLX model unavailability (missing runtime, missing model, failed smoke test) without crashing.
- [x] Bounded prompt/response sizes documented so action stories can budget tokens.
- [x] No prompt content, screenshots, OCR text, or model outputs are logged by default.

Notes:

- Decision: 2026-04-29 - Local-First AI Default. Local is the unconditional default; Cloud Mode is the opt-in upgrade.
- Decision: 2026-04-29 - Local Vision Runtime Via MLX. Image-aware Local Mode should use an optional installed MLX/VLM model rather than waiting for Apple image prompt input.
- Sequencing: ship before any cloud action so we never have a state where AI features only work online.
- Image context to local is allowed by default since nothing leaves the device; cloud image context still needs the per-action opt-in defined in `ACT-007`.
- Apple Foundation Models remains text-only for Pixel Pane until Apple exposes image prompt input.
- MLX image input is only available after `ACT-012` setup and `ACT-013` adapter are complete.
- Completed 2026-04-29. Added `AIBackend`, `HybridLocalAIBackend`, `AppleFoundationModelsBackend`, MLX availability detection, Settings status display, and bounded local prompt/output limits.

### `ACT-012` - MLX Local Vision Model Discovery And Setup

Goal: Add a setup flow that helps users install or select a compatible local MLX vision model for image-aware actions.

Acceptance:

- [x] Detect whether `mlx_vlm.generate` or the supported MLX helper runtime exists.
- [x] Discover already-downloaded Hugging Face models under `~/.cache/huggingface/hub/models--*`.
- [x] Prefer installed compatible vision models, including `mlx-community/Qwen3.6-35B-A3B-6bit` when present.
- [x] If no compatible model is installed, recommend `mlx-community/Qwen3.6-35B-A3B-6bit` as the default local vision model for now.
- [x] Show source repo, approximate disk size, license, destination path, and hardware/RAM warning before download.
- [x] Download only after explicit user action; never auto-download large models.
- [x] Run a smoke test after setup and store model path/status in app settings.
- [x] If the model cannot run, show recovery steps and keep image-aware local actions disabled.

Notes:

- Current machine check on 2026-04-29 found `mlx_vlm.generate` at `/opt/homebrew/bin/mlx_vlm.generate`, did not find `mlx-run35` on PATH, and found `mlx-community/Qwen3.6-35B-A3B-6bit` in Hugging Face cache.
- See `workflow/references.md` for the current recommended model and MLX references.
- Completed 2026-04-29. Settings now shows MLX runtime status, compatible cached models, recommended model metadata, explicit install command copying, model page opening, and a user-triggered setup check that persists the selected model path/status.
- Updated 2026-04-29 after user feedback. Settings now has a simpler Local AI section and supports choosing any local MLX vision model folder, including a Hugging Face cache root, snapshot folder, or direct model directory with config and weights.
- Updated 2026-04-29 after setup bug report. Validation now rejects text-only MLX models by requiring vision/VLM metadata before marking image-aware Local AI ready.
- Updated 2026-04-29 after model-list feedback. Downloaded text-only MLX models remain visible in Settings and are labeled incompatible instead of being filtered out.

### `ACT-013` - MLX Vision Backend Adapter

Goal: Let Explain, Ask, and Debug use the captured image locally through the selected MLX vision model.

Acceptance:

- [x] Implement an `MLXVisionBackend` conforming to the protocol from `ACT-011`.
- [x] Sends prompt text plus captured image to the selected MLX model.
- [x] Uses a helper process or local server boundary rather than embedding Python directly in Swift.
- [x] Supports cancellation and bounded generation.
- [x] Streams or chunks partial result text back to the panel.
- [x] Deletes temporary image files after inference if the MLX tool requires file paths.
- [x] Distinguishes runtime missing, model missing, model too large, timeout, and generation failure.
- [x] Does not log prompt content, screenshots, OCR text, or model outputs by default.

Notes:

- Completed 2026-04-29. `MLXVisionBackend` invokes `mlx_vlm.generate` as a helper process using the selected model snapshot, writes captured images to a temporary PNG only for inference, streams stdout snapshots, handles cancellation/timeout, and deletes the temporary file.

---

## Epic 3 - Privacy And Onboarding

| ID | Story | Status | Depends On |
|---|---|---|---|
| `PRIV-001` | First-run onboarding | Done | `CORE-001` |
| `PRIV-002` | Screen Recording permission guidance | Done | `CORE-003` |
| `PRIV-003` | Accessibility permission guidance for future event tap path | Not Started | Future `CGEventTap` decision |
| `PRIV-004` | Ephemeral capture audit | Not Started | `CORE-003` |
| `PRIV-005` | Local/cloud mode setting and enforcement | Done | `ACT-001` |
| `PRIV-006` | Result source transparency | Not Started | `CORE-008` |
| `PRIV-007` | Settings structure | Not Started | `CORE-001` |
| `PRIV-008` | First-capture tutorial | Not Started | `CORE-002` |
| `PRIV-009` | Remove or formalize onboarding QA reset | Not Started | Beta readiness |

### `PRIV-001` - First-Run Onboarding

Goal: Explain screen access before macOS prompts appear.

Acceptance:

- [x] Shown once on first launch.
- [x] Explains selected-region capture.
- [x] Explains no continuous recording.
- [x] Explains in-memory capture handling.

Notes:

- Completed 2026-05-21. Added a first-run onboarding window shown before the default assistant surface when `PrivacyOnboarding.Completed` is unset. It explains selected-region capture, no continuous recording, and ephemeral in-memory screenshot handling. Continue marks onboarding complete and opens the assistant; Start First Capture marks onboarding complete and starts the capture flow. Local verification wrapper build succeeded.
- Follow-up 2026-05-22. Increased the onboarding window/content minimum height so the bottom action buttons do not clip or overflow. Local verification wrapper build succeeded.
- Follow-up 2026-05-22. Added a temporary Settings -> Permissions -> Onboarding QA control to show the first-run onboarding again during local testing. Tracked removal/formalization in `PRIV-009`.

### `PRIV-002` - Screen Recording Permission Guidance

Goal: Make Screen Recording permission failures recoverable.

Acceptance:

- [x] App detects capture permission failures.
- [x] UI explains the exact permission needed.
- [x] User can open System Settings or gets precise manual steps.

Notes:

- Completed 2026-05-22. Capture denial already flows through `CaptureError.screenRecordingPermissionDenied`; this story hardened the user-facing recovery. Settings and the recovery panel now explain the exact macOS permission, show manual steps for System Settings -> Privacy & Security -> Screen & System Audio Recording, and remind users to quit/reopen Pixel Pane if macOS asks. Opening settings refreshes permission state. Local verification wrapper build succeeded.

### `PRIV-003` - Accessibility Permission Guidance For Future Event Tap Path

Goal: Support Accessibility recovery if a future `CGEventTap` implementation is added.

Acceptance:

- [ ] App checks whether Accessibility trust is granted only when an event tap path is enabled.
- [ ] App can request/prompt using the appropriate API if `CGEventTap` is used.
- [ ] User gets clear recovery if denied.

### `PRIV-004` - Ephemeral Capture Audit

Goal: Verify privacy promise at implementation level.

Acceptance:

- [ ] Normal capture path writes no screenshots to disk.
- [ ] Capture reference is released when panel closes.
- [ ] Any retained image is in-memory only.
- [ ] QA checklist includes file-system spot check.

### `PRIV-005` - Local/Cloud Mode Setting And Enforcement

Goal: Make data routing explicit. Local is the default; cloud is opt-in.

Acceptance:

- [x] Default state: Local Mode (no cloud calls of any kind).
- [x] Settings exposes a "Use Cloud Models" opt-in. The control is disabled until `FOUND-004` and `FOUND-005` make the backend and app auth available, so toggling cannot accidentally invoke cloud during alpha.
- [x] The result panel labels current routing with a Local Mode badge. Per-action cloud-send labels become relevant when the backend is enabled.
- [x] Sending the captured image to the cloud requires a separate opt-in setting on top of Cloud Mode. The image setting is also disabled until cloud is available.
- [x] With cloud unavailable or disabled, action routing remains local and existing panels keep their current local result state.

Notes:

- Completed 2026-04-29 as a guarded Cloud Mode placeholder. Added `AIRoutingSettings`, persisted routing preferences in `AppState`, surfaced disabled Cloud Mode and image-consent controls in Settings, and labeled result panels with the active Local Mode routing badge. `ACT-015` later enabled the deployed cloud path.

### `PRIV-006` - Result Source Transparency

Goal: Help users judge reliability.

Acceptance:

- [ ] Panel shows OCR/source type.
- [ ] Panel shows detected language.
- [ ] Ambiguity/cultural-specific badges can be added later without redesign.

### `PRIV-007` - Settings Structure

Goal: Build a settings window that can grow without becoming cluttered.

Acceptance:

- [ ] General tab exists.
- [ ] Privacy tab exists.
- [ ] Account tab can be empty/placeholder until monetization.
- [ ] About tab includes version and docs links.

### `PRIV-008` - First-Capture Tutorial

Goal: Get new users to a successful first capture.

Acceptance:

- [ ] Overlay has first-use tip.
- [ ] Tutorial state is separate from onboarding state.
- [ ] Tutorial does not repeat after success.

### `PRIV-009` - Remove Or Formalize Onboarding QA Reset

Auto-created during `PRIV-001` follow-up on 2026-05-22.

Goal: Do not ship a rough QA-only onboarding reset control by accident.

Acceptance:

- [ ] Decide whether the onboarding reset belongs in production Settings or should be debug-only.
- [ ] If production-facing, move it into the final Privacy/About settings structure with user-facing copy.
- [ ] If debug-only, hide it from release builds or remove it before beta.
- [ ] Update `workflow/status.md` with the final decision.

---

## Epic 4 - Content-Aware Expansion

| ID | Story | Status | Depends On |
|---|---|---|---|
| `EXP-001` | Rule-based content classifier | Not Started | `ACT-002` |
| `EXP-002` | Mode override UI | Not Started | `EXP-001` |
| `EXP-003` | Message mode | Not Started | `ACT-004`, `EXP-001` |
| `EXP-004` | Study mode | Not Started | `ACT-005`, `EXP-001` |
| `EXP-005` | Menu mode | Not Started | `ACT-004`, `EXP-001` |
| `EXP-006` | Technical mode integration | Not Started | `ACT-008`, `EXP-001` |
| `EXP-007` | Local glossary storage | Not Started | `PRIV-007` |
| `EXP-008` | Glossary prompt injection | Not Started | `EXP-007`, `ACT-003` |
| `EXP-009` | Page-by-page PDF import | Not Started | `ACT-004`, `ACT-005` |

### `EXP-001` - Rule-Based Content Classifier

Goal: Classify capture content without adding ML complexity.

Acceptance:

- [ ] General, Message, Study, Menu, Technical modes exist.
- [ ] Rules are deterministic and testable.
- [ ] Telemetry logs only classification label when opt-in.

### `EXP-002` - Mode Override UI

Goal: Let users correct classification.

Acceptance:

- [ ] Panel exposes current mode.
- [ ] User can switch mode.
- [ ] Action output updates for selected mode.

### `EXP-003` - Message Mode

Goal: Translate messages with tone/context.

Acceptance:

- [ ] Translation appears first.
- [ ] Tone/register note appears below.
- [ ] Optional reply starters are available.

### `EXP-004` - Study Mode

Goal: Explain academic content for understanding.

Acceptance:

- [ ] Key terms are identified and defined.
- [ ] Simplified paragraph is included.
- [ ] One optional follow-up question is offered.

### `EXP-005` - Menu Mode

Goal: Translate menu items without losing cultural context.

Acceptance:

- [ ] Original dish names are preserved.
- [ ] Translation/description follows.
- [ ] Notes appear only where literal translation is misleading.

### `EXP-006` - Technical Mode Integration

Goal: Connect technical classification to Debug behavior.

Acceptance:

- [ ] Technical mode exposes Debug.
- [ ] Non-technical modes hide Debug unless manually selected.

### `EXP-007` - Local Glossary Storage

Goal: Store preferred terms locally.

Acceptance:

- [ ] Add/edit/delete glossary entries.
- [ ] Import/export JSON.
- [ ] Data is local by default.

### `EXP-008` - Glossary Prompt Injection

Goal: Make cloud/local actions use preferred terminology.

Acceptance:

- [ ] Client matches glossary terms in OCR text.
- [ ] Top matches are injected into prompts.
- [ ] Prompt injection is bounded and deterministic.

### `EXP-009` - Page-By-Page PDF Import

Goal: Work through longer documents without repeated screen captures.

Acceptance:

- [ ] File picker imports PDFs.
- [ ] User can navigate pages.
- [ ] Current page supports Translate and Explain.
- [ ] PDF text layer is preferred when available; OCR fallback is allowed.

---

## Epic 5 - Monetization

| ID | Story | Status | Depends On |
|---|---|---|---|
| `MON-001` | Plan and entitlement model | Not Started | `FOUND-003` |
| `MON-002` | Server-side free limit enforcement | Not Started | `FOUND-004`, `MON-001` |
| `MON-003` | RevenueCat integration | Not Started | `MON-001` |
| `MON-004` | Paywall UI | Not Started | `MON-003` |
| `MON-005` | Student plan handling | Not Started | `MON-004` |
| `MON-006` | Local history storage | Not Started | `CORE-005` |
| `MON-007` | History browser UI | Not Started | `MON-006` |
| `MON-008` | Account/settings billing surface | Not Started | `MON-003` |
| `MON-009` | Team tier spec only | Not Started | Product decision |

### `MON-001` - Plan And Entitlement Model

Goal: Centralize free/pro/student/team capabilities.

Acceptance:

- [ ] Typed plan model exists.
- [ ] Feature gates reference one entitlement source.
- [ ] Free/pro/student behavior is documented.

### `MON-002` - Server-Side Free Limit Enforcement

Goal: Make cloud usage limits enforceable.

Acceptance:

- [ ] Backend tracks daily cloud actions by device/user.
- [ ] Client displays remaining actions from server.
- [ ] UTC reset behavior is documented.

### `MON-003` - RevenueCat Integration

Goal: Use RevenueCat entitlements to unlock paid features.

Acceptance:

- [ ] SDK configured with app user ID.
- [ ] CustomerInfo entitlement check updates app state.
- [ ] Sandbox/production behavior is documented.

### `MON-004` - Paywall UI

Goal: Convert users at natural limit/upgrade moments.

Acceptance:

- [ ] Paywall explains Pro benefits.
- [ ] Upgrade buttons invoke purchase flow.
- [ ] Restore purchases works.

### `MON-005` - Student Plan Handling

Goal: Offer discounted student plan without unclear verification.

Acceptance:

- [ ] Student price/eligibility approach is documented.
- [ ] UI distinguishes Student from Pro.

### `MON-006` - Local History Storage

Goal: Save captures/results locally when user opts in.

Acceptance:

- [ ] CoreData model stores result text, mode, timestamp, and thumbnail.
- [ ] History is off by default.
- [ ] Free history is limited to last 5 captures.

### `MON-007` - History Browser UI

Goal: Let users revisit and delete saved captures.

Acceptance:

- [ ] Dedicated history window opens from menu bar.
- [ ] Search works over result text.
- [ ] Delete one/all works.

### `MON-008` - Account/Settings Billing Surface

Goal: Let users see plan and manage subscription.

Acceptance:

- [ ] Settings Account tab shows current plan.
- [ ] Manage subscription opens the correct billing surface.
- [ ] Sign-in/linking state is clear.

### `MON-009` - Team Tier Spec Only

Goal: Document future team requirements without building them early.

Acceptance:

- [ ] Shared glossary requirements documented.
- [ ] Admin retention policy requirements documented.
- [ ] Explicitly marked post-MVP.

---

## Epic 6 - Cross-Cutting Quality

| ID | Story | Status | Depends On |
|---|---|---|---|
| `QUAL-001` | Accessibility labels and VoiceOver order | Not Started | Stable UI |
| `QUAL-002` | Keyboard navigation and shortcuts | Not Started | `CORE-009` |
| `QUAL-003` | Reduced Motion and visual accessibility | Not Started | Stable UI |
| `QUAL-004` | Localization infrastructure | Not Started | Stable strings |
| `QUAL-005` | Crash reporting decision/integration | Not Started | `FOUND-008` |
| `QUAL-006` | Performance instrumentation | Not Started | `CORE-010` |
| `QUAL-007` | QA checklist per milestone | Not Started | Each milestone |
| `QUAL-008` | Beta release readiness checklist | Not Started | Alpha complete |
| `QUAL-009` | Liquid Glass overlay panel redesign | In Review | `CORE-005`, `ACT-001` |
| `QUAL-010` | Response style slider (Brief/Balanced/Thorough) | In Review | `ACT-011`, `QUAL-009` |
| `QUAL-011` | Normalize model-output math and special characters | Done | `ACT-006`, `ACT-007`, `ACT-011` |
| `QUAL-012` | Notch-attached result surface | Done | `CORE-005`, `ACT-001`, `QUAL-009` |
| `QUAL-013` | Hover-expanded notch interaction polish | Done | `QUAL-012` |

### `QUAL-001` - Accessibility Labels And VoiceOver Order

Goal: Make core UI understandable to assistive technologies.

Acceptance:

- [ ] Buttons and menu items have meaningful labels.
- [ ] Result panel reading order is sensible.
- [ ] OCR/result text is accessible.

### `QUAL-002` - Keyboard Navigation And Shortcuts

Goal: Support users who avoid mouse workflows.

Acceptance:

- [ ] Menu capture is keyboard reachable.
- [ ] Panel supports Command-C and Command-W.
- [ ] Action rail can be used by keyboard.

### `QUAL-003` - Reduced Motion And Visual Accessibility

Goal: Respect macOS accessibility settings.

Acceptance:

- [ ] Overlay/panel animations respect Reduce Motion.
- [ ] Text contrast meets WCAG AA.
- [ ] Light/dark mode are both usable.

### `QUAL-004` - Localization Infrastructure

Goal: Prepare the app for future UI localization.

Acceptance:

- [ ] User-facing strings are extractable.
- [ ] String Catalog approach is documented.
- [ ] RTL layout risk is noted for Arabic.

### `QUAL-005` - Crash Reporting Decision/Integration

Goal: Decide how to learn from crashes without violating privacy.

Acceptance:

- [ ] Decision recorded: Apple-only, Sentry, or deferred.
- [ ] Crash reporting is opt-in if third-party.
- [ ] No prompt/OCR/result content is attached.

### `QUAL-006` - Performance Instrumentation

Goal: Measure the speed promises.

Acceptance:

- [ ] Hotkey-to-overlay timing can be measured.
- [ ] OCR duration can be measured.
- [ ] Cloud first-token timing can be measured when cloud exists.

### `QUAL-007` - QA Checklist Per Milestone

Goal: Make manual testing repeatable.

Acceptance:

- [ ] `workflow/qa-checklist.md` has Alpha, Beta, Launch sections.
- [ ] Each completed epic has relevant checks.

### `QUAL-008` - Beta Release Readiness Checklist

Goal: Know when the app is ready for external testers.

Acceptance:

- [ ] Permissions/onboarding pass.
- [ ] Core loop passes on a fresh Mac.
- [ ] Known issues are documented.
- [ ] Signing/notarization path is ready.

### `QUAL-009` - Liquid Glass Overlay Panel Redesign

Auto-created on 2026-04-29 from a user-driven UI revamp request.

Goal: Make the result panel read clearly as a floating overlay rather than a windowed app.

Acceptance:

- [x] Panel uses a borderless `NSPanel` with `.fullSizeContentView`; no traffic lights, no system title bar.
- [x] Custom 16pt continuous corner radius with native window shadow tracking the rounded mask.
- [x] HUD-grade material blur (`NSVisualEffectView` `.hudWindow`, behind-window blending) so the overlay reads as floating glass.
- [x] Refractive 1pt border with top-left highlight and bottom-right shade, plus subtle gradient wash inside the panel.
- [x] Panel is movable from anywhere via `isMovableByWindowBackground`.
- [x] Custom circular close button with hover affordance replaces the system traffic-light close.
- [x] Action rail is a pill-shaped segmented bar with `matchedGeometryEffect` slide animation between selections.
- [x] Header has a gradient action badge, rounded-display title, and softer subtitle/timestamp hierarchy.
- [x] Footer separates primary actions (Copy/Export) from icon-chip metadata, with a transient confirmation pill.
- [x] Recovery panel and Ask transcript share the same glass card visual language.
- [x] Subtle scale+fade entrance animation when the panel appears.
- [x] Existing keyboard shortcuts (Esc, Cmd-W, Cmd-C) preserved.

Notes:

- Implemented 2026-04-29 across `ResultPanelController.swift`, `ResultPanelView.swift`, and `RecoveryPanelView.swift`.
- The borderless panel relies on a custom `OverlayPanel` subclass to keep `canBecomeKey` / `canBecomeMain` true so SwiftUI keyboard shortcuts continue to fire.
- Window-shadow correctness depends on the hosting `NSHostingView` having `wantsLayer`/`cornerRadius`/`masksToBounds`; `panel.invalidateShadow()` is called after content install.
- Visual primitives (`GlassOverlayContainer`, `VisualEffectBlur`, `OverlayPillButton`, `OverlayCloseButton`, `SegmentedActionBar`, `OverlayMetadataChip`, `OverlayTextField`) are private to `ResultPanelView.swift` for now; promote to a shared visual module if Settings or future overlays adopt the same style.

### `QUAL-010` - Response Style Slider (Brief / Balanced / Thorough)

Auto-created on 2026-04-29 from a user-driven perf request.

Goal: Let users trade response detail for speed without restructuring the action rail.

Acceptance:

- [x] Three discrete levels: `brief`, `balanced` (default), `thorough`.
- [x] Persisted in UserDefaults under `ResponseDetailLevel`.
- [x] Settings → Local AI exposes a 3-stop slider with a live description of the selected level.
- [x] Brief mode forces Explain, Simplify, and the Ask first turn onto Apple Foundation Models text-only, even when MLX Vision is ready, since MLX VLM generation is the dominant latency on most Macs.
- [x] No response style silently pre-warms Explain or Simplify; non-selected actions load only when selected or chosen as the smart default.
- [x] Per-action `maxOutputTokens` scales with the level (≈0.5× brief / 1.0× balanced / 1.6× thorough), with a 60-token floor and rounded to multiples of 10.
- [x] Debug always keeps MLX Vision when available — visual context is the point of debugging a screenshot.
- [x] Thread the level from `AppState` through `ResultPanelController.show()` into `ResultPanelView`.

Notes:

- The biggest perf win is the Brief-mode model swap, not the token-cap reduction; Apple Foundation Models is dramatically faster than Qwen-class MLX VLMs.
- `ResponseDetailLevel.usesImageInput(for:)` is the single source of truth for whether an action is allowed to attach the captured image; the panel also routes Ask's preferred provider through it so the routing badge stays honest.
- Translate already runs Apple text-only, so the slider only changes its token cap.
- Updated 2026-05-06 after visual QA: simplified the Settings slider to the selected style, native slider control, and Brief/Balanced/Thorough tick labels only.
- Updated 2026-05-06 after visual QA: removed the selected style description line from the Response Style slider for a cleaner control.
- Updated 2026-05-06 after visual QA: replaced the native slider with a custom three-stop control so labels align to the track endpoints and the thumb no longer shows the native focus/highlight ring.
- Updated 2026-05-06 after console QA: fixed the Local AI model picker so it does not render with an invalid untagged `nil` selection before Settings finishes initializing its selected model state.

### `QUAL-011` - Normalize Model-Output Math And Special Characters

Auto-created during user-reported UI bug fix on 2026-04-29.

Goal: Prevent LaTeX-style model output such as `$\\mathbb{C}^m$` from rendering as raw prompt syntax in the result panel.

Acceptance:

- [x] Strip inline math delimiters from action output before display/copy/export.
- [x] Convert common LaTeX math commands to readable display characters, including `\\mathbb{C}` to blackboard C.
- [x] Apply normalization to MLX final output, Apple streamed snapshots, and Ask answers.
- [x] App builds successfully.

Notes:

- Implemented 2026-04-29 with `ModelDisplayTextNormalizer`, used by `ModelOutputFormatter` and `ResultPanelView`.
- This is intentionally display normalization, not a full equation renderer; the panel remains selectable plain text.

### `QUAL-012` - Notch-Attached Result Surface

Auto-created during `QUAL-012` on 2026-05-18 from a user-driven UI direction change.

Goal: Present post-capture results as a top-center notch extension instead of a floating window near the selected region.

Acceptance:

- [x] Existing region-selection overlay remains unchanged for precise capture.
- [x] Normal capture results open first as a compact top-center island attached to the menu bar/notch area after the user selects a region.
- [x] The notch surface can expand into the full action/result view on click, then collapse back to the compact island.
- [x] Existing action state, smart default selection, local/cloud routing, Ask, copy/export, and recovery logic remain reused.
- [x] Captured image preview is hidden by default in the notch surface so the result reads as a compact system answer surface.
- [x] Permission/recovery panels are not forced into the notch layout.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-18. `ResultPanelController` now supports `ResultPanelPresentationStyle` and uses `.notchAttached` for normal results. The panel is positioned at the top center of the relevant screen in the menu-bar/notch band and grows downward when expanded.
- `ResultPanelView` keeps the existing action/result logic and adds a notch-specific compact island plus expanded view. The large capture preview stays hidden in notch presentation.

### `QUAL-013` - Hover-Expanded Notch Interaction Polish

Auto-created during `QUAL-012` follow-up on 2026-05-20 from user UI feedback.

Goal: Make the notch surface feel more like a native black notch extension, primarily opened by hover instead of click.

Acceptance:

- [x] Compact notch is smaller and avoids text preview content that can cover underlying screen text.
- [x] Compact notch expands on hover and collapses after hover leaves.
- [x] Notch window opens without activating Pixel Pane as a normal app window.
- [x] Notch shell uses a black background with square top corners and rounded lower corners.
- [x] Existing action state, routing, copy/export, Ask, and close behavior remain available in the expanded surface.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-20. The compact notch is now a short black top-center shape with only minimal status indicators. Hover expands it into the full action/result workspace; leaving the surface collapses it after a short delay.
- The notch container now uses square top corners and rounded lower corners so it reads as an extension of the physical/menu-bar notch rather than a detached rounded pill.
- Follow-up manual QA polish keeps expanded controls below the hardware notch, hardens notch-safe-area placement across notched Macs, and disables background dragging for notch-attached result panels.
- Follow-up manual QA polish also hides the top panel seam with slight screen-edge overscan, makes collapse shrink back into the notch, and pins compact notifications to the physical notch's right edge.

---

## Epic 7 - Notch Assistant

| ID | Story | Status | Depends On |
|---|---|---|---|
| `ASSIST-001` | Make the notch a chat-first assistant surface | Done | `QUAL-013`, `ACT-007`, `ACT-015` |
| `ASSIST-002` | Add user-granted local file read/search tools | Done | `ASSIST-001` |
| `ASSIST-003` | Add confirmed local file create/edit tools | Done | `ASSIST-002` |
| `ASSIST-004` | Add local chat persistence | Done | `ASSIST-001` |
| `ASSIST-005` | Expand local model setup to text-only MLX models | Done | `ASSIST-001` |
| `ASSIST-006` | Add full chat history browser and search | Not Started | `ASSIST-004` |
| `ASSIST-007` | Add minimal context prompt router | Done | `ASSIST-001`, `ASSIST-005` |
| `ASSIST-008` | Answer app-state questions without calling the model | Done | `ASSIST-005`, `ASSIST-007` |
| `ASSIST-009` | Gate local file context search to file-aware questions | Done | `ASSIST-002`, `ASSIST-007` |
| `ASSIST-010` | Tune Brief-mode local generation budgets | Done | `ASSIST-007` |
| `ASSIST-011` | Evaluate persistent MLX text runtime | Done | `ASSIST-005`, `ASSIST-010` |
| `ASSIST-012` | Add app-managed warm MLX text server | Done | `ASSIST-011` |
| `ASSIST-013` | QA local model responses and deterministic fallbacks | Done | `ASSIST-012` |
| `ASSIST-014` | Show local model peak memory in chat | Done | `ASSIST-005` |

### `ASSIST-001` - Make The Notch A Chat-First Assistant Surface

Goal: Let Pixel Pane behave like a native local ChatGPT-style assistant in the notch while preserving screenshot capture as optional context.

Acceptance:

- [x] A plain assistant notch can open without capture context.
- [x] Hovering the notch opens the expanded assistant surface.
- [x] New captures open a fresh Ask-first notch session with the capture/OCR attached as context.
- [x] Users can still start capture from the menu/hotkey.
- [x] Settings exposes Local vs Cloud as one routing choice instead of confusing simultaneous toggles.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-21. App startup creates an invisible notch hover target for plain assistant chat. Capture results now open in Chat-first mode, so the selected region is optional context for the first chat rather than forcing a smart default action. Follow-up polish removed the redundant Open Assistant menu item, removed Export from the notch footer, auto-focuses the chat field on hover open, supports no-capture chat in both local and cloud modes, makes chat typography denser, and exposes precise chat token budgets in Settings. The visible assistant surface was then simplified further into a single chat UI: the action rail and footer controls are gone, capture/routing state appears as lightweight context chips, and Extract/Translate/Explain/Simplify are natural-language chat intents rather than top-level tabs. Chat remains session-only for now.

### `ASSIST-002` - Add User-Granted Local File Read/Search Tools

Goal: Let the notch assistant inspect local files only after the user grants file or folder access.

Acceptance:

- [x] User can grant a folder or file from the assistant or Settings.
- [x] Assistant can list granted folders.
- [x] Assistant can read text files in granted locations.
- [x] Assistant can search text in granted locations.
- [x] No writes are allowed in this story.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-21. Added a read-only local file access store with explicit user-granted file/folder selection from the assistant and Settings. The notch chat can list granted paths, search text-like files inside granted locations, and include bounded relevant snippets in local or cloud chat prompts depending on the selected routing mode. Writes, edits, deletes, and moves remain intentionally out of scope for this story. Debug app build, backend typecheck, and Worker deploy succeeded.
- Follow-up 2026-05-22: Added a compact Files menu directly in the chat composer so users can choose a folder, choose a file, review granted sources, and remove a source without opening Settings.
- Follow-up 2026-05-22: Reordered the composer controls and added Clear File Sources so all granted file references can be removed from the chat window.

### `ASSIST-003` - Add Confirmed Local File Create/Edit Tools

Goal: Let the assistant create or edit files locally with explicit confirmation.

Acceptance:

- [x] Assistant can propose a file creation.
- [x] Assistant can propose a text edit.
- [x] User must confirm before any write occurs.
- [x] Confirmation UI names the target path.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-21. Added a deterministic local write proposal parser for chat commands such as `create file`, `append to`, and `replace in`, limited to user-granted files/folders. The assistant stages a proposal in the chat transcript, then shows a local confirmation panel naming the target path; Confirm applies the write locally and Cancel leaves files unchanged. No model output directly mutates files. Debug build succeeded.

### `ASSIST-004` - Add Local Chat Persistence

Goal: Store assistant chats locally once the notch chat UX is validated.

Acceptance:

- [x] Chat messages are stored locally.
- [x] Users can clear local chat history.
- [x] Captures remain ephemeral unless explicitly retained.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-21. Added a local `ChatHistoryStore` backed by UserDefaults for text-only chat transcripts. Plain notch chats resume the latest assistant session, capture chats persist their message transcript with a lightweight "Screen region" label, and screenshots are not saved in history. The composer now has a small history menu for recent chats and a New Chat action. Settings now includes a History tab with saved-chat count, per-chat delete, and Clear History. Debug build succeeded.
- Follow-up 2026-05-22: Split the composer controls so New Chat is a direct small action and History is a labeled recent-chat menu with relative recency, keeping the UI minimal while making the two entry points easier to find. Full search/browser work remains tracked in `ASSIST-006`.

### `ASSIST-005` - Expand Local Model Setup To Text-Only MLX Models

Goal: Support local text LLMs in addition to the current MLX vision setup.

Acceptance:

- [x] Settings distinguishes Text, Vision, and Text+Vision model capabilities.
- [x] Text-only MLX models are selectable for chat.
- [x] Vision-only requirements no longer block text chat model setup.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-21. Added MLX model capability detection for Text, Vision, Text + Vision, and Unsupported models; Settings now displays capability labels and separate text/vision runtime status. Local setup accepts usable text-only MLX models instead of requiring VLM metadata, and `HybridLocalAIBackend` routes text-only local chat/actions through a selected MLX text model via `mlx_lm.generate` when available, falling back to Apple Foundation Models otherwise. Existing MLX Vision routing remains gated on a vision-capable selected model. Debug build succeeded.

### `ASSIST-006` - Add Full Chat History Browser And Search

Auto-created during `ASSIST-004` follow-up on 2026-05-22.

Goal: Make previous assistant chats easy to find and reopen, beyond the compact composer history menu.

Acceptance:

- [ ] A dedicated chat history surface opens from the assistant and/or menu bar.
- [ ] Users can search saved chat titles and message text.
- [ ] Users can reopen an assistant chat without implying screen-region context.
- [ ] Capture-context chats are clearly labeled and do not retain screenshot images.
- [ ] Users can delete one chat or clear all chats from the same surface.

### `ASSIST-007` - Add Minimal Context Prompt Router

Auto-created during local Qwen speed/prompt QA on 2026-05-22.

Goal: Make assistant prompts model-agnostic and as small as possible, adding screen/file/history context only when it is actually present and needed.

Acceptance:

- [ ] Plain chat with no capture, files, or prior turns sends only the user message plus the smallest necessary direct-answer/no-reasoning guard.
- [ ] Screen/OCR instructions are included only for capture-context chats.
- [ ] File context instructions are included only when file snippets are attached.
- [ ] Prior-chat transcript is included only when there are previous turns relevant to the current chat.
- [ ] Brief mode does not mention absent context labels such as `Screen: none`, `OCR: none`, `Files: none`, or `Prior: none`.
- [ ] App builds successfully.

Notes:

- Risk: Low. The current prompt builder is centralized in the Ask flow and can be split into small prompt cases. The main risk is accidentally dropping useful context from capture or file chats, so QA should cover plain, capture, file, and follow-up turns.
- Implemented 2026-05-22. The Ask prompt builder now emits small, context-specific prompts. Plain chat no longer mentions absent screen, OCR, file, or prior-chat sections. Capture OCR/image, file snippets, and prior transcript are added only when present.

### `ASSIST-008` - Answer App-State Questions Without Calling The Model

Auto-created during local Qwen speed/prompt QA on 2026-05-22.

Goal: Return instant, accurate answers for questions Pixel Pane can answer from app state instead of asking the selected LLM to infer them.

Acceptance:

- [ ] Questions like "what model is this?", "which model?", and "what are you running?" answer from the selected MLX model/backend metadata.
- [ ] Questions about Local vs Cloud routing answer from `AIRoutingSettings`.
- [ ] Questions about granted file sources answer from the local file access store.
- [ ] These deterministic answers do not start a local or cloud model request.
- [ ] App builds successfully.

Notes:

- Risk: Low. This is a deterministic preflight before model routing. Keep patterns narrow so normal content questions still reach the model.
- Implemented 2026-05-22. Ask now answers selected-model/routing/file-source questions from app state before invoking local or cloud AI. "Which one?" after a model question is handled from the stored MLX selection.

### `ASSIST-009` - Gate Local File Context Search To File-Aware Questions

Auto-created during local Qwen speed/prompt QA on 2026-05-22.

Goal: Avoid scanning granted folders before every chat turn when the user is asking a plain conversational question.

Acceptance:

- [ ] Plain chat turns do not search granted files unless the question appears file/project/code/path/document related.
- [ ] Explicit requests such as "search files", "in this project", "in README", or a visible file/path mention still attach local file snippets.
- [ ] Direct file-source questions still use the existing instant local answer path.
- [ ] If no snippets are attached, the prompt does not mention files at all.
- [ ] App builds successfully.

Notes:

- Risk: Medium. A heuristic can miss implicit file questions. Bias toward clear triggers first, and leave a visible Files control plus natural-language "search files for..." escape hatch.
- Implemented 2026-05-22. Granted files are searched only when the question has file/project/code/path signals or names a granted source. If no search runs, the prompt omits file context entirely.

### `ASSIST-010` - Tune Brief-Mode Local Generation Budgets

Auto-created during local Qwen speed/prompt QA on 2026-05-22.

Goal: Make Brief mode faster for local MLX text models without cutting off complete answers.

Acceptance:

- [ ] Simple Brief plain-chat turns use a small generation budget.
- [ ] Brief follow-ups with light context use a moderate budget instead of the full Ask ceiling.
- [ ] Questions that ask for detail, lists, code, or multi-step output still get enough room to finish.
- [ ] Brief mode continues to hide model thinking/reasoning UI.
- [ ] App builds successfully.

Notes:

- Risk: Medium. Token caps can make answers feel clipped if too aggressive. Treat caps as routing hints based on question shape, not a hard global limit for Brief.
- Implemented 2026-05-22. Brief mode now uses adaptive Ask budgets: 128 tokens for simple plain turns, 256-512 for light follow-ups, and 1024 when context or long-answer signals are present.

### `ASSIST-011` - Evaluate Persistent MLX Text Runtime

Auto-created during local Qwen speed/prompt QA on 2026-05-22.

Goal: Determine whether Pixel Pane can avoid the per-message `mlx_lm.generate` startup cost by using a persistent local MLX text worker or server.

Acceptance:

- [ ] Measure current one-shot MLX Text first-token latency on a simple prompt.
- [ ] Identify a supported persistent MLX-LM serving path or a safe app-managed worker process.
- [ ] Prototype or document why the persistent path is not viable.
- [ ] Preserve fallback to the current one-shot process if the worker fails.
- [ ] Record follow-up implementation or rejection notes in `workflow/status.md`.

Notes:

- Risk: High. This is the biggest likely speed win, but it depends on MLX-LM process/server behavior, memory residency, cancellation, app lifecycle cleanup, and packaging. Treat it as a spike before relying on it for product speed.
- Completed 2026-05-22. On the user's cached `mlx-community/Qwen3-30B-A3B-4bit`, one-shot `mlx_lm.generate` answered a 32-token identity prompt in about 2.63 seconds. A warm `mlx_lm.server` on localhost answered comparable chat-completion requests in about 0.43-0.55 seconds after startup. Recommendation: add a follow-up implementation story for an app-managed persistent MLX text server with lifecycle cleanup and fallback to one-shot generation.

### `ASSIST-012` - Add App-Managed Warm MLX Text Server

Auto-created during `ASSIST-011` on 2026-05-22.

Goal: Use `mlx_lm.server` as a warm local text backend so repeated MLX text chat turns avoid one-shot process startup overhead.

Acceptance:

- [x] App starts or reuses a localhost `mlx_lm.server` process for the selected text-compatible MLX model.
- [x] Requests use the server's OpenAI-compatible chat completions endpoint with thinking disabled.
- [x] If `mlx_lm.server` is unavailable, the app falls back to the current one-shot `mlx_lm.generate` path; if the installed server starts but fails, the app fails cleanly instead of launching a second heavy MLX process.
- [x] Server lifecycle is tied to app/model selection and cleans up on model change or app quit.
- [x] The implementation avoids exposing the server beyond localhost.
- [x] App builds successfully.

Notes:

- `mlx_lm.server` warns that it is not recommended for production as a public server, but a localhost-only app-managed helper is viable if we keep it bound to `127.0.0.1`, avoid broad CORS exposure, and retain one-shot fallback.
- Implemented 2026-05-22. `MLXTextBackend` now tries a lazy warm `mlx_lm.server` first, bound to `127.0.0.1` on an app-selected free port with thinking disabled. The server is reused for the selected model, shut down after idle time, stopped on model changes/clear selection/app termination, and falls back to one-shot `mlx_lm.generate` if startup, health check, request, or parsing fails. Local verification wrapper build succeeded.
- Follow-up hardening 2026-05-22. Warm server output is now drained so helper logs cannot block startup. If an installed warm server fails to start or respond, Pixel Pane now surfaces the local-model failure instead of immediately launching `mlx_lm.generate`, avoiding two back-to-back large MLX model loads that can pressure memory and get the debug app killed. One-shot fallback remains for machines without `mlx_lm.server`.
- Follow-up hybrid fix 2026-05-22. Active chat requests no longer wait for warm-server startup. If a matching `mlx_lm.server` process is already healthy, Pixel Pane uses it for fast local text responses. If not, Pixel Pane uses the known-good one-shot `mlx_lm.generate` path and starts the warm server in the background after the one-shot response succeeds.

### `ASSIST-013` - QA Local Model Responses And Deterministic Fallbacks

Auto-created during local model QA on 2026-05-22.

Goal: Exercise the selected local Qwen MLX path with representative prompts and patch model-agnostic behavior that should not depend on generation.

Acceptance:

- [x] Test simple Brief prompts against a warm local MLX model and record latency/behavior.
- [x] Verify thinking does not leak for normal and adversarial Brief prompts.
- [x] App answers assistant identity from Pixel Pane instead of the model's own identity.
- [x] App does not let a model guess about the screen when no capture context is attached.
- [x] Warm-server responses use the same output formatter as one-shot responses.
- [x] App builds successfully.

Notes:

- Completed 2026-05-22. Warm `mlx_lm.server` responses on the cached `mlx-community/Qwen3-30B-A3B-4bit` test model returned in about 0.24-0.40 seconds after startup. Brief prompts did not leak thinking, including a direct request for step-by-step reasoning. The app now answers "what is your name?" as Pixel Pane and "what is on my screen?" without attached capture as unavailable screen context before calling a model. Warm-server output now passes through `ModelOutputFormatter`.

### `ASSIST-014` - Show Local Model Peak Memory In Chat

Auto-created during local model memory polish on 2026-05-22.

Goal: Make local MLX memory usage visible in the chat surface without adding a larger diagnostics UI.

Acceptance:

- [x] Chat turn metadata shows the parsed local MLX peak memory value when available.
- [x] The memory value is only shown for local MLX backends.
- [x] App builds successfully.

Notes:

- Completed 2026-05-22. The existing `Peak memory:` statistic parsed from MLX one-shot output now appears in local MLX chat metadata as `Peak <value>`.
