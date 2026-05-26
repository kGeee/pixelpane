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
Pixel Pane stores chat transcripts locally so the notch assistant can resume recent conversations. Capture chats initially stored only message text, backend labels, and a lightweight "Screen region" context label. Captured screenshots are not persisted in chat history. This decision is extended by the 2026-05-24 assistant tool-state decision, which allows bounded source/snippet/OCR metadata but still forbids screenshot or attached-image pixel retention by default.

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

## 2026-05-22 - Local Mode Requires A Validated MLX Model

Status: Accepted

Decision:
Pixel Pane should not allow AI Mode to remain Local when no MLX model is selected. Clearing the selected MLX model or choosing the explicit "No MLX model selected" state moves routing to Cloud Mode, and Local Mode can be selected again only after a model has been validated.

Context:
Settings previously allowed the confusing combination of "No MLX model selected" and "Local". Even though Apple Foundation Models can still be a local text fallback internally, the visible routing choice should map to a concrete user-selected local model.

Consequences:
- Settings must keep local setup reachable when Cloud Mode is active only because no local model exists.
- The Local AI Mode control is disabled until setup has an active selected model.
- Clearing local model selection returns the assistant to Cloud Mode instead of leaving a contradictory Local/no-model state.

Follow-up:
Manual QA should verify Clear Selection, the "No MLX model selected" picker row, app relaunch with no saved model, and switching back to Local after validating a model.

## 2026-05-22 - Hybrid Warm MLX Text Runtime

Status: Accepted

Decision:
Pixel Pane may use a warm `mlx_lm.server` helper for local text chat only when the helper is already healthy. Active user chat requests must not block while starting or health-checking the warm server. If no matching healthy warm server is available, the app uses the existing one-shot `mlx_lm.generate` path, then starts or refreshes the warm server in the background after the one-shot response finishes.

Context:
Directly waiting on `mlx_lm.server` startup inside the chat request caused the notch UI to remain on "Thinking..." while localhost health checks returned connection refused. On large local models, startup/loading can take long enough that Xcode or the OS kills the debug session before the server reaches listen state.

Consequences:
- First/cold local text turns use the reliable one-shot path.
- Follow-up turns can be fast when the background warm server is ready.
- Warm startup failures no longer block the active chat turn.
- The helper remains localhost-only and is still stopped on model changes, Clear Selection, idle timeout, and app termination.

Follow-up:
Manual QA should send one cold local prompt, wait for the response, then send a follow-up after the background warm server has had time to become healthy. If warm startup remains unreliable for large models, consider an external launcher/worker process with explicit readiness telemetry instead of starting the server from the app process.

## 2026-05-22 - Ephemeral Capture Last Result

Status: Accepted

Decision:
Pixel Pane may keep the last capture's OCR text and metadata for the menu-bar "Show Last Result" convenience path, but it must not keep the captured screenshot image in `AppState.lastResult`. The active panel may hold the `CGImage` only while the panel is open so capture-context actions can run, and panel close releases that active reference.

Context:
The privacy promise says screenshots are processed in memory by default and discarded when the panel closes. Keeping `AppState.lastResult` as the full `CaptureResult` retained the screenshot beyond the active panel lifetime, even though chat history persisted only text.

Consequences:
- "Show Last Result" can reopen the last OCR/text result, but cannot rehydrate screenshot/image context.
- Capture-context image actions remain available while the active result panel is open.
- Future screenshot thumbnails or capture history must be explicit opt-in work, not a side effect of the normal capture path.

Follow-up:
Manual QA should confirm closing a capture panel and reopening "Show Last Result" does not show image-aware context chips or allow image-backed local/cloud analysis from the retained result.

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

## 2026-05-24 - App-Owned Model-Agnostic Assistant Harness

Status: Accepted

Decision:
Pixel Pane should add an app-owned assistant harness that mediates tools, permissions, context packing, image inputs, file access, deterministic app-state answers, and confirmed writes before any model route receives context. Model adapters declare capabilities; they do not own permission decisions.

