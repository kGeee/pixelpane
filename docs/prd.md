# Product Requirements Document: Pixel Pane

## Introduction / Overview

Pixel Pane is a native macOS utility that lets a user select any region of the screen and instantly **translate, explain, simplify, extract text, or ask a follow-up question** about what they see. The product's defining interaction is a global hotkey → drag-select overlay → compact floating result panel. It is not a desktop chatbot; it is the fastest way to understand foreign or difficult text anywhere on a Mac, without switching apps or windows.

## Goals

1. Deliver a sub-second hotkey-to-panel experience for any on-screen text.
2. Make translation the acquisition wedge and explanation the retention engine.
3. Win on privacy: explicit capture only, local OCR always available, optional local model setup for image-aware AI, ephemeral in-memory captures by default.
4. Ship a focused, opinionated v1 that builds daily habit before monetizing.

## Non-Goals (v1)

- Autonomous app control or browser automation
- Continuous screen recording or a saved screen timeline
- Persistent personal memory across sessions
- Full multi-page layout-preserving PDF export
- Enterprise SSO or advanced admin controls (post-MVP)

## Target Users

| Segment | Repeated Need |
|---|---|
| Students & self-learners | Dense textbook passages, lecture slides, problem statements |
| Multilingual professionals | Coworker messages, emails, internal docs, support threads |
| Everyday users & travelers | Menus, product pages, PDFs, signs, webpages |

## Success Metrics (North Star)

- **Primary**: Helpful captures per weekly active user (user copied, saved, exported, pasted, or asked a follow-up after the result)
- **Supporting**: Time from hotkey to first answer; first-session activation rate; 7-day retention among activated users; share of sessions using Translate vs. Explain; free-to-paid conversion rate

---

## Epics and User Stories

### Epic 0: Foundations
*Decisions and infrastructure that must exist before product epics can ship. These are largely invisible to the user but block everything else.*

**Story 0.1 – Distribution Model & Code Signing**
As the team, we need to set up Direct distribution with Developer ID signing and Sparkle updates so all downstream stories can rely on the same release path.
- Acceptance: Direct distribution decision recorded in `architecture.md`; Apple Developer account configured; Developer ID certificate installed on build machine; entitlements file finalized; first signed-and-notarized DMG runs cleanly on a fresh macOS install.

**Story 0.2 – Claude API Backend Proxy**
As the system, we need a backend service that holds the Claude API key, accepts authenticated requests from the client, applies rate limits, and forwards calls to Anthropic, so that the API key never ships in the binary.
- Acceptance: A small service (e.g., Cloudflare Workers, Vercel, or Fly.io) with endpoints `/translate`, `/explain`, `/simplify`, `/ask`, `/study`, `/menu`, `/debug`; each accepts an auth token and returns a streamed Claude response; per-token daily request counter; logging excludes prompt content by default.

**Story 0.3 – Authentication & Anonymous Device IDs**
As a user, I want to use the app without creating an account on the free tier, but link my purchases to a real account when I upgrade, so that I don't hit a sign-up wall on first run.
- Acceptance: Anonymous device ID generated and stored in Keychain on first launch; backend issues a JWT scoped to that ID; Sign in with Apple offered (and required) to upgrade to Pro; account links the existing device ID to the upgraded subscription.

**Story 0.4 – Minimum OS Strategy**
As a user, I want the minimum macOS requirement to be explicit before install so that I know whether Pixel Pane can run on my Mac.
- Acceptance: Minimum supported macOS version is recorded in `architecture.md`; product docs and release requirements state macOS 15.2+; unsupported older macOS versions are handled by installer/release messaging rather than an in-app compatibility mode.

**Story 0.5 – Privacy-Preserving Telemetry**
As the team, we need opt-in usage analytics that capture event-level data (e.g., "translate action used," "session duration") without ever capturing prompt content, screenshots, or OCR text.
- Acceptance: Telemetry off by default; consent prompt during onboarding (after permissions); event schema documented in `architecture.md`; telemetry SDK choice (e.g., PostHog self-hosted, Plausible, or custom) recorded; user can revoke and clear local queue any time.

