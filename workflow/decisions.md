# Architectural Decisions

Record decisions here when they affect product direction, technical architecture, privacy, distribution, or long-term maintenance.

## Template

```md
## YYYY-MM-DD - Decision Title

Status: Proposed | Accepted | Rejected | Superseded

Decision:

Context:

Options Considered:

Consequences:

Follow-up:
```

## 2026-04-28 - Direct Distribution

Status: Accepted

Decision:
Pixel Pane v1 targets Direct distribution using Developer ID signing and Sparkle updates.

Context:
The app needs reliable global hotkey behavior, screen capture permissions, and non-sandboxed capabilities that do not fit cleanly with Mac App Store constraints.

Options Considered:
- Direct distribution with Developer ID + Sparkle
- Mac App Store with sandbox constraints

Consequences:
- Payments should use Stripe + RevenueCat, not StoreKit.
- Releases need notarized DMGs and Sparkle update feed.
- The app can use lower-level macOS APIs needed for the core capture loop.

Follow-up:
Set up signing, notarization, Sparkle, and release packaging before beta.

## 2026-04-28 - Minimum macOS

Status: Accepted

Decision:
Pixel Pane alpha and v1 target macOS 15.2+.

Context:
The simple selected-rectangle capture implementation uses `SCScreenshotManager.captureImage(in:)`, available on macOS 15.2+.

Options Considered:
- Keep macOS 15.2+ for a cleaner first app
- Build a more complex ScreenCaptureKit compatibility path for macOS 14/15.0

Consequences:
- The current selected-region capture path stays simple and aligned with the existing code.
- Pixel Pane does not support macOS 14 or macOS 15.0/15.1 in alpha or v1.
- No `SCContentFilter` + `SCStreamConfiguration` compatibility story is needed unless the product decision changes later.

Follow-up:
Keep product positioning, QA, and release requirements aligned to macOS 15.2+.

## 2026-04-29 - Local-First AI Default

Status: Accepted

Decision:
Pixel Pane's default routing for every AI-assisted action (Explain, Simplify, Ask, Translate, Debug, future modes) is on-device. Cloud calls to Claude are an explicit opt-in upgrade.

Context:
macOS 26 ships Apple Foundation Models, an on-device LM available via the `FoundationModels` framework on Apple Silicon. The original intent was to use it for the full local AI path, but the current SDK only exposes text prompt input for Pixel Pane. The local-first product direction still stands; the image-aware portion is amended by the later "Local Vision Runtime Via MLX" decision.

Options Considered:
- Cloud-default (previous direction): faster ship, better quality on day one, but worse privacy story, real per-token cost, and a degraded offline experience.
- Local-default with cloud opt-in (this decision): slightly slower ship because we need a `LocalLLMClient` before any AI action lands, but matches the "local-first, ephemeral, private" pitch the PRD already makes elsewhere.
- Hybrid auto-routing: pick local or cloud per action based on heuristics. Rejected for alpha — opaque to users and harder to test.

Consequences:
- Every AI action ships with a local code path before its cloud path. The cloud path is gated behind a Settings toggle ("Use Cloud Models") and any per-action opt-in (e.g., "Send image to cloud").
- Image context can be sent to the local model without an extra opt-in (nothing leaves the device); sending the image to the cloud requires the explicit toggle plus the per-action consent already specified in `ACT-007`.
- `PRIV-005` (Local/Cloud Mode) flips: Local is the default state, Cloud Mode is the opt-in. The existing "image-context cloud requests require explicit opt-in" remains.
- `ACT-005`, `ACT-006`, `ACT-007`, `ACT-008` acceptance criteria are updated to require a local backend before/alongside the cloud backend.
- A new story `ACT-011` adds the shared local backend protocol so Apple Foundation Models, MLX vision, and later cloud-compatible adapters can share action-side plumbing.
- Quality disclaimers on local responses are still warranted because the on-device model is much smaller than Claude.

Follow-up:
Implement `ACT-011` before any cloud action lands. Update `PRIV-005`, `ACT-005`, `ACT-006`, `ACT-007`, `ACT-008`, PRD Story 2.5, and PRD Story 3.3 to reflect the local-first default plus MLX-based local image setup.

## 2026-04-29 - Alpha Global Hotkey API

Status: Accepted

