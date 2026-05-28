# Product Requirements Document: Pixel Pane

Last updated: 2026-05-28

## Overview

Pixel Pane is a local-first, notch-native assistant shell for macOS. Assistant execution now routes through AGENTV2, an app-owned model-agnostic runtime, while preserving the native shell: notch chat, capture/OCR, settings, local file grants, chat history shell, routing settings, and model backend plumbing.

## Goals

1. Preserve a fast Mac-native notch chat shell.
2. Keep Local Mode as the default and Cloud Mode explicit.
3. Use selected screen regions, OCR, images, files, folders, and terminal/process observations only through explicit app-owned context boundaries.
4. Build AGENTV2 as a deterministic runtime where product policy lives in Swift, not internal prompts.
5. Make approvals, tool execution, evidence, receipts, cancellation, and failure states clear and testable.

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

## Current Shell Requirements

| ID | Requirement |
|---|---|
| PR-01 | The notch chat is the primary product surface. |
| PR-02 | Chat opens and routes messages through Agent Kernel V2. |
| PR-03 | Capture/OCR/image context remains available as shell context. |
| PR-04 | Screenshots and attached image pixels are transient unless a future explicit export feature says otherwise. |
| PR-05 | Local Mode is default; Cloud Mode is explicit opt-in. |
| PR-06 | User-granted files/folders remain the only local file access boundary. |
| PR-07 | Settings remain compact around assistant routing, local models, permissions/files, history, updates, and privacy. |
| PR-08 | Saved chats do not persist screenshot/image pixels by default. |

## AGENTV2 Target Requirements

| ID | Requirement |
|---|---|
| AV2-01 | The runtime owns task state, event flow, approvals, cancellation, loop budgets, failures, and completion. |
| AV2-02 | Chat transcript contains user messages and assistant messages only; control-plane events stay separate. |
| AV2-03 | Models may propose final text or typed tool calls; Swift validates and executes. |
| AV2-04 | File, visual context, finite command, long-running process, and local server lifecycle capabilities are typed tools. |
| AV2-05 | File writes are staged proposals inside granted locations and require visible confirmation. |
| AV2-06 | Risky, destructive, process-control, install, network, privileged, or system-affecting commands require confirmation or are blocked. |
| AV2-07 | Retrieved file, OCR, image-derived, terminal, and tool-output text is treated as untrusted data. |
| AV2-08 | Final answers never claim tool/source usage without explicit observations. |
| AV2-09 | Fixture models prove malformed output, repeated calls, timeouts, cancellation, approvals, and completion before real providers are wired. |

## Success Metrics

- Useful completed assistant tasks per weekly active user after AGENTV2 integration.
- Low rate of repeated no-op loops or unsupported local-model failures.
- Confirmation clarity: users can understand target, risk, and result of side effects.
- Source trust: users can tell what context was used for an answer.
- Local-first adoption: Local Mode remains usable without cloud by default.

## Current Open Product Decisions

- Telemetry remains deferred. If revisited, it must be opt-in and exclude screenshots, OCR text, prompts, answers, clipboard contents, filenames, and file contents.
- Beta packaging and release operations still need final manual verification before distribution.
