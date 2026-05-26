# Pixel Pane Story Backlog

Last updated: 2026-05-26 (model-first terminal routing follow-up)

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

`ASSIST-021` - Add prompt-injection and tool-safety hardening for files/images is the current recommended story.

Reason: `ASSIST-040` added the selected-model action planner and narrowed the old shortcut router to fallback behavior. The next sprint slice should harden prompt-injection and tool-safety boundaries before the live cross-model matrix in `ASSIST-022`.

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
- [x] App builds successfully.
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
| `PRIV-004` | Ephemeral capture audit | Done | `CORE-003` |
| `PRIV-005` | Local/cloud mode setting and enforcement | Done | `ACT-001` |
| `PRIV-006` | Result source transparency | Not Started | `CORE-008` |
| `PRIV-007` | Settings structure | Not Started | `CORE-001` |
| `PRIV-008` | First-capture tutorial | Done | `CORE-002` |
| `PRIV-009` | Remove or formalize onboarding QA reset | Done | Beta readiness |

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
- Follow-up 2026-05-23. Revised the onboarding into a sharper privacy-first introduction: selected-region control, no background recording, screenshot non-retention, Local Mode by default, and Cloud Mode as opt-in. Added a Screen Recording readiness row with Request Access/Open Settings actions, renamed Continue to Open Assistant, and kept Start First Capture as the primary action. Local verification wrapper build succeeded.

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

- [x] Normal capture path writes no screenshots to disk.
- [x] Capture reference is released when panel closes.
- [x] Any retained image is in-memory only.
- [x] QA checklist includes file-system spot check.

Notes:

- Completed 2026-05-22. Audited `ScreenCapturer`, `AppState`, `ResultPanelController`, `ResultPanelView`, `ChatHistoryStore`, `CloudAIBackend`, and `MLXVisionBackend`.
- Normal capture/OCR remains in memory through `SCScreenshotManager.captureImage(in:)` and Vision OCR; `ChatHistoryStore` persists text turns only.
- Fixed `AppState.lastResult` so the menu-bar "Show Last Result" convenience path retains OCR text and metadata only, not the captured `CGImage`.
- Hardened MLX Vision helper cleanup so temporary `pixel-pane-mlx-*.png` files are removed on success, cancellation, timeout, process launch failure, and image-write failure.
- Added privacy spot-check steps to `workflow/qa-checklist.md` and recorded the last-result image-retention decision in `workflow/decisions.md`.

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

- [x] Overlay has first-use tip.
- [x] Tutorial state is separate from onboarding state.
- [x] Tutorial does not repeat after success.

Notes:

- Completed 2026-05-23. Added a separate `FirstCaptureTutorial.Completed` flag. Until the first successful capture, the region overlay says "Drag over text to ask Pixel Pane"; after success, the flag is persisted so the default overlay hint returns. Local verification wrapper build succeeded.

### `PRIV-009` - Remove Or Formalize Onboarding QA Reset

Auto-created during `PRIV-001` follow-up on 2026-05-22.

Goal: Do not ship a rough QA-only onboarding reset control by accident.

Acceptance:

- [x] Decide whether the onboarding reset belongs in production Settings or should be debug-only.
- [x] If production-facing, move it into the final Privacy/About settings structure with user-facing copy.
- [x] Debug-only path not chosen; reset remains production-facing.
- [x] Update `workflow/status.md` with the final decision.

Notes:

- Completed 2026-05-23. Decision: keep the reset as a production-facing Settings -> Permissions control for now so users and QA can revisit the privacy introduction. Renamed the section to "Privacy Introduction" and the action to "View Privacy Introduction Again"; it no longer presents as a QA-only reset. Local verification wrapper build succeeded.

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
| `QUAL-014` | Performance pass for capture, chat, and local context | Done | `QUAL-013`, `ASSIST-002`, `ASSIST-012` |

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
- Follow-up 2026-05-24. Plain/new assistant chats now use continuous rounded top and bottom corners and skip screen-edge overscan so the rounded edges are not clipped; capture-attached notch panels keep the square top edge.
- Follow-up 2026-05-24. Removed the completed-state green compact notification; only the three orange loading dots show while processing, then the notch returns to the invisible hover target.
- Follow-up 2026-05-24. Collapsed hover target now resolves to the actual notch bounds when available and uses a smaller fallback, preventing the overlay from opening from the wider invisible panel area.
- Follow-up 2026-05-24. Expanded assistant windows now use a dynamic hosting-layer rounded mask plus a frame-filling SwiftUI notch shell, keeping the blank/new-chat bottom corners rounded while leaving compact notification and capture-notch behavior unchanged.

### `QUAL-014` - Performance Pass For Capture, Chat, And Local Context

Auto-created during performance review follow-up on 2026-05-22.

Goal: Remove obvious UI-thread and per-token churn from the current capture/chat/local-context paths without changing product behavior.

Acceptance:

- [x] Vision OCR request execution no longer runs synchronously on the main actor.
- [x] Streamed Ask responses no longer persist the full chat store or resize the notch on every token/snapshot.
- [x] Ask transcript autoscroll no longer runs on every streamed text mutation.
- [x] Local file context search caps full-content reads and prioritizes path matches before expensive content scans.
- [x] Result panel routing uses cached local AI capability state instead of rescanning MLX capability paths during panel actions.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-22. This is a targeted hot-path cleanup, not full profiling instrumentation.

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
| `ASSIST-015` | Keep notch stable after New Chat | Done | `ASSIST-001` |
| `ASSIST-016` | Add model-agnostic assistant capability contract and tool router | Done | `ASSIST-007`, `ASSIST-008`, `ASSIST-012`, `ASSIST-013` |
| `ASSIST-017` | Normalize user-provided image context and attachments | Done | `ASSIST-016`, `ACT-013`, `PRIV-004` |
| `ASSIST-018` | Add model-agnostic local file tool execution layer | Done | `ASSIST-016`, `ASSIST-002`, `ASSIST-003` |
| `ASSIST-019` | Add source-aware context packing and budget manager | Done | `ASSIST-016`, `ASSIST-017`, `ASSIST-018` |
| `ASSIST-020` | Add tool-use transcript and source transparency UI | Not Started | `ASSIST-017`, `ASSIST-018`, `PRIV-006` |
| `ASSIST-021` | Add prompt-injection and tool-safety hardening for files/images | Not Started | `ASSIST-018`, `ASSIST-019` |
| `ASSIST-022` | Add cross-model assistant harness QA matrix | Not Started | `ASSIST-016`, `ASSIST-017`, `ASSIST-018`, `ASSIST-019`, `ASSIST-020`, `ASSIST-021` |
| `ASSIST-023` | Add bounded terminal tool support for granted repos | Done | `ASSIST-016`, `ASSIST-018`, `ASSIST-019` |
| `ASSIST-024` | Fix follow-up granted-source routing for local file tools | Done | `ASSIST-016`, `ASSIST-018`, `ASSIST-019`, `ASSIST-023` |
| `ASSIST-025` | Add terminal-backed file discovery and edit target resolution | Done | `ASSIST-016`, `ASSIST-018`, `ASSIST-019`, `ASSIST-023`, `ASSIST-024` |
| `ASSIST-026` | Add mode-independent agentic file discovery/read loop | Done | `ASSIST-016`, `ASSIST-018`, `ASSIST-019`, `ASSIST-023`, `ASSIST-025` |
| `ASSIST-027` | Add general terminal agent with risk-based approval | Done | `ASSIST-016`, `ASSIST-023`, `ASSIST-026` |
| `ASSIST-028` | Fix folder-selection continuation loops in the agent harness | Done | `ASSIST-018`, `ASSIST-024`, `ASSIST-026`, `ASSIST-027` |
| `ASSIST-029` | Add copy-chat debug export for agent transcripts | Done | `ASSIST-004`, `ASSIST-019`, `ASSIST-020` |
| `ASSIST-030` | Harden dev-server and natural-language terminal routing from copied transcripts | Done | `ASSIST-027`, `ASSIST-029` |
| `ASSIST-031` | Add modular workspace profiling for agentic terminal planning | Done | `ASSIST-027`, `ASSIST-030` |
| `ASSIST-032` | Route delegated file writes through selected-model planning | Done | `ASSIST-003`, `ASSIST-018`, `ASSIST-026`, `ASSIST-027` |
| `ASSIST-033` | Ground delegated writes in current-session observations | Done | `ASSIST-004`, `ASSIST-019`, `ASSIST-032` |
| `ASSIST-034` | Route recent-file rewrite follow-ups through app-owned edit planning | Done | `ASSIST-018`, `ASSIST-019`, `ASSIST-032`, `ASSIST-033` |
| `ASSIST-035` | Constrain model-planned writes to the app-resolved named grant | Done | `ASSIST-018`, `ASSIST-032`, `ASSIST-033`, `ASSIST-034` |
| `ASSIST-036` | Resolve named granted folders for local file listing | Done | `ASSIST-018`, `ASSIST-024`, `ASSIST-028`, `ASSIST-035` |
| `ASSIST-037` | Read files referenced from the last folder listing | Done | `ASSIST-018`, `ASSIST-019`, `ASSIST-024`, `ASSIST-036` |
| `ASSIST-038` | Prefer recent source observations over broad grant/search fallbacks | Done | `ASSIST-018`, `ASSIST-019`, `ASSIST-024`, `ASSIST-037` |
| `ASSIST-039` | Prefer workspace execution over generic port inspection | Done | `ASSIST-027`, `ASSIST-031`, `ASSIST-038` |
| `ASSIST-040` | Replace hard-coded terminal/file intent shortcuts with a model-planned action loop | Done | `ASSIST-016`, `ASSIST-018`, `ASSIST-019`, `ASSIST-027`, `ASSIST-031`, `ASSIST-039` |
| `ASSIST-041` | Scope deictic project searches to the current observed folder | Done | `ASSIST-018`, `ASSIST-019`, `ASSIST-038`, `ASSIST-040` |
| `ASSIST-042` | Polish notch assistant model-answer text formatting | Done | `ASSIST-001`, `ASSIST-018` |
| `ASSIST-043` | Add app-owned folder/project profiling tool | Done | `ASSIST-018`, `ASSIST-031`, `ASSIST-040` |
| `ASSIST-044` | Add agent task framing and bounded completion loop | Not Started | `ASSIST-021`, `ASSIST-040`, `ASSIST-043` |
| `ASSIST-045` | Add synthesis-first answers with source/tool receipts | Not Started | `ASSIST-020`, `ASSIST-043`, `ASSIST-044` |
| `ASSIST-046` | Add confirmed file/script creation and execution workflow | Not Started | `ASSIST-003`, `ASSIST-021`, `ASSIST-027`, `ASSIST-044` |
| `ASSIST-047` | Refactor assistant harness runner out of UI and split modules | Not Started | `ASSIST-044`, `ASSIST-045`, `ASSIST-046` |

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

- Implemented 2026-05-21. Added a local `ChatHistoryStore` backed by UserDefaults for text-only chat transcripts. Capture chats persist their message transcript with a lightweight "Screen region" label, and screenshots are not saved in history. The composer now has a small history menu for explicitly reopening recent chats and a New Chat action. Settings now includes a History tab with saved-chat count, per-chat delete, and Clear History. Debug build succeeded.
- Follow-up 2026-05-26: Fresh assistant chats no longer auto-restore the latest saved assistant session. History remains per saved chat and is only reintroduced by explicitly reopening a session; new chats start with empty turns/tool state unless they are capture-context chats.
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

### `ASSIST-015` - Keep Notch Stable After New Chat

Auto-created during notch assistant polish on 2026-05-22.

Goal: Prevent the expanded notch from shrinking under the cursor and immediately collapsing when New Chat clears the transcript.

Acceptance:

- [x] New Chat immediately returns to the compact empty-chat expanded size after clearing chat content.
- [x] Hover-out collapse is briefly suppressed only for resize-caused hover loss.
- [x] The chat input stays focused after starting the new empty chat.
- [x] App builds successfully.

Notes:

- Completed 2026-05-22. New Chat originally held the active expanded size for one second, but that left a large blank panel.
- Revised 2026-05-22. New Chat now resizes immediately to the compact empty-chat layout, cancels pending collapse work, briefly suppresses only hover-collapse caused by the resize, and refocuses the chat input.

### Assistant Harness Sprint - Model-Agnostic Tools, Images, And Files

Prepared during research on 2026-05-24.

Sprint goal: Any user-set model should get the same high-quality assistant experience: it can use user-provided images, inspect only user-granted files/folders, answer app-state questions accurately, and request confirmed local writes through an app-owned permission layer. Native tool-calling models can use provider tools, but Pixel Pane must not depend on native tool calling for correctness.

Implementation order:

1. `ASSIST-016` defines the adapter capability contract and central router.
2. `ASSIST-017` and `ASSIST-018` convert images and files into first-class app tools.
3. `ASSIST-019` packs context safely across small and large context windows.
4. `ASSIST-020` exposes what was used so users can trust the answer.
5. `ASSIST-021` hardens untrusted file/image content and side-effect boundaries.
6. `ASSIST-022` proves the same flow works across local text, local vision, cloud, and weak/no-tool models.

Non-goals for this sprint: autonomous computer control, background screen monitoring, unbounded shell access, unconfirmed file writes, remote write tools, persistent screenshot memory, or model-specific hard-coded answers.

### `ASSIST-016` - Add Model-Agnostic Assistant Capability Contract And Tool Router

Goal: Create a single assistant harness layer that decides what app capabilities are available, which model route can consume them, and how model/tool results flow back into the chat.

Acceptance:

- [x] Add an `AssistantModelCapabilities` contract for each backend/adapter covering text chat, image input, native tool calling, structured-output reliability, streaming, context budget, and local/cloud routing.
- [x] Centralize app-owned assistant tools behind one router before model invocation: app-state answers, file grants/list/search/read, image/OCR context, and local write proposal/confirmation.
- [x] Support native provider tool calls when available, but keep an app-side fallback path for models that only emit plain text.
- [x] Remove scattered Ask-flow decisions that duplicate tool routing, while preserving existing deterministic answers and file-search gating.
- [x] App builds successfully.

Notes:

- Research basis: OpenAI, Anthropic, MCP, and Hugging Face all treat tool use as a structured request that application code executes; the model does not directly access the system. Local models vary widely in native tool support, so the router must be model-agnostic.
- Relevant seams today: `ResultPanelView.sendAskQuestion()`, `directAppStateAnswer`, `LocalFileContextProvider`, `LocalFileWriteProposalParser`, `AIBackendRequest`, `HybridLocalAIBackend`, `MLXTextBackend`, `MLXVisionBackend`, and `CloudAIBackend`.
- Risk: Medium-high. This touches the main Ask path. Keep the first pass as a refactor/contract with behavior parity and tight regression QA.
- Completed 2026-05-24. Added `AssistantHarness.swift` with `AssistantModelCapabilities`, route/image/tool capability metadata, `AssistantToolEnvironment`, and `AssistantToolRouter`. The Ask path now uses the router for deterministic Pixel Pane answers, local file grant answers, local write proposal preflight, and file-search gating before model invocation. The old duplicated direct-answer/write/search helpers were removed from `ResultPanelView`. Local verification wrapper build succeeded.