Context:
The notch assistant now supports local MLX text, MLX vision, Cloud Mode, deterministic app-state answers, user-granted file read/search, and confirmed local file writes. As users choose different local models, the app cannot rely on each model to know whether it can access files, decide when to search, or safely handle images and writes. Provider and local-model research shows tool use is a request/execution loop: models propose tool calls or structured intents, while application code runs tools and returns results.

Options Considered:
- Keep adding model-specific prompt heuristics in the Ask flow. Rejected because it creates stale/hard-coded behavior and weakens consistency across user-set models.
- Require native tool-calling support from every model. Rejected because many useful local models and command-line adapters do not reliably support native tool calls.
- Add one app-owned router and capability contract, with native tool calling as an optional adapter optimization. Proposed.

Consequences:
- The next assistant sprint starts with `ASSIST-016`, a capability contract and central tool router.
- File access, image context, app-state answers, and write proposals are app tools with deterministic permission checks.
- Native tool-calling models may receive schemas, but no model is trusted to enforce file grants or side-effect policy.
- Retrieved file/OCR/image content is untrusted data and must be isolated from instructions.
- Chat UI should expose concise source/tool metadata so users can see what Pixel Pane used.

Follow-up:
Implement `ASSIST-016` through `ASSIST-022` before broadening assistant automation beyond user-granted files/images and confirmed local writes.

## 2026-05-24 - Persistent Assistant Tool State And Source-Aware Packing

Status: Accepted

Decision:
Pixel Pane may persist bounded per-chat assistant tool state alongside chat transcripts: source metadata, last listed folder, recent file snippet previews, recent tool summaries, and active visual/OCR context metadata. Image pixels are still transient and are not stored in chat history. Context sent to models must be packed by source group and retrieved file/OCR/image/tool text must be labeled as untrusted data.

Context:
The assistant needs reliable follow-ups across weak/no-tool local models. After a user lists or grants a folder, a follow-up such as "what is Snehith's experience?" should search/read likely granted files from the previous folder context instead of relying on model memory or native tool calls. At the same time, file and OCR content can contain hostile instructions, so source boundaries must be explicit before any model sees the data.

Consequences:
- Follow-up planning can use app-owned state instead of asking the model whether it has access.
- Chat history may contain bounded source/snippet/OCR excerpts needed for continuity, but not screenshot or attached-image pixels.
- Native model tool calling remains an optional adapter optimization only after route capability metadata proves support.
- `ASSIST-020` should expose concise source/tool state in the UI so users can see what Pixel Pane used.

Follow-up:
Run the `ASSIST-022` cross-model matrix after source transparency and prompt-injection hardening land.

## 2026-05-24 - Bounded Local Terminal Tool

Status: Accepted

Decision:
Pixel Pane may expose terminal execution to the notch assistant only as an app-owned tool. Terminal commands must run from an existing user-granted folder working directory, with bounded runtime and output capture. High-risk or destructive commands require visible user confirmation before execution, and privileged shell patterns are blocked.

Context:
Repo work often requires real terminal feedback: builds, tests, linting, git status, and project-specific helper scripts. The model should be able to benefit from that feedback, but it must not receive unchecked shell access or hard-code Pixel Pane-specific commands. The existing assistant harness already owns local file grants, write confirmation, context packing, and tool state, so terminal execution belongs behind the same contract.

Consequences:
- Terminal output is local tool output and is treated as untrusted data in model context.
- Commands default to user-granted folder working directories; the model cannot pick arbitrary filesystem roots.
- Common repo commands are discovered from scripts and manifests where possible instead of hard-coded to this repo.
- The UI must show a confirmation panel for high-risk commands and record terminal runs in assistant tool state.
- This is not autonomous computer control or unbounded shell access.

