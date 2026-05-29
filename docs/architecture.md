# Pixel Pane Architecture

Last updated: 2026-05-29

Pixel Pane is a local-first, notch-native assistant shell for macOS. The current implementation uses the `AGENTR` durable agent runtime described here and in `workflow/agent-architecture-revision.md`.

## Target Runtime

The agent architecture is split into durable, testable layers:

- `AgentRunStore`: Application Support backed sessions, runs, steps, waits, events, evidence, side effects, and artifacts.
- `AgentRunner`: checkpointed step executor with explicit statuses and relaunch recovery.
- `AgentModelGateway`: provider adapters gated by capability tier.
- `AgentPermissionPolicy`: app-owned allow/ask/deny decisions for tools and side effects.
- `AgentToolKit`: typed tools and app-owned executors for files, commands, processes, local server checks, and visual context.
- `AgentEvidenceStore`: evidence packets, artifact references, and final answer support records.
- `AgentRunViewModel`: SwiftUI projection of durable run state into the notch chat.

## Execution Model

1. UI sends an intent: start run, cancel run, approve wait, deny wait, retry interrupted step, or load session.
2. The runner creates or resumes a durable run and checkpoints each step.
3. Deterministic controllers collect local-state evidence for common tasks before asking a model.
4. The model gateway selects an allowed provider tier, normalizes provider protocol output, and returns typed model events or typed provider failures.
5. The tool orchestrator handles typed tool calls, applies permission policy, executes deterministic tools, records evidence, and feeds observations back to the model.
6. The permission policy decides whether tool requests are allowed, denied, or require a durable approval wait.
7. App-owned executors apply approved side effects exactly once and record before/after verification.
8. Evidence packets and artifacts feed answer synthesis and support checks.
9. Chat, progress, approval cards, history, and trace export are projections from durable run events.

## Provider Tiers

- Tier A: full agent. Requires native tool calls or strict structured output, deadlines, cancellation, and conformance tests.
- Tier B: constrained structured text. May support low-risk read-only/proposal workflows after fixture proof.
- Tier C: plain chat or synthesis. No tool control, no side effects, no control-plane JSON.

Best-effort text protocol is compatibility, not the default full-agent control plane.

Raw provider protocol JSON is never projected as assistant prose. It must normalize into typed tool/final events or fail as structured output.

## Tool Calling Model

Tool calls are durable control-plane steps. `AgentToolOrchestrator` repeats the standard loop: model request, typed tool call, policy decision, deterministic app execution, evidence or approval wait, tool-result observation, and final answer. Visible chat only shows user messages and final assistant answers.

The current app-owned tools cover granted local roots, folder listing, file search, file read, and staged file-write proposals. Approved writes execute exactly once through `AgentSideEffectController`; denied writes do not touch disk. Tier A providers may use full-agent mode, Tier B providers use constrained structured text for read/proposal workflows, and Tier C providers remain plain chat.

Local file tools use `AgentLocalPathResolver` as the shared policy/execution authority for granted paths. The resolver prioritizes absolute granted paths, explicit grant-name references, preferred granted directories, exact file grants, existing relative matches, and only then broad fallbacks. Ambiguous relative targets are rejected instead of silently selecting a broad grant.

Provider protocol text is parsed from raw model output. Display formatting and Markdown/math cleanup are applied only to user-visible prose, never before tool-protocol JSON is decoded.

## Safety Model

- Local files require explicit user grants.
- Sensitive paths and credential files are denied by policy.
- Writes, raw shell commands, installs, network commands, privileged commands, and process-control actions require approval unless a narrow deterministic allow rule applies.
- Approved side effects execute from immutable approval artifacts with stable side-effect IDs.
- File changes record snapshots or hashes and support revert where practical.
- Terminal and process actions record command, working directory, policy class, timeout, output, and recovery state.

## Evidence Model

Every local-state tool result must create structured evidence or an artifact reference. Evidence packets include answer-critical fields such as paths, snippets, URLs, ports, commands, statuses, source IDs, trust class, privacy class, and truncation state.

Final answers should link to supporting evidence IDs. Model-based verification is advisory only when deterministic support exists.

## UI Model

The notch chat remains the primary surface, but SwiftUI does not own agent execution. The UI renders explicit run states: running, waiting for approval, interrupted, completed, blocked, failed, or canceled. Empty answer text is not a runtime state.

## Current Implementation State

`AGENTR` is implemented as the active runtime path. Superseded AGENTV2 runtime files were deleted after the durable store, runner, provider gateway, permission policy, side-effect controller, evidence packets, UI projection, trace export, and tool orchestration were in place. Automated fixture coverage and the debug build pass; manual real-provider and notch-shell smoke checks remain beta QA gates.

`TOOLR` hardening is complete for the latest `docs/example-chats` failures: `random-tests` paths now resolve to explicit grants, raw text-protocol newlines are preserved, missing write parents are rejected before approval, and failed approved writes fail the durable run with trace diagnostics.