### `ASSIST-017` - Normalize User-Provided Image Context And Attachments

Goal: Let users provide image context intentionally and make screenshot/user-image inputs available to capable models through one normalized image pipeline.

Acceptance:

- [x] Define an `AssistantImageContext` value that can represent active capture screenshots, user-selected image files, clipboard/paste images if available, OCR text extracted from images, and transient metadata.
- [x] Add a minimal assistant UI path for attaching an image from user selection without saving persistent screenshots by default.
- [x] Route images to MLX-VLM or Cloud Mode only when the selected backend supports image input and the current routing/privacy state allows it.
- [x] Provide an OCR/text fallback for text-only models so attached images can still help when they contain readable text.
- [x] Ensure temporary image exports for MLX helpers are cleaned up on success, cancellation, timeout, and error.
- [x] App builds successfully.

Notes:

- Research basis: multimodal model APIs commonly represent message content as typed text/image parts, while MLX-VLM currently works well with image paths/server input. Apple Vision can extract OCR as a local fallback.
- Privacy constraint: user-selected images should be treated like capture screenshots: transient by default, not added to chat history as pixels unless a future explicit retention story says otherwise.
- Risk: Medium. The hard part is preserving ephemeral capture semantics while adding user-supplied images.
- Completed 2026-05-24. Added `AssistantImageContext` and a composer image menu for choosing, replacing, and clearing a transient user image. Attached images are kept in memory, OCR'd locally for text-only fallback, surfaced as assistant context badges, and cleared when opening history or starting a new chat. Ask routing now prefers the user-attached image for MLX Vision/Cloud image-capable routes and falls back to attached-image OCR for text-only routes. The existing MLX temporary-image cleanup path remains unchanged. Local verification wrapper build succeeded.

### `ASSIST-018` - Add Model-Agnostic Local File Tool Execution Layer

Goal: Replace heuristics and direct prompt stuffing with explicit file tools that work consistently across all model adapters.

Acceptance:

- [x] Define file tools for listing grants, searching grants, reading bounded text, explaining unavailable access, and staging local write proposals.
- [x] Enforce user-granted roots in the tool executor, not in model prompts.
- [x] Keep writes local-only and confirmation-gated with the existing proposal UI before any file mutation.
- [x] For models without native tool calling, preserve a deterministic app-side planner for obvious file intents and a structured prompt fallback for ambiguous cases.
- [x] Return structured file tool results with source IDs, paths, byte/line ranges when available, and truncation flags.
- [x] App builds successfully.

Notes:

- Research basis: tool definitions should have schemas, precise descriptions, and high-signal outputs; execution stays in app code. Permission checks must be deterministic and independent of model compliance.
- Risk: Medium. Existing file search works, but this story changes ownership from prompt builder heuristics to a reusable tool executor.
- Completed 2026-05-24. Added `AssistantLocalFileToolExecutor` with explicit list-grants, search, read, unavailable-access, and stage-write proposal tools. Grant enforcement now lives in the executor, Ask file search goes through the tool router, and write proposals remain confirmation-gated before any file mutation. Local verification wrapper build succeeded.
- Follow-up 2026-05-24. Broad folder questions now route to local file tools before the no-screen fallback, and a single granted folder can be answered with a deterministic top-level contents overview. Local verification wrapper build succeeded.
- Follow-up 2026-05-24. File/folder capability questions such as "can you view my folders?" now route through deterministic local grant answers before model invocation. Local verification wrapper build succeeded.

### `ASSIST-019` - Add Source-Aware Context Packing And Budget Manager

Goal: Give models enough relevant context from chat, files, OCR, and images without overflowing small local context windows or hiding source boundaries.

Acceptance:

- [ ] Add a context packer that budgets user question, system/tool instructions, prior turns, OCR, file snippets, image OCR, and tool results separately.
- [ ] Prefer source titles, paths, snippets, and summaries over full file content unless the user explicitly asks to read a file.
- [ ] Degrade gracefully for small local models by shrinking or omitting lower-priority context instead of sending misleading "none" sections.
- [ ] Mark untrusted retrieved content as data, not instructions, before it reaches any model.
- [ ] Preserve Brief/Balanced/Thorough response style without using truncating token caps as a substitute for context packing.
- [ ] App builds successfully.

Notes:

- Research basis: MLX-LM supports prompt caching and long-context options, but user-selected models can vary heavily. The app needs an adapter-level budget rather than one global prompt shape.
- Risk: Medium-high. Poor packing can silently degrade answers. Add visible source/debug metadata in `ASSIST-020`.
- Completed 2026-05-24. Added explicit assistant tool registry definitions with stable schemas, risk levels, and permission requirements for `list_grants`, `list_folder`, `search_files`, `read_file`, `stage_write_proposal`, and `describe_screen_or_image_context`. Added persistent per-chat `AssistantToolState` for sources, listed folders, snippets, visual context, and recent tool results. Ask now uses conversation-aware file follow-up planning, validates deterministic tool calls against schemas and grants before execution, records tool state into chat history, and packs prompt/cloud context through a source-aware budget manager that separates instructions, question, prior turns, OCR/image OCR, file snippets, and tool results without fake "none" sections. Retrieved file/OCR/image/tool content is marked as untrusted data. Project-summary searches now prioritize likely project files such as README and manifest/docs files.
- Follow-up 2026-05-24: Context-dependent file search now enriches pronoun follow-ups with recent turns and source names. Portfolio/resume-style searches expand generic experience/background/skills terms, prioritize common web/resume files such as `index.html`, `whoami.html`, and `resume-latex/resume.tex`, and choose the densest snippet window instead of the first match. This targets the observed `What is his experience?` miss after identifying a portfolio owner. Local verification wrapper build succeeded; no XCTest harness exists, so manual QA prompts are recorded in `workflow/status.md`.

### `ASSIST-020` - Add Tool-Use Transcript And Source Transparency UI

Goal: Make it clear when Pixel Pane used files, OCR, images, or deterministic app state so users can trust and debug the assistant.

Acceptance:

- [ ] Chat turn metadata shows whether the answer used app state, OCR, image context, local files, confirmed write proposals, Local Mode, or Cloud Mode.
- [ ] File-backed answers expose concise source chips with path/display name and snippet count without crowding the notch surface.
- [ ] Image-backed answers distinguish active capture, user-attached image, and OCR-only fallback.
- [ ] Cloud Mode clearly indicates when file snippets or image context were sent to the cloud route.
- [ ] Source transparency supports `PRIV-006` rather than creating a second, inconsistent source UI.
- [ ] App builds successfully.

Notes:

- This should stay minimal in the notch. Prefer a compact source row/details popover over large cards.
- Risk: Low-medium. Mostly UI clarity, but it depends on structured outputs from the preceding stories.
- Follow-up 2026-05-26: Notch assistant loading-state polish replaced the static `Thinking...` chat placeholder with a compact animated indicator. This did not start or complete the broader `ASSIST-020` source transparency UI story.
- Follow-up 2026-05-26: Notch assistant transcript polish keeps the latest chat turn anchored to the bottom during new/streaming answers and uses automatic scroll indicators so the scrollbar hides when idle. This did not start or complete the broader `ASSIST-020` source transparency UI story.
- Follow-up 2026-05-26: Assistant answers now render absolute `/Users/...` paths as clickable Finder reveal controls. This did not start or complete the broader `ASSIST-020` source transparency UI story.
- Follow-up 2026-05-26: Assistant answers now also resolve relative `- File:` and `- Folder:` rows from recent folder listings against tool-state folders, so listed child items are clickable Finder reveal controls. This did not start or complete the broader `ASSIST-020` source transparency UI story.