Follow-up:
`ASSIST-020` should include terminal tool runs in the source/tool-use transparency UI, and `ASSIST-021` should include terminal-output prompt-injection and destructive-command QA cases.

## 2026-05-24 - Terminal-Backed File Discovery Before Model Chat

Status: Accepted

Decision:
Pixel Pane should route specific local-file discovery questions through deterministic terminal-backed search inside user-granted folders before model chat or generic grant-list answers. Discovered paths should become structured file sources in assistant tool state so follow-up reads and confirmed edit proposals can resolve the same files.

Context:
The assistant had access to `/Users/nayak/Documents/snehithnayak.github.io` but still answered a resume question as if it could not read the nested resume source/PDF, then fell back to listing granted folders. This shows that model chat and generic grant inventory are not enough for reliability. Open-source coding agents such as Cline, OpenHands, and aider converge on the same principle: terminal/file actions should be explicit tool observations that the harness feeds back into state, not hopeful model narration.

Consequences:
- File discovery is an app-owned action, not a model claim.
- The terminal tool may run low-risk search commands such as `rg --files`/`find` in granted folders without hard-coded paths.
- Terminal file-search output is treated as untrusted data but can update source state for follow-up file reads and staged write proposals.
- Confirmed writes remain confirmation-gated and limited to granted folders even when a recent terminal search found a target.
- Generic "what files can you view?" answers remain available, but they should not block concrete "can you see/find X?" searches.

Follow-up:
Add these terminal discovery cases to the `ASSIST-022` cross-model QA matrix and expose terminal/file sources in `ASSIST-020` source transparency UI.

## 2026-05-25 - Mode-Independent Agentic Tool Loop

Status: Accepted

Decision:
Pixel Pane's assistant harness should own the agentic loop independently of the selected model route. The app runs deterministic safe tool steps such as terminal-backed file discovery, local file reads, source tracking, and context packing before handing a prompt to MLX Text, MLX Vision, Apple local text, or Cloud Mode. Local Mode keeps every part of that loop local.

Context:
The same user prompt could fail differently in Local Mode and Cloud Mode because the selected model was still being asked to infer when tools should run. That is backwards for a reliable local assistant. OpenCode and pi use model-agnostic agent runtimes where provider choice is separate from file/terminal/session orchestration; OpenHands and Cline likewise keep tools as explicit actions/observations. Pixel Pane needs the same split in Swift: model route decides language quality, not whether local tools actually execute.

Consequences:
- Local/Cloud mode changes model routing only; it does not change tool availability, tool planning, or file grant enforcement.
- App-generated low-risk discovery commands may run automatically inside user-granted folders.
- User-authored, destructive, privileged, or write-like terminal commands still require confirmation or are blocked.
- File discovery can fan out across multiple granted folders when the user asks for a concrete target.
- File reads are app-owned observations and can be packed into Local or Cloud prompts with route-specific privacy labels.
- Terminal/file UI should show concise action summaries and sources, not raw generated shell scripts unless needed for transparency.

Follow-up:
`ASSIST-020` should expose these automatic agent steps as compact source/tool chips, and `ASSIST-022` should test the same prompts across Local Mode, Cloud Mode, and weak/no-tool local models.

## 2026-05-25 - General Terminal Agent With Risk-Based Approval

Status: Accepted

Decision:
Pixel Pane may expose broad terminal execution through the same app-owned agent harness across Local Mode and Cloud Mode. The harness, not the selected model, decides when a terminal command can run automatically, when it needs confirmation, and when it must be blocked. Safe read-only observation commands can run without a granted file folder; potentially risky commands require visible confirmation before execution.

Context:
The assistant needs to answer general computer and repo questions such as "what are the top running processes?", "run this script", "build this project", and "create a folder" without being limited to file-search flows. OpenCode, pi, Cline, and OpenHands all separate provider/model choice from terminal and filesystem orchestration. Pixel Pane should use the same architecture: local models and cloud models produce language, while the Swift harness owns command planning, command execution, permission prompts, tool observations, and privacy routing.