**Story 0.6 – App Update Mechanism**
As a user, I want the app to update itself silently in the background so I always have the latest version without checking manually.
- Acceptance: Sparkle integrated, update feed served via HTTPS, EdDSA-signed updates, and a new release verifies on a fresh machine.

---

### Epic 1: Core Capture Loop
*Deliver the universal select-to-understand interaction. This is the product's defining loop and must feel instant and native.*

**Story 1.1 – Global Hotkey Activation**
As a user, I want to press a global keyboard shortcut from any app so that I can begin a capture without switching windows.
- Acceptance: Hotkey works system-wide, including over full-screen apps, via Carbon `RegisterEventHotKey`; default `⌘⇧Space`; configurable in Settings; conflict detection rejects single-key bindings, plain modifiers, reserved combos like `⌘Q`/`⌘W`/`⌘Tab`, and combinations macOS rejects; registration failures show clear recovery. Accessibility permission is not required for the alpha Carbon path; `CGEventTap` is deferred unless Carbon fails QA.

**Story 1.2 – Dimmed Overlay & Region Selection**
As a user, I want a full-screen dimmed overlay to appear where I can click-drag to select a region, so that I can precisely target the text I need help with.
- Acceptance: One overlay window per `NSScreen` (multi-display support); overlay appears within 100ms of hotkey; cursor changes to crosshair; selected region is highlighted with a bright border and a cleared cutout; coordinates captured at native HiDPI pixel density; pressing Escape cancels cleanly with no temp files written; selections smaller than 20×20 pixels are rejected with a brief tooltip.

**Story 1.3 – Local OCR**
As a user, I want OCR to run locally on the captured image so that my screen contents never leave my device unless I explicitly choose a cloud action.
- Acceptance: Uses Apple Vision (`VNRecognizeTextRequest`, `.accurate` mode); processes in <1s for ≤200 words, <3s for ≤1000 words on Apple Silicon; progress indicator shown if processing exceeds 1s; handles standard font sizes down to 10pt; returns ordered text plus per-line bounding boxes; runs in-process from `CGImage` (no disk write).

**Story 1.4 – Language Detection**
As a user, I want the app to automatically detect the language of the captured text so that I don't have to specify source language manually.
- Acceptance: Uses `NLLanguageRecognizer` immediately after OCR; result cached on the capture record so downstream actions (Translate, Explain) reuse it; detection result shown in the result panel header; falls back to "Unknown" with a manual selector when confidence < 0.5; supports top 30 languages at launch.

**Story 1.5 – Floating Result Panel**
As a user, I want a compact floating panel to appear near my selection so that I can see the result without losing context of the underlying app.
- Acceptance: Panel placement tries 4 anchor points (right, below, left, above) and picks the first that fully fits within the active screen's visible frame; falls back to screen center if none fit; resizes to content with min 320×200 and max 600×800; draggable by header; closeable with Escape; keyboard shortcuts in panel: `T` Translate, `E` Explain, `S` Simplify, `X` Extract, `A` Ask, `⌘C` copy result, `⌘W` close.

**Story 1.6 – Menu Bar App & Status Item**
As a user, I want the app to live in the menu bar with a small icon so that it's always accessible but never intrusive.
- Acceptance: App is `LSUIElement` (no Dock icon); status item with custom icon; clicking it shows a menu with: Capture (triggers hotkey flow), History when available, Settings, Pause Hotkey, Quit; right-click shows the same menu; icon adapts to light/dark menu bar.

---

### Epic 2: Action Rail & Result Formats
*Give users the five primary actions with outputs that feel tailored to content type, not generic.*

**Story 2.1 – Translate Action**
As a user, I want to translate the captured text to my preferred language so that I can understand foreign-language content instantly.
- Acceptance: Detects source language; translates to user's default target language; result shows source language, target language, and translated text; ambiguous phrases flagged.

**Story 2.2 – Explain Action**
As a user, I want a plain-English explanation of the captured text so that I understand not just the words but the meaning and context.
- Acceptance: Response calibrated to general reading level; includes a brief context note if the content is domain-specific; follow-up input enabled.