### `ASSIST-021` - Add Prompt-Injection And Tool-Safety Hardening For Files/Images

Goal: Treat file contents, OCR, image text, and tool outputs as untrusted data so malicious instructions in local files/images cannot broaden access or trigger side effects.

Acceptance:

- [ ] Retrieved file/image/OCR content is wrapped with explicit untrusted-data boundaries in prompts and tool results.
- [ ] Tool executor validates arguments against user grants, current session intent, path normalization, file size/type limits, and side-effect policy.
- [ ] Any write/create/edit remains human-confirmed and cannot be requested solely by retrieved content.
- [ ] Add tests or manual QA prompts with injected instructions inside granted files and images.
- [ ] Log/metadata records blocked or downgraded tool attempts locally without storing sensitive content.
- [ ] App builds successfully.

Notes:

- Research basis: OWASP and provider guidance recommend least privilege, structured separation, action validation, and human confirmation for consequential actions. This is especially important for RAG/file contents and multimodal injection.
- Risk: High. This is a trust-boundary story; complete it before making file/image tools feel automatic.

### `ASSIST-022` - Add Cross-Model Assistant Harness QA Matrix

Goal: Prove the harness works across representative user-set models and routing modes, including models that do not reliably emit tool calls.

Acceptance:

- [ ] Add a QA matrix for local MLX text, local MLX vision, Cloud Mode, text-only fallback, no selected local model, and a weak/no-native-tool local model.
- [ ] Cover app-state answers, file grant questions, file search/read, image attachment, screenshot context, OCR fallback, confirmed write proposal/cancel/confirm, and prompt-injection attempts.
- [ ] Record expected behavior for each route in `workflow/qa-checklist.md` or an equivalent workflow doc.
- [ ] Run the matrix on the current development machine where feasible and record gaps in `workflow/status.md`.
- [ ] App builds successfully after any fixes required by QA.

Notes:

- This is the exit story for the sprint. Do not mark the harness sprint complete until this matrix has run or each unrun case has an explicit blocker.

### `ASSIST-023` - Add Bounded Terminal Tool Support For Granted Repos

Auto-created during terminal-harness work on 2026-05-24.

Goal: Let the notch assistant reliably run terminal commands for repo work through Pixel Pane's app-owned tool layer, without hard-coding project-specific paths or commands.

Acceptance:

- [x] Terminal execution is represented as an assistant tool with schema, risk metadata, validation, and source/tool-state recording.
- [x] Commands run only from an existing user-granted folder working directory.
- [x] Explicit commands such as backticked shell commands, `terminal: ...`, `shell: ...`, and `$ ...` can be routed to the terminal tool.
- [x] Common repo tasks such as build/test/lint can be discovered from repo helpers/manifests instead of hard-coded to Pixel Pane.
- [x] Terminal execution captures stdout, stderr, exit code, duration, timeout, and truncation metadata without blocking the UI.
- [x] Risky/destructive commands require visible confirmation before running; privileged shell patterns are blocked.
- [x] Settings explains that terminal commands are local and tied to granted folders.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-24. Added `run_terminal_command` to the assistant tool registry and a bounded `AssistantTerminalCommandExecutor` that runs shell commands off the main actor with timeout and output caps. Added `AssistantTerminalCommandPlanner` for explicit shell requests plus repo task discovery from executable scripts, Makefile targets, package.json scripts, Swift/Cargo/Go manifests, and Xcode projects/workspaces. The Ask flow now routes terminal requests before model calls, auto-runs low/medium-risk commands, and stages a confirmation panel for high-risk commands. Local verification wrapper build succeeded.

### `ASSIST-024` - Fix Follow-Up Granted-Source Routing For Local File Tools

Auto-created during follow-up tool-routing QA on 2026-05-24.

Goal: Make the assistant reliably carry a selected granted source across follow-up file and write requests, especially when the selected local model does not use native tool calls.

Acceptance:

- [x] Ordinal follow-ups such as "what is the second one?" resolve through the app-owned local file tool layer instead of model chat.
- [x] Selecting a single granted folder updates the persistent assistant tool state for later "this folder" requests.
- [x] Ambiguous multi-folder list prompts do not silently set the first folder as the active folder.
- [x] Folder-content requests such as "what is in the second one?" can list the referenced granted folder directly.
- [x] Confirmed local write proposals resolve relative target paths against the active folder when one is selected.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-24. Added granted-source ordinal reference routing to `AssistantLocalFileToolExecutor`, tightened `AssistantToolState.record` so only single-folder results become active, and passed active-folder context into `LocalFileWriteProposalParser`. Added support for explicit `edit file`, `modify file`, `update file`, and `overwrite file` write proposal prefixes. Local verification wrapper build succeeded, and compiled harness checks reproduced the screenshot flow plus relative write routing to the selected grant.

### `ASSIST-025` - Add Terminal-Backed File Discovery And Edit Target Resolution

Auto-created during terminal-harness reliability work on 2026-05-24.

Goal: Make file existence/search questions and follow-up edits reliably use deterministic terminal/file-tool execution inside user-granted folders before falling back to model chat.

Acceptance:

- [x] Specific file discovery questions such as "can you see my resume within this granted folder?" route to a terminal-backed file search instead of a generic grant list or model denial.
- [x] The file search command is discovered from the granted working directory and uses `rg --files` when available with a `find` fallback; it does not hard-code user paths or project-specific file names.
- [x] Terminal file-search output is parsed into structured file sources and persisted into assistant tool state for follow-up reads/edits.
- [x] Generic grant-list answers no longer block specific file discovery prompts when the user asks about a concrete file type or target.
- [x] Confirmed local write proposals can resolve relative or basename targets against recent terminal/file sources and recursively inside granted folders while still requiring visible confirmation before writing.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-24. Added a file-search terminal intent, terminal search planning for concrete file-location prompts, structured parsing of discovered file paths into assistant tool state, and follow-up edit target resolution against recent/nested files. Compiled harness verification against `/Users/nayak/Documents/snehithnayak.github.io` found `resume.pdf` and `resume-latex/resume.tex`, and a no-write edit proposal for `resume.tex` resolved to the nested LaTeX source. Local verification wrapper build succeeded.

### `ASSIST-026` - Add Mode-Independent Agentic File Discovery/Read Loop

Auto-created during agentic harness hardening on 2026-05-25.

Goal: Make Pixel Pane behave like an app-owned local agent harness: run safe terminal/file discovery and read steps before model generation, regardless of whether the selected route is MLX Text, MLX Vision, Apple local text, or Cloud Mode.

Acceptance:

- [x] The same terminal/file tool planning runs before local and cloud model generation.
- [x] Local Mode keeps all terminal execution, file discovery, file reads, and model prompting local.
- [x] App-generated low-risk file discovery commands run automatically; risky or user-authored terminal commands still require confirmation.
- [x] Concrete file-content prompts can fan out terminal searches across multiple granted folders instead of asking the user to choose a folder.
- [x] Discovered files can be read by the app-owned file tool and packed into model context before either local or cloud routing.
- [x] Terminal result UI avoids dumping long generated shell commands by default and shows concise folder/source summaries.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-25. Added batched terminal file-search proposals, automatic low-risk discovery, contextual read selection for discovered files, larger focused file-read previews, and mode-independent prompt packing. Harness verification for `what is in my resume? list my experience` with two granted folders produced two automatic file-search proposals, required no confirmation, found `/Users/nayak/Documents/snehithnayak.github.io/resume-latex/resume.tex`, read that file, and packed it into both Local and Cloud prompts with route-specific labels. `PixelPane/Scripts/verify-debug-build.sh` succeeded.