Consequences:
- Local Mode remains fully local: terminal planning, execution, output capture, context packing, and model prompting stay on the Mac.
- Cloud Mode uses the same local tool loop but only receives app-packed observations after local execution.
- Existing-folder working directories are allowed even when they are not user-granted file folders, so general system inspection can run from the user's home folder.
- Low-risk read-only commands such as process, disk, OS, date/time, and explicit read-only shell inspection may auto-run.
- Write-like commands, builds, scripts, package installs, network commands, process control, privileged commands, and system-affecting commands require visible confirmation.
- Known shell-bomb patterns remain blocked.
- Confirmation UI needs continued polish under `ASSIST-020` so terminal runs are transparent without dumping long shell text into the chat.

Follow-up:
`ASSIST-022` should promote `PixelPane/Scripts/assistant-terminal-harness-check.swift` into the cross-model QA matrix, including Local Mode, Cloud Mode, and weak/no-tool local models.

## 2026-05-25 - Evidence-Based Workspace Profiling For Agentic Terminal Planning

Status: Accepted

Decision:
Pixel Pane should profile granted folders and candidate nested workspaces before planning build/test/lint/serve terminal commands. The app-owned harness should choose a target workspace from evidence such as manifests, project files, static website markers, model artifacts, image/document collections, prompt terms, and recent tool state before command discovery runs.

Context:
The assistant incorrectly served Pixel Pane's nested backend package when the user asked to build/view a personal website because the old planner grabbed the first `package.json` it found. That is not how a reliable coding agent behaves. Agentic systems such as ChatGPT-style code interpreters, OpenCode, and Hermes-like local agents separate target selection from command execution: first identify the workspace/artifact, then plan the command, then verify the observation.

Consequences:
- Terminal planning no longer treats "first manifest found" as the target.
- Static websites, Xcode apps, package backends, model folders, image folders, and document folders can be recognized as different workspace shapes.
- Serving a site can use a generic local static server when no package dev script exists.
- Dev-server port reporting must prefer verified URLs from the launched process/logs over arbitrary machine-wide listeners.
- Broad filesystem grants require bounded, shallow profiling with skipped dependency/system folders rather than unbounded scans.

Follow-up:
`ASSIST-022` should expand the QA matrix to include target-selection cases for static websites, nested package apps, Xcode apps, model folders, image folders, and broad home/Documents grants.

## 2026-05-26 - Selected Model Plans Delegated Local Writes

Status: Accepted

Decision:
When the user asks Pixel Pane to create or edit a local file and delegates choices such as filename, subject, or content, the selected model route should plan the write draft. Pixel Pane then validates the model-selected target against user-granted locations and stages a confirmation-gated local write proposal. Model output still never mutates files directly.

Context:
The prior harness rejected prompts like "create a txt file inside this folder containing a short story; you can pick what the story is about" because the deterministic write parser required the user to provide both a path and exact content. A follow-up like `write "this is a test" inside the text file` could then fall into terminal/test routing. That is the wrong split for a Codex-like local assistant: the model should reason about underspecified tasks, while the app owns permissions, observations, validation, and side effects.

Consequences:
- Local model choice now affects delegated file-write planning quality.
- Pixel Pane keeps the safety boundary: only granted files/folders are valid targets and the user must confirm before any write.
- The deterministic parser remains only for exact user-authored write commands; delegated tasks go through model planning.
- Natural file-write prompts are excluded from terminal command planning so they cannot be misread as build/test/run requests.

Follow-up:
Generalize this planning boundary beyond writes into a fuller Codex-like action/observation loop where the selected model can request file reads, edits, and terminal commands, while Pixel Pane remains the executor and policy layer.

## 2026-05-26 - Current Session Is The Assistant Memory Boundary

Status: Accepted