**Story 2.3 – Simplify Action**
As a user, I want complex or dense text rewritten in simpler language so that I can quickly grasp the main idea.
- Acceptance: Output is shorter than input; preserves core meaning; readable at ~8th-grade level.

**Story 2.4 – Extract Text Action**
As a user, I want to extract the raw text from a screenshot so that I can copy and paste it into other apps.
- Acceptance: Returns structured plain text; preserves line breaks from original; one-click copy to clipboard.

**Story 2.5 – Ask (Follow-up) Action**
As a user, I want to type a follow-up question about the captured content so that I can go deeper without re-capturing.
- Acceptance: Text input appears in the panel; default backend is local. Text-only turns use Apple Foundation Models when available; image-aware first turns use the installed MLX vision model after local model setup passes a smoke test. When the user has switched on Cloud Mode and granted the per-action image opt-in, the request routes to the Claude proxy instead. Subsequent turns never resend image data regardless of backend, to keep token cost and latency bounded; supports up to 5 turns per capture; conversation cleared when panel closes.

**Story 2.6 – Debug Action (Contextual)**
As a user, I want a Debug action to appear automatically when the captured text looks like code, logs, or an error message so that I get technical help without seeing this button for normal text.
- Acceptance: Content classifier detects code-like or error-like patterns; Debug button appears in action rail when confidence > 0.8; output explains the issue and suggests next steps.

**Story 2.7 – Copy / Export Controls**
As a user, I want to copy the result text or export it so that I can use it elsewhere.
- Acceptance: Copy button in panel copies result to clipboard; Export saves as plain text file to Downloads; both actions show a brief confirmation.

**Story 2.8 – Error & Empty States**
As a user, I want clear, actionable error messages when something goes wrong so that I know what to do next.
- Acceptance: OCR returns no text -> "No text found. Try a larger region or higher contrast." with a "Try Again" button. Network failure -> "Couldn't reach Pixel Pane servers. Try again or use a local action." with retry. Cloud rate limit (429) -> "You've hit today's free limit. Upgrade to Pro for unlimited." Translation pack missing -> inline download progress with size and ETA. Selection too small -> "Select a larger region." None of these errors discard the in-memory capture until the user dismisses the panel.

---

### Epic 3: Privacy & Onboarding
*Make privacy a feature, not fine print. The onboarding must build trust before requesting screen-recording permission.*

**Story 3.1 – Permissions Onboarding Flow**
As a new user, I want a clear onboarding screen that explains exactly what screen access the app requires and why, so that I feel confident granting permission.
- Acceptance: Onboarding shown on first launch before any permission prompt; states the three promises: (1) only captures selected regions, (2) never records continuously, (3) captures are processed in memory by default and discarded when the panel closes.

**Story 3.2 – Ephemeral Capture Handling**
As a user, I want selected screen captures to stay ephemeral so that sensitive content isn't stored.
- Acceptance: Capture is held in memory as a `CGImage` and is not written to disk during the normal capture/OCR/action flow; if an error occurs, the in-memory capture may be retained only until the user dismisses the panel or retries; cancellation and panel close release the capture reference; unit tests verify the capture pipeline does not create temp files.

**Story 3.3 – Local vs. Cloud Mode Toggle**
As a user, I want every AI action to run locally by default and a clear opt-in to upgrade to cloud quality so that my content stays on-device unless I explicitly route it out.
- Acceptance: Default state is Local — OCR, Extract Text, language detection, Translate, Explain, Simplify, Ask, and Debug all run on-device when their required local runtime is available. Apple Vision handles OCR, Apple Foundation Models handles text-only local AI when available, and optional MLX setup enables image-aware local AI. Settings exposes a "Use Cloud Models" opt-in that routes AI actions to the Claude proxy for higher quality when network is available; a separate per-feature opt-in is required before any captured image is sent to the cloud; UI labels every action that will hit the network before the user invokes it; a quality disclaimer is shown on local responses ("Local mode is fast and private; cloud mode may be more accurate"); turning Cloud Mode off or losing network instantly falls back to local without losing the in-flight panel.