Decision:
Pixel Pane alpha will implement the default global capture shortcut with Carbon `RegisterEventHotKey`.

Context:
The alpha needs one reliable global shortcut, `Command + Shift + Space`, to start the capture loop from other apps. A `CGEventTap` is more flexible, but it observes lower-level keyboard events and requires Accessibility trust for normal user processes. That adds permission friction and a heavier privacy explanation before the product has proven it needs that power.

Options Considered:
- Carbon `RegisterEventHotKey`
- Core Graphics `CGEventTap`

Consequences:
- The default alpha hotkey should not require Accessibility permission.
- Hotkey code should stay behind a `HotkeyManager` abstraction so the implementation can change later.
- Shortcut validation must avoid reserved combinations and combinations macOS rejects.
- If Carbon proves unreliable in full-screen or foreground-app QA, revisit a `CGEventTap` fallback and add Accessibility recovery UX then.

Follow-up:
Implement `CORE-007` using Carbon `RegisterEventHotKey` and document any QA failures that would justify revisiting `CGEventTap`.

## 2026-04-29 - Foundation Models Image Context Limitation

Status: Superseded by 2026-04-29 - Local Vision Runtime Via MLX

Decision:
Treat `ACT-011` as blocked until the product decides how Local Mode should handle visual image context. The current Xcode 26.4 macOS SDK exposes Apple Foundation Models as a text-prompt, guided-generation, tool-calling API with streaming, availability, context-size, and token-count support, but it does not expose `CGImage`, `NSImage`, image attachment, or other prompt image input in `FoundationModels.LanguageModelSession`.

Context:
`ACT-011`, `ACT-005`, `ACT-007`, and `ACT-008` currently require the local backend to receive both OCR text and the captured image so explanations and debug responses can reason about diagrams, screenshots, and layout without sending anything to the network. Official Apple docs describe `LanguageModelSession`, `Prompt`, `SystemLanguageModel.Availability`, and `streamResponse`, and the installed `FoundationModels.swiftinterface` confirms those text-generation APIs. The same interface contains no image prompt representation.

Options Considered:
- Ship Local Mode AI actions as OCR-text-only for now, with the API surface accepting an optional captured image that the local backend explicitly does not consume until Apple ships image prompt support or another local visual understanding path is chosen.
- Keep `ACT-011` blocked until a true local multimodal framework is available.
- Route image-aware Explain/Debug to cloud only after Cloud Mode and per-action image consent are implemented. This preserves truthfulness but means local default cannot satisfy image-aware acceptance criteria.

Consequences:
- The existing Local-First AI Default decision needs an amendment before coding `LocalLLMClient` as the gate for every AI action.
- It is still reasonable to build the backend protocol, availability recovery, text-only streaming, and prompt budgets, but marking `ACT-011` done would overstate local image understanding.
- Cloud image opt-in requirements remain unchanged.

Follow-up:
Choose whether the next implementation should proceed with OCR-text-only local AI actions or wait for a real local image-understanding API.

## 2026-04-29 - Local Vision Runtime Via MLX

Status: Accepted

Decision:
Pixel Pane will add an optional local MLX vision setup path for image-aware actions. Apple Foundation Models remains useful for lightweight text-only local generation when available, but local image understanding should route through an installed MLX/VLM model instead of waiting for Apple to expose image prompt input.

Context:
The Apple Foundation Models SDK currently blocks local image-context actions because `LanguageModelSession` has no image prompt input. The user wants a setup addition that can discover models already downloaded through Hugging Face, recommend the locally available `mlx-community/Qwen3.6-35B-A3B-6bit` model when present, and offer one-click install for the recommended local vision model when absent. `mlx_vlm.generate` is installed on the current machine; `mlx-run35` was not found on PATH during this check.

Options Considered:
- Keep waiting on Apple Foundation Models image input.
- Use cloud image understanding only.
- Add an optional local MLX/VLM runtime for image actions while preserving Apple Foundation Models for text-only local actions.

Consequences:
- `ACT-011` is no longer blocked on Apple image input alone; it should become a hybrid local backend protocol that can route text-only work to Apple Foundation Models and image-aware work to MLX when configured.
- A new setup story is needed to discover Hugging Face cache models, recommend compatible MLX vision models, install them with explicit user consent, and show disk/RAM expectations before download.
- MLX model downloads are large and should never happen silently. The setup UI must clearly state model source, approximate size, license, local path, and that model execution is local.
- The app should not claim image-aware Local Mode is available until an MLX vision model is installed and a smoke test passes.