### `ASSIST-027` - Add General Terminal Agent With Risk-Based Approval

Auto-created during agentic harness hardening on 2026-05-25.

Goal: Let Pixel Pane use the terminal as a model-agnostic agent capability for system inspection, repo work, scripts, and file operations, while automatically running only safe read-only commands and asking permission for commands that can mutate state, run code, touch the network, or affect the system.

Acceptance:

- [x] Terminal planning is owned by the app harness and works regardless of Local Mode, Cloud Mode, or selected local model.
- [x] General safe system-inspection prompts can plan and run terminal commands without requiring a granted folder.
- [x] Explicit shell prompts such as `run ps aux | head -n 5` are detected and preserve the requested command.
- [x] Potentially risky commands, including `mkdir`, `touch`, writes/redirection, installs, builds, scripts, network commands, kill/process-control commands, and `sudo`/privileged commands require visible confirmation.
- [x] Known shell-bomb patterns remain blocked.
- [x] Repo build/test/lint discovery still uses manifests and helper scripts instead of hard-coded project commands.
- [x] Compiled harness checks cover process inspection, explicit commands, bare shell commands, folder creation approval, build-script approval, and privileged-command approval.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-25. Terminal working-directory validation now allows any existing folder, so general computer queries can run from the user's home folder without a file grant. The planner maps common system questions to bounded commands for running processes, disk space, memory, OS info, date/time, and local IP info; it also detects natural folder-creation requests, broader explicit shell commands, and bare shell commands such as `echo harness-ok`. The risk policy now auto-runs low-risk read-only commands but requires confirmation for write-like, build/script, package-manager, network, process-control, privileged, and system-affecting commands. Added `PixelPane/Scripts/assistant-terminal-harness-check.swift`; it passed, as did `PixelPane/Scripts/verify-debug-build.sh`.
- Follow-up 2026-05-25. Fixed system-inspection terminal runs so prompts like `what are the top running processes on my computer?` use a neutral home working directory instead of inheriting the most recent repo/folder context. Added a `systemInspection` terminal intent and a concise process summary formatter so the chat shows top process names/PIDs/CPU/memory instead of dumping raw `ps aux` output. The compiled harness now covers the prior-regression case with recent repo tool state, and `PixelPane/Scripts/verify-debug-build.sh` succeeded.

### `ASSIST-028` - Fix Folder-Selection Continuation Loops In The Agent Harness

Auto-created during agentic harness hardening on 2026-05-25.

Goal: Make granted-folder selection behave like an actual agent tool action instead of a placeholder that can loop when the user replies with an ordinal follow-up.

Acceptance:

- [x] Ordinal replies such as `1st one` after an ambiguous folder prompt select the referenced granted folder and immediately list its top-level contents.
- [x] Ambiguous folder prompts record an explicit pending folder-selection continuation in assistant tool state.
- [x] Resolving that pending continuation clears it, avoiding stale follow-up routing.
- [x] Numeric ordinal aliases such as `1st`, `2nd`, and `3rd` work in the same routing path as word aliases.
- [x] The harness no longer replies with `Inspect /path` placeholders for granted folder selection.
- [x] Compiled harness checks cover the ambiguous-folder and ordinal-selection flow through explicit pending tool state.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-25. `AssistantLocalFileToolExecutor` now turns directory source references into `list_folder` execution directly. Ambiguous folder prompts record a `selectFolderToList` pending continuation with the candidate sources, and ordinal follow-ups resolve against that state instead of a phrase-specific shortcut. The compiled harness check now reproduces the screenshot flow with two folder grants: `what is in this folder?` asks which grant to inspect and records pending state; `1st one` lists the selected folder and clears pending state. `PixelPane/Scripts/verify-debug-build.sh` succeeded.

### `ASSIST-029` - Add Copy-Chat Debug Export For Agent Transcripts

Auto-created during agentic harness debugging on 2026-05-25.

Goal: Let the user copy a complete temporary chat/debug transcript so agent behavior can be pasted into a development thread and improved.

Acceptance:

- [x] The assistant composer exposes a compact `Copy Chat` control.
- [x] The copied transcript includes user prompts, assistant answers, backend labels, and model statistics where available.
- [x] The transcript includes current route, response style, capture context status, granted file sources, active image context metadata, recent tool results, selected/pending source state, and pending terminal or file-write confirmations.
- [x] The export avoids retaining or serializing screenshot image pixels.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-25. Added an icon-only `Copy Chat` button next to the existing Files/History/Image controls in the notch composer. It copies a Markdown-style debug transcript to the pasteboard, including conversation turns and the app-owned tool state needed to debug terminal/file harness behavior. `PixelPane/Scripts/verify-debug-build.sh` succeeded.

### `ASSIST-030` - Harden Dev-Server And Natural-Language Terminal Routing From Copied Transcripts

Auto-created during agentic harness debugging on 2026-05-25.

Goal: Fix copied-transcript regressions where the assistant narrated fake terminal work, failed to start/check local dev servers agentically, or executed natural-language localhost troubleshooting as a shell command.

Acceptance:

- [x] Natural-language localhost troubleshooting such as `http://localhost:3000 doesnt work. is it another port?` routes to a safe listening-port inspection instead of executing the sentence as a command.
- [x] Explicit command-shaped prompts such as `curl http://localhost:3000` still route as terminal commands.
- [x] Site/local-view prompts discover package dev-server scripts from `package.json` without hardcoded project paths.
- [x] Follow-ups such as `yes start it` can use selected/recent granted repo context to propose the discovered dev-server command.
- [x] Dev-server startup runs only after visible confirmation and reports likely `localhost` URLs from listening ports.
- [x] Cloud and local model prompts are instructed not to claim file, terminal, build, or server actions unless Pixel Pane has actual app tool results for them.
- [x] Focused harness checks cover the copied-transcript regressions.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-25. `AssistantRepositoryCommandDiscoverer` now has a `serve` task that detects `dev`, `start`, `serve`, or `preview` package scripts and wraps them in a confirmation-gated background command that emits a log path plus `lsof` listening-port output. Terminal planning now treats local dev-server and localhost troubleshooting as first-class system-inspection flows, while the shell-command classifier distinguishes URL-containing natural-language questions from explicit command-shaped input. Context packing now tells both local and cloud routes not to narrate imagined tool execution. The compiled harness check and `PixelPane/Scripts/verify-debug-build.sh` succeeded.

### `ASSIST-031` - Add Modular Workspace Profiling For Agentic Terminal Planning

Auto-created during agentic harness architecture hardening on 2026-05-25.

Goal: Replace first-match command discovery with an evidence-based workspace profiling layer so terminal planning can choose the right local target across apps, websites, packages, model folders, document folders, image folders, and broad filesystem grants.

Acceptance:

- [x] Workspace profiling is separated from terminal command planning.
- [x] Granted folders are profiled for evidence such as package scripts, static websites, Xcode projects, Swift/Rust/Go/Python projects, model artifacts, image collections, and document collections.
- [x] Terminal build/test/lint/serve planning selects a workspace by prompt/task evidence before discovering commands.
- [x] Static websites without `package.json` can be served locally through a generic local HTTP server.
- [x] Package dev-server startup scopes port discovery to the launched process tree and reports verified local URLs instead of arbitrary system listeners.
- [x] Copied-transcript regression is covered: a personal static website grant wins over an unrelated nested Pixel Pane backend package.
- [x] Focused harness checks cover static website selection, nested backend selection, explicit terminal commands, system inspection, folder creation approval, and folder-selection continuations.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-25. Added `AssistantWorkspaceIntelligence.swift` with `AssistantWorkspaceProfiler` and `AssistantWorkspaceTargetResolver`. The terminal planner now resolves workspace targets before command discovery for build/test/lint/serve tasks, while explicit shell and general system inspection keep their existing neutral working-directory behavior. Static websites are served with `python3 -m http.server 0 --bind 127.0.0.1` and verified via the launched PID's listening socket. Package dev servers now inspect the launched process tree and log-discovered localhost URLs rather than listing every matching port on the machine. The terminal result formatter prioritizes `Verified URL:` lines. The compiled harness check and `PixelPane/Scripts/verify-debug-build.sh` succeeded.