**Story 3.4 – Detected Language & Source Transparency**
As a user, I want the result panel to show the detected language and whether text came from OCR or structured input, so that I can judge the result's reliability.
- Acceptance: Result header shows: detected language, source type (OCR / PDF text layer), and a badge when a phrase is flagged as ambiguous or culturally specific.

**Story 3.5 – Settings Window**
As a user, I want a dedicated Settings window where I can configure the hotkey, default target language, local/cloud mode, glossary, account, and privacy controls.
- Acceptance: Opened from menu bar; tabs: General (hotkey, target language, model speed), Local Models (discover/install/select MLX vision model), Privacy (local/cloud mode, telemetry opt-in, ephemeral capture confirmation), Account (sign-in status, plan, manage subscription), Glossary when available (list, add, edit, delete), About (version, view onboarding, view licenses); all changes persist immediately to `UserDefaults` or Keychain; closing the window does not quit the app.

**Story 3.6 – First-Capture Tutorial**
As a new user, I want the app to walk me through my first capture with a sample image or guided overlay so that I get to a successful "aha" within 60 seconds of install.
- Acceptance: After onboarding completes, status item bounces or shows a tooltip with the configured hotkey; first time the user presses the hotkey, the overlay shows a tip strip ("Drag to select any text"); after the first successful capture, a toast says "Try the Translate or Explain buttons →"; tutorial state tracked separately from `hasCompletedOnboarding` so it does not re-show.

---

### Epic 4: Content-Aware Modes (Expansion)
*Make the product feel purpose-built for real-world content types rather than generic.*

**Story 4.1 – Content Classification**
As the system, I want to classify captured content into Message, Study, Menu, or Technical so that the correct mode and prompt are applied automatically.
- Acceptance: Lightweight classifier (rule-based for v1, with optional lightweight model later) runs after OCR; classification result is logged only when telemetry is enabled and never with OCR text; user can override in the panel.

**Story 4.2 – Message Mode**
As a multilingual professional, I want translated messages to include a tone note and optional reply suggestions, so that I can respond appropriately, not just literally.
- Acceptance: Translation shown first; short note on tone/register (e.g., "formal," "urgent," "casual") below; 2–3 reply starters offered as optional chips.

**Story 4.3 – Study Mode**
As a student, I want explanations of academic text to define key terms, simplify the passage, and optionally ask me a clarifying question before going deeper, so that I actually understand rather than just get an answer.
- Acceptance: Key terms bolded and defined inline; simplified paragraph follows; one Socratic follow-up question offered (user can skip).

**Story 4.4 – Menu Mode**
As a traveler, I want translated menu items to preserve original dish names alongside a translated description and notes on culturally unfamiliar terms, so that I know what I'm ordering.
- Acceptance: Output format: [Original Name] — [Translation] — [Context note if needed]; notes appear only for terms where literal translation would be misleading.

**Story 4.5 – Glossary Support**
As a returning user, I want to save specific translations or term definitions to a personal glossary so that the app uses my preferred terminology in future sessions.
- Acceptance: "Save to Glossary" button in result panel captures source phrase + preferred translation/note; glossary stored locally (CoreData); on each translate/explain request, the client scans OCR text for glossary matches (case-insensitive substring) and injects the top 20 matches into the system prompt as a "Preferred terminology" section; entries listed, editable, and deletable in Settings; export/import as JSON.

**Story 4.6 – Page-by-Page PDF Import**
As a user, I want to import a PDF and translate or explain it page by page, so that I can work through longer documents without re-capturing each page manually.
- Acceptance: File picker supports PDF import; pages displayed one at a time; Translate / Explain actions apply to current page; navigation arrows for prev/next page.

---

### Epic 5: Monetization & Subscriptions (Monetization Release)
*Add commercial layer after core habit is established.*

**Story 5.1 – Free Plan Limits & Gating**
As the product, I want to enforce daily limits on cloud actions for free users so that the business is viable while still allowing habit formation.
- Acceptance: Free plan: unlimited local OCR, unlimited local capture, 10 cloud actions per day; **limit enforced server-side** in the backend proxy keyed on anonymous device ID; client displays the count returned by the server; resets at UTC midnight; when limit is hit, the action button shows "Upgrade for unlimited" with a link to the paywall.