Decision:
Pixel Pane should not auto-inject global or latest-chat history into a fresh assistant chat. Current-session turns may be used to resolve follow-up references such as "these results," and saved chats may be reopened explicitly, but a new assistant chat starts with empty turns and empty assistant tool state unless it is created from a screen capture context.

Context:
Delegated file-write planning improved by asking the selected local/cloud model to draft the target and content, but a QA chat revealed an under-contexted write: after a terminal process-list answer, the user asked to create a file "with these results" and the planner did not receive the prior answer, so the model hallucinated generic test results. At the same time, the app still auto-restored the latest saved assistant session for fresh chats, which is a hidden global-memory behavior the user does not want.

Consequences:
- Model-planned writes receive bounded prior turns from the active chat only.
- The write-planning prompt explicitly tells the selected model not to assume hidden or global chat history.
- Fresh assistant panels no longer restore the latest saved assistant session.
- Chat history remains local and per-session, available through explicit history selection and clearing.
- Capture-context chats can still carry their capture/OCR context and same-session follow-ups without retaining screenshot pixels in history.

Follow-up:
`ASSIST-020` should expose current-session tool/result provenance clearly, and `ASSIST-022` should include clean-new-chat regressions so no prompt path accidentally reintroduces global history.

## 2026-05-26 - Recent File Rewrite Follow-Ups Stay App-Owned

Status: Accepted

Decision:
When the user asks to format, clean up, polish, or otherwise rewrite a recently created/read granted file, Pixel Pane should resolve the target file from app-owned tool state, read its current content through the Local Files tool, and ask the selected model only for transformed replacement content. The result must still become a confirmed local write proposal before any file changes.

Context:
A QA chat successfully created a file from prior terminal output, but the follow-up "it's formatted poorly. please format it nicer." fell through to ordinary model chat because the target file was not recorded as recent file context. When the user then pasted the file path, the terminal planner treated the path as a command and zsh returned permission denied. This exposed a model-agnostic harness issue: file edit follow-ups need app-owned target resolution and file reads, not model guesses or shell execution.

Consequences:
- Staged write proposals record their target file as recent source context for follow-up edits.
- Formatting/rewrite follow-ups can route to selected-model write planning across local/cloud models.
- The app reads the granted file before model transformation so the model receives actual current content.
- Bare non-executable granted file paths are file references, not terminal commands.
- Weak local models may produce lower-quality formatting, but target resolution, file reads, grant validation, and confirmation remain independent of model choice.

Follow-up:
`ASSIST-022` should include cross-model QA for create-then-format, raw filepath reads, and exact-file rewrite confirmation behavior.

## 2026-05-26 - App Resolves Named Write Grants Before Model Targets

Status: Accepted

Decision:
When a user names a folder for a delegated write, Pixel Pane should resolve the intended granted folder in app code before accepting the selected model's target path. If the model proposes a path in a different grant, Pixel Pane should preserve the filename and content but constrain the staged write to the app-resolved folder.

Context:
A QA chat asked to create a text file in `pixel-pane-texts` while grants included `/Users/nayak/Documents/pixel-pane` and `/Users/nayak/Documents/pixel-pane-test`. The selected model produced a plausible file with the correct content but staged it in `/Users/nayak/Documents/pixel-pane/top_processes.txt`, because the app was trusting the model to choose among granted folders. This should be model-agnostic harness logic instead.

Consequences:
- The app resolves exact granted paths/names first, then uses bounded edit-distance matching for folder-like tokens.
- A typo such as `pixel-pane-texts` resolves to `pixel-pane-test` instead of the broader `pixel-pane` grant.
- Selected models still choose filename/content for delegated writes, but they no longer own the grant selection when the user names a target folder.
- Confirmation remains required before any file is written.

Follow-up:
`ASSIST-022` should include cross-model tests for multiple grants with similar names, typos, exact folder names, and model-proposed absolute paths in the wrong grant.