### `ASSIST-032` - Route Delegated File Writes Through Selected-Model Planning

Auto-created during harness architecture review on 2026-05-26.

Goal: Remove the brittle hard-coded write-parser failure path so the selected local/cloud model can choose filenames and content for delegated local write tasks, while Pixel Pane keeps grant validation and confirmation-gated execution.

Acceptance:

- [x] Natural write prompts that delegate creative/practical choices, such as creating a short story in a granted folder, are not rejected for missing explicit content.
- [x] The selected model plans the write draft as structured JSON, including operation, target path, and complete content.
- [x] Pixel Pane validates the model-chosen target against user-granted files/folders before staging any proposal.
- [x] Writes still use the existing visible confirmation UI and no file is changed until Confirm.
- [x] Natural file-write prompts are not misrouted to terminal/test/build command planning.
- [x] Harness checks cover delegated writes, model-planned relative target resolution, and the copied `write "this is a test"` regression.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-26. Added `AssistantWritePlanning.swift` for selected-model write planning prompts, JSON draft parsing, and natural write intent detection. `ResultPanelView` now routes delegated write prompts through the selected backend first, then converts the model draft into the existing confirmation-gated `LocalFileWriteProposal`. `LocalFileWriteProposalParser` now accepts generated drafts and resolves grant-relative paths such as `pixel-pane-test/story.txt` or `story.txt` against active folder state. The terminal planner now exits early for natural file-write prompts so they cannot be mistaken for test commands. The compiled harness check and `PixelPane/Scripts/verify-debug-build.sh` succeeded.
- Follow-up 2026-05-26: moved selected-model write planning before generic app-owned file preflight in Ask routing so delegated writes are not stopped by deterministic path/content clarification or folder-listing fallbacks. The detector now recognizes `md file`/markdown-style natural writes, deictic `write this/these` prompts with recent tool context, and folder-name clarifications after a pending write parser message, including bounded typo matching against granted folder names.

### `ASSIST-033` - Ground Delegated Writes In Current-Session Observations

Auto-created during delegated write QA on 2026-05-26.

Goal: Ensure model-planned file writes can resolve references like "these results" from the active chat without leaking or auto-restoring global chat history into new sessions.

Acceptance:

- [x] Delegated write planning receives recent turns from the current chat before the pending write turn is appended.
- [x] The write-planning prompt explicitly forbids hidden/global history assumptions.
- [x] Referenced prior terminal/model output is available to the selected model for content generation.
- [x] Fresh assistant chats do not auto-load the latest saved assistant session.
- [x] Harness checks cover prior-result write grounding and clean-session prompt behavior.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-26. `AssistantWritePlanningPromptBuilder` now includes bounded current-session prior turns and rules for preserving referenced result/output lines when the user asks to save "these results." The write planner now uses the full default output budget so structured drafts can carry real observed content instead of short placeholders. `ResultPanelView` no longer restores `ChatHistoryStore.latestAssistantSession()` for new assistant panels, and the unused global latest-session helper was removed. Harness checks cover the process-results regression, clean write prompts without prior turns, and preservation of generated result content.
- Follow-up 2026-05-26: write-planning prompts now state that a current user message may be a clarification to a prior write request, and `this` joins `these results`/`that output`/`previous result` as a prior-answer reference. Harness checks cover the copied `write this to a md file within pizel-pane-tess` flow and a `pixel-pane-tests folder` clarification.

### `ASSIST-034` - Route Recent-File Rewrite Follow-Ups Through App-Owned Edit Planning

Auto-created during delegated write/edit QA on 2026-05-26.

Goal: Make follow-ups such as "it's formatted poorly, format it nicer" operate on the recently created/read granted file through the app-owned file tool layer, without relying on a specific local model or executing file paths as shell commands.

Acceptance:

- [x] Staged local write proposals record their target file as recent file context for follow-up edits.
- [x] Formatting/rewrite follow-ups for a recent file route to selected-model write planning instead of plain chat.
- [x] The app reads the recent granted file before asking the selected model to transform its content.
- [x] Bare granted text-file paths route to Local Files reads instead of terminal execution.
- [x] Common generated-write literal newline artifacts such as ` n-` are normalized before staging.
- [x] Harness checks cover the recent-file formatting flow, raw filepath regression, and newline artifact normalization.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-26. `stage_write_proposal` results now include the target file as a source and `AssistantToolState` treats staged write targets as recent files. Formatting/cleanup/rewrite prompts for a recent file now route to selected-model write planning, and `ResultPanelView` first asks the app-owned local file tool to read the recent file so any selected local/cloud model receives actual current content as a snippet. The terminal planner no longer treats non-executable granted file paths as shell commands, while raw file paths are accepted by the read preflight. Generated write content now normalizes the observed ` n-` newline artifact before confirmation. The compiled harness check and `PixelPane/Scripts/verify-debug-build.sh` succeeded.

### `ASSIST-035` - Constrain Model-Planned Writes To The App-Resolved Named Grant

Auto-created during delegated write QA on 2026-05-26.

Goal: Prevent selected models from placing generated files into the wrong granted folder when the user names or slightly mistypes the intended folder.

Acceptance:

- [x] The app resolves folder-like user text to a specific granted folder before accepting a model-planned write target.
- [x] Small folder-name typos such as `pixel-pane-texts` resolve to the closest granted folder such as `pixel-pane-test`.
- [x] If the model proposes an absolute target in a different granted folder, Pixel Pane keeps the filename/content but stages the write inside the app-resolved folder.
- [x] Exact granted folder names continue to work without relying on the selected model.
- [x] Harness checks cover the wrong-grant absolute-target regression.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-26. `AssistantLocalFileToolExecutor` now resolves an explicit preferred write folder from the user request before staging deterministic or generated write proposals. The resolver uses exact granted paths/names first, then bounded edit-distance matching over folder-like tokens so a typo such as `pixel-pane-texts` selects `pixel-pane-test` over the broader `pixel-pane` grant. For generated writes, an absolute model target outside the app-resolved folder is constrained to the proposed filename under the intended folder before grant validation and confirmation. The compiled harness check and `PixelPane/Scripts/verify-debug-build.sh` succeeded.

### `ASSIST-036` - Resolve Named Granted Folders For Local File Listing

Auto-created during folder-listing QA on 2026-05-26.

Goal: Make folder content questions use the app-resolved named grant instead of falling through to model chat or the most recent/broader grant.

Acceptance:

- [x] Named folder content questions route to the Local Files tool before model generation.
- [x] Similar granted folder names prefer the explicit longer match, so `pixel-pane-test` does not resolve to `pixel-pane`.
- [x] Small separator/plural typos such as `pixel=pane-tests` resolve to the closest granted folder.
- [x] A stale `lastListedFolder` cannot override an explicit folder name in the current user prompt.
- [x] Harness checks cover exact, typo, and stale-recent-folder cases.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-26. Folder overview routing now uses the same app-owned preferred-directory resolver introduced for write targeting. The resolver builds folder-like tokens across punctuation boundaries, so `pixel=pane-tests` and `pixel-pane-tests` can match the granted `pixel-pane-test` folder without choosing the broader `pixel-pane` grant. The compiled harness check and `PixelPane/Scripts/verify-debug-build.sh` succeeded.

