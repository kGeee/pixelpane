# Pixel Pane Status

Last updated: 2026-05-22

## Current Focus

Epic 1, Epic 2, and the current Epic 7 notch-assistant alpha slice are closed. Pixel Pane now has a hover-open notch chat surface, capture-context chats, user-granted local file read/search, confirmed local file create/edit, local chat persistence, text-only MLX local chat setup, repeatable local build verification, and first-run privacy onboarding. Next: Screen Recording permission guidance.

Current phase: Notch assistant alpha.

Current epic: Epic 3 - Privacy And Onboarding.

Current recommended story: `PRIV-002` Screen Recording permission guidance.

## Current State

- Xcode project at `PixelPane/PixelPane.xcodeproj`.
- App builds successfully and produces a properly codesigned `.app` via:

```bash
xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build
```

- Xcode Product → Run works again as of 2026-04-29; the earlier `LaunchExecutableValidationErrorDomain` issue is resolved.
- Epic 1 (Core Capture Loop) validated end-to-end on user hardware on 2026-04-29; `CORE-011` subsequently fixed a selected-region/captured-image coordinate mismatch.
- Foundation files in place:
  - `PixelPane/PixelPane/PixelPaneApp.swift`
  - `PixelPane/PixelPane/App/AppState.swift`
  - `PixelPane/PixelPane/App/SystemStatus.swift`
  - `PixelPane/PixelPane/App/HotkeyManager.swift`
  - `PixelPane/PixelPane/Actions/*`
  - `PixelPane/PixelPane/Capture/*`
  - `PixelPane/PixelPane/OCR/OCREngine.swift`
  - `PixelPane/PixelPane/OCR/LanguageDetector.swift`
  - `PixelPane/PixelPane/Panel/*`
  - `PixelPane/PixelPane/Settings/SettingsView.swift`

## Known Architectural Decisions

- App is menu-bar-first using `MenuBarExtra`.
- App is configured as `LSUIElement`.
- App sandbox is disabled to align with Direct distribution.
- Pixel Pane alpha and v1 target macOS 15.2+ because `SCScreenshotManager.captureImage(in:)` requires it.
- Alpha global hotkey uses Carbon `RegisterEventHotKey`; `CGEventTap` is deferred unless Carbon fails QA.
- **Local-First AI Default (2026-04-29):** every AI action defaults to on-device. Apple Foundation Models handles text-only local AI when available; optional MLX/VLM setup handles local image understanding. Cloud Mode is an explicit Settings opt-in, and the current single Cloud Mode toggle covers cloud-capable text and image context.
- **Local Vision Runtime Via MLX (2026-04-29):** image-aware Local Mode should use an installed MLX vision model. Current recommended setup model is `mlx-community/Qwen3.6-35B-A3B-6bit` when compatible with the user's Mac.
- **Cloud Proxy Contract And Hosting (2026-04-29):** the first cloud-upgrade backend is a Cloudflare Workers proxy in front of Anthropic. The macOS app talks to the Pixel Pane `/v1` contract in `docs/backend-api.md` and never stores provider API keys.
- **Sparkle Release Update Process (2026-05-21):** Direct distribution updates use Sparkle with a planned production appcast at `https://pixelpane.app/appcast.xml`; beta builds may temporarily use an HTTPS release-site appcast. Sparkle EdDSA private keys are release secrets and must not be committed, embedded in the app, or deployed to the backend.
- **Notch-Native Local Assistant (2026-05-21):** Pixel Pane's core surface is now a hover-open notch assistant. Plain chat can open without capture context; captures create a fresh contextual Ask session; local remains default and Cloud Mode is a single explicit routing choice.
- **Chat-Only Notch Surface (2026-05-21):** The visible notch UI is now a single chat assistant. Extract, Translate, Explain, and Simplify are natural-language capabilities through chat/context, not top-level tabs.
- **User-Granted Read-Only Local Files (2026-05-21):** The notch assistant may read/search only files or folders explicitly granted by the user. File snippets stay local in Local Mode and may be sent only when the user routes the chat through Cloud Mode. Create/edit/delete/move tools are deferred to a separate confirmed-write story.
- **Local Chat History Without Screenshot Retention (2026-05-21):** Chat transcripts are stored locally so the notch assistant can resume conversations. Capture chats persist only message text and a lightweight Screen region label; screenshots are not retained unless a future explicit retention feature is added.
- **Local Text Runtime Via MLX (2026-05-21):** Local Mode can use a selected text-only MLX model for text chat/actions through `mlx_lm.generate` when setup passes. MLX Vision remains separately gated on a vision-capable model and `mlx_vlm.generate`.
- **Confirmed Local File Writes (2026-05-21):** The assistant may stage local file creation or text edits only inside user-granted file/folder locations. Writes require a visible confirmation naming the target path before any file is changed; model output never directly mutates files.

## Open Decisions

- Telemetry is deferred for now and is not a product requirement for the app (`FOUND-008`). Keep the decision visible for beta planning; if revisited, telemetry must remain opt-in and exclude screenshots, OCR text, prompts, questions, result text, and clipboard contents.

## Story Snapshot

Epic 0 — Foundations
- `FOUND-001` Minimum macOS / capture compatibility: Done
- `FOUND-002` Signing, entitlements, and Direct distribution baseline: Done
- `FOUND-003` Backend proxy API contract: Done
- `FOUND-004` Backend proxy MVP: Done
- `FOUND-005` Anonymous device identity and auth-token flow: Done
- `FOUND-006` Secret-management rules for app and backend: Done
- `FOUND-007` Sparkle update/release process: Done
- `FOUND-009` Add CI build verification: Done

Epic 1 — Core Capture Loop (all Done as of 2026-04-29)
- `CORE-001` Menu-bar shell · `CORE-002` Overlay & region selection · `CORE-003` Selected-region capture · `CORE-004` Vision OCR · `CORE-005` Result panel · `CORE-006` Permission recovery UX · `CORE-007` Global hotkey · `CORE-008` Language detection · `CORE-009` Panel placement & keyboard · `CORE-010` Multi-display QA · `CORE-011` Capture coordinate alignment fix

Epic 2 — Action Rail
- `ACT-011` Hybrid local action backend protocol: Done
- `ACT-012` MLX local vision model discovery and setup: Done
- `ACT-013` MLX vision backend adapter: Done
- `ACT-001` Action rail UI: Done
- `ACT-002` Extract Text action: Done
- `ACT-004` Translate action with local/cloud routing: Done
- `ACT-005` Explain action: Done
- `ACT-006` Simplify action: Done
- `ACT-007` Ask follow-up conversation: Done
- `ACT-008` Contextual Debug action: Done
- `ACT-009` Copy/export result controls: Done
- `ACT-010` Error and empty states: Done
- `ACT-003` Cloud API client shell: Done
- `ACT-014` Smart default action selection: Done
- `ACT-015` Enable Cloud Mode app wiring: Done

Epic 3 — Privacy And Onboarding
- `PRIV-001` First-run onboarding: Done
- `PRIV-002` Screen Recording permission guidance: Not Started
- `PRIV-005` Local/cloud mode setting and enforcement: Done

Epic 6 — Cross-Cutting Quality
- `QUAL-011` Normalize model-output math and special characters: Done
- `QUAL-012` Notch-attached result surface: Done
- `QUAL-013` Hover-expanded notch interaction polish: Done

