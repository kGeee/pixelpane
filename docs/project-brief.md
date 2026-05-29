# Project Brief: Pixel Pane

Last updated: 2026-05-29

## Problem Statement

Mac users want help that can understand local context and take small useful actions without forcing them into a browser chatbot or a terminal-only coding agent. Existing assistants are often detached from local context, cloud-first, or too heavyweight for quick Mac-native use.

## Current Product

Pixel Pane is a local-first, notch-native assistant shell for macOS. It lives in the menu bar/notch area, opens quickly into chat, and preserves local context affordances such as selected screen regions, OCR, attached images, user-granted files/folders, and model routing settings.

The current agent implementation is unreliable and is being replaced by the `AGENTR` durable runtime. The shell remains valuable; the execution architecture is the part being rebuilt.

## Target Product

Pixel Pane should be a Mac-native assistant that can inspect explicitly granted context, use app-owned tools, ask before side effects, recover from interruption, and answer from structured evidence rather than brittle prompt state.

## Key Differentiators

1. Notch-native: always nearby without becoming a full desktop workspace.
2. Local-first: Local Mode is default; Cloud Mode is explicit opt-in.
3. Context-aware: screen captures, OCR, images, files, folders, terminal/process output, and chat history are explicit bounded sources.
4. Runtime-owned safety: Pixel Pane validates grants, classifies risk, gates side effects, and treats retrieved content as untrusted data.
5. Durable execution: sessions, runs, waits, evidence, artifacts, side effects, and trace records survive reloads and drive UI projection.
6. Model-agnostic by capability: full agent mode is available only to providers that support native tool calls or strict structured output.

## Out Of Scope For Current Alpha

- Autonomous background operation without an active user request.
- Continuous screen recording or a saved screen timeline.
- Unrestricted file-system access.
- Silent file writes, installs, destructive commands, network commands, privileged commands, or process-control actions.
- Browser automation and broad app control.
- Enterprise administration, team workspaces, auth, monetization polish, PDF import, or expansion features unless a story explicitly asks for them.

## Success Definition

Pixel Pane is working when a user can ask it to understand local context, inspect a granted project or capture, run safe observations, propose confirmed changes, and receive a coherent answer without manually shuttling information between apps.

For the rearchitecture, success means the native shell remains stable while `AGENTR` prevents indefinite thinking, preserves run state durably, gates side effects through app policy, and produces answers backed by evidence packets and traceable run events.

## Current Roadmap

| Phase | Scope |
|---|---|
| `ARCHREV` | Architecture revision, research, audits, findings, and implementation sprint |
| `DOCREV` | Delete stale docs and align remaining docs to the selected architecture |
| `AGENTR` | Implement durable run store, runner, model gateway, policy, side effects, evidence, UI projection, trace export, cleanup, and regression gates |

## Technical Constraints

- macOS 15.2+ minimum.
- SwiftUI plus AppKit interop for notch/chat surfaces, settings, panels, overlays, and menu-bar behavior.
- ScreenCaptureKit for selected-region capture and Apple Vision for OCR.
- Local text and vision through MLX runtimes where configured, with Apple Foundation Models remaining a possible lightweight text route.
- Cloud Mode through the Pixel Pane backend proxy; provider keys never ship in the app.
- Direct distribution with Developer ID and Sparkle.
- App sandbox disabled for direct distribution and local-agent capabilities, while product-level file grants remain the trust boundary.