### `ASSIST-037` - Read Files Referenced From The Last Folder Listing

Auto-created during folder-listing follow-up QA on 2026-05-26.

Goal: Make follow-ups such as "what's inside that txt file?" and "sure do it" read the file exposed by the prior folder listing through the app-owned Local Files tool.

Acceptance:

- [x] Folder listing tool results include visible top-level file sources, not only the folder source.
- [x] Recording a folder-listing result stores visible files as recent file sources for follow-up turns.
- [x] Generic follow-ups that reference a file type, such as `that txt file`, resolve to a unique recent readable file of that type.
- [x] Confirmation-style follow-ups such as `sure do it` can read the unique recent readable file instead of falling through to model chat.
- [x] The implementation is generic over filenames, extensions, granted folders, and selected models.
- [x] Harness checks cover list-then-read and list-then-confirm-read flows.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-26. `list_folder` results now carry visible child files as `File` sources, and `AssistantToolState.record` stores those files as recent file context while still tracking the listed folder separately. Read preflight can resolve app-owned implicit references such as `that txt file`, `read it`, and `sure do it` against the recent readable files before model generation. The compiled harness check and `PixelPane/Scripts/verify-debug-build.sh` succeeded.

### `ASSIST-038` - Prefer Recent Source Observations Over Broad Grant/Search Fallbacks

Auto-created during hard-coded harness cleanup on 2026-05-26.

Goal: Remove the brittle behavior where follow-ups like "what are these files?" ignore the latest folder-list observation and fall back to broad grant inventory or unrelated search snippets.

Acceptance:

- [x] Recent source references are resolved from structured tool state before grant inventory answers.
- [x] Recent source references are resolved before broad file search/model context paths can pollute `lastFileSources`.
- [x] The implementation is generic over filenames, folders, extensions, and selected models.
- [x] A later unrelated file search does not override the latest folder-list source set for deictic source questions.
- [x] Harness checks cover `what are these files?` after a folder listing and after polluted file-search state.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-26. Added a state-first recent-source summary path that detects deictic source references from the current prompt and answers from the latest structured `list_folder` sources. Preflight now checks that recent-source path before selected-model chat, broad grant inventory, and file search. This replaces the observed broad grant fallback without hard-coding product behavior to a specific filename or folder. The compiled harness check and `PixelPane/Scripts/verify-debug-build.sh` succeeded.

### `ASSIST-039` - Prefer Workspace Execution Over Generic Port Inspection

Auto-created during hard-coded harness cleanup on 2026-05-26.

Goal: Fix the brittle terminal-planner priority where a prompt like "build this site and tell me what port its running on locally" scans all listening ports instead of building/serving the recently selected workspace.

Acceptance:

- [x] Workspace execution intents are considered before passive system-inspection shortcuts when the prompt asks to build/run/serve a project or site.
- [x] Localhost troubleshooting without an execution action still routes to safe listening-port inspection.
- [x] "Build this site ... locally/port" resolves against recent tool state such as the last listed granted folder.
- [x] Static websites are served with a generic local server from the selected folder and report a verified localhost URL.
- [x] The implementation is generic over grants, folder names, and selected model route.
- [x] Harness checks cover the copied chat regression and the preserved localhost troubleshooting case.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-26. The terminal planner now gives workspace build/test/lint/serve tasks priority over generic system inspection once the prompt includes an execution intent. `isServeIntent` was narrowed so bare localhost/port troubleshooting does not look like a request to start a server, while "build this site and tell me what port its running on locally" is treated as a local serve task and resolved through the workspace profiler. Added a harness regression using the last listed static site folder and preserved the existing "is it another port?" `lsof` behavior. The compiled harness check and `PixelPane/Scripts/verify-debug-build.sh` succeeded.

### `ASSIST-040` - Replace Hard-Coded Terminal/File Intent Shortcuts With A Model-Planned Action Loop

Auto-created during hard-coded harness cleanup on 2026-05-26.

Goal: Move Pixel Pane closer to Codex CLI/Claude Code by letting the selected model plan tool actions from the user's prompt and current observations, while Pixel Pane remains the model-agnostic executor, safety policy, permission layer, and source tracker.

Acceptance:

- [x] Add a selected-model planning pass that can request bounded actions such as list folder, read file, search files, propose write, run terminal command, or answer directly.
- [x] Keep deterministic code focused on permissions, risk classification, source resolution, validation, execution, and fallback behavior rather than broad natural-language task selection.
- [x] Support a short observe-plan-act loop so the model can inspect a workspace before choosing a build/dev-server command when needed.
- [x] Preserve Local Mode privacy: local model planning, tool execution, observations, and follow-up prompts stay on the Mac.
- [x] Maintain safety: writes, server starts, scripts, installs, destructive commands, and privileged commands require confirmation or are blocked.
- [x] Retire or narrow the existing phrase shortcut lattice once model-planned actions cover the same workflows.
- [x] Add a cross-model harness suite with weak local models, stronger local models, and Cloud Mode over the same task set. Initial route-agnostic planner/parser/policy harness coverage is in place; live weak/strong/cloud route execution is explicitly deferred to `ASSIST-022`.
- [x] App builds successfully.

Notes:

- This is the sprint continuation requested by the user after multiple QA transcripts showed brittle deterministic behavior. The expected product direction is not "more clever hard-coded phrases"; it is an agent loop where better user-selected models produce better plans, and Pixel Pane enforces the local tool contract.
- Implemented 2026-05-26. Added `AssistantActionPlanning.swift` with a JSON action-plan contract and parser for `answer_directly`, `list_grants`, `list_folder`, `search_files`, `read_file`, `stage_write_proposal`, and `run_terminal_command`. The Ask path now runs app-owned facts/confirmations first, then asks the selected local/cloud model to plan tool actions before falling back to the old deterministic router. The planner supports a bounded two-step observe-plan-act loop for list/read/search observations, routes model-planned writes through confirmed write proposals, and sends model-planned terminal commands through the existing risk classifier. Typed follow-ups such as `sure` now execute a pending terminal proposal, fixing the copied transcript process-stop failure. The compiled harness check and `PixelPane/Scripts/verify-debug-build.sh` succeeded. Next recommended story is `ASSIST-021`; full live cross-model route QA remains `ASSIST-022` after source/safety prerequisites.

### `ASSIST-041` - Scope Deictic Project Searches To The Current Observed Folder

Auto-created during hard-coded harness cleanup on 2026-05-26.

Goal: Remove the brittle behavior where a follow-up like "what is this project though?" searches every granted folder and lets unrelated high-scoring snippets override the current folder the user just selected.

Acceptance:

- [x] Deictic project/repo/site/folder questions use the latest observed folder as the search scope when that folder is inside an active grant.
- [x] Broad granted-folder search remains available when the user asks a new unscoped discovery question.
- [x] The selected model receives snippets only from the current observed folder for scoped project-summary follow-ups.
- [x] The implementation is generic over folder names, project names, and selected local/cloud model route.
- [x] Harness checks cover a website folder selected after another repo grant and verify snippets do not come from the unrelated repo.
- [ ] App builds successfully.

Notes:

- Implemented 2026-05-26. `localFileSearchResult` now accepts assistant tool state and scopes search to `lastListedFolder` when the prompt refers to the current local scope. The Ask path passes updated tool state into search, preventing unrelated grants such as the Pixel Pane repo from contaminating "this project" questions about a different listed folder. The compiled harness check and `PixelPane/Scripts/verify-debug-build.sh` succeeded.