Epic 7 — Notch Assistant
- `ASSIST-001` Make the notch a chat-first assistant surface: Done
- `ASSIST-002` Add user-granted local file read/search tools: Done
- `ASSIST-003` Add confirmed local file create/edit tools: Done
- `ASSIST-004` Add local chat persistence: Done
- `ASSIST-005` Expand local model setup to text-only MLX models: Done

See `workflow/backlog.md` for all stories.

## Last Completed Work

- 2026-05-22: Follow-up onboarding visual polish for `PRIV-001`. Replaced the Continue button's default macOS button styling with a subdued custom secondary style so it no longer appears highlighted/focused when onboarding opens. Local verification wrapper build succeeded.
- 2026-05-22: Follow-up QA reset for `PRIV-001`. Added a temporary Settings -> Permissions -> Onboarding QA control that shows first-run onboarding again without relying on Terminal defaults commands. Auto-created `PRIV-009` to remove or formalize the reset before beta.
- 2026-05-22: Follow-up fix for `PRIV-001`. Increased the first-run onboarding window/content minimum height so the Continue and Start First Capture buttons no longer clip or overflow at the bottom of the window. Local verification wrapper build succeeded.
- 2026-05-21: Completed `PRIV-001`. Added a first-run onboarding window that appears before the default assistant surface until `PrivacyOnboarding.Completed` is set. It explains selected-region capture, no continuous recording, and in-memory/ephemeral screenshot handling. Continue opens the assistant; Start First Capture starts the capture flow after the privacy explanation. Local verification wrapper build succeeded.
- 2026-05-21: Completed `FOUND-009`. Added `PixelPane/Scripts/verify-debug-build.sh` as an executable local verification wrapper around the Debug Xcode build and documented it in `workflow/README.md`. The wrapper build succeeded.
- 2026-05-21: Completed `ASSIST-003`. Added confirmed local file write proposals for chat commands such as create file, append to, and replace in. Proposals are restricted to user-granted files/folders, shown in the chat transcript, and require a visible confirmation panel naming the target path before any local write is applied. Settings -> Files now describes confirmed local writes. Debug build succeeded.
- 2026-05-21: Completed `ASSIST-005`. Local MLX setup now detects model capability as Text, Vision, Text + Vision, or Unsupported; Settings shows those capability labels plus separate text/vision runtime status. Text-only MLX models can be selected for local chat/actions through `mlx_lm.generate`, while image-aware local behavior remains gated on a vision-capable model and `mlx_vlm.generate`. Debug build succeeded.
- 2026-05-21: Completed `ASSIST-004`. Added local chat transcript persistence with `ChatHistoryStore`. Plain notch chats resume the latest assistant session; capture chats save message text under a lightweight Screen region label while screenshots remain ephemeral and are not written to history. The chat composer now has a compact history menu with recent chats and New Chat, and Settings -> History exposes saved-chat count, per-chat delete, and Clear History. Debug build succeeded.
- 2026-05-21: Follow-up chat polish. Shortened the Ask prompt/context sent to local/cloud backends, capped OCR/file/transcript context sizes, darkened the expanded notch surface so underlying screen text does not read as Pixel Pane UI, and forced compact notification sizing whenever a notification is created so the dot should stay on the notch's right/trailing edge. Debug build succeeded.
- 2026-05-21: Follow-up prompt hygiene. Cloud chat no longer sends the internal Ask scaffold as OCR/context, and streamed Ask output now strips exact and partial prompt echoes before updating the transcript. Debug build succeeded.
- 2026-05-21: Completed `ASSIST-002`. Added explicit user-granted local file and folder access from the assistant and Settings, plus a read-only context provider that lists grants, searches text-like files, and feeds bounded relevant snippets into chat. Cloud Mode now receives local snippets only when that routing mode is selected; Local Mode keeps file context on the Mac. No file writes are allowed yet. Debug app build, backend typecheck, and Worker deploy succeeded.
- 2026-05-21: Follow-up polish for `ASSIST-002`. Removed the confusing Clean Missing button from Settings -> Files; the visible file-access controls are now only Grant Folder, Grant File, and per-location remove. Debug build succeeded.
- 2026-05-21: Follow-up polish for `ASSIST-002`. Removed inline file/folder grant buttons from the notch chat; file access is now configured only in Settings -> Files while chat keeps passive context chips for already-granted access. Debug build succeeded.
- 2026-05-21: Follow-up notch placement fix for `ASSIST-001`/`ASSIST-002`. New capture notifications now reset the panel to the compact right-edge notch size before positioning, avoiding the stale expanded-frame case where the tiny indicator could render on the left side. Plain assistant startup now uses the invisible hover target instead of a notification dot. Debug build succeeded.
- 2026-05-21: Follow-up capture-context fix for `ASSIST-001`. Selected-region chat now treats the captured screen region as the primary reference: visual-capable local/cloud turns attach the screenshot image on every turn, text-only local turns treat OCR as the primary capture context, and empty OCR in text-only mode explains the local vision limitation instead of asking for filenames or coordinates. Debug build succeeded.
- 2026-05-21: Completed `ASSIST-001`. The app now creates a plain assistant notch hover target on launch and opens capture results in Chat-first mode so screenshot/OCR context feeds the first chat. Settings now presents Local vs Cloud as one segmented AI Mode choice instead of separate confusing toggles. Follow-up polish removed the hanging Export control, removed the redundant Open Assistant menu item, auto-focuses the chat field on hover open, supports no-capture chat in both local and cloud modes, makes the transcript denser, and raises visible chat token budgets so responses are less likely to be cut off. Chat remains session-only; local file access and persistence are deferred to follow-up assistant stories. Debug build succeeded.
- 2026-05-21: Follow-up notch chat polish for `ASSIST-001`. The expanded chat surface is wider/taller, the transcript uses roomier native chat bubbles, cloud metadata is condensed into one quiet line, and reset times are formatted as human-readable text instead of raw ISO timestamps. Debug build succeeded.
- 2026-05-21: Follow-up product simplification for `ASSIST-001`. The result panel now forces Chat as the visible mode, removes the action rail and footer controls from the assistant surface, shows only lightweight context chips such as Screen region and On-device/Cloud, and uses a larger composer. Build succeeded.

- 2026-05-21: Completed `FOUND-007`. `docs/release.md` now documents the planned production Sparkle appcast URL, temporary beta appcast option, release-channel approach, Sparkle integration prerequisites, EdDSA private-key handling, and appcast generation/verification as part of the Developer ID signed/notarized DMG release checklist. Recorded the Sparkle release update process decision in `workflow/decisions.md`.