**Story 5.2 – Pro Subscription ($8–12/month)**
As a power user, I want a Pro plan that unlocks unlimited cloud actions, faster model options, PDF import, saved history, and glossary memory, so that the product fits into my daily workflow.
- Acceptance: Stripe subscription managed through RevenueCat for Direct distribution; Pro badge in Settings; all gated features unlocked on subscription confirmation.

**Story 5.3 – Student Subscription (~$4–6/month)**
As a student, I want a discounted subscription plan so that I can afford the full feature set.
- Acceptance: Student plan offered in paywall; includes all Pro features except Team features; priced at ~50% of Pro.

**Story 5.4 – Saved History**
As a Pro user, I want to browse my past captures and results so that I can revisit translations or explanations I did earlier.
- Acceptance: History opens in a **dedicated window** from the menu bar (not as a sidebar of the floating panel); captures stored locally in CoreData with thumbnail (downscaled to 256px wide), result text, mode used, and timestamp; searchable by text content (full-text index); deletable individually or all-at-once; opt-in only; not synced to cloud by default; Pro users get unlimited local history, while free users can keep the last 5 captures.

**Story 5.5 – Team Tier (Post-MVP)**
As a team admin, I want shared glossaries, workspace billing, and admin controls so that my team has a consistent translation and terminology experience.
- Acceptance: Invite-based team workspace; shared glossary editable by admins; per-seat billing; admin can set data retention policy (ephemeral only vs. local history).

---

### Epic 6: Cross-Cutting Quality
*Required quality bars that span the whole app and don't fit cleanly into a single feature epic.*

**Story 6.1 – Accessibility Support**
As a user with disabilities, I want the app to support VoiceOver, Dynamic Type, sufficient color contrast, and reduced motion so that I can use it the way I use the rest of macOS.
- Acceptance: All interactive elements have meaningful `accessibilityLabel`; result panel readable by VoiceOver in proper reading order; respects system Dynamic Type up to xxxLarge; all text/background combinations meet WCAG AA contrast (4.5:1 normal, 3:1 large); respects "Reduce Motion" preference (overlay fade and panel slide become instant); hotkey-equivalent action available from the menu bar status item for users who can't use chord keystrokes.

**Story 6.2 – App UI Localization (Top 10 Languages)**
As a non-English-speaking user, I want the app's interface in my language so that the tool feels native.
- Acceptance: All user-facing strings extracted to `.strings` / `String Catalog`; localized into top 10 by share: English, Spanish, Simplified Chinese, Hindi, Arabic, Portuguese, Russian, Japanese, German, French; right-to-left layout works for Arabic; date/number formatting uses `Locale.current`; localization process documented for future languages.

---

## Functional Requirements Summary

| ID | Requirement |
|---|---|
| FR-01 | Global hotkey activates overlay from any app, including full-screen |
| FR-02 | Region selection with dimmed overlay and crosshair cursor |
| FR-03 | Local OCR via Apple Vision, processing in <1s on M-series |
| FR-04 | Automatic language detection for top 30 languages |
| FR-05 | Floating result panel anchored to selection, draggable, escapable |
| FR-06 | Five primary actions: Translate, Explain, Simplify, Extract Text, Ask |
| FR-07 | Contextual Debug action triggered by code/error content detection |
| FR-08 | Copy to clipboard and export to file from result panel |
| FR-09 | Ephemeral in-memory capture handling with no normal-path disk writes |
| FR-10 | Local vs. cloud mode toggle with quality disclaimer |
| FR-11 | Result panel shows detected language, source type, ambiguity flags |
| FR-12 | Content classification into Message / Study / Menu / Technical modes |
| FR-13 | Mode-specific result formats (tone notes, key terms, dish names) |
| FR-14 | Personal glossary with save, edit, delete |
| FR-15 | Page-by-page PDF import with per-page translate/explain |
| FR-16 | Free plan daily limits with in-app counter |
| FR-17 | Pro and Student subscriptions via Stripe + RevenueCat |
| FR-18 | Local saved history with search and delete |
| FR-19 | macOS 15.2+ minimum supported version; no macOS 14/15.0 compatibility mode in alpha or v1 |
| FR-20 | Model routing: Haiku for Translate / Extract / Simplify; Sonnet for Explain / Study / Menu / Debug / Ask follow-ups |
| FR-21 | Server-side rate limiting on free tier (anonymous device ID) |
| FR-22 | App UI localized in top 10 languages |
| FR-23 | Anonymous-by-default; Sign in with Apple required only for Pro |

