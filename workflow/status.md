# Pixel Pane Status

Last updated: 2026-05-29

## Product Focus

Pixel Pane is a local-first, notch-native assistant shell for macOS. Keep the native shell, capture/OCR foundation, local file grants, settings, backend routing, and approval UX. The unreliable pre-rearchitecture agent path has been replaced by the `AGENTR` durable runtime.

## Current Phase

Current recommended story: none in the tool reliability sprint.

Why: `TOOLR` is implemented and automated fixtures plus debug build pass. Remaining confidence work is live notch-shell QA with the real local provider and granted folders.

## Current App State

- Xcode project: `PixelPane/PixelPane.xcodeproj`.
- Build command:

```bash
PixelPane/Scripts/verify-debug-build.sh
```

- Last app verification: 2026-05-29, `PixelPane/Scripts/verify-debug-build.sh` succeeded after `TOOLR`.
- Last agent verification: 2026-05-29, all AGENTR, TOOLC, and TOOLR fixture scripts passed, including `run-agent-model-gateway-fixture-tests.sh`, `run-agent-permission-policy-fixture-tests.sh`, and `run-agent-tool-calling-fixture-tests.sh`.
- Last architecture revision: 2026-05-29, `ARCHREV` completed and selected a durable agent runtime with provider tiers, policy-owned side effects, evidence packets, and UI projection from run state.
- Last documentation reset: 2026-05-29, `DOCREV-004` aligned repo instructions, product docs, backend docs, release docs, references, and QA around `AGENTR`.
- Last implementation update: 2026-05-29, `TOOLR` fixed live tool-call reliability defects from `docs/example-chats`: canonical path resolution, raw provider protocol parsing, failed side-effect run state, and regression coverage.

## Active Roadmap

1. Sprint ARCHREV: Agent Architecture Revision - Done
   - Failure corpus, architecture map, comparable-platform research, audits, findings, and implementation sprint were completed.
   - Source artifact: `workflow/agent-architecture-revision.md`.
2. Sprint DOCREV: Documentation Reset After Architecture Revision - Done
   - `DOCREV-001` Inventory every repository document for stale agent context - Done
   - `DOCREV-002` Delete deprecated documentation instead of preserving it - Done
   - `DOCREV-003` Rewrite the focused architecture and workflow docs - Done
   - `DOCREV-004` Align repo instructions, backend docs, and code-adjacent docs - Done
3. Sprint AGENTR: Agent Runtime Rearchitecture Implementation - Done
   - `AGENTR-001` Build durable agent run store and event schema - Done
   - `AGENTR-002` Add checkpointed runner and app-launch recovery - Done
   - `AGENTR-003` Build capability-tiered model gateway - Done
   - `AGENTR-004` Build permission policy and filtered tool catalog - Done
   - `AGENTR-005` Split side-effect drafts, approvals, execution, and rollback - Done
   - `AGENTR-006` Add evidence packets, artifacts, and deterministic local controllers - Done
   - `AGENTR-007` Replace chat UI bridge with durable run projection - Done
   - `AGENTR-008` Replace debug export and chat history with trace projections - Done
   - `AGENTR-009` Remove superseded AGENTV2 runtime paths and wire the new runtime - Done
   - `AGENTR-010` Add rearchitecture regression matrix and real-provider QA gates - Done
4. Sprint TOOLC: Durable Tool Calling Integration - Done
   - `TOOLC-001` Add durable model-tool-result orchestration loop - Done
   - `TOOLC-002` Add deterministic local file tool executors - Done
   - `TOOLC-003` Wire file-write approvals to exactly-once execution and continuation - Done
   - `TOOLC-004` Route notch chat through the tool-capable runtime mode - Done
   - `TOOLC-005` Add tool-calling regression fixtures and review architecture - Done
5. Sprint TOOLR: Tool Reliability Hardening - Done
   - `TOOLR-001` Build canonical grant-aware path resolution - Done
   - `TOOLR-002` Route policy and tool executors through the canonical resolver - Done
   - `TOOLR-003` Preserve raw model protocol output before display formatting - Done
   - `TOOLR-004` Tighten side-effect failure states and diagnostics - Done
   - `TOOLR-005` Add regression coverage for the latest chat failures and review architecture - Done

## Durable Decisions

- Direct distribution with Developer ID and Sparkle.
- macOS 15.2+ minimum.
- App is menu-bar/notch-first and configured as `LSUIElement`.
- App sandbox is disabled for direct distribution and local-agent capabilities.
- Local-first AI is the default; Cloud Mode is opt-in.
- Cloud backend is a Pixel Pane backend proxy; provider keys never ship in the app.
- Local files are accessible only through explicit user grants.
- Screenshots/images remain transient unless a future explicit export feature says otherwise.
- Risky local effects require app-owned confirmation gates.
- Durable agent runs are the source of truth; visible chat history is a projection.
- Provider capability tiers decide which agent behaviors are available.
- App policy owns side effects.
- Evidence packets drive local-state answers.
- Durable tool orchestration owns model-tool-result loops.
- Canonical local path resolution must be shared by policy and execution.
- Provider protocol parsing must use raw model text, not display-normalized prose.
- The notch UI projects durable run state.

See `workflow/decisions.md` for the compact decision register.

## Notes For Next Agent

- The agent rearchitecture sprint is complete. Do not revive AGENTV2 runtime hardening.
- The `TOOLC` and `TOOLR` sprints are complete. Do not add new local-file path resolution outside `AgentLocalPathResolver`, and do not feed display-normalized model text into agent protocol parsing.
- Manual real-provider and notch-shell QA should specifically cover granted folder listing, file search/read, staged write approval, denial, reload during approval, no shell-suggestion fallback when tools are available, and `random-tests` write tasks with multiple grants.
- Manual real-provider and notch-shell QA gates are recorded in `workflow/qa-checklist.md`.
- The next blocked product decision is `FOUND-008` only if telemetry is revisited.
- Keep implementation changes inside `PixelPane/` and tracking updates inside `workflow/`.
- Keep docs compact. Delete stale context instead of preserving deprecated architecture narratives.