- 2026-05-20: Completed `QUAL-013`. The compact result notch is now a smaller black top-center extension with square top corners and rounded lower corners, no text preview in compact state, hover-to-expand behavior, delayed hover-out collapse, and non-activating presentation for normal capture results. Expanded notch content continues to reuse the existing action/result workspace, Ask, routing, copy/export, and close behavior.
- 2026-05-20: Follow-up fix for `QUAL-013` after manual QA found the hover-expanded notch closed immediately after opening. Hover-out collapse now checks the current mouse location against the expanded notch bounds before collapsing, which avoids treating the resize/content swap as a real pointer exit.
- 2026-05-20: Follow-up polish for `QUAL-013` after manual QA found the closed state visually enlarged the Mac notch. The collapsed hover target is now transparent and renders no black mini-notch/status content; the black notch extension is drawn only while expanded.
- 2026-05-20: Follow-up polish for `QUAL-013` after manual QA found the expanded notch still read as a bordered window. Removed the explicit SwiftUI stroke around the notch container and disabled the AppKit window shadow for notch presentation.
- 2026-05-20: Added unread processing/completion notification polish to `QUAL-013`. While an action is running, the collapsed notch hover target shows a yellow pulsing glow; once processing finishes it turns green. The first hover marks the notification as seen and removes the compact indicator after the user leaves the expanded notch.
- 2026-05-20: Follow-up fix for `QUAL-013` notification visibility. The compact notification now appears green immediately when the notch first opens with a ready Extract result, instead of only appearing after an async action changes loading state.
- 2026-05-20: Follow-up notch notification layout fix for `QUAL-013`. The compact notification no longer turns on the full black notch container; it renders as a small right-aligned black capsule with yellow/green glow so the visible change extends to the right of the notch instead of enlarging both sides.
- 2026-05-20: Follow-up notch alignment fix for `QUAL-013` after manual QA showed the compact notification was rendered below/behind the physical notch. Compact positioning now uses `NSScreen.auxiliaryTopRightArea` when available, anchoring the indicator to the unobscured top-right area adjacent to the camera notch instead of centering it behind the notch.
- 2026-05-20: Follow-up notch attachment polish for `QUAL-013` after manual QA showed a visible gap between the physical notch and the compact notification. The compact notification now overlaps farther under the notch edge and uses a square left edge so it reads as an extension of the existing notch.
- 2026-05-20: Follow-up notch expanded-state polish for `QUAL-013` after manual QA found the expanded surface still felt like a floating macOS window. The notch-expanded header no longer renders the explicit close/X button; floating recovery-style panels keep their close control.
- 2026-05-20: Follow-up notch header polish for `QUAL-013` after manual QA found the action logo indicator too large and tinted. The notch-expanded header now uses a smaller neutral icon badge while the original gradient badge remains available to floating presentation surfaces.
- 2026-05-20: Follow-up notch header indicator polish for `QUAL-013` after manual QA found the neutral badge still too large. The notch-expanded header now uses a tiny white glowing dot instead of an action icon badge.
- 2026-05-20: Follow-up notch shape polish for `QUAL-013` after manual QA found the extension corner too rounded compared with the physical notch. Compact and expanded notch masks now use a smaller lower-corner radius so the extension reads closer to the almost-rectangular hardware notch.
- 2026-05-20: Follow-up compact notification polish for `QUAL-013` after manual QA found the right-side notification icon still too large. The compact notification now uses a 4-point yellow/green dot with a faint glow instead of a capsule/bar indicator.
- 2026-05-20: Follow-up compact notch sizing polish for `QUAL-013` after manual QA found the right-side extension too wide for the tiny dot. The visible compact notification extension is now much narrower, and after the notification is dismissed the transparent hover target recenters over the physical notch so hovering the notch still opens the overlay.
- 2026-05-20: Follow-up expanded overlay visual polish for `QUAL-013` after manual QA asked for a more Apple liquid-glass-like surface. The expanded notch shell now uses translucent HUD material layering, larger rounded lower corners, a subtle glass highlight/stroke, and a softened inner result card.
- 2026-05-20: Follow-up expanded overlay notch-blend polish for `QUAL-013` after manual QA found the physical notch too visible through the translucent top. The expanded shell now uses a top-heavy black vertical fade so it merges into the hardware notch before transitioning into the glassy body.
- 2026-05-20: Follow-up compact notification animation polish for `QUAL-013`. The processing dot now uses a slow breathing loop where the tiny dot and glow subtly scale and fade instead of rendering as a static dot.
- 2026-05-20: Follow-up notch-blend darkening for `QUAL-013` after manual QA found the expanded overlay top still too translucent. The top fade now holds near-black opacity through the upper band before tapering into the glassy body.
- 2026-05-20: Follow-up expansion animation polish for `QUAL-013`. Hover expansion now uses a slower custom ease-out AppKit frame animation and delays/fades/scales in the expanded content so the notch feels like it pops out instead of snapping open.
- 2026-05-20: Follow-up footer/header simplification for `QUAL-013`. The notch footer now keeps only essential metadata chips, combines translation language route into one chip, removes backend implementation noise, and hides unknown language chips. The notch-expanded header also no longer shows the timestamp or collapse chevron; hover-out remains the collapse path.
- 2026-05-20: Follow-up notch header simplification for `QUAL-013`. The expanded notch surface no longer renders the selected action title/subtitle block above the action rail.
- 2026-05-20: Follow-up notch placement hardening for `QUAL-013` after manual QA found the compact digital extension could jump to the left side of the physical notch. Placement now derives a sanitized hardware notch rect from both auxiliary safe areas when available, falls back from either side when one safe area is missing, anchors the visible notification to the hardware notch right edge, and centers the transparent hover target on the notch.
- 2026-05-20: Follow-up notch-safe layout polish for `QUAL-013` after manual QA found the hardware notch clipping the top controls. The expanded notch surface now reserves a black top inset under the physical notch before the action rail, and the notch-attached panel no longer allows background dragging so it behaves like a fixed system surface.
- 2026-05-20: Follow-up animation and placement polish for `QUAL-013`. Collapse now starts the AppKit shrink animation immediately so the surface flows back into the notch instead of fading away first, the top edge slightly overscans above the screen to hide the panel seam, and compact notification placement now pins directly to the right auxiliary safe area when available.
- 2026-05-20: Follow-up compact notch visual match for `QUAL-013`. Compact notification placement no longer applies the expanded-overlay top overscan, and the visible extension now uses a flatter pure-black shape with a smaller lower-right radius so it aligns more closely with the hardware notch edge.
- 2026-05-20: Follow-up compact notification animation polish for `QUAL-013`. The processing indicator remains a tiny dot but now adds a subtle expanding radar ring plus a restrained core/glow pulse inside the compact notch extension.
- 2026-05-20: Follow-up collapse animation polish for `QUAL-013`. When the notification has been dismissed, collapse now visibly shrinks into the tiny notch extension first, then restores the larger transparent hover target after the animation completes so the surface no longer becomes a wide black rectangle on the way back in.
- 2026-05-20: Follow-up reverse-hover animation polish for `QUAL-013`. Collapse now keeps the expanded shell active while it shrinks toward the transparent notch hover target and fades the shell out during the resize, mirroring the hover-open flow without swapping into compact notification content mid-animation.
- 2026-05-20: Follow-up notification placement fix for `QUAL-013`. Action/tab-triggered processing notifications now force the notch panel back to the true compact right-edge size when the surface is collapsed, while dismissed notifications still restore the wider invisible hover target.
- 2026-05-20: Follow-up compact loading indicator polish for `QUAL-013`. The processing notification now uses a tiny three-dot assistant-style working animation with staggered dot motion and a restrained glow, while completed notifications remain a single green dot.