## Non-Functional Requirements

| ID | Requirement |
|---|---|
| NFR-01 | Hotkey to overlay: <100ms |
| NFR-02 | OCR: <1s for ≤200 words; <3s for ≤1000 words on Apple Silicon; progress indicator beyond 1s |
| NFR-03 | Cloud action total response: <3s on stable connection |
| NFR-04 | App binary size: <50MB (excluding optional language packs) |
| NFR-05 | macOS 15.2+ minimum supported version |
| NFR-06 | No continuous screen recording; only explicit user-triggered captures |
| NFR-07 | Local mode must work fully offline (assumes language packs already downloaded) |
| NFR-08 | All analytics must be opt-in; no prompt content, OCR text, or screenshots ever logged |
| NFR-09 | Cloud responses are streamed; first token must appear in <800ms p50 |
| NFR-10 | Multi-display support: one overlay per `NSScreen`, capture at native pixel density |
| NFR-11 | Accessibility: VoiceOver, Dynamic Type, WCAG AA contrast, Reduce Motion |
| NFR-12 | Crash reporting via opt-in Apple-bundled crash reporter or Sentry |

## Technical Assumptions

- **Platform**: macOS 15.2+ (Sequoia) minimum. SwiftUI for panels and Settings; AppKit for overlay (`NSWindow`).
- **Distribution**: **Direct (Developer ID + Sparkle)** is the v1 path because the app needs ScreenCaptureKit permission UX, Sparkle updates, and Stripe + RevenueCat outside the Mac App Store. The alpha global hotkey uses Carbon `RegisterEventHotKey`; `CGEventTap` is deferred unless Carbon fails QA.
- **OCR**: Apple Vision framework (`VNRecognizeTextRequest`, `.accurate` mode)
- **On-device translation**: local Apple model through Apple Foundation Models when Apple Intelligence is available
- **Cloud AI**: Claude API behind a backend proxy. **Model routing**: Haiku for Translate / Extract / Simplify (cheap, latency-sensitive); Sonnet for Explain / Study / Menu / Debug / multi-turn Ask (reasoning-heavy)
- **Backend**: Lightweight proxy (Cloudflare Workers, Vercel, or Fly.io) holding the Anthropic API key, applying per-device rate limits, streaming responses to the client
- **Screen capture**: `ScreenCaptureKit` for the captured region; overlay rendering is plain `NSWindow` (does not need ScreenCaptureKit)
- **Payments**: Stripe + RevenueCat for Direct distribution
- **Auth**: Anonymous device ID (Keychain) + Sign in with Apple for Pro
- **Updates**: Sparkle update feed for Direct distribution
- **Telemetry**: Opt-in only; PostHog (self-hosted) or Plausible
- **Crash reporting**: Apple's bundled reporter or Sentry, both opt-in
- **PDF**: PDFKit for page-by-page import (Expansion release)
- **Persistence**: `UserDefaults` for settings, Keychain for secrets, CoreData for history and glossary

## Release Milestones

| Release | Epics | Goal |
|---|---|---|
| **Foundations** | 0 | Distribution, backend, auth, telemetry, updates — invisible but blocking |
| **Launch** | 1, 2, 3, 6 | Core loop, action rail, privacy, accessibility, localization |
| **Expansion** | 4 | Content-aware modes, glossary, PDF |
| **Monetization** | 5 | Subscriptions, history, Team tier |

## Open Decisions

These decisions block downstream stories. Resolve them before kicking off Epic 0:

1. **PDF import scope** — Keep in Expansion release or defer further?
2. **Telemetry vendor** — PostHog self-hosted, Plausible, or something else?
3. **Backend hosting** — Cloudflare Workers, Vercel, Fly.io, or other?