Follow-up:
Add stories for MLX model discovery/setup and the MLX vision backend adapter, then update `ACT-011` acceptance to define the shared local backend protocol.

## 2026-04-29 - Cloud Proxy Contract And Hosting

Status: Accepted

Decision:
Pixel Pane's first cloud-upgrade backend will be a Cloudflare Workers proxy in front of the Anthropic Messages API. The macOS app talks only to Pixel Pane endpoints documented in `docs/backend-api.md`; it never stores provider API keys or constructs final provider prompts.

Context:
The local-first action rail is now implemented. The remaining Epic 2 cloud client story needs a stable API contract before code can safely route opted-in cloud actions. The proxy must stream responses, enforce server-side limits, keep Anthropic keys out of the app, and preserve the privacy promise that OCR text, screenshots, prompts, questions, and model output are not logged by default.

Options Considered:
- Cloudflare Workers: streaming-friendly edge runtime, simple secret storage, low operational overhead for an early proxy.
- Fly.io: more control over long-running processes and regional placement, but more operational surface for the first backend.
- Vercel/serverless functions: familiar deployment model, but less clearly aligned with the streaming proxy and edge/runtime constraints already documented.

Consequences:
- `FOUND-003` can define a concrete `/v1` API contract for the macOS client and backend.
- `ACT-003` can implement a client shell against Pixel Pane's normalized SSE events instead of forwarding raw Anthropic event details into app code.
- The backend owns provider prompt construction and model choice, so prompt/model upgrades do not require a macOS app release.
- Production logs may include request IDs, action names, status, latency, plan, token counts, and byte sizes, but not user content.

Follow-up:
Implement `ACT-003` against `docs/backend-api.md`, then implement the Worker MVP in `FOUND-004` and the anonymous token flow in `FOUND-005`.

## 2026-04-29 - Secret Ownership For Cloud Backend

Status: Accepted

Decision:
Pixel Pane stores only anonymous device IDs and Pixel Pane session/auth tokens in the macOS app Keychain. Provider API keys, signing secrets, payment secrets, and update-signing secrets are never shipped in the app and belong in backend, release, or vendor secret stores.

Context:
Cloud Mode now has a Worker proxy, app token flow, and cloud client shell. The app needs enough local state to authenticate Pixel Pane requests and enforce anonymous quota, but it must not expose Anthropic, Stripe, RevenueCat, Cloudflare, Sparkle, notarization, or signing secrets in the bundle or repository.

Options Considered:
- Store provider keys in the app for faster prototyping. Rejected because extraction from a distributed macOS app is straightforward and would break the cloud-cost and privacy model.
- Store only Pixel Pane tokens/device identity in Keychain and keep provider/vendor secrets server-side. Accepted.
- Require full user accounts before any cloud requests. Deferred; anonymous device tokens are enough for the MVP free tier.

Consequences:
- `CloudAuthTokenProvider` may store an anonymous device UUID and short-lived Pixel Pane bearer token in Keychain.
- `CloudAIBackend` sends only Pixel Pane bearer tokens to the Worker, never provider keys.
- Worker secrets include `ANTHROPIC_API_KEY` and `APP_AUTH_SECRET`.
- `.env` and `.env.*` remain ignored, with `.env.example` tracked for local setup documentation.
- Future Stripe, RevenueCat, Sparkle, notarization, and Developer ID secrets must be documented before use and kept out of git.

Follow-up:
Before real deployment, provision Cloudflare secrets/KV and complete release/payment secret docs in the relevant foundation or monetization stories.

## 2026-05-06 - Single Cloud Mode Consent Toggle

Status: Accepted

Decision:
Pixel Pane will use one Cloud Mode toggle instead of separate text-cloud and image-cloud toggles. When Cloud Mode is off, actions run locally. When Cloud Mode is on, cloud-capable actions may send OCR text and captured image context to the Pixel Pane cloud proxy when the selected action supports image input.