- 2026-05-18: Completed `QUAL-012`. Normal post-capture results now open first as a compact top-center notch island instead of a large panel near the selected region. Clicking the island expands it into the existing action/result workspace and the expanded view can collapse back. The capture selection overlay remains unchanged, action/routing/Ask/copy/export logic is reused, the large capture preview is hidden in notch mode, and permission/recovery panels keep their existing placement behavior.
- 2026-05-18: Follow-up fix for `QUAL-012` after manual QA found the app could hang after displaying a result in compact notch mode. The compact island now caps the preview string to a short single-line summary instead of asking SwiftUI to measure the full OCR/model output as a title, and the redundant on-appear notch resize was removed.
- 2026-05-18: Follow-up fix for `QUAL-012` after manual QA narrowed the hang to expanding the notch island. Expansion/collapse now uses a direct non-animated AppKit frame update and removes the SwiftUI transition/spring while swapping compact and expanded content. Reintroduce animation only after the expanded layout is stable under manual QA.

- 2026-05-10: Completed `FOUND-002`. Confirmed the app target remains non-sandboxed for Direct distribution, hardened runtime remains enabled, no checked-in app entitlements file is present, and generated Info.plist metadata keeps the app menu-bar-only via `LSUIElement`. The Debug app's generated signing entitlements include user-selected read-only file access and debug `get-task-allow`, with no App Sandbox entitlement. Added `docs/release.md` documenting the signing/entitlement baseline and a manual Developer ID signed/notarized DMG checklist. Linked the release baseline from `docs/architecture.md`.

- 2026-05-10: Closed `ACT-015` after user manual QA confirmed Cloud Mode works for text captures, image-only/no-text captures, and Ask on image-only captures. Epic 2 is now complete.

- 2026-05-10: Fixed empty-OCR captures incorrectly disabling the whole action rail. The panel now keeps Extract available for the empty OCR recovery state and enables image-capable actions when the captured image can actually be sent to a backend, such as Cloud Mode with image consent or Local Mode with MLX Vision ready. Text-only actions still stay disabled when no OCR text exists.
- 2026-05-10: Follow-up fix for image-only Cloud Mode captures. Empty-OCR captures now default directly to Explain when an image-aware route exists, and Cloud Mode image routing now follows the single visible "Use Cloud Mode" toggle instead of a stale hidden image-consent flag.

- 2026-05-06: Normalized model-output formatting before display/copy/export. `ModelDisplayTextNormalizer` now strips common Markdown artifacts from cloud and local model output, including `##` headings, `**bold**` markers, inline backticks, horizontal rules, and pipe-table syntax. Markdown tables are converted into readable labeled lines so narrow panels do not show broken wrapped table source.

- 2026-05-06: Fixed the app-side Cloud Mode SSE parser bug behind the repeated "Cloud completed the request but returned no text" Simplify failure. `URLSession.AsyncBytes.lines` did not surface blank SSE separator lines, so the parser accumulated `meta`/`snapshot`/`done` fields into one final event named `done` and never yielded snapshots. `CloudAIBackend` now frames SSE events at the byte level using LF/CRLF delimiters, parses each event independently, and flushes a final buffered event at EOF.

- 2026-05-06: Investigated a manual QA report where Simplify showed "Cloud completed the request but returned no text." A direct deployed smoke test against `/v1/simplify` using matching OCR text returned `meta`, multiple `snapshot`, and terminal `done` events, and the current app tree already accepts cloud snapshots before `done`. The local Debug build also succeeds. Current assessment: this screenshot most likely came from an older running app instance or an earlier Worker deployment; retry QA after quitting Pixel Pane and launching the freshly built app.

- 2026-05-06: Fixed the deployed Worker path that could emit `done` without any parsed snapshots. The Anthropic upstream SSE parser now accepts both LF and CRLF event delimiters, parses CRLF data lines, and flushes any final buffered event before closing the Pixel Pane stream. This addresses app QA where Simplify surfaced "Cloud completed the request but returned no text" even though the cloud endpoint was reachable.

- 2026-05-06: Raised the deployed Cloud Mode alpha quota from 10 to 100 free cloud actions per anonymous device per UTC day so manual QA does not exhaust the backend after a few tab/action retries. Also replaced the invalid `cloud.slash` SF Symbol in cloud recovery states with `cloud`, which is available on the target macOS symbol set.

- 2026-05-06: Tightened Cloud Mode empty-response handling after manual QA showed Explain could finish back at the static "Explaining..." placeholder. `CloudAIBackend` now treats a `done` event without any displayable snapshot text as a cloud error, and the result panel converts any completed cloud placeholder into the existing Retry Cloud/Open Settings recovery state instead of leaving stale loading copy onscreen. Cloud error copy no longer mentions local fallback.

- 2026-05-06: Fixed Cloud Mode output display getting stuck on "Simplifying"/"Explaining." Cloud snapshots now bypass the local-only prompt-echo suppression filter, and the SSE parser treats whitespace-only lines as event delimiters. This lets cloud snapshots update the visible output instead of leaving the loading placeholder in place.

- 2026-05-06: Fixed Cloud Mode stream completion handling in the app. A direct curl test against the deployed Worker confirmed `/v1/simplify` streams `meta`, `snapshot`, and `done` events correctly. The app-side SSE parser now flushes any pending event when the URLSession byte stream reaches EOF, preventing a final `done` event from being dropped and incorrectly reported as "Cloud stream ended before completion."

- 2026-05-06: Collapsed Cloud Mode settings from two toggles into one "Use Cloud Mode" toggle. Enabling Cloud Mode now enables cloud routing and cloud image context together for cloud-capable actions; disabling it keeps all actions local. Existing old two-toggle preferences are normalized on launch.

- 2026-05-06: Removed automatic local fallback while Cloud Mode is enabled. Cloud Mode actions now either stream from Pixel Pane Cloud or surface the cloud error while staying labeled as Pixel Pane Cloud; the panel no longer runs the local model behind the user's back.

- 2026-05-06: Replaced the native Response Style `Slider` with a custom three-stop control so the track, tick marks, thumb, and labels share the same geometry. This fixes the Brief/Balanced/Thorough label alignment and removes the native thumb focus/highlight ring.

- 2026-05-06: Fixed Settings window ordering from the menu bar. The Settings menu item now explicitly opens Settings, activates Pixel Pane, and asks the actual Settings window to make itself key/order front so it does not appear underneath the current app window.

- 2026-05-06: Removed the Response Style slider description line in Settings → Local AI. The control now stays minimal: current style, slider, and Brief/Balanced/Thorough labels only.

- 2026-05-06: Fixed the SwiftUI picker warning in Settings → Local AI. The MLX model picker now uses a non-optional selection binding with a valid model ID fallback, so the picker no longer renders with an untagged `nil` selection before `onAppear` initializes local state.

- 2026-05-06: Fixed Cloud Mode falling back immediately to local because the app could not decode the Worker token response timestamp. `CloudAuthTokenProvider` now accepts both fractional-second and non-fractional ISO8601 `expires_at` values from `/v1/auth/token`. A direct curl smoke test against the deployed Worker confirmed `/v1/auth/token` and `/v1/explain` return valid token/SSE responses before the patch, and the app build succeeds after the decoding fix.

- 2026-05-06: Simplified the Response Style slider in Settings → Local AI. It now presents only the current style, the native slider, and Brief/Balanced/Thorough tick labels, removing the extra speed captions and summary text that made the control feel crowded.