## 2026-05-26 - App Resolves Named Folder Listings Before Model Chat

Status: Accepted

Decision:
When a user asks what is inside a named granted folder, Pixel Pane should resolve the intended folder in app code before model generation. The resolver should prefer exact and longer folder-name matches over prefixes, support bounded typo matching, and let explicit current-prompt folder names override stale recent-folder state.

Context:
A QA chat asked what was in `pixel=pane-tests` and then clarified `pixel-pane-test`, but the assistant first fell through to local model chat and later listed `/Users/nayak/Documents/pixel-pane` instead of `/Users/nayak/Documents/pixel-pane-test`. The root cause matched the write-targeting issue: folder selection was still brittle app logic, with prefix matching that let `pixel-pane` win before `pixel-pane-test`.

Consequences:
- Folder listing correctness no longer depends on the selected local/cloud model.
- The same named-grant resolver is used for folder listings and delegated writes.
- Typos such as `pixel=pane-tests` can resolve to `pixel-pane-test` without granting broader access.
- Recent folder state remains useful for "this folder" follow-ups, but explicit names in the current prompt take precedence.

Follow-up:
`ASSIST-022` should include cross-model QA for named folder listings with similar grants, punctuation mistakes, pluralization, and stale recent-folder state.

## 2026-05-26 - Folder Listings Carry File Sources For Follow-Up Reads

Status: Accepted

Decision:
When Pixel Pane lists a granted folder, the tool result should include visible child files as structured file sources in addition to the folder source. Follow-up read requests should resolve unique recent file/type references, such as "that txt file" or "sure do it," through the app-owned Local Files read tool before model generation.

Context:
A QA chat listed `/Users/nayak/Documents/pixel-pane-test` and showed `top_processes.txt`, but a follow-up asking what was inside that text file fell through to model chat. The model correctly complained that no tool result contained readable file content. The missing piece was not model intelligence; it was an incomplete observation handoff from the folder-list tool to the next turn.

Consequences:
- Folder listings become actionable observations, not just display text.
- The selected model can remain agentic over accurate app-provided observations.
- File reads still enforce grants and readable-file checks in app code.
- The behavior is generic over filenames, extensions, grants, and selected local/cloud models.

Follow-up:
`ASSIST-022` should include list-then-read QA for single and multiple visible files, file type references, ambiguous follow-ups, and confirmation-style follow-ups.

## 2026-05-26 - Recent Source Observations Win Before Broad Fallbacks

Status: Accepted

Decision:
Pixel Pane should resolve follow-up questions that point at recent file/folder sources from structured assistant tool state before invoking broad grant inventory, fresh file search, or selected-model chat. Broad fallbacks are still useful, but only after current-session observations fail to resolve the request.

Context:
A QA chat listed two files in `pixel-pane-test`, then the user asked "what are these files?" The harness routed through broad file/grant behavior and the selected model answered with the full grant list instead of the files just observed. This happened because generic file-search/grant heuristics outranked the latest structured tool observation.

Consequences:
- The assistant behaves more like a CLI agent: observe, preserve sources, then act on the latest observation.
- Deictic follow-ups such as "these files" no longer depend on hard-coded filenames or folder names.
- Broad search remains available for new discovery questions, but does not overwrite the user's immediate referent.
- The selected model receives cleaner context and is less likely to produce stale or irrelevant access summaries.

Follow-up:
`ASSIST-022` should include source-reference precedence cases across Local Mode, Cloud Mode, and weak/no-tool local models.

## 2026-05-26 - Workspace Execution Wins Before Generic Port Inspection

Status: Accepted

Decision:
When a prompt asks Pixel Pane to build, run, start, serve, or otherwise execute a known workspace, terminal planning should resolve the workspace and discover the appropriate command before considering generic local port inspection. Port/listener inspection remains appropriate for passive troubleshooting prompts that ask what is already running.

