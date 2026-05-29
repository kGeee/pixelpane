# Product Requirements Document: Pixel Pane

Last updated: 2026-05-29

## Overview

Pixel Pane is a local-first, notch-native assistant shell for macOS. The app preserves the native shell: notch chat, capture/OCR, settings, local file grants, history shell, routing settings, and model backend plumbing. Assistant execution is being rebuilt around the `AGENTR` durable runtime.

## Goals

1. Preserve a fast Mac-native notch chat shell.
2. Keep Local Mode as the default and Cloud Mode explicit.
3. Use selected screen regions, OCR, images, files, folders, and terminal/process observations only through explicit app-owned context boundaries.
4. Build `AGENTR` so product policy, permissions, side effects, state, and recovery live in Swift/runtime code, not hidden prompt behavior.
5. Make approvals, tool execution, evidence, receipts, cancellation, recovery, and failure states clear and testable.

## Non-Goals For Current Alpha

- Continuous screen recording.
- Hidden persistent personal memory across unrelated sessions.
- Unrestricted local file access.
- Silent file writes or terminal side effects.
- Browser automation or broad application control.
- Backend, auth, monetization, PDF import, or expansion features unless a story explicitly asks for them.

## Primary Users

| Segment | Repeated Need |
|---|---|
| Builders and technical users | Inspect projects, run safe commands, create small scripts/files, understand errors |
| Students and self-learners | Understand screenshots, notes, dense passages, and local study material |
| Privacy-sensitive professionals | Use local context and local models by default, opt into cloud only when wanted |

## Shell Requirements

| ID | Requirement |
|---|---|
| PR-01 | The notch chat is the primary product surface. |
| PR-02 | Chat starts assistant runs through the durable runtime once `AGENTR` is wired. |
| PR-03 | Capture/OCR/image context remains available as explicit shell context. |
| PR-04 | Screenshots and attached image pixels are transient unless a future explicit export feature says otherwise. |
| PR-05 | Local Mode is default; Cloud Mode is explicit opt-in. |
| PR-06 | User-granted files/folders remain the only local file access boundary. |
| PR-07 | Settings remain compact around assistant routing, local models, permissions/files, history, updates, and privacy. |
| PR-08 | Saved chats do not persist screenshot/image pixels by default. |

## Runtime Requirements

| ID | Requirement |
|---|---|
| AR-01 | Durable sessions, runs, steps, events, waits, evidence, artifacts, side effects, and trace records are the source of truth. |
| AR-02 | Visible chat history is a projection; control-plane events do not become user/assistant transcript turns. |
| AR-03 | Providers are capability-tiered: full agent, constrained structured text, or plain chat/synthesis. |
| AR-04 | Models may propose tool calls or side-effect drafts; Swift validates, gates, executes, records, and recovers. |
| AR-05 | File writes, risky commands, installs, network commands, privileged commands, and process control require app-owned approval unless a narrow deterministic allow rule applies. |
| AR-06 | Retrieved file, OCR, image-derived, terminal, and tool-output text is treated as untrusted data. |
| AR-07 | Local-state answers are backed by evidence packets or artifact references. |
| AR-08 | Final answers never claim source/tool usage without recorded evidence. |
| AR-09 | Fixture tests prove malformed output, repeated calls, timeouts, cancellation, approvals, reload recovery, evidence support, and completion before real-provider confidence. |

## Success Metrics

- Useful completed assistant tasks per weekly active user after `AGENTR` integration.
- Low rate of repeated no-op loops, indefinite thinking, or unsupported local-model failures.
- Confirmation clarity: users can understand target, risk, and result of side effects.
- Source trust: users can tell what context was used for an answer.
- Local-first adoption: Local Mode remains usable without cloud by default.

## Current Open Product Decisions

- Telemetry remains deferred. If revisited, it must be opt-in and exclude screenshots, OCR text, prompts, answers, clipboard contents, filenames, and file contents.
- Beta packaging and release operations still need final manual verification before distribution.