- 2026-05-06: Implemented `ACT-015` app-side Cloud Mode wiring. The app now has the deployed Worker base URL in `AIRoutingSettings`, enables Cloud Mode and image-consent controls in Settings, instantiates `CloudAIBackend` with `CloudAuthTokenProvider` in the result panel, sends structured cloud OCR/question/conversation metadata to the proxy, routes Translate/Explain/Simplify/Ask/Debug through Pixel Pane Cloud only when Cloud Mode is enabled, sends captured images only when the separate image consent toggle is enabled and the endpoint supports images, surfaces Cloud backend/quota metadata, and falls back to local text generation on cloud failures without losing the panel state. `ACT-015` is In Review until manual UI QA verifies real cloud actions.

- 2026-05-06: Added `ACT-015` to track the missing app-side Cloud Mode wiring. The story owns instantiating `CloudAIBackend` against the deployed Worker, using `CloudAuthTokenProvider`, enabling guarded Cloud Mode/image-consent settings, routing opted-in actions to cloud, preserving local-first defaults, and QA'ing real cloud calls.

- 2026-05-06: Stopped precomputing non-selected action tabs after capture. The result panel now generates only the smart default action when the selector chooses one from OCR/language/technical signals, or an action the user explicitly opens from the rail. Extract-default captures no longer silently warm Explain, and Explain completion no longer silently starts Simplify.

- 2026-05-06: Deployed the Cloudflare Worker backend to `https://pixel-pane-api.snehithn5.workers.dev` after the user registered the account-level `workers.dev` subdomain. Verified `/v1/auth/token` returns a signed bearer token, and verified `/v1/explain` accepts that token, decrements KV quota, calls Anthropic via the Worker secret, and streams normalized Pixel Pane SSE `meta`/`snapshot`/`done` events. Cloud execution backend is live; app wiring was later implemented under `ACT-015`.

- 2026-05-06: Configured the Cloudflare Worker KV namespace bindings for `RATE_LIMIT_KV` in `PixelPane/Backend/wrangler.toml` after the user created production and preview namespaces with Wrangler. The user set `ANTHROPIC_API_KEY` and `APP_AUTH_SECRET` as Worker secrets. `npm run typecheck` and `npx wrangler deploy --dry-run` both succeeded; dry-run now reports the real KV binding.

- 2026-04-29: Removed the fixed five-question cap from Ask. The Ask input and Send button now stay available after any number of turns, and the empty-state copy says "Ask follow-up questions about this capture." The first turn can still include the image through MLX when ready; later turns continue to use OCR text plus prior transcript only.

- 2026-04-29: Shipped `ACT-014` (Smart default action selection). Added a synchronous `SmartDefaultActionSelector` that uses existing OCR text, detected language, and technical classification only, so choosing the default does not add a model call or image-processing step. The result panel now opens on Debug for technical captures, Translate for confident non-English captures, Simplify for dense text, Explain for explanation-like content, and Extract as the low-confidence/empty fallback. Background Explain prewarm is skipped when a non-Extract smart default is already active to keep the initial action fast.

- 2026-04-29: Shipped `QUAL-011` (model-output math and special-character normalization). Added `ModelDisplayTextNormalizer` to turn common LaTeX-style output into readable plain text before display/copy/export, including inline math delimiters and commands such as `\\mathbb{C}`. Wired it through `ModelOutputFormatter` for MLX output and through `ResultPanelView` for Apple streamed snapshots, final action output, hidden reasoning, and Ask answers.

- 2026-04-29: Shipped `QUAL-010` (Response style slider). Added `ResponseDetailLevel` (Brief/Balanced/Thorough), persisted in UserDefaults, exposed on `AppState`, threaded through `ResultPanelController.show()` into `ResultPanelView`. Brief mode skips MLX Vision for Explain/Simplify/Ask (the dominant latency source) and disables silent Explain/Simplify pre-warming. All actions now use `responseDetail.maxOutputTokens(for:)` so Brief shrinks output ~0.5× and Thorough lengthens it ~1.6×, with a 60-token floor. Debug always keeps Vision when available. Settings → Local AI gains a "Response Style" section with a 3-stop slider, live summary, and tick labels. The biggest perf win is the model swap to Apple Foundation Models, not the token-cap change.

- 2026-04-29: Shipped `QUAL-009` (Liquid Glass overlay panel redesign). Replaced the result panel's `.titled` window chrome with a borderless `OverlayPanel`, added an `NSVisualEffectView`-backed `GlassOverlayContainer`, restyled the header into a gradient action badge plus custom circular close button, swapped the underlined action rail for a pill-shaped `SegmentedActionBar` with `matchedGeometryEffect`, restructured the footer with a transient confirmation pill and icon-chip metadata, ported the recovery panel to the same glass-card visual language, and added a subtle scale+fade entrance animation. Window shadow stays correct via a `NSHostingView` layer mask and `panel.invalidateShadow()`. Behavior preserved: tab caching, MLX vs Apple routing, Esc/Cmd-W/Cmd-C, Try Again/Open Settings recovery actions.