Context:
A QA chat listed the user's granted static website folder, then the user asked to "build this site and tell me what port its running on locally." The harness saw "what port" first and ran `lsof -nP -iTCP -sTCP:LISTEN | head -80`, returning unrelated system listeners without building or serving the site. The issue was not model quality; it was a deterministic shortcut outranking the observe-plan-act flow.

Consequences:
- Recent tool state such as the last listed folder can drive workspace execution tasks.
- A prompt that asks to serve a site gets a confirmation-gated server command from the selected workspace, not a machine-wide listener dump.
- Bare localhost troubleshooting such as "localhost:3000 doesn't work; is it another port?" still uses safe read-only listener inspection.
- The immediate fix is model-agnostic, but it also reinforces the next sprint direction: task selection should move from phrase shortcuts to selected-model action planning, with Pixel Pane enforcing permissions and risk policy.

Follow-up:
`ASSIST-040` should replace the remaining broad terminal/file shortcut lattice with a selected-model action planner and keep deterministic code focused on safety, validation, source resolution, and execution.

## 2026-05-26 - Current Observed Scope Wins For Project Search

Status: Accepted

Decision:
When a user asks a deictic local-project question such as "what is this project?" after Pixel Pane has just listed or selected a folder, local file search should be scoped to that observed folder before the selected model receives context. Broad search across all grants should be reserved for unscoped discovery prompts.

Context:
A QA chat listed `/Users/nayak/Documents/snehithnayak.github.io`, then asked "what is this project though?" Pixel Pane searched all granted folders, packed both website snippets and Pixel Pane product docs, and the selected MLX model answered about Pixel Pane. The answer looked like a hard-coded response because the context was polluted by an unrelated grant.

Consequences:
- Current-session observations define the referent for "this project," "this repo," "this site," and similar follow-ups.
- The selected model still writes the final answer, but it receives relevant snippets instead of a mixed bag from every grant.
- The fix is model-agnostic and avoids hard-coding a project answer; Pixel Pane only constrains the search scope from state.
- This does not replace the need for `ASSIST-040`; the larger sprint should still move broad task selection into a selected-model action planner.

Follow-up:
`ASSIST-040` should use the same principle in the planner loop: resolve current observed scope first, then ask the selected model what action to take inside that scope.

## 2026-05-26 - Selected Model Plans Assistant Tool Actions

Status: Accepted

Decision:
Pixel Pane should ask the selected local or cloud model to plan bounded assistant actions before using broad deterministic terminal/file phrase shortcuts. The model may request actions such as direct answer, list grants, list folder, search files, read file, stage a confirmed write proposal, or run a terminal command. Pixel Pane remains the executor and policy boundary: it validates paths, enforces grants, classifies terminal risk, asks for confirmation before side effects, records sources, and treats observations as untrusted data.

Context:
Copied QA transcripts showed that first-match deterministic routing made the assistant feel hard-coded. The most visible failure was a local server stop flow: Pixel Pane asked for permission to end a process, but typed follow-ups like "sure" and "end it" fell back to model chat and never executed the pending process-control action. More generally, better selected models should be able to plan more capable workflows without requiring app code to encode every phrase ordering.

Consequences:
- Local Mode planning stays on the Mac because the selected local backend receives the action-planning prompt and local observations.
- Cloud Mode uses the same app-owned tool contract, but only after the user has explicitly selected Cloud Mode.
- Deterministic code is narrowed toward app facts, pending confirmations, validation, risk classification, execution, and fallback behavior.
- Terminal commands proposed by a model are never trusted directly; process control, server starts, scripts, installs, privileged commands, destructive commands, and writes still require confirmation or are blocked.
- Weak or non-JSON local models may still need fallback behavior and should be measured explicitly.

Follow-up:
`ASSIST-022` should run the same model-planned task matrix across weak local models, stronger local models, and Cloud Mode, including list-read, build/serve, process-stop, write-proposal, prompt-injection, and fallback cases.