Context:
The two-toggle Settings UI was confusing during manual QA. The user explicitly asked to collapse "Use Cloud Models" and "Allow captured images for cloud actions" into one realistic control.

Consequences:
- Settings presents one "Use Cloud Mode" toggle.
- Existing installs are normalized on launch: if Cloud Mode was already enabled under the old two-toggle model, image context is enabled with it.
- The backend still receives explicit `image.user_consented = true` only when Cloud Mode is enabled and the action supports image upload.
- Local-first remains the default because the single Cloud Mode toggle defaults off.

Follow-up:
If future account or plan tiers need separate image privacy controls, reintroduce them with clearer copy and an explicit product reason.

## 2026-05-18 - Telemetry Deferred For Alpha

Status: Proposed

Decision:
Telemetry is deferred for now. It is not a requirement for the app during the current alpha distribution work.

Context:
The app can continue without analytics. Telemetry may become useful later for beta diagnostics and product reliability, but it should not block Sparkle, release, app quality, or core product work.

Options Considered:
- Choose PostHog now.
- Choose Plausible/custom telemetry now.
- Defer telemetry and keep the decision visible for beta planning.

Consequences:
- No analytics SDK or event collection should be added during current alpha work.
- `FOUND-008` stays open as a visible future decision instead of being treated as a current app requirement.
- If telemetry is revisited, it must be opt-in and exclude screenshots, OCR text, prompts, questions, result text, and clipboard contents.

Follow-up:
Revisit before beta only if product or reliability diagnostics need it.

## 2026-05-21 - Sparkle Release Update Process

Status: Accepted

Decision:
Pixel Pane's Direct distribution update channel will use Sparkle with an HTTPS appcast at `https://pixelpane.app/appcast.xml` once the production domain is live. Beta builds may temporarily use an HTTPS release-site URL until the custom domain is ready. Sparkle EdDSA private keys are release secrets and are stored only in the release secret store, never in git, app source, backend secrets, or documentation.

Context:
The signing and entitlement baseline is documented, but beta readiness needs a concrete update plan so release packaging, app metadata, and secret handling are consistent.

Options Considered:
- Production appcast on the Pixel Pane domain from the start.
- Temporary beta appcast on an existing HTTPS release-site host, then move to the production domain.
- No appcast until public launch.

Consequences:
- Release documentation now treats Sparkle appcast generation as part of the normal Developer ID/notarized DMG checklist.
- The app should embed exactly one channel URL per build channel; start with a beta channel and add stable later only when needed.
- Sparkle's public EdDSA key may be embedded in app metadata, but the private key stays with release-only credentials.
- Backend hosting and Cloudflare Worker secrets are separate from update-signing material.

Follow-up:
When Sparkle is integrated in code, add the framework, set `SUFeedURL`, set the public EdDSA key, and verify an update from one signed/notarized beta build to the next on a fresh Mac.

## 2026-05-21 - Notch-Native Local Assistant

Status: Accepted

Decision:
Pixel Pane's primary surface will become a hover-open notch assistant: a native local ChatGPT-style chatbox that can work without capture context, while screenshots/OCR become optional context attached by the capture flow. Local Mode remains the default, and Cloud Mode remains an explicit routing choice.

Context:
The user wants Pixel Pane to stay in the notch window and behave like a quick native assistant, not a separate full chat application. A new capture should start a fresh contextual chat, but the user should also be able to hover the notch and ask plain questions with no selected region.

Consequences:
- The expanded notch should default to Ask/chat behavior.
- Capture results should open Ask-first instead of forcing smart-default Translate/Explain/Simplify.
- Chat persistence can wait until the UX is validated.
- Local file access should be added as explicit user-granted tools, with read/search before create/edit.
- Settings should expose Local vs Cloud as a single mode choice so users do not think both modes can be active at the same time.

Follow-up:
Implement user-granted read/search file tools, then add confirmed create/edit tools and local chat persistence.

## 2026-05-21 - Chat-Only Notch Surface

Status: Accepted

Decision:
Pixel Pane's visible notch UI should be a single chat assistant, not an action-tab utility. Extract, Translate, Explain, and Simplify remain capabilities the model can perform from natural language and capture context, but they should not appear as top-level tabs in the notch surface.

Context:
The action rail made the app feel like an OCR workflow tool. The stronger product direction is a private Mac-native assistant that lives in the notch, sees user-selected context, and answers or acts through chat.