- Applied user-reported panel and Settings polish: the result panel now opens wider with a two-pane workspace, keeps the selected capture visible in a compact preview pane, uses lighter native-feeling surfaces with weaker borders, a slimmer action rail/footer, subtler active states, quieter metadata pills, and model runtime stats hidden behind a Details disclosure, MLX vision output is sanitized through a model-agnostic formatter that hides `<think>`/prompt echo noise behind an optional "Model Thinking" disclosure, Ask now uses chat-style question/answer turns with a shorter prompt/output cap and answer cleanup to prevent question/transcript echo loops, and Ask prefers MLX Vision for the whole conversation when a ready image-aware model exists while only sending the captured image on the first turn, action tabs cache their current output state so switching between Extract, Translate, Simplify, Explain, Debug, and Ask does not recompute completed results, Explain now starts warming/generating silently in the background as soon as the result panel appears and Simplify starts silently after Explain completes if it has not already been run, Explain has a richer context/meaning prompt while Simplify is constrained to a shorter rewrite so their outputs have distinct jobs, Simplify now uses MLX Vision when a ready image-aware model is available to avoid Apple text-model false refusals on normal screenshots, prompt-like streamed chunks are suppressed so action prompts never flash in the output pane, loading placeholders render with a small typing animation, Translate now routes directly through the local Apple model instead of Apple Translation and explicitly targets English until a target-language setting exists, and Settings is split into Capture, Permissions, Local AI, and Cloud tabs.
- Completed `FOUND-006`: recorded secret ownership in `workflow/decisions.md`. The app stores only an anonymous device ID and short-lived Pixel Pane bearer token in Keychain; provider keys and backend signing secrets live in Cloudflare secrets; `.env` and `.env.*` stay ignored with `.env.example` tracked.
- Completed `FOUND-005`: added `CloudAuthTokenProvider` with Keychain-backed anonymous device ID generation and cached bearer token storage. Added the Worker `/v1/auth/token` endpoint, which signs short-lived HMAC Pixel Pane tokens from anonymous device IDs, and documented the endpoint in `docs/backend-api.md`. Sign in with Apple remains deferred until account/upgrade work.
- Completed `FOUND-004`: added a Cloudflare Worker backend under `PixelPane/Backend` with TypeScript/Wrangler setup, HMAC bearer-token validation plus dev-token support, schema validation for every `/v1` action endpoint, KV-backed daily free quota, Anthropic Messages streaming, and normalized Pixel Pane SSE `meta`/`snapshot`/`done`/`error` events. Added backend deployment notes and `.env.example`; provider keys remain Worker secrets only. Deployment still needs Cloudflare KV namespace IDs, `ANTHROPIC_API_KEY`, `APP_AUTH_SECRET`, and the `FOUND-005` client token flow.
- Completed `PRIV-005`: added `AIRoutingSettings`, persisted Cloud Mode and image-consent preferences in `AppState`, initially surfaced Cloud Mode in Settings as a guarded placeholder, and labeled result panels with the active Local Mode routing badge. `ACT-015` later enabled the deployed cloud path while preserving local-first defaults.
- Completed `ACT-003`: added `CloudAIBackend` under `PixelPane/PixelPane/API`. It conforms to `AIBackend`, builds requests against `docs/backend-api.md`, refuses to run unless Cloud Mode is enabled in its configuration, rejects image uploads without explicit image consent, parses normalized Pixel Pane SSE `snapshot`/`done`/`error` events, maps auth/rate-limit/network/cloud-disabled failures into structured errors, and keeps provider keys out of the app. `ACT-015` later instantiated it from the result panel routing path.
- Completed `FOUND-003`: added `docs/backend-api.md` with the Cloudflare Workers proxy contract for translate, explain, simplify, ask, study, menu, and debug. The contract defines shared request schemas, normalized Pixel Pane SSE events, auth headers, rate-limit and error responses, image consent rules, and a retention policy that excludes prompt content, screenshots, OCR text, user questions, and model output from default logs. Recorded the Cloudflare Workers hosting decision in `workflow/decisions.md` and linked the contract from `docs/architecture.md`.
- Completed `ACT-007`: Ask is enabled in the action rail with an inline panel input, streamed local answers, transcript rendering, and no fixed turn cap. The first Ask turn may include the captured image through MLX Vision when ready; later turns never resend image data and use OCR text plus the prior transcript. Closing the result panel clears the conversation state. Cloud routing remains deferred until `ACT-003`/`PRIV-005`.
- Completed `ACT-008`: added a rule-based technical-content classifier with a documented `0.8` Debug threshold, stores classification on each capture, and shows Debug only for technical-looking OCR. Debug runs through the shared local backend, includes captured image input only when MLX Vision is ready, and otherwise uses OCR text only. Cloud routing remains deferred until `ACT-003`/`PRIV-005`.
- Completed `ACT-010`: empty OCR results now carry an explicit empty-state flag, preserve the captured image, and show a Try Again recovery action. Local AI failures now render inline recovery panels with retry, Apple Intelligence Settings, or Pixel Pane Settings actions depending on the unavailable reason. Cloud-only error criteria are deferred until `ACT-003` and `PRIV-005` introduce Cloud Mode.
- Updated MLX model discovery after user feedback. Settings now lists downloaded Hugging Face MLX cache models even when they are text-only, labels incompatible models in the picker/details, and still rejects them during setup so Vision remains unavailable.
- Fixed MLX vision setup validation after user report. Setup now requires vision/VLM metadata such as image processor or image-token configuration before saving a model as ready, and saved selections are revalidated on refresh so text-only MLX models cannot keep Vision marked available.
- Polished the capture overlay and result panel after visual QA. The overlay now accepts the first drag without an extra focus click, shows a clearer dimmed cutout with selection handles, and the result panel uses compact custom controls with a material background instead of default chunky bordered controls.
- Simplified Settings after user feedback. The Settings window is now organized around Capture, Permissions, and Local AI, and the Local AI section supports choosing any local MLX vision model folder instead of only auto-discovered Hugging Face cache entries.
- Completed `ACT-009`: added Export for the active panel result via `NSSavePanel` and visible confirmation after copy/export.
- Completed `ACT-006`: enabled Simplify in the action rail and routes it through the shared local backend with a bounded rewrite prompt that preserves meaning and shortens when practical.
- Completed `ACT-005`: enabled Explain in the action rail. It uses MLX Vision with the captured image only when image-aware Local AI setup is ready; otherwise it uses text-only local generation.
- Completed `ACT-004`: enabled Translate in the action rail. It uses the local Apple model through the shared local backend; the Apple Translation framework path was removed after user QA showed it could stall on unavailable language assets.
- Fixed the MLX setup capability label after user report: installed-but-not-selected models now show as setup-needed instead of model-missing. Local inspection confirmed the preferred model exists at `~/.cache/huggingface/hub/models--mlx-community--Qwen3.6-35B-A3B-6bit`.
- Completed `ACT-002`: added `ExtractTextAction` as a local-only OCR pass-through and changed the panel copy behavior to copy active action output, preserving OCR line breaks and avoiding network calls.
- Completed `ACT-001`: added a typed action model and result-panel action rail. Extract is selected by default, AI actions are visible but disabled with hover help, and the state model carries selection/loading/disabled states for follow-on action stories.
- Completed `ACT-012`: expanded MLX setup from a coarse detector into a Settings setup flow. The app now detects `mlx_vlm.generate`, discovers compatible cached Hugging Face models, prefers `mlx-community/Qwen3.6-35B-A3B-6bit`, shows model repo/disk/license/destination/hardware warning, copies an explicit install command, opens the model card, and persists a user-selected model path/status only after setup check.
- Completed `ACT-013`: added `MLXVisionBackend` behind the shared `AIBackend` protocol. Image-aware requests now route to `mlx_vlm.generate` only when setup marks a selected model ready; the adapter writes a temporary PNG for the helper process, streams stdout snapshots, supports cancellation/timeout, deletes the temporary image, and distinguishes runtime/model/memory/timeout/generation failures without logging user content.
- Completed `ACT-011`: added the backend-agnostic local AI protocol, streaming event model, structured local errors, bounded prompt/output limits, Apple Foundation Models text backend, hybrid local router, and MLX runtime/model availability detector. Settings now shows local text and image-aware AI capability status.
- Recorded the product decision to add optional local MLX/VLM setup for image-aware Local Mode. Updated `ACT-011` from a blocked Apple-only local backend into a hybrid local backend protocol story, and added `ACT-012` for MLX model discovery/setup plus `ACT-013` for the MLX vision adapter. Current machine check: `mlx_vlm.generate` exists, `mlx-run35` was not found on PATH, and Hugging Face cache includes `mlx-community/Qwen3.6-35B-A3B-6bit`.
- Fixed `CORE-011`, a selected-region capture alignment regression reported when capturing over Xcode. The overlay still stores the AppKit/global selection rectangle for panel placement, but `ScreenCapturer` now receives a separate Quartz display-space capture rectangle derived from `CGDisplayBounds`, matching `SCScreenshotManager.captureImage(in:)`'s upper-left-origin display coordinate space.
- Investigated `ACT-011` against Xcode 26.4 / macOS SDK 26.4 and official Apple Foundation Models docs. Found that `LanguageModelSession` supports text prompts, streaming response snapshots, model availability states, context size, and token counting, but no image prompt input API. Recorded the blocker in `workflow/decisions.md`, `workflow/references.md`, and `workflow/backlog.md`.
- Closed `CORE-010` after manual QA pass on user hardware: hotkey, language pills, panel placement, Esc/Cmd-C/Cmd-W shortcuts, second-capture stability all confirmed working.
- Updated `workflow/qa-checklist.md` Core Loop section with the validated checks and the date.
- Earlier in the session: shipped `CORE-007`, `CORE-008`, `CORE-009`; fixed an overlay-sizing regression and a use-after-free crash in `OverlayCoordinator`; recorded the Local-First AI Default decision; added `ACT-011`; reflowed Epic 2 dependencies and acceptance criteria so cloud is the upgrade and local is the default; added image+text input to `ACT-005` (Explain) and `ACT-008` (Debug).