### `ASSIST-042` - Polish Notch Assistant Model-Answer Text Formatting

Auto-created during screenshot UI polish on 2026-05-26.

Goal: Make model-generated local-file answers read cleanly without changing the surrounding notch assistant layout.

Acceptance:

- [x] Existing notch assistant shell, prompt row, user bubble alignment, and backend metadata layout are preserved.
- [x] Absolute local paths with dotted folder names are parsed as one path without leftover suffix fragments.
- [x] Local path chips display concise Finder targets inside model answers.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-26 and revised after screenshot QA. The first pass changed broader chat-shell layout and was reverted. The final scoped change preserves the existing notch assistant layout and only keeps model-answer path formatting: absolute-path parsing now preserves dotted folder names such as `snehithnayak.github.io`, trims only trailing sentence punctuation, and renders concise Finder path chips. `PixelPane/Scripts/verify-debug-build.sh` succeeded after the correction.

### `ASSIST-043` - Add App-Owned Folder/Project Profiling Tool

Created during the model-agnostic agentic harness sprint on 2026-05-26.

Goal: Make broad local-scope questions such as "what is in this folder? what is this project?" produce a synthesized profile from app-owned tools instead of stopping at a raw file read.

Acceptance:

- [x] Add `profile_folder` to the model-agnostic action/tool contract.
- [x] Folder/project/site/repo/workspace questions can route to app-owned profiling before plain model chat.
- [x] Profiling uses generic workspace evidence, top-level contents, and common project markers without user-specific hard-coding.
- [x] The transcript regression for a selected website folder returns a synthesized profile and does not stop at `Read granted file`.
- [x] App builds successfully.

Notes:

- Implemented 2026-05-26. Added a `profile_folder` action/tool, app-owned profiling over granted folders, generic evidence from `AssistantWorkspaceProfiler`, README/config marker summaries, and top-level contents. App-owned preflight now resolves ordinal granted-source references before model chat so follow-ups can establish a last listed folder, and project/folder questions can return a synthesized Local Files answer. The action planner can also request `profile_folder`. The compiled harness check verifies the copied transcript failure path returns a website/project profile instead of raw README output. `PixelPane/Scripts/verify-debug-build.sh` succeeded.
- Follow-up 2026-05-26. Fixed the broader terminal-routing root cause exposed by a copied top-processes transcript: app-owned terminal planning now runs before selected-model action planning, preventing platform-specific system-inspection prompts from being handled by invented model shell commands. Model-planned system-inspection commands still sanitize known Linux-style `ps --sort` output into macOS-compatible syntax, and terminal results treat usage/illegal-option stderr as failure even if the shell exits zero. Harness coverage verifies macOS-compatible top-process planning and usage-error failure detection. `PixelPane/Scripts/verify-debug-build.sh` succeeded.

### `ASSIST-044` - Add Agent Task Framing And Bounded Completion Loop

Created during the model-agnostic agentic harness sprint on 2026-05-26.

Goal: Replace the fixed two-step observe-plan-act loop with a task frame and completion check that can continue read-only investigation until the user's goal is actually answered.

Acceptance:

- [ ] Add a task frame with goal, target scope, allowed actions, required evidence, and completion criteria.
- [ ] The runner can perform up to a bounded number of automatic read-only steps before final synthesis.
- [ ] The runner stops for ambiguity, missing grants, risky terminal commands, writes, script execution, or destructive actions.
- [ ] Weak/no-tool model paths can use deterministic task framing and app-owned tools before synthesis.
- [ ] Harness scenarios cover viewing files, summarizing folders/projects, terminal investigation, and failure iteration.

Notes:

- Follow-up 2026-05-26: the copied personal-site transcript exposed the still-open need for a real bounded task/completion loop. As an incremental generic fix, package-based local serve verification now extracts any declared localhost port from the project script, checks whether an existing listener already owns that port, and includes recent log output when no URL can be verified. The action-planning context now includes terminal exit codes so future loop iterations can reason from failed observations. This does not hard-code a user project or port; the harness fixture uses one fixed port only as a regression example. Full task-frame/completion-loop work remains Not Started under this story.
- Follow-up 2026-05-26: Ask routing now gives the selected-model action planner a chance to resolve natural prompts before the deterministic terminal planner runs. The old keyword list no longer decides whether a prompt is "terminal enough"; nontrivial chats with granted or recent tool context route through model planning first, and the planner can choose `answer_directly` or a tool action. The terminal planner remains as executor/fallback and for confirmed pending commands, but phrases such as `kill it` no longer become literal shell commands. Deictic process-control text must be resolved from recent terminal observations, such as a prior PID, before Pixel Pane will stage a confirmation-gated terminal command. Harness coverage verifies that `kill it` is not treated as executable shell while `kill <pid>` still parses and requires confirmation.
- Follow-up 2026-05-26: standardized the permission and recovery behavior exposed by the local-server/kill transcript. Status questions about whether something is already running locally now use read-only listener inspection and do not start servers. Process-control commands always require confirmation, including piped forms like `lsof -ti :8000 | xargs kill -9`. If a confirmed kill fails because the PID is stale, the runner performs one bounded read-only inspection of the referenced localhost port and, if a listener still exists, stages a new confirmation-gated kill for the actual listener instead of auto-killing or stopping after the first failed command. This is generic port/process reasoning, not project-specific hard-coding. Harness coverage verifies local status inspection, `xargs kill` risk classification, stale-kill continuation, and model-first deictic process handling.

### `ASSIST-045` - Add Synthesis-First Answers With Source/Tool Receipts

Created during the model-agnostic agentic harness sprint on 2026-05-26.

Goal: Treat tool outputs as observations and require final synthesized answers for explanatory tasks, with compact receipts for files, folders, and terminal commands used.

Acceptance:

- [ ] Raw tool output is shown directly only for explicit read/show/list requests.
- [ ] Explanatory prompts synthesize observations into a user-facing answer.
- [ ] Answers include concise source/tool receipts without dumping debug state.
- [ ] Prompt-injection text inside files/images/OCR cannot become tool instructions.
- [ ] Harness scenarios verify summarization, project explanation, and command-output explanation across model routes.

### `ASSIST-046` - Add Confirmed File/Script Creation And Execution Workflow

Created during the model-agnostic agentic harness sprint on 2026-05-26.

Goal: Support general file creation/editing and helper-script workflows through the app-owned permission layer without allowing the model to mutate or execute files directly.

Acceptance:

- [ ] File creation/editing remains constrained to granted paths and requires visible confirmation.
- [ ] Script generation is staged as a confirmed file write before any execution is offered.
- [ ] Script execution requires a separate terminal confirmation and bounded output.
- [ ] The harness can iterate after script/build/test failure by reading relevant files and proposing the next safe step.
- [ ] Harness scenarios cover creating notes, rewriting a file, writing a helper script, and running the script after confirmation.

### `ASSIST-047` - Refactor Assistant Harness Runner Out Of UI And Split Modules

Created during the model-agnostic agentic harness sprint on 2026-05-26.

Goal: Reduce harness debt by moving orchestration out of `ResultPanelView.swift` and splitting the monolithic assistant harness into focused modules.

Acceptance:

- [ ] `ResultPanelView` owns UI state/rendering but not planning loops, tool routing, terminal policy, or final synthesis.
- [ ] Tool definitions/state, file tools, terminal tools, workspace profiling, write/script tools, and the agent runner live in focused files.
- [ ] Typed action payloads replace broad `[String: String]` argument plumbing where actions cross subsystem boundaries.
- [ ] Duplicate read-path implementations are collapsed.
- [ ] Existing harness checks and app build continue to pass.