Consequences:
- The result panel now forces Chat as the visible mode.
- The notch surface no longer shows the action rail or footer controls.
- Captured OCR/screenshot context is represented as a context chip and prompt input, not as separate action tabs.
- Older action code can remain behind the scenes while the product validates the chat-only surface.

Follow-up:
Add local chat persistence, then user-granted file read/search tools, and later confirmed local file creation/editing.

## 2026-05-21 - User-Granted Read-Only Local Files

Status: Accepted

Decision:
Pixel Pane's notch assistant can inspect local files only through explicit user-granted file or folder access. The first implementation is read-only: it can list granted locations, scan text-like files, search for relevant snippets, and attach bounded context to chat. It cannot create, edit, delete, or move files.

Context:
The product direction is a local-first native assistant that lives in the Mac notch and can help with the user's computer. File access is powerful enough that the trust model should start with visible, explicit grants and read-only behavior before introducing confirmed write tools.

Consequences:
- Settings has a Files area for granting and removing local file/folder access.
- The chat surface can add file/folder access inline without leaving the notch workflow.
- In Local Mode, file snippets remain on the Mac.
- In Cloud Mode, relevant snippets may be sent to Pixel Pane Cloud because the user explicitly selected cloud routing.
- Write operations are deferred to `ASSIST-003` and must require explicit confirmation naming the target path.

Follow-up:
Add local chat persistence next so file-aware conversations can feel continuous, then implement confirmed create/edit tools as a separate trust-building slice.

## 2026-05-21 - Local Chat History Without Screenshot Retention

Status: Accepted

Decision:
Pixel Pane stores chat transcripts locally so the notch assistant can resume recent conversations. Capture chats store only message text, backend labels, and a lightweight "Screen region" context label. Captured screenshots are not persisted in chat history.

Context:
The assistant should feel continuous, but the product is local-first and screen captures can contain sensitive information. Persisting screenshots by default would change the privacy model and should require a separate explicit retention feature later.

Consequences:
- Plain assistant chats can reopen from local history.
- Capture chat transcripts can be revisited, but the original pixels are not available after the capture session ends.
- Settings must provide clear local history deletion.
- Future screenshot retention, summaries, or searchable memory should be opt-in and tracked as a separate story.

Follow-up:
Expand local text model setup so persisted chat is useful even without Apple Foundation Models or a configured vision model.

## 2026-05-21 - Local Text Runtime Via MLX

Status: Accepted

Decision:
Pixel Pane Local Mode can use a selected text-only MLX model for chat and text generation when `mlx_lm.generate` is available and setup validates a usable model folder. MLX image understanding remains a separate capability that requires `mlx_vlm.generate` and a vision-capable model.

Context:
The notch assistant should remain useful even when Apple Foundation Models is unavailable, disabled, or not ready. The previous MLX setup path showed text-only cached models but rejected them because it was designed only for VLM setup.

Consequences:
- Settings must distinguish Text, Vision, Text + Vision, and Unsupported MLX model capabilities.
- Text-only MLX model selection can satisfy local chat/text generation without enabling screenshot vision.
- Image-aware Local Mode remains gated on a vision-capable model and the MLX-VLM runtime.
- Apple Foundation Models remains the fallback text backend when no text-capable MLX model is selected.

Follow-up:
Manual QA should validate one selected text-only MLX model through a plain notch chat turn and one selected Text + Vision model through a capture-context chat turn.

## 2026-05-21 - Confirmed Local File Writes

Status: Accepted

Decision:
Pixel Pane may create or edit local files only after the assistant stages a proposal inside a user-granted file or folder location and the user confirms a UI that names the exact target path. Model output must not directly mutate local files.

Context:
The notch assistant now has read/search access to user-granted local files. Adding writes is useful, but it changes the trust model and must be visibly constrained.

Consequences:
- Local writes are limited to user-granted file/folder locations.
- The assistant can propose creates, appends, and targeted replacements.
- The app shows a confirmation panel with the operation and target path before any write.
- Cancel leaves the file system unchanged.
- Cloud Mode does not execute remote write tools; confirmed file writes still run locally.

Follow-up:
Manual QA should validate a create, append, replacement edit, and cancel path against a temporary granted folder.