## Files Changed In Last Session

- `PixelPane/PixelPane/Onboarding/OnboardingView.swift`
- `workflow/status.md`

## Last Verification

- 2026-05-22: `PixelPane/Scripts/verify-debug-build.sh` succeeded after removing the highlighted default Continue button styling from onboarding.
- 2026-05-22: `PixelPane/Scripts/verify-debug-build.sh` succeeded after adding the temporary onboarding QA reset control.
- 2026-05-22: `PixelPane/Scripts/verify-debug-build.sh` succeeded after fixing first-run onboarding button clipping.
- 2026-05-21: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after completing `ASSIST-005` text-only MLX setup.
- 2026-05-21: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after completing `ASSIST-003` confirmed local file create/edit tools.
- 2026-05-21: `PixelPane/Scripts/verify-debug-build.sh` succeeded after adding the local build verification wrapper.
- 2026-05-21: `PixelPane/Scripts/verify-debug-build.sh` succeeded after completing `PRIV-001` first-run onboarding.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after changing the notch result surface to hover-expand, compact black status-only presentation.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after guarding hover-out collapse with current mouse-position bounds.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after making the collapsed notch hover target transparent.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after removing the notch border and shadow.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after adding yellow processing and green completion notch notification states.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after making the green ready notification appear for non-async Extract results.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after making compact notifications right-aligned and separate from the expanded notch background.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after anchoring compact notification positioning to `NSScreen.auxiliaryTopRightArea`.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after increasing the compact notification notch overlap and squaring its attaching edge.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after removing the close/X button from the notch-expanded result header.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after replacing the notch-expanded action badge with a smaller neutral variant.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after replacing the notch-expanded header badge with a tiny glowing dot.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after reducing notch extension lower-corner radii.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after reducing the compact right-side notification indicator to a tiny dot.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after narrowing the visible compact notification extension and adding the centered transparent notch hover target for dismissed notifications.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after adding a translucent glass treatment and larger lower corners to the expanded notch overlay.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after adding the black-to-glass top fade for hardware notch blending.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after animating the compact notification processing dot.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after strengthening the expanded overlay top fade.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after slowing the hover expansion animation and adding delayed content reveal.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after simplifying footer metadata chips and removing timestamp/chevron from the notch-expanded header.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after removing the notch-expanded title/subtitle header block.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after hardening notch bounds detection and compact placement.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after adding the notch-safe top inset and disabling background dragging for notch-attached panels.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after smoothing collapse animation, hiding the top seam with notch overscan, and pinning compact notifications to the right notch edge.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after realigning the compact notification extension with the hardware notch and flattening its black shape.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after adding the tiny radar-ring processing animation to the compact notch indicator.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after changing collapse to shrink into the compact notch extension before restoring the invisible hover target.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after mirroring the hover-open flow during collapse and fading the expanded shell instead of showing compact content mid-animation.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after forcing action/tab-triggered compact notifications to use the right-edge compact notch size.
- 2026-05-20: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after replacing the compact processing indicator with a tiny assistant-style three-dot animation.
- 2026-05-18: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after revising the notch surface to compact-first island behavior with click-to-expand.
- 2026-05-18: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after capping compact notch preview text and removing the redundant on-appear resize.
- 2026-05-18: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after disabling animated notch expand/collapse.
- 2026-05-10: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after `FOUND-002` documentation updates.
- 2026-05-10: Project inspection confirmed `ENABLE_APP_SANDBOX = NO`, `ENABLE_HARDENED_RUNTIME = YES`, `INFOPLIST_KEY_LSUIElement = YES`, and no checked-in app entitlements file. `codesign -d --entitlements :-` on the Debug app showed user-selected read-only file access and debug `get-task-allow`, with no App Sandbox entitlement.
- 2026-05-10: User manual QA confirmed Cloud Mode works for text captures, image-only/no-text captures, and Ask on image-only captures.
- 2026-05-10: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after enabling image-capable actions for empty-OCR captures.
- 2026-05-10: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after making empty-OCR Cloud Mode captures default to Explain and relaunching the rebuilt Debug app.
- 2026-05-06: Ran a local formatter smoke test using the reported `##`/`**bold**`/backtick/table examples; output becomes plain headings and labeled rows without Markdown source markers.
- 2026-05-06: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after model-output formatting normalization.
- 2026-05-06: Restarted the rebuilt Debug app from `/Users/nayak/Library/Developer/Xcode/DerivedData/PixelPane-fqxsagvqzeiyomgtuwxcttcqkuqa/Build/Products/Debug/PixelPane.app`.
- 2026-05-06: Reproduced the app parser failure with a Swift `URLSession.AsyncBytes.lines` smoke test: the deployed Worker streamed snapshots, but the line reader did not emit blank separator lines, leaving `sawSnapshot false`.
- 2026-05-06: Verified the replacement byte-level SSE parser with a Swift smoke test against deployed `/v1/simplify`; it emitted `meta`, multiple `snapshot`, terminal `done`, and ended with `sawSnapshot true sawDone true`.
- 2026-05-06: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after replacing the app-side Cloud Mode SSE parser.
- 2026-05-06: Quit the prior Pixel Pane process and launched the rebuilt Debug app from `/Users/nayak/Library/Developer/Xcode/DerivedData/PixelPane-fqxsagvqzeiyomgtuwxcttcqkuqa/Build/Products/Debug/PixelPane.app`.
- 2026-05-06: Direct deployed smoke test against `https://pixel-pane-api.snehithn5.workers.dev/v1/simplify` for the captured "Workers and Pages" text returned `meta`, multiple `snapshot`, and terminal `done` events.
- 2026-05-06: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded during Cloud Mode empty-response investigation.
- 2026-05-06: `npm run typecheck` succeeded after making the Worker upstream SSE parser tolerate CRLF delimiters and flush the final buffer.
- 2026-05-06: `npx wrangler deploy` deployed `pixel-pane-api` version `17abf03e-904e-49d6-8b12-64d93c0319b6`.
- 2026-05-06: Direct deployed curl smoke tests against `/v1/simplify` and `/v1/explain` both showed `meta`, multiple `snapshot`, and terminal `done` events after the Worker parser fix.
- 2026-05-06: `npm run typecheck` succeeded in `PixelPane/Backend` after raising the Worker alpha quota.
- 2026-05-06: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after replacing invalid `cloud.slash` symbols.
- 2026-05-06: `npx wrangler deploy` deployed `pixel-pane-api` version `04020fda-06ae-40af-81b0-e28d45db4f77` with `FREE_DAILY_LIMIT = "100"`.
- 2026-05-06: Direct `curl -N` smoke test against deployed `/v1/simplify` returned `remaining_cloud_actions: 94`, streamed a snapshot, and completed with `done`.
- 2026-05-06: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after adding Cloud Mode empty-response handling.
- 2026-05-06: Direct `curl -N` smoke tests against `https://pixel-pane-api.snehithn5.workers.dev/v1/explain` verified both text-only Explain and normal-sized PNG image Explain stream `meta`, multiple `snapshot`, and terminal `done` events.
- 2026-05-06: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after allowing Cloud Mode snapshots to bypass the local prompt-echo filter and accepting whitespace-only SSE delimiter lines.
- 2026-05-06: Direct `curl -N` smoke test against `https://pixel-pane-api.snehithn5.workers.dev/v1/simplify` returned normalized SSE `meta`, multiple `snapshot`, and terminal `done` events.
- 2026-05-06: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after fixing app-side SSE EOF flushing for Cloud Mode.
- 2026-05-06: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after single-toggle Cloud Mode settings and removing automatic local fallback in Cloud Mode.
- 2026-05-06: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after replacing the Response Style slider with the aligned custom three-stop control.
- 2026-05-06: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after fixing Settings window ordering and removing the Response Style description line.
- 2026-05-06: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after fixing the Local AI model picker `nil` selection warning.
- 2026-05-06: `curl` smoke test against `https://pixel-pane-api.snehithn5.workers.dev/v1` confirmed `/auth/token` returns a bearer token with fractional-second `expires_at`, and `/explain` streams `HTTP 200` SSE events with that token.
- 2026-05-06: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after fixing Cloud auth token date decoding.
- 2026-05-06: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after simplifying the Response Style slider.
- 2026-05-06: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after `ACT-015` Cloud Mode app wiring.
- 2026-05-06: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after removing background action precomputation.
- 2026-05-06: `npm run typecheck` succeeded in `PixelPane/Backend` after wiring real Cloudflare KV namespace IDs.
- 2026-05-06: `npx wrangler deploy --dry-run` succeeded in `PixelPane/Backend` and reported the `RATE_LIMIT_KV` binding with the production namespace ID.
- 2026-05-06: `npx wrangler deploy` succeeded and published `pixel-pane-api` at `https://pixel-pane-api.snehithn5.workers.dev`.
- 2026-05-06: `curl` smoke tests confirmed GET requests reach the Worker and return app-level `405` JSON, `/v1/auth/token` returns a bearer token, and `/v1/explain` returns `HTTP 200` with normalized SSE events from Anthropic.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after removing the Ask five-question cap.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after `ACT-014` (smart default action selection).
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after `QUAL-011` (model-output math and special-character normalization).
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after `QUAL-010` (Response style slider).
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after the Liquid Glass overlay panel redesign (`QUAL-009`).
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after adding background Explain warm-up/generation and multi-action loading state in the panel rail.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after hiding the initial background Explain loading indicator and tightening Explain responses to under 90 words.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after routing Simplify through MLX Vision when a ready screenshot-capable model is available.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after suppressing prompt-echo stream chunks and adding an animated working placeholder for loading action output.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after tightening Ask prompts/output caps and stripping repeated question/transcript echoes from Ask answers.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after adding explicit local backend preferences and routing all Ask turns through MLX when available while attaching the screenshot only to the first Ask request.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after adding per-action result-panel output caching so tab switches restore previous results instead of rerunning actions.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after chaining silent Simplify prewarm from Explain completion and separating Explain/Simplify prompt budgets.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after the lighter native result-panel UI pass with slimmer controls, quieter surfaces, compact preview, and hidden model stats.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after restoring larger action/footer click targets and always-visible model stats while keeping the lighter output surface.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after making Translate explicitly target English, removing Apple Translation, routing Translate directly to the local Apple model, and renaming the panel badge.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after splitting MLX runtime stats into metric chips and rendering Ask as chat-style turns.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after the two-pane result panel with capture preview, panel metadata, MLX output formatting, Translate fallback, and tabbed Settings polish.
- 2026-04-29: `npm run typecheck` succeeded in `PixelPane/Backend`.
- 2026-04-29: `npx wrangler deploy --dry-run` succeeded in `PixelPane/Backend`.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after `FOUND-005` app token flow and `FOUND-006` secret guardrails.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after `FOUND-004` backend proxy MVP.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after `PRIV-005` Cloud Mode routing guard.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after `ACT-003` cloud client shell.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after `FOUND-003` backend proxy contract docs.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after `ACT-008` contextual Debug.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after `ACT-007` Ask follow-up conversation.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after `ACT-010` error and empty states.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after showing incompatible downloaded MLX models in Settings.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after tightening MLX vision model validation.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after overlay first-click handling and result-panel visual polish.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after Settings simplification, manual MLX model folder support, Translate, Explain, Simplify, and Export.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after `ACT-012` and `ACT-013`.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after `ACT-001`.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after `ACT-002` and the MLX setup label fix.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after `ACT-011`.
- 2026-04-29: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after the `CORE-011` coordinate fix.
- 2026-04-29: `xcodebuild ... build` succeeded after every meaningful code change.
- 2026-04-29: `codesign -dvv` against the built `.app` confirmed a valid Apple Development signature with Hardened Runtime.
- 2026-05-21: `xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build` succeeded after completing `FOUND-007`.
- 2026-04-29: User confirmed Xcode Product → Run works again; no direct DerivedData app launch workaround is needed.
- 2026-04-29: User completed the Epic 1 manual QA walkthrough on their Mac.
- 2026-04-29: No app build was run for the MLX setup planning update because only workflow/reference docs changed.

