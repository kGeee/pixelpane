# Project Brief: Pixel Pane

Last updated: 2026-05-28

## Problem Statement

Mac users want help that can understand local context and take small useful actions without forcing them into a browser chatbot or a terminal-only coding agent. Existing assistants are often detached from local context, cloud-first, or too heavyweight for quick Mac-native use.

## Current Product

Pixel Pane is a local-first, notch-native assistant shell for macOS. It lives in the menu bar/notch area, opens quickly into chat, and preserves local context affordances such as selected screen regions, OCR, attached images, user-granted files/folders, and model routing settings.

The previous agentic runtime has been deleted. The app now routes chat through Agent Kernel V2, an app-owned runtime with typed tools, explicit approvals, and bounded control-plane events.

## Target Product

AGENTV2 makes Pixel Pane a Mac-native assistant that can inspect explicitly granted context, use app-owned typed tools, ask before side effects, and keep working through bounded tasks.

## Key Differentiators

1. Notch-native: always nearby without becoming a full desktop workspace.
2. Local-first: Local Mode is default; Cloud Mode is explicit opt-in.
3. Context-aware: screen captures, OCR, images, files, folders, terminal/process output, and chat history are explicit bounded sources.
4. Runtime-owned safety: Pixel Pane validates grants, classifies risk, gates side effects, and treats retrieved content as untrusted data.
5. Model-agnostic: fixture models define the kernel contract before real providers are wired.

## Out Of Scope For Current Alpha

- Autonomous background operation without an active user request.
- Continuous screen recording or a saved screen timeline.
- Unrestricted file-system access.
- Silent file writes, installs, destructive commands, network commands, privileged commands, or process-control actions.
- Browser automation and broad app control.
- Enterprise administration, team workspaces, and monetization polish.

## Success Definition

Pixel Pane is working when a user can ask it to understand local context, inspect a granted project or capture, run safe observations, propose confirmed changes, and receive a coherent answer without manually shuttling information between apps.

After AGENTV2 integration, success means the native shell remains stable while real local/cloud providers can complete bounded tasks through the V2 runtime without chat/control event pollution.

## Current Roadmap

| Phase | Scope |
|---|---|
| Sprint 1 | Stable shell cleanup and runtime deletion |
| Sprint 2 | New AGENTV2 kernel with fixture models |
| Sprint 3 | Typed file, visual, command, process, and evidence capabilities |
| Sprint 4 | Thin provider adapters |
| Sprint 5 | Notch integration, regression matrix, and release hardening |

## Technical Constraints

- macOS 15.2+ minimum.
- SwiftUI plus AppKit interop for notch/chat surfaces, settings, panels, overlays, and menu-bar behavior.
- ScreenCaptureKit for selected-region capture and Apple Vision for OCR.
- Local text and vision through MLX runtimes where configured, with Apple Foundation Models remaining a possible lightweight text route.
- Cloud Mode through the Pixel Pane Cloudflare Worker proxy; provider keys never ship in the app.
- Direct distribution with Developer ID and Sparkle.
- App sandbox disabled for Direct distribution and local-agent capabilities, while product-level file grants remain the trust boundary.