## Active Blockers

- Apple Foundation Models remains text-only for Pixel Pane until Apple exposes image prompt input. Image-aware Local Mode now has an MLX adapter path, but actual use still depends on the user having MLX-VLM and a compatible model installed and selected in Settings.
- Full release packaging still needs user-owned Apple Developer ID/notarization credentials before a signed, notarized DMG can be produced and verified.

## Next Best Story

`PRIV-002` - Screen Recording permission guidance.

Suggested prompt:

```text
Complete PRIV-002.
```

## Notes For Next Agent

- Keep implementation work inside `PixelPane/`.
- Keep workflow/task tracking inside `workflow/`.
- `ACT-011` introduced the shared local backend protocol (`AIBackend`) so Apple text, MLX vision, and later cloud clients can conform without action-side rewrites.
- Apple Foundation Models requires Apple Intelligence enabled by the user. MLX requires a local runtime plus a compatible model. Surface both through the existing `RecoveryPanelView` pattern from `CORE-006` rather than inventing a new recovery UI.
- Do not imply image-aware Local Mode is universally available; it is available only when Settings reports a ready MLX model selection.
- Cloud routing UI is enabled. Use Settings → Cloud to turn on "Use Cloud Mode"; the single toggle covers cloud-capable text and image context, while Local Mode remains the default.
- Backend code lives in `PixelPane/Backend`. Local checks are `npm run typecheck` and `npx wrangler deploy --dry-run`.
- `CloudAuthTokenProvider` is invoked by `CloudAIBackend` when Cloud Mode actions run and stores only the anonymous device ID plus short-lived Pixel Pane bearer token in Keychain.
- If Xcode-window captures still emit `Unable to obtain a task name port right` in the debug console, treat it as system/Xcode logging first and check the visible captured OCR region before changing app permissions. The app-level coordinate mismatch fix is in `CORE-011`.
- If asked "where am I?", answer from this file plus `workflow/backlog.md`.
