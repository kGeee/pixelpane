# Agent Architecture Revision

Last updated: 2026-05-29

This is the compact working artifact for the agent rearchitecture. It should stay focused on current failure evidence, researched architecture patterns, remove / modify / add findings, and the implementation sprint that follows.

## Operating Position

AGENTV2 is the current implementation under audit, not a fixed constraint. The revision may keep, modify, or replace any current runtime decision if the evidence and research support it.

## Failure Taxonomy

- Hang: the UI or runtime remains active without a terminal event.
- Wrong answer: assistant gives an answer contradicted by available evidence.
- Correct evidence hidden from model: tools collected enough information, but model-visible observations were too lossy or poorly shaped to support synthesis.
- Incorrect block: runtime blocks a turn even though available evidence supports an answer.
- Unsafe proposal: model or runtime proposes a side effect without appropriate policy, preview, or approval.
- Schema/protocol failure: provider output or tool arguments do not satisfy the runtime contract.
- Stale context: old observations or state influence a new turn incorrectly.
- Approval/resume failure: an approval wait, approval resolution, or side-effect continuation diverges from the runtime.
- UI/runtime desync: UI loading/progress/pending state does not match runtime terminal state.
- Provider-specific failure: behavior appears tied to Apple local, MLX, cloud, or OpenAI-compatible path quality.

## Failure Corpus

### FC-001 - Search Found The File But The Agent Could Not Answer

Source: deleted chat export summarized during `ARCHREV-001`.

User asked: "do you see my counter.py file?"

Expected behavior:
The assistant should answer that `/Users/nayak/Documents/random-tests/counter.py` exists and identify it from the granted folder search results. It may optionally mention other lower-score references.

Actual behavior:
The runtime searched for `counter.py` and found `/Users/nayak/Documents/random-tests/counter.py`, but the model repeatedly claimed it only saw snippets without paths, repeated the same read-only search, and eventually blocked as `answerability_deferred_after_retry`.

Classification:
- Correct evidence hidden from model
- Incorrect block
- Schema/protocol-adjacent observation shape failure
- Provider-specific failure: observed on Local Apple Model text protocol

Likely architectural layer:
Observation/result shaping, model context packing, read-only reuse, answerability guard, and final synthesis contract.

Repro type:
Fixture and integration. A fixture should receive a search result containing exact file paths and prove the runtime can synthesize without asking for another listing.

Notes:
The exported Agent Tool State Snapshot had the answer. The model-visible summary appears to have been too lossy or not structured enough for reliable synthesis.

### FC-002 - Correct Localhost Answer Blocked By Final-Claim Verification

Source: deleted chat export summarized during `ARCHREV-001`.

User asked: "is it running on any localhost port on my computer?" after identifying the personal website folder.

Expected behavior:
The assistant should answer that the personal website is running on ports `59620` and `59784`, served by Python HTTP servers from `/Users/nayak/Documents/snehithnayak.github.io`.

Actual behavior:
Preflight discovered 12 localhost listeners, found two matching the granted website folder, and the model produced the correct final answer. The runtime then called final-claim verification; the verifier response was a tool call that apparently failed decoding, and the task blocked with `malformed_final_claims`.

Classification:
- Incorrect block
- Schema/protocol failure
- Correct answer rejected after evidence-backed synthesis
- Provider-specific failure: observed on Local Apple Model text protocol

Likely architectural layer:
Final-claim verification, verifier output parsing, final-answer acceptance policy, and fallback behavior when a verifier call fails.

Repro type:
Fixture and integration. A fixture should prove a supported final answer is accepted when verifier output is malformed but deterministic evidence already supports the answer.

Notes:
This is a strong signal that model-based verification cannot be a single point of failure for accepting otherwise evidence-backed local-state answers.

### FC-003 - Follow-Up Script Modification Hung On Local Model Call

Source: deleted chat export summarized during `ARCHREV-001`.

User first asked for a script that prints "hello world" in `random-tests`, then asked: "actually modify it to create a text file which contains 'hello world' and increments the filename every time i run the script."

Expected behavior:
The assistant should stage a modification to the existing script, ask for write approval, then optionally offer or ask approval to run it.

Actual behavior:
The first write eventually succeeded after one schema repair. The follow-up hung at `Calling Local Apple Model`, with memory use continuing and no response.

Classification:
- Hang
- Provider-specific failure
- Approval/resume or context-continuation risk
- UI/runtime desync risk
- Schema/protocol failure on the preceding successful turn

Likely architectural layer:
Provider call controller, model-call cancellation/timeout, context packing across follow-up turns, write-target memory, and runtime progress terminal-state guarantees.

Repro type:
Integration and manual. A fixture can cover the follow-up write flow, but the memory/hang symptom likely needs a provider-stub or real-provider watchdog test.

Notes:
Later AGENTV2 work added deadlines and stronger cancellation, but the rearchitecture should still treat "no indefinite model calls" as a core runtime invariant.

### FC-004 - Provider Protocol JSON Leaked As Assistant Prose

Source: `workflow/backlog.md` (`AGENTV2-023`, `AGENTV2-024`)

Expected behavior:
Provider protocol output should be parsed into typed runtime events or rejected before any visible assistant message is created.

Actual behavior:
Manual QA previously observed protocol-shaped provider text leaking into user-visible assistant prose, including a `port 8000 ?` style local-server protocol leak.

Classification:
- Schema/protocol failure
- UI/runtime desync risk
- Provider-specific failure

Likely architectural layer:
Model adapter boundary, output normalization, typed event projection, and UI transcript ownership.

Repro type:
Fixture and unit. A provider event containing protocol-shaped text must never become a transcript final message.

### FC-005 - Malformed Evidence Planning Became User-Visible Or Derailed The Turn

Source: `workflow/backlog.md` (`AGENTV2-028`, `AGENTV2-029`)

Expected behavior:
Malformed evidence-planning output should be a control-plane observation or a recoverable planner failure, not a user-facing answer.

Actual behavior:
Real-provider QA found malformed evidence planning could become visible to the user or interrupt ordinary local-context questions.

Classification:
- Schema/protocol failure
- Incorrect block or wrong visible answer
- Provider-specific failure

Likely architectural layer:
Evidence planner model pass, protocol decoder, planner fallback, and UI final-message boundary.

Repro type:
Fixture and adapter integration.

### FC-006 - Incomplete Staged-Write Tool Calls Surfaced As Schema Errors

Source: `workflow/backlog.md` (`AGENTV2-026`, `AGENTV2-031`)

Expected behavior:
An incomplete but recognizable staged-write request should either be safely repairable as a bounded control-plane observation or blocked with a clear tool failure, not shown as raw schema mechanics.

Actual behavior:
Manual QA showed local text models could omit required write arguments or use wrong names such as `path` / `filename`, and the app could surface schema failure as the assistant answer before later hardening.

Classification:
- Schema/protocol failure
- Provider-specific failure
- Tool contract weakness

Likely architectural layer:
Tool schema design, argument validation, repair policy, provider tool-description clarity, and user-facing error projection.

Repro type:
Fixture and unit.

### FC-007 - Deferral Answers Accepted Despite Available Tools

Source: `workflow/decisions.md` (`Answerability Deferral Guard`) and `workflow/backlog.md` (`AGENTV2-032`)

Expected behavior:
When the user asks an answerable local-state question and safe tools are available, the assistant should collect evidence or answer from existing evidence, not ask for pre-confirmation or say it cannot confirm.

Actual behavior:
Manual QA showed the model could hedge, ask whether to proceed, or say it could not confirm even when runtime capabilities were available.

Classification:
- Incorrect block
- Correct evidence not collected
- Model/runtime responsibility split failure

Likely architectural layer:
Task router, deterministic preflight, answerability guard, and model-loop stop conditions.

Repro type:
Fixture and integration.

### FC-008 - Stale Context And Full-Ledger Packing Increased Confusion And Memory Pressure

Source: `workflow/decisions.md` (`Bounded Model Context And Deadlines`) and `workflow/backlog.md` (`AGENTV2-034`)

Expected behavior:
Each model call should receive only the trusted inventory, relevant transcript continuity, and current-turn observations needed for the active task.

Actual behavior:
Manual QA showed old tool observations were packed into future model calls, allowing stale output to become implicit memory and increasing prompt size/memory pressure.

Classification:
- Stale context
- Hang/provider pressure risk
- Wrong-answer risk

Likely architectural layer:
Context packing, session memory, ledger projection, and provider call limits.

Repro type:
Fixture, unit, and provider integration.

### FC-009 - Approved Writes Bypassed Runtime Continuation

Source: `workflow/decisions.md` (`Kernel-Owned Approved Writes`) and `workflow/backlog.md` (`AGENTV2-035`)

Expected behavior:
Approving a write should resume the same durable runtime turn, execute the side effect exactly once, record evidence, and continue or terminally complete through the runtime.

Actual behavior:
Manual QA showed approved staged writes could be executed by the UI outside the kernel, leaving the runtime and loading state divergent.

Classification:
- Approval/resume failure
- UI/runtime desync
- Side-effect ownership failure

Likely architectural layer:
Human-in-loop wait/resume, side-effect idempotency, UI/runtime ownership, and event persistence.

Repro type:
Fixture and integration.

### FC-010 - Localhost Routing Produced Overconfident Or Hard-Coded Behavior

Source: `workflow/backlog.md` (`AGENTV2-033`, `AGENTV2-037`, `AGENTV2-040`)

Expected behavior:
Localhost answers should be based on explicit port/URL evidence, managed process evidence, or bounded listener discovery. Missing target information should not produce hard-coded answers.

Actual behavior:
Manual QA found bare `localhost` could be treated as port 80, one failed probe could imply no localhost server existed elsewhere, and preflight initially had hard-coded blocked prose for unknown local-server targets.

Classification:
- Wrong answer risk
- Incorrect block risk
- Deterministic router overreach

Likely architectural layer:
Preflight classifier, local-server discovery, final-answer verification, and evidence-to-answer policy.

Repro type:
Fixture and integration.

### FC-011 - Generated Script Artifacts Passed Through To Approval

Source: deleted chat export plus `workflow/backlog.md` (`AGENTV2-035`, `AGENTV2-044`).

Expected behavior:
Generated code with obvious syntax artifacts or runtime NameErrors should be rejected before user approval and fed back as model-visible repair evidence.

Actual behavior:
Search snippets and QA notes show generated scripts containing newline marker artifacts such as `nimport` / `ndir_path` and Python bugs such as `os.path.abspath(file)` instead of `__file__`.

Classification:
- Unsafe proposal
- Schema/protocol-adjacent generated-content failure
- Provider-specific failure

Likely architectural layer:
Write proposal preflight, language-specific generated-content validation, approval preview, and post-write verification.

Repro type:
Fixture, unit, and integration.

### FC-012 - Notch Chat Layout And Progress Could Hide Runtime State

Source: `workflow/status.md` hotfixes and `workflow/backlog.md` (`AGENTV2-042`, `AGENTV2-043`)

Expected behavior:
The UI should show stable progress, bounded composer dimensions, visible terminal state, and no ambiguous indefinite Thinking state.

Actual behavior:
Manual QA found composer/control layout regressions and insufficient live progress before later hotfixes. These are not core reasoning failures, but they make agent failures harder to diagnose and recover from.

Classification:
- UI/runtime desync
- Hang diagnosis weakness

Likely architectural layer:
Runtime event stream, active phase projection, SwiftUI state ownership, and layout regression coverage.

Repro type:
UI regression harness and manual QA.

## Research Notes

Primary sources are tracked in `workflow/references.md`. This section records the research takeaways only; it intentionally avoids copying long external documentation into the repo.

### OpenAI Agents SDK

Sourced facts:

- The SDK separates agent definitions from runner execution. Runner configuration covers model/provider/session defaults, guardrails, handoffs, model input shaping, and tracing/observability.
- The SDK has built-in tracing for a full run record, including LLM generations, tool calls, handoffs, guardrails, and custom events.
- Guardrails are explicit runtime hooks. Input/output guardrails apply around agent runs, while tool guardrails are the right level when a workflow includes managers, handoffs, or delegated specialists.
- Handoffs are a first-class concept rather than plain tool calls; handoff input can be filtered before another agent receives state.

Pixel Pane inference:

- Pixel Pane should have an app-owned runner/run object separate from model adapters and UI state.
- Tracing should be a permanent architecture primitive, not a temporary debug export bolted onto the chat surface.
- Final-answer validation should be deterministic or guardrail-like where possible. A second brittle model call should not be able to reject a supported answer by failing its own output protocol.
- If Pixel Pane keeps specialists later, specialist routing should be a typed handoff/step transition with scoped input, not another free-form model prompt.

Sources:

- https://openai.github.io/openai-agents-python/running_agents/
- https://openai.github.io/openai-agents-python/tracing/
- https://openai.github.io/openai-agents-python/guardrails/
- https://openai.github.io/openai-agents-python/handoffs/

### Anthropic Claude Code

Sourced facts:

- Claude Code uses hierarchical settings files for permissions, environment, tool behavior, memory files, skills, and MCP servers.
- Permission rules include explicit allow/ask/deny behavior and can deny sensitive paths such as `.env`, secrets, and build artifacts.
- MCP servers are configured by scope. Local-scoped MCP servers stay private to one project; project/user/enterprise scopes allow broader sharing or enforcement.
- MCP tools require explicit permission unless narrower allowlists are configured; broad bypass modes disable more safety prompts than MCP access alone requires.

Pixel Pane inference:

- The next permission model should be declarative and inspectable: allow, ask, deny, with rule scopes for file paths, terminal command classes, network access, process control, and write/delete operations.
- Tool registration should include permission metadata as data, not scattered conditional checks.
- Project/workspace-scoped extensions are useful, but Pixel Pane should start with built-in local tools and a clear extension boundary before exposing arbitrary MCP servers.
- Sensitive-file deny rules need to be enforced before read/search/list results are shaped into model-visible observations.

Sources:

- https://code.claude.com/docs/en/settings
- https://code.claude.com/docs/en/mcp
- https://docs.anthropic.com/en/docs/claude-code/iam
- https://docs.anthropic.com/en/docs/claude-code/security

### LangGraph

Sourced facts:

- LangGraph uses a persistence layer that saves graph state as checkpoints.
- Checkpoints are organized by thread and allow state to persist across multiple interactions.
- Durable execution saves execution-step state to a durable store. Pending writes preserve completed node work when another node fails in the same step.
- Human-in-loop workflows use interrupts that save graph state and wait for resume input.

Pixel Pane inference:

- Pixel Pane needs durable runs/checkpoints for active agent work, especially before and after side effects, approval waits, provider calls, and finalization.
- A thread/session should own durable state across turns, while each run should own a resumable step sequence.
- Approval should be modeled as a runtime interrupt/wait, not SwiftUI-only pending state.
- Restart recovery should be explicit: after app relaunch, the run store should know whether a run is waiting, completed, failed, canceled, or needs safe recovery.

Sources:

- https://docs.langchain.com/oss/python/langgraph/persistence
- https://docs.langchain.com/oss/python/langgraph/durable-execution
- https://docs.langchain.com/oss/python/langgraph/human-in-the-loop
- https://reference.langchain.com/python/langgraph/checkpoints/

### Microsoft AutoGen Core

Sourced facts:

- AutoGen Core models agents as message-driven components with a runtime that manages lifecycle and delivery.
- Messages are explicit typed values rather than only chat transcript text.
- Tool execution can be represented as typed function-call messages and typed function-execution results.
- Cancellation is part of execution through cancellation tokens.

Pixel Pane inference:

- The agent runtime should not treat the visible chat transcript as the control plane. Typed events/messages should be the source of truth; chat is a projection.
- Tool requests and tool results should be serializable runtime messages with stable IDs, arguments, outputs, errors, and evidence links.
- Provider cancellation and tool cancellation should share one run-cancellation contract that every step observes.

Sources:

- https://microsoft.github.io/autogen/stable/user-guide/core-user-guide/framework/agent-and-agent-runtime.html
- https://microsoft.github.io/autogen/stable/user-guide/core-user-guide/components/tools.html
- https://microsoft.github.io/autogen/stable/reference/python/autogen_core.html

### Google Agent Development Kit

Sourced facts:

- ADK separates agents from runner/runtime execution and exposes multiple runtime surfaces such as dev UI, CLI, API server, and ambient agents.
- The runtime event loop is documented as a yield/pause/resume cycle.
- ADK has technical references for resuming and canceling agent runs.
- Callback hooks can inspect, replace, or skip behavior before/after agent, model, and tool execution.
- Sessions are a named service concept; session state can be created, passed to runners, and updated through events/state deltas.

Pixel Pane inference:

- Pixel Pane's UI should consume a stream of runtime events rather than infer state from one final async result.
- Runtime callbacks/hooks map well to guardrails, trace spans, tool authorization, generated-write validation, and UI progress.
- A small local session service backed by SQLite or JSON files would fit Pixel Pane better than `UserDefaults` transcript-only persistence.

Sources:

- https://adk.dev/runtime/
- https://adk.dev/callbacks/types-of-callbacks/
- https://adk.dev/sessions/session/

### LlamaIndex Workflows

Sourced facts:

- LlamaIndex Workflows use event-driven steps. AgentWorkflow is described as steps that emit and receive events.
- Human-in-loop can be represented by emitting an input-required event and waiting for a matching human-response event.
- Workflows include utilities for state management, looping, debugging, and stepwise execution.

Pixel Pane inference:

- A step/event runtime is a better fit than one monolithic actor loop for Pixel Pane's reliability work.
- Human approval should be an event pair with a wait ID and typed response, not a special case embedded in view state.
- Pixel Pane should be able to step through runs during fixture tests, which requires each runtime step to be independently testable.

Sources:

- https://developers.llamaindex.ai/python/framework/understanding/workflows/
- https://developers.llamaindex.ai/python/framework/understanding/agent/human_in_the_loop/

### Goose And MCP-Based Local Agents

Sourced facts:

- Goose positions MCP as its extension/tool integration mechanism and documents many local/remote extensions.
- MCP provides a common standard for connecting agents to tools and data sources, but the host still owns trust, permission, and tool-loading policy.

Pixel Pane inference:

- MCP is useful as a future extension boundary, but adopting MCP does not replace Pixel Pane's need for a local permission engine, durable run store, and compact observation shaping.
- For beta reliability, built-in file/terminal/process tools should be first-class typed tools. MCP should be an optional later layer behind the same permission and tracing model.

Sources:

- https://block.github.io/goose/
- https://modelcontextprotocol.io/

### Cursor-Style Products

Sourced facts:

- Cursor describes dynamic context discovery as a way to avoid stuffing all static context into the prompt.
- Cursor's public write-up calls out long tool responses as a source of context bloat and describes turning long responses into files/artifacts.
- Skills can be represented as files with names/descriptions in static context, while the agent discovers details dynamically through search.
- Cursor exposes background agents as separate running work items that can be listed and resumed from a sidebar/API surface.

Pixel Pane inference:

- Long tool results and debug snapshots should become artifacts referenced by ID/path, not repeatedly packed into every model call.
- Repo instructions, workflow status, and docs should be compact entry points with dynamic discovery. Deleting stale docs is directly aligned with this pattern.
- Long-running agent work needs a run list/history surface in the UI or debug export so stuck work is visible and recoverable.

Sources:

- https://cursor.com/blog/dynamic-context-discovery
- https://docs.cursor.com/background-agent
- https://docs.cursor.com/tools

### Windsurf Cascade

Sourced facts:

- Cascade separates Code and Chat modes; Code mode can modify code while Chat mode is optimized for questions and may propose changes.
- Cascade includes planning/todo lists for longer tasks, tool calling, checkpoints, real-time awareness, and linter integration.
- Memories are workspace-associated local context; durable team-shared behavior belongs in Rules or `AGENTS.md`.
- Rules can exist at global, workspace, or system levels and can be inferred from `AGENTS.md`.

Pixel Pane inference:

- Pixel Pane should have explicit task modes or run profiles: answer/read-only, propose-write, execute-approved-command/process, and maybe long-running work. Mode should affect tool availability and permission gates.
- Checkpoints/reverts are important for write actions. Even local beta writes should have before/after snapshots for user recovery.
- Persistent memory should be deliberate and scoped. Pixel Pane should not treat prior tool observations as permanent memory unless explicitly promoted.

Sources:

- https://docs.windsurf.com/windsurf/cascade/cascade
- https://docs.windsurf.com/windsurf/cascade/memories

### Standard Patterns To Apply To Pixel Pane

Use these as audit criteria for `ARCHREV-004` through `ARCHREV-008`.

1. Durable run/session store.
   - A session/thread owns user-visible conversation continuity.
   - A run owns a specific user task, step state, pending waits, tool calls, evidence, trace spans, cancellation, and terminal status.
   - Chat history is a projection, not the source of truth.

2. Event-driven runtime steps.
   - Replace the central "do everything" actor loop with a small runner that executes typed steps.
   - Steps should be individually testable: route, plan, call model, execute tool, wait for approval, validate artifact, synthesize, complete.

3. Durable human-in-loop waits.
   - Approval is an interrupt/wait event with a stable ID and typed resume payload.
   - Approval state must survive app relaunch and must execute approved side effects exactly once.

4. Permission scopes as data.
   - Every tool declares risk, required scopes, default allow/ask/deny behavior, allowed path roots, and whether network/process/write/delete/install actions are possible.
   - A policy engine decides before execution. UI renders the decision and proposal preview.

5. Structured tool outputs and artifacts.
   - Tool results need stable IDs, machine-readable fields, human summaries, evidence records, and artifact references for long outputs.
   - The model gets compact observations with enough structure to answer; full raw output stays addressable outside the prompt.

6. First-class tracing.
   - Each run should record spans for model calls, tool calls, guardrails, approvals, validation, retries, provider timeouts, and cancellation.
   - Debug export should serialize the trace instead of reconstructing it from UI state.

7. Capability-tiered model adapters.
   - Native tool-call providers should use native structured tool calling.
   - Text-protocol providers should be limited to narrower modes unless fixture evidence proves reliability.
   - Weak/local text-only models should not control arbitrary side effects or final verification.

8. Deterministic validation before model validation.
   - Local-state answers should be accepted when deterministic evidence supports them.
   - Model-based verification can annotate confidence or request clarification, but malformed verifier output must not block an otherwise supported answer.

9. Bounded context packing.
   - Pack only current task instructions, compact session continuity, relevant observations, and selected artifacts.
   - Never pack full stale ledgers by default. Discovery should retrieve context on demand.

10. Explicit mode separation.
    - Read-only answer mode, write-proposal mode, command/process mode, and long-running background mode should have different tool access and UI states.
    - The model should not infer whether it is allowed to write or execute; the runtime should know.

11. Reversible side effects where practical.
    - File writes should have snapshots/diffs before approval and post-write verification.
    - Process starts should have managed process records with stop/recover behavior.
    - Terminal commands should record working directory, command policy class, timeout, output cap, and whether they can be safely retried.

12. Compact documentation and rules.
    - Keep permanent repo context to current architecture, current workflow, active decisions, and operational rules.
    - Delete stale architecture docs once their evidence has been folded into the revision artifact.

## Current Architecture Map

### Active Files And Roles

- `PixelPane/PixelPane/Panel/ResultPanelView.swift`
  - Primary SwiftUI bridge for the assistant surface.
  - Owns live UI state: `askTurns`, `askTask`, `askRuntimeProgress`, `lastAskRuntimeProgress`, `pendingLocalFileWriteProposal`, `pendingTerminalCommandProposal`, `pendingAgentKernelApproval`, `assistantToolState`, `agentKernelLedger`, `chatContextID`, active text, image context, loading state, and copy-chat export.
  - Builds `AgentKernelChatContextV2` for each turn from the current ledger, file grants, visual context, allowed working directories, recent write targets, response budget, and progress callback.
  - Calls `AgentKernelChatRuntimeV2.runTurn` for user turns and `resolveApproval` for approved side effects.
  - Applies runtime output back into UI state, then persists projected chat sessions.

- `PixelPane/PixelPane/AgentKernel/AgentKernelChatRuntimeV2.swift`
  - Main runtime actor and current orchestration center.
  - Owns the per-turn loop: append user message, run preflight/evidence planning, collect evidence, call model, validate/execute tools, wait for approval, resume approval, gate final answers, emit UI events, and return terminal/pending results.
  - Uses `maxToolSteps = 5` and `modelCallTimeoutSeconds = 30`.
  - Instantiates or receives local context tools, finite command tool, process tool, runtime guards, evidence planner, preflight planner, evidence verifier, answerability guard, and output normalizer.
  - Runtime itself is not durable; it receives and returns a value-type ledger.

- `PixelPane/PixelPane/AgentKernel/AgentKernelSessionLedgerV2.swift`
  - Append-only event log and state reducer.
  - Stores transcript events and control events in one ordered sequence.
  - Projects transcript messages, control-event export records, observation messages, context snapshots, packed context, evidence records, and current task state.
  - Does not persist itself directly through `ChatHistoryStore`; saved chats store visible turns and `AssistantToolState`, then reconstruct a simplified ledger from visible turns on load.

- `PixelPane/PixelPane/AgentKernel/AgentKernelToolRegistryV2.swift`
  - Registry and validation layer for tool definitions, argument schemas, scope requirements, deny rules, risk class, and approval requirement.
  - Delegates duplicate/no-progress and approval decisions to `AgentKernelRuntimeGuardsV2`.

- `PixelPane/PixelPane/AgentKernel/AgentKernelLocalContextToolsV2.swift`
  - Owns local grants, folder listing, file search, file read, staged write proposal, and visual context description.
  - Enforces grants through existing local file primitives and returns bounded source/evidence-shaped outputs.

- `PixelPane/PixelPane/AgentKernel/AgentKernelFiniteCommandToolV2.swift`
  - Owns bounded finite command execution, working-directory validation, timeout/output caps, and command policy.

- `PixelPane/PixelPane/AgentKernel/AgentKernelProcessLifecycleToolV2.swift`
  - Actor for in-memory managed process state.
  - Owns start/status/tail/stop and local server probe/discovery.
  - Managed process records live inside the process tool actor for the lifetime of the `AgentKernelChatRuntimeV2` instance, not in a durable process store.

- `PixelPane/PixelPane/AgentKernel/AgentKernelModelAdapterV2.swift`
  - Provider-neutral adapter contract.
  - Defines descriptor, route, capabilities, request, response, events, streaming mode, and limits.

- `PixelPane/PixelPane/AgentKernel/AgentKernelAIBackendAdapterV2.swift`
  - Active bridge from existing `AIBackend` providers into the kernel.
  - Converts kernel requests into one large text prompt for `AIBackend.streamResponse`.
  - Uses the text protocol whenever tools or text-protocol response format are requested.
  - Attempts one repair pass for malformed protocol output.

- `PixelPane/PixelPane/AgentKernel/AgentKernelProtocolAdaptersV2.swift` and `AgentKernelModelOutputNormalizerV2.swift`
  - Own text protocol prompt building, parsing, partial tool-call recovery, and protocol-shaped final-text normalization.

- `PixelPane/PixelPane/AgentKernel/AgentKernelEvidencePlanningV2.swift`
  - Model-based evidence-needs and final-claim declaration layer.
  - Maps declared evidence needs into runtime tool calls.

- `PixelPane/PixelPane/AgentKernel/AgentKernelPreflightPlanningV2.swift`
  - Deterministic router before model-driven evidence planning.
  - Currently recognizes local-server status, managed-process status, grant visibility, workflow status, file path/read/list/search intent, and local-server discovery.

- `PixelPane/PixelPane/AgentKernel/AgentKernelEvidenceVerifierV2.swift`
  - Verifies model-declared final claims against ledger evidence.

- `PixelPane/PixelPane/AgentKernel/AgentKernelAnswerabilityGuardV2.swift`
  - Rejects deferral answers when tools or evidence should be used.

- `PixelPane/PixelPane/App/ChatHistoryStore.swift`
  - Persists `StoredChatSession` to `UserDefaults`.
  - Stores visible turns plus optional `AssistantToolState`.
  - Does not store full control-event ledger, approval waits, model calls, or durable run checkpoints.

- `PixelPane/PixelPane/App/AppState.swift`
  - Owns app-level capture flow, routing settings, local AI setup status, file grants, and panel presentation.
  - Refreshes local capabilities and stops the MLX text server when MLX setup changes.

- `PixelPane/PixelPane/Actions/AIBackend.swift` and provider implementations
  - Existing provider abstraction used by non-agent actions and bridged into the agent runtime.
  - Streams metadata, snapshots, final output, and completion events.

### Turn Lifecycle

1. User submits chat in `ResultPanelView.sendAskQuestion()`.
2. UI clears pending proposals, appends an empty visible `AskConversationTurn`, sets loading state, records initial progress, and builds `AgentKernelChatContextV2`.
3. UI creates an `AgentKernelAIBackendAdapterV2` from the selected `AIBackend` and calls `agentKernelRuntime.runTurn`.
4. Runtime appends the user message to the ledger.
5. Runtime reports planning progress.
6. If `shouldPlanEvidence` is true, runtime runs deterministic preflight first.
7. If preflight is unclassified, runtime calls the model for `declare_evidence_needs`.
8. Evidence needs are mapped to normal typed tool calls.
9. Each tool call is validated by the registry or finite command validator.
10. Read-only tools execute immediately and append tool results plus evidence.
11. Side-effect tools return pending approval, with UI-facing write or terminal proposals.
12. If approval is needed, runtime returns a pending result. UI stores `pendingAgentKernelApproval` plus proposal state.
13. On approval, UI calls `AgentKernelChatRuntimeV2.resolveApproval`; runtime appends approval resolution, executes the approved side effect, records result/evidence, and continues the same loop.
14. In the normal model loop, runtime builds a model request from app context inventory plus `ledger.packedContextSnapshot().modelMessages`.
15. The provider bridge turns the request into text protocol if tools are present.
16. Model output is parsed, repaired once if possible, and normalized before runtime handling.
17. A final answer goes through answerability guard, deterministic final-answer blockers, and model-based final-claim verification.
18. If accepted, runtime appends assistant message and task completion, returns a final UI event, and reports completed progress.
19. UI applies the output, updates `askTurns`, pending state, `assistantToolState`, active progress, loading state, and persists a projected chat session.
20. Copy-chat export is a projection of visible turns, control events, tool state, and temporary debug diagnostics.

### State And Persistence Owners

- Live UI turn state: `ResultPanelView.askTurns`.
- Active task handle: `ResultPanelView.askTask`.
- Active runtime progress: `ResultPanelView.askRuntimeProgress` and `lastAskRuntimeProgress`.
- Pending approvals and proposal previews: `ResultPanelView.pendingAgentKernelApproval`, `pendingLocalFileWriteProposal`, `pendingTerminalCommandProposal`.
- Current in-memory ledger: `ResultPanelView.agentKernelLedger`.
- Ledger events and task state during a runtime call: `AgentKernelSessionLedgerV2`.
- Tool state snapshot for UI/export/history: `AssistantToolState` in `ResultPanelView`, patched by `AgentKernelAssistantStatePatchV2`.
- File grants: `LocalFileAccessStore`, passed into the kernel as context.
- Allowed working directories: derived from current file grants.
- Recent write targets: derived from pending write proposal and `AssistantToolState.recentToolResults`.
- Managed processes: `AgentKernelProcessLifecycleToolV2.processes`, in memory inside the runtime actor's process tool.
- Provider routing/settings: `AIRoutingSettings` and `AppState`.
- Provider process/cache state: `MLXTextServerManager`, `MLXVisionModelSetup`, `HybridLocalAIBackend`, and specific backend implementations.
- Saved chat history: `ChatHistoryStore` in `UserDefaults`, visible turns plus `AssistantToolState`; full ledger is not persisted.
- Debug export: generated on demand from current UI state, current ledger, and `AssistantToolState`.

### Current Architecture Risks To Audit

- `AgentKernelChatRuntimeV2` is a large central actor that mixes planning, preflight routing, model calls, tool dispatch, evidence recording, approval handling, write preflight, final verification, and UI result construction.
- The ledger is the strongest runtime abstraction, but it is not durably persisted as the source of truth for saved chats. Loading a saved chat reconstructs a simplified ledger from visible turns, losing control events and evidence.
- Human-in-loop approval is runtime-owned during active execution, but pending approval state is stored in SwiftUI `@State`, not a durable wait/checkpoint.
- Managed process state is in memory inside the process tool actor; app relaunch or runtime recreation loses managed process ownership even if the OS process survives.
- Active model route in the app goes through `AgentKernelAIBackendAdapterV2`, which relies on best-effort text protocol even for agentic tool use.
- Final-claim verification is itself model-mediated and can block a correct answer if the verifier output is malformed.
- Observation messages are mostly string summaries, while debug/tool snapshots may contain richer structured source data than the model receives.
- Preflight has accumulated scenario-specific routing logic inside one deterministic classifier.
- UI and runtime share state through value snapshots and async task results; there is no durable run ID/checkpoint boundary that guarantees recovery after app interruption.
- Temporary debug export code marked `TEMP_DEBUG_EXPORT_AGENTS_033` still lives in the production tree behind DEBUG.

## Architecture Audits

### ARCHREV-004 - Runtime State, Persistence, Replay, And Resumability

Current facts:

- `AgentKernelSessionLedgerV2` is a Codable value log with sequenced events and a reducer-style task state. This is the best current foundation.
- The ledger is held in `ResultPanelView.agentKernelLedger`, passed into `AgentKernelChatRuntimeV2`, mutated during an async turn, then returned in `AgentKernelChatResultV2`.
- `ChatHistoryStore` persists only `StoredChatSession`: visible turns plus optional `AssistantToolState`, stored in `UserDefaults`.
- Loading a saved chat reconstructs a simplified ledger from visible question/answer turns through `ResultPanelView.agentKernelLedger(for:)`. Model calls, tool proposals, tool results, approvals, evidence, terminal reasons, and pending waits are lost.
- Pending approvals are returned in `AgentKernelChatResultV2` and stored in SwiftUI state: `pendingAgentKernelApproval`, `pendingLocalFileWriteProposal`, and `pendingTerminalCommandProposal`.
- Approval resume depends on the UI passing the in-memory `AgentKernelPendingApprovalV2` object back to `resolveApproval`.
- `runTurn` and `resolveApproval` are single async calls. A model call is timeout-wrapped, but intermediate state is not checkpointed to durable storage while the task is running.
- Model call/task cancellation is best-effort process memory. If the app quits during a model call, tool call, or approval wait, the durable state does not know where the run stopped.
- Managed processes live in `AgentKernelProcessLifecycleToolV2.processes`, an in-memory actor dictionary. Started OS processes can outlive app/runtime state, but the runtime loses ownership records after recreation.
- The ledger has one `sessionID` and one scalar `state`. It does not distinguish a long-lived conversation thread from one resumable run/turn.

Comparison to researched patterns:

- Mature runtimes separate session/thread state from run state. Pixel Pane currently blurs these in one in-memory ledger.
- LangGraph-style durable execution requires checkpoints before/after steps and pending writes. Pixel Pane only has a final returned ledger after the async call completes or blocks.
- LlamaIndex/ADK-style human-in-loop waits are runtime events with durable resume inputs. Pixel Pane's waits are UI state plus an in-memory pending object.
- Cursor-style context management treats long outputs as artifacts. Pixel Pane stores some evidence but does not persist a durable artifact index or use artifact references as the main context source.
- OpenAI/ADK tracing treats run events as first-class diagnostics. Pixel Pane reconstructs debug export from current UI state and current ledger instead of reading a durable run trace.

Failure impact:

- App relaunch after an approval request loses the approval wait and forces a transcript-only reload.
- App relaunch or view recreation after a model hang loses the run's active step; the UI can only show a canceled/failed visible turn if it had already been patched.
- Duplicate side effects are possible in future recovery work unless approved side-effect execution has idempotency keys and durable "started/completed" records.
- Stale context can enter later turns because `AssistantToolState` survives as a compact snapshot while the actual event/evidence graph does not.
- Replay/debug is incomplete: the visible chat can be restored, but the control plane that caused failures is missing.

Keep:

- Keep a typed event log as the core abstraction. `AgentKernelSessionEventPayloadV2` is close to the right shape and should be evolved, not discarded.
- Keep chat transcript as a projection of events.
- Keep task states, terminal reasons, tool call IDs, approval IDs, and evidence IDs.
- Keep bounded text and metadata values, but pair them with artifact references for raw or long data.

Replace:

- Replace transcript-only `ChatHistoryStore` as the source of agent continuity.
- Replace SwiftUI-owned pending approval state with durable runtime waits.
- Replace one scalar ledger state with separate `AgentSession`, `AgentRun`, `AgentStep`, and `AgentWait` state.
- Replace in-memory managed process ownership with durable process records plus recovery probing.

Add:

- Add an `AgentRunStore` under Application Support. Preferred shape: local SQLite for indexed sessions/runs/events/waits/artifacts, plus filesystem artifact blobs for large tool outputs and debug payloads. Avoid `UserDefaults` for run state.
- Add stable IDs:
  - `sessionID` for conversation/thread continuity.
  - `runID` for each user task.
  - `stepID` for each deterministic/model/tool/approval step.
  - `waitID` for human approval/input.
  - `sideEffectID` for exactly-once approved writes/commands/process actions.
- Add checkpoint writes before and after every model call, tool call, approval request, approval resolution, side effect, validation pass, and terminal event.
- Add run recovery on app launch:
  - `waitingForApproval`: restore proposal UI from durable wait.
  - `runningModel` or `runningTool`: mark interrupted and offer retry/cancel; do not silently continue side effects.
  - `runningProcess`: reconstruct status from durable PID/processID/working directory/ports where possible.
  - `completed`, `blocked`, `failed`, `canceled`: project final transcript and trace.
- Add artifact records with privacy class, trust class, size, hash, summary, source, and retention policy.
- Add deterministic session compaction. Future model calls should request relevant event/artifact slices by current run need, not use full ledger or stale `AssistantToolState`.

State that must survive app relaunch:

- Sessions, runs, event log, step status, wait status, approval decisions, side-effect execution status, terminal status, final visible messages, tool calls, tool results, evidence records, artifact references, file-write snapshots/diffs, terminal command proposals/results, managed process records, and model-call diagnostics.

State that may remain ephemeral:

- SwiftUI layout state, live progress animations, `Task` handles, provider streaming continuations, in-flight token streams, transient screenshot image bytes unless explicitly attached to a run, and current hover/focus state.

Decision:

The next architecture needs a durable run store and checkpointed step graph. A simpler fresh-turn model would reduce persistence complexity, but it would not solve the user's observed approval/resume, hang recovery, stale context, or traceability failures.

### ARCHREV-005 - Model Adapter Contracts And Provider Failure Handling

Current facts:

- `AgentKernelModelAdapterV2` defines a useful provider-neutral descriptor, capabilities object, request, response, event enum, and stream method.
- The active app bridge is `AgentKernelAIBackendAdapterV2`. It converts a typed request into one text prompt for the older `AIBackend.streamResponse(for:)` API.
- `AgentKernelModelAdapterCapabilitiesV2.aiBackendBridge(...)` marks every `AIBackend` route as `.textProtocol` and `.bestEffort` when text is available. This includes Apple Foundation Models, MLX Text, Pixel Pane Cloud, and hybrid local routing.
- The runtime asks for tools whenever tools exist, then relies on JSON text protocol parsing and one optional repair call.
- `AgentKernelOpenAICompatibleAdapterV2` also uses the text protocol prompt and sends it as a single user message to a chat-completions endpoint. It does not use native tool calling or structured response formats.
- `AgentKernelNativeToolCallAdapterV2` exists, but it is only a wrapper that changes the requested response format. The current production provider path does not implement a true native tool-call adapter.
- `AIBackendRequest` is plain prompt oriented. It does not carry typed messages, tool schemas, trace IDs, run IDs, cancellation/deadline metadata, response schema, or native structured-output requirements.
- Provider failures are collapsed into coarse model events: `.malformedOutput`, `.emptyOutput`, or `.timedOut`. Cancellation is often represented as `.timedOut`.
- `AgentKernelChatRuntimeV2.modelResponse(...)` applies a 30 second timeout around adapter response, while MLX backends and server manager still have longer internal request timeouts. Cancellation is best effort.
- The runtime currently uses the same model route for planning, normal synthesis, and final-claim verification, so a weak text protocol path can fail multiple control-plane roles.

Comparison to researched patterns:

- OpenAI-style and AutoGen-style agent runtimes keep model calls, tool calls, and guardrail outputs typed. Pixel Pane currently emulates typed tool calls through prompt text for all active providers.
- Provider capability is too coarse. A route with plain text generation is not automatically safe for tool planning, tool invocation, JSON repair, final verification, or side-effect proposal.
- Mature systems distinguish cancellation, timeout, tool/schema failure, policy failure, model refusal, provider unavailable, auth/rate-limit, empty output, and malformed structured output. Pixel Pane's current event model loses these distinctions.
- Durable runtimes attach diagnostics to a trace/run. Pixel Pane stores model-call payload summaries in the ledger, but raw provider payloads, parse failures, repair prompts, latency, and retry policy are not durable artifacts.

Failure impact:

- FC-001 and FC-002 are consistent with the model receiving lossy text observations, then failing or being blocked by another model-mediated text-protocol step.
- FC-003 is consistent with nested provider timeouts/cancellation gaps and large prompt/context pressure on a local text model.
- FC-004, FC-005, and FC-006 are direct symptoms of best-effort JSON protocol controlling the runtime boundary.
- Treating all active providers as `.textProtocol` encourages the runtime to expose the same tool loop to weak local models that cannot reliably follow the protocol.

Keep:

- Keep provider-neutral descriptors, route metadata, modality metadata, limits, and availability reporting.
- Keep fixture adapters as the first-class test path.
- Keep a strict decoder for text-protocol outputs, but treat it as a compatibility path, not the default full-agent path.

Replace:

- Replace the legacy `AIBackend` bridge as the main agent adapter path. `AIBackend` can stay for non-agent actions and simple chat, but agent runs need typed provider adapters.
- Replace "tools exist, therefore prompt text protocol" with capability-tiered runtime profiles.
- Replace `.malformedOutput(error.localizedDescription)` as the catch-all provider failure with typed provider diagnostics.
- Replace model-mediated final-claim verification as a required acceptance gate for deterministic local-state answers.

Add:

- Add provider capability tiers:
  - Tier A, full agent: native tool calls or strict structured output; supports typed tool calls, schema validation, deadlines, cancellation, and trace metadata.
  - Tier B, structured text compatibility: JSON/text protocol may be used only for low-risk read-only planning/synthesis under fixture-proven constraints.
  - Tier C, plain chat: no tools, no side effects, no control-plane JSON; can summarize or answer from already-collected deterministic evidence.
- Add distinct run modes tied to provider tiers: read-only answer, deterministic local-state answer, write proposal, terminal/process, and long-running background work.
- Add a provider error taxonomy: unavailable, auth, rate-limited, context-too-large, timeout, canceled, empty-output, structured-output-invalid, tool-call-invalid, transport-error, provider-refusal, and unknown.
- Add per-request deadlines and cancellation tokens to the adapter contract. Provider implementations must honor the runtime deadline; nested MLX/server timeouts cannot exceed the run step deadline.
- Add model-call trace artifacts: request role/messages metadata, tool schema names/hashes, selected provider/model, prompt size, response size, latency, parse outcome, repair attempt count, token/statistics where available, and raw provider response artifact when privacy policy permits.
- Add native structured adapters before broad tool use:
  - Pixel Pane Cloud should expose a typed agent model endpoint if cloud is used for agent tasks.
  - OpenAI-compatible local/cloud should use native tool calling or JSON schema response formats where the endpoint supports them; otherwise it is Tier B or C.
  - Apple and MLX local paths should default to Tier B/C until empirical fixtures and manual QA prove stricter behavior.
- Add provider conformance tests for each tier. The test matrix should prove timeout, cancellation, malformed output, empty output, oversized prompt, repair-disabled behavior, and unsupported tool mode behavior.

Decision:

The next architecture should be capability-tiered. Best-effort text protocol remains a compatibility adapter, not the standard full-agent control plane. Full agent execution should require native/strict structured output or a provider endpoint Pixel Pane controls.

### ARCHREV-006 - Tool, Approval, Permission, And Side-Effect Boundaries

Current facts:

- `AgentKernelToolRegistryV2` has useful foundations: tool definitions, argument schemas, output type summaries, risk, scope requirements, `requiresApproval`, deny rules, and validation.
- Tool scopes are coarse. `grantedScopes(_:)` grants both `.grantedFileRead` and `.grantedFileWrite` whenever any local file grant exists. File grants are described to users as local read/search access, while writes are governed later by approval.
- All registry schemas are made available to the model regardless of provider capability tier or run mode.
- `stage_write_proposal` is both the model-facing write-draft tool and the approved execution tool. Before approval it stages a proposal; after approval `resolveApproval` calls the same tool call again with `approvedSideEffect: true`.
- File write execution re-runs proposal resolution from the tool-call arguments instead of executing an immutable approved proposal artifact.
- File writes have approval, but not durable before/after snapshots, content hashes, idempotency keys, or rollback records.
- `run_finite_command` is registered as read-only/no-approval, then command policy regexes can upgrade it to approval or block. Commands that do not match policy regexes run without approval through `/bin/zsh -lc`.
- Command policy is regex-based over a shell string. This catches many obvious risky commands, but it is not a reliable shell safety boundary.
- `start_process` and `stop_process` require approval and process-control scope. Managed process records are in memory inside `AgentKernelProcessLifecycleToolV2`.
- `discover_local_servers` and `process_status` are read-only but rely on process-control style inspection. They can inspect local process/listener state once any working directory scope exists.
- Local file grants persist path strings in `UserDefaults`; the app is unsandboxed by decision, so this is functionally sufficient but not a fine-grained policy record.
- Sensitive-file deny rules are minimal. There is no default cross-tool deny policy for secrets, SSH keys, `.env`, signing identities, credential stores, keychains, or package-manager credential files.

Comparison to researched patterns:

- Claude Code-style permissions are declarative allow/ask/deny rules with scopes. Pixel Pane currently has per-tool risk plus scattered command regexes and broad scope derivation.
- OpenAI-style guardrails and ADK callbacks point toward a policy engine around every tool call. Pixel Pane validates tools, but approval, preflight, execution, and result verification are still coupled inside the central runtime.
- LangGraph/LlamaIndex human-in-loop patterns model approval as a durable interrupt/resume event. Pixel Pane returns pending approval to UI state.
- Cursor/Windsurf-style write agents rely on checkpoints/reverts around file edits. Pixel Pane approval previews exist, but there is no durable checkpoint or revert path.

Failure impact:

- FC-009 maps directly to approval state and approved side effects not being durable runtime-owned waits.
- FC-011 maps to missing generated-content validation before approval. Current script normalization catches some newline artifacts, but this should be formal write-preflight validation, not ad hoc repair.
- Regex command policy leaves a broad false-negative surface for shell mutations.
- Re-running proposal resolution at approval time risks executing something different from the approved preview if grants, recent-target context, normalization, or parser behavior changes.

Keep:

- Keep typed tool definitions, argument schemas, scope requirements, risk classes, local file tools, finite command tool concept, process lifecycle concept, local server probe/discovery, and visual context metadata.
- Keep approval for writes, risky commands, installs, network commands, privileged commands, process control, and stop/start operations.
- Keep bounded command output and file-read limits.

Replace:

- Replace `requiresApproval: Bool` as the main safety lever with a declarative permission policy engine: allow, ask, deny.
- Replace one `stage_write_proposal` tool that both drafts and executes with separate app-owned steps:
  - model/tool drafts a `FileChangeDraft`.
  - runtime validates and creates immutable `FileChangeProposal`.
  - UI approves a durable wait.
  - app-owned executor applies the immutable approved proposal by `sideEffectID`.
- Replace default raw-shell execution for unmatched commands with a safer default:
  - deterministic allowlist for read-only inspection commands.
  - ask for all raw shell commands outside the allowlist.
  - deny known destructive/secret-touching classes.
- Replace in-memory process records with durable process records and recovery probes.
- Replace broad "any file grant means write scope" with read roots, write roots, and per-operation approval policy. If the UI still uses one grant list, the policy must make clear that writes require separate explicit approval inside those roots.

Add:

- Add `AgentPermissionPolicy`:
  - inputs: run mode, provider tier, tool definition, arguments, local grants, sensitive path rules, command policy, network/process/write scopes.
  - output: allow, ask, deny, with risk class, reason, preview, and required wait type.
- Add default deny rules for secrets and credentials across read, search, write, and terminal commands:
  - `.env`, `.env.*`, private keys, SSH keys, cloud credential files, signing keys, keychains, package-manager auth files, and hidden credential stores.
- Add tool schema filtering by run mode and provider tier. A plain chat or Tier B model should not even see side-effect tools.
- Add a side-effect execution ledger:
  - `sideEffectID`, `toolCallID`, `proposalID`, `approvedWaitID`, operation hash, before hash/snapshot, after hash/snapshot, startedAt, completedAt, status, and error.
- Add immutable approval artifacts:
  - file diff/content preview artifact.
  - command string/working directory/timeout/policy class artifact.
  - process command/working directory/processID artifact.
- Add post-effect verification:
  - file exists/content hash after write.
  - command exit/output record.
  - process PID/status/port tail.
- Add rollback/revert where practical:
  - restore previous file content for replace/append.
  - delete created file if user reverts.
  - stop started managed process.
- Add generated-content validators before approval:
  - syntax checks for common script types where cheap and local.
  - reject obvious marker artifacts and unresolved placeholders.
  - report validation failures as model-visible repair observations, not as approval prompts.

Decision:

The next architecture should keep Pixel Pane's typed tool idea but rewrite the permission and side-effect boundary. The model may draft and request; the app policy engine approves, waits, executes, verifies, records, and recovers.

### ARCHREV-007 - Evidence, Observation Packing, Answerability, And Verification

Current facts:

- `AgentKernelEvidenceRecordV2` is a useful typed record with kind, summary, optional body, metadata, privacy class, trust class, truncation flag, and related tool call ID.
- Evidence is recorded for `read_file`, approved writes, visual context, finite commands, local server probes/discovery, and managed processes.
- `recordSearch(...)` and `recordFileList(...)` append only `toolResult` summaries and UI `AssistantToolState` patches. They do not append `evidenceRecorded` events.
- `AgentKernelSessionLedgerV2.observationMessage` turns `toolResult` into a terse string: `tool_result search_files succeeded: Found N local file snippet(s).`
- `packedContextSnapshot()` sends recent transcript plus current-turn observation messages. It does not automatically include `AssistantToolState` snippets/sources, and it does not select artifact-backed evidence.
- This means model-visible search/list observations can omit the actual paths/snippets while copy-chat/debug export still contains them through `AssistantToolState`.
- Evidence planning is a model call that asks for `declare_evidence_needs`, then maps declared needs into tools. Malformed/timeout planner output is logged as a failed tool result and the runtime continues with the normal loop.
- Final answer verification is also model-mediated: another model call must declare final claims before deterministic `AgentKernelEvidenceVerifierV2` can check them.
- If the final-claim declaration model call is malformed or times out, the runtime blocks the answer even if deterministic evidence already supports it.
- `AgentKernelAnswerabilityGuardV2` is lexical. It detects deferrals, injects one retry observation, and then blocks if the model defers again.
- Deterministic final-answer blockers exist for a few known cases, such as overbroad localhost negatives and file-access contradiction.

Direct failure mapping:

- FC-001: `search_files` found `/Users/nayak/Documents/random-tests/counter.py`, but search results were not recorded as rich evidence. The model-visible context likely contained only a count summary, not the path/source records.
- FC-002: the model produced a correct localhost answer, but final-claim verification failed its own protocol and blocked the supported answer.
- FC-007: lexical answerability guard retries and then blocks, but it does not synthesize from structured evidence itself.
- FC-008: context packing is bounded to the current turn, which is good, but it is not a relevance-ranked evidence/artifact packer.

Comparison to researched patterns:

- Mature runtimes treat tool outputs as structured events/artifacts and make compact, task-relevant observations available to the model. Pixel Pane has structure internally, but not every tool result becomes model-visible evidence.
- Guardrails should be deterministic where possible. Pixel Pane has a deterministic verifier, but still depends on a model to declare which claims to verify.
- Cursor-style context discovery suggests keeping long data in artifacts and selecting it on demand. Pixel Pane currently has bounded bodies but no artifact index or relevance selection.

Keep:

- Keep `AgentKernelEvidenceRecordV2` and deterministic `AgentKernelEvidenceVerifierV2` as core ideas.
- Keep current-turn observation packing and caps as a guard against stale full-ledger context.
- Keep deterministic answerability/final-answer blockers, but make them broader and evidence-aware.

Replace:

- Replace tool-result summaries as the main model-visible observation with evidence packets that include the fields needed for answer synthesis.
- Replace model-mediated final-claim declaration as a blocking gate. A verifier model failure must not block a supported answer.
- Replace lexical answerability guard as the main protection against deferral with deterministic task controllers and evidence-aware synthesis paths.
- Replace ad hoc preflight special cases with a routed set of deterministic local-state controllers.

Add:

- Add evidence recording for every read-only local-state tool:
  - grants listed.
  - folder entries with paths, item count, truncation, and root grant.
  - search snippets with path, score, preview, and matched grant.
  - local server discovery with URL, port, PID, process, working directory, HTTP status, title, and grant match.
- Add an `EvidencePacket` model projection:
  - compact human summary.
  - structured facts as stable key/value or JSON.
  - source IDs and artifact IDs.
  - confidence/trust class and privacy class.
  - exact path/URL/port/command fields when they are the likely answer.
- Add evidence artifacts for long bodies/output:
  - file content artifact.
  - command stdout/stderr artifact.
  - search result artifact.
  - debug/provider artifact.
  - model prompt should receive selected excerpts and artifact references, not full raw data by default.
- Add deterministic controllers for common local-state tasks:
  - "do I have/access/see file X?"
  - "what files match X?"
  - "is localhost/port/site running?"
  - "what happened after command/write/process action?"
  - These controllers can answer directly or provide an answer packet before model synthesis.
- Add deterministic claim extraction for common local-state answer shapes. Use verifier models only as advisory or for unsupported ambiguous prose.
- Add answer support records:
  - final answer points to evidence IDs.
  - unsupported claims are flagged before display.
  - verifier failure becomes trace diagnostics unless no deterministic support exists.
- Add relevance-ranked context packing:
  - current run instructions.
  - compact conversation continuity.
  - selected evidence packets for the current task.
  - selected artifact excerpts.
  - no stale UI tool-state snapshots by default.

Decision:

The next architecture should make evidence packets and deterministic local-state controllers the default for answerable local questions. Model synthesis can phrase the answer, but deterministic evidence selection and verification decide what facts are available and whether the answer is supported.

### ARCHREV-008 - UI Runtime Integration And Stuck-Turn Recovery

Current facts:

- `ResultPanelView` owns agent runtime construction, the runtime actor instance, live ledger, visible turns, active `Task`, progress state, pending approvals, pending write/terminal proposals, assistant tool state, chat context IDs, persistence, and copy-chat debug export.
- The UI calls `runTurn(...)` or `resolveApproval(...)` and waits for a single returned `AgentKernelChatResultV2`. Progress updates are callbacks into SwiftUI state, not a durable event stream.
- Pending approvals are SwiftUI `@State` values. A pending write/command can only resume while `pendingAgentKernelApproval` and the proposal are still in memory.
- `applyAgentKernelOutput(...)` clears loading and progress, applies state patches, persists the projected session, and updates visible answer text from the primary UI event.
- If a runtime returns pending approval without a primary chat event, the visible turn can still have an empty answer while loading is removed. The transcript then renders a thinking indicator based on `turn.answer.isEmpty`, even though the runtime may actually be waiting for user approval.
- Some UI cards are derived from answer text parsing (`FileWriteContinuationBanner.parse`, `RunningTerminalBanner.parse`) instead of typed runtime events.
- Cancellation is UI-driven: `cancelAskQuestion()` cancels the task, optionally kills MLX server process, appends `.taskCanceled` to the in-memory ledger, mutates the last visible answer, and persists the projected transcript.
- Chat loading state is keyed by `loadingActions`. This works for simple one-shot actions but is too coarse for a durable agent run with waiting, retryable, interrupted, and terminal states.
- Copy-chat export uses visible turns, `AssistantToolState`, current ledger, current progress, pending UI state, and a temporary DEBUG-only `AgentKernelDebugExportV2`.
- `AgentKernelDebugExportV2.swift` explicitly says it is temporary and should be deleted before production.
- Saved chat history is restored from visible turns/tool state, which loses run status, waits, trace, and evidence.

Comparison to researched patterns:

- ADK/OpenAI-style runtimes expose event/trace streams. Pixel Pane's UI receives progress callbacks plus one final result, so it cannot observe or recover each step independently.
- LangGraph-style durable execution lets interrupted runs be resumed or marked recoverable. Pixel Pane cannot recover a run after app interruption because the UI owns live task handles and pending waits.
- Cursor/Windsurf-style products expose checkpoints, background/stuck work, and restore/revert surfaces. Pixel Pane has debug export and visible banners, but no durable run list or recovery contract.

Failure impact:

- FC-003 hang diagnosis depends on live progress text such as `Calling Local Apple Model`; there is no durable watchdog event that says the model call exceeded deadline, was canceled, or is recoverable.
- FC-009 approval/resume divergence exists because UI state can execute or lose approval without a durable wait.
- FC-012 layout/progress issues made runtime failures harder to interpret because empty answer, loading state, and progress state are separate UI heuristics.

Keep:

- Keep the notch-native chat surface and compact progress affordance.
- Keep visible chat turns as a projection for user readability.
- Keep copy/export, but source it from durable trace data.
- Keep manual cancel/retry controls.

Replace:

- Replace UI-owned live agent state with an `AgentRunViewModel` that observes a durable `AgentRunStore` and runtime event stream.
- Replace `Task`-result application as the primary boundary with typed event projection by `sessionID` and `runID`.
- Replace empty-answer-is-thinking rendering with explicit run status: running, waiting, interrupted, completed, blocked, failed, canceled.
- Replace text-parsed banners with typed event/wait/proposal views.
- Replace temporary debug export with a production-safe trace export generated from durable run events and artifacts.

Add:

- Add a UI/runtime contract:
  - UI sends intents: start run, cancel run, approve wait, deny wait, retry interrupted step, start new chat, load session.
  - Runtime/store emits events: run created, step started, progress, model request, model response, tool requested, tool result, approval wait created, approval resolved, side effect started/completed, evidence recorded, terminal status.
  - UI renders only from current session/run projection.
- Add run statuses:
  - draft, queued, running, waitingForApproval, waitingForUserInput, interrupted, completed, blocked, failed, canceled.
- Add stuck-turn recovery:
  - watchdog marks long-running model/tool steps as interrupted with retry/cancel actions.
  - app launch scans active runs and marks unsafe in-flight steps interrupted.
  - pending approval waits restore their proposal cards.
- Add typed progress:
  - progress event IDs, phase, summary, stepID, startedAt, updatedAt, deadlineAt, provider/tool metadata.
  - terminal events clear progress by runID, not by UI heuristics.
- Add typed approval views:
  - file change preview/diff.
  - terminal command preview and policy reason.
  - process start/stop preview.
  - approve/deny dispatches wait resolution to runtime by waitID.
- Add trace export:
  - session/run IDs.
  - ordered events.
  - evidence IDs and artifacts.
  - provider diagnostics.
  - redaction of file contents, prompt bodies, screenshots, and secrets unless explicitly included by debug mode.

Decision:

The next architecture should make the notch UI a projection of durable run state. `ResultPanelView` should no longer own the agent loop, pending approvals, or trace reconstruction.

### Stale Or Context-Heavy Inputs To Revisit During DOCREV

- Deleted AGENTV2 architecture documents were audit inputs only; their useful findings now live in this revision artifact.
- `workflow/backlog.md` contains a long completed AGENTV2 history that is useful for this revision but expensive as future agent context.
- `workflow/status.md` still contains many historical AGENTV2 notes for audit continuity.
- `AssistantHarness.swift` contains reusable shell/tool state structs but carries an old harness name.
- `AgentKernelDebugExportV2.swift` is explicitly temporary.

## Remove / Modify / Add Findings

### Chosen Direction

Pixel Pane should move from a monolithic in-memory agent loop to a durable, event-driven local agent runtime:

- `AgentRunStore`: durable sessions, runs, steps, waits, events, evidence, and artifacts.
- `AgentRunner`: small step executor with checkpoints before/after each step.
- `AgentPermissionPolicy`: declarative allow/ask/deny policy for tools and side effects.
- `AgentToolKit`: typed tools, deterministic local-state controllers, app-owned side-effect executors.
- `AgentEvidenceStore`: evidence packets, artifact references, answer support records.
- `AgentModelGateway`: provider adapters gated by capability tier.
- `AgentRunViewModel`: SwiftUI projection of durable run state.

This is a rearchitecture, not another AGENTV2 hardening pass. Existing AGENTV2 code can be reused only where it cleanly fits this shape.

### Remove

- Remove `AgentKernelChatRuntimeV2` as the central "does everything" runtime. Its responsibilities should be split into runner, store, policy, tools, evidence, model gateway, and projection layers.
- Remove transcript-only `ChatHistoryStore` as the source of agent continuity. Chat history should be a projection from durable run events.
- Remove SwiftUI-owned pending approval as the only approval state. Approval must be a durable wait.
- Remove model-mediated final-claim verification as a blocking gate for supported local-state answers.
- Remove full-agent behavior for best-effort text protocol providers.
- Remove default raw-shell execution for commands that merely fail to match risky regexes.
- Remove `stage_write_proposal` as both draft and execution mechanism. Separate draft, immutable proposal, durable approval, app-owned apply, verify, and rollback.
- Remove temporary `AgentKernelDebugExportV2.swift` after durable trace export exists.
- Remove text-parsed UI banners for file/terminal continuations. Render typed events/waits/proposals.
- Remove stale AGENTV2 docs after DOCREV folds useful findings into current architecture docs.

### Modify

- Modify `AgentKernelSessionLedgerV2` into a durable event model with:
  - session ID, run ID, step ID, wait ID, side-effect ID.
  - append-only events persisted during execution.
  - explicit run status and recovery status.
- Modify provider adapters into capability-tiered adapters:
  - Tier A: native/strict structured output, full agent.
  - Tier B: constrained structured text, low-risk read/proposal only.
  - Tier C: plain chat/synthesis only.
- Modify tool definitions into policy-aware tool specs:
  - risk, scopes, allow/ask/deny defaults, sensitive path rules, provider/run-mode visibility, artifact behavior.
- Modify file-search/list outputs so they record evidence packets with exact paths, snippets, scores, roots, and truncation.
- Modify command execution to use a deterministic safe-command allowlist plus approval for raw shell.
- Modify process lifecycle to persist process records and recover status from PID/processID/ports.
- Modify `AssistantToolState` into a UI projection/cache only. It must not be runtime memory.
- Modify copy-chat export to read from durable run traces and artifacts.
- Modify `ResultPanelView` so it delegates agent state to an `AgentRunViewModel`.

### Add

- Add an Application Support backed `AgentRunStore`, preferably SQLite for indexed metadata plus artifact files for large payloads.
- Add a checkpointed step graph:
  - create run.
  - route task.
  - select provider/run mode.
  - collect deterministic evidence.
  - request model synthesis if needed.
  - validate answer support.
  - create wait for approval if needed.
  - execute approved side effect exactly once.
  - verify effect/evidence.
  - terminal status.
- Add durable app-launch recovery:
  - waiting approvals restore.
  - in-flight model/tool steps become interrupted.
  - managed process records are reprobed.
  - terminal runs project cleanly.
- Add a declarative `AgentPermissionPolicy` with sensitive-file denial and scoped allow/ask/deny decisions.
- Add immutable approval artifacts:
  - file diff/content preview.
  - command preview with working directory, timeout, and policy class.
  - process command preview.
- Add side-effect records with hashes/snapshots, started/completed status, error, and rollback/revert data.
- Add evidence packets and artifacts for every local-state tool result.
- Add deterministic controllers for common local questions:
  - file visibility/existence/search.
  - localhost/site/port status.
  - command/write/process status.
  - cancellation/completion state.
- Add answer support records linking final visible answers to evidence IDs.
- Add provider conformance tests by capability tier.
- Add runner/store/policy/tool/evidence fixture tests before real-provider testing.
- Add a production-safe trace export with privacy redaction.
- Add UI run recovery controls: cancel, retry interrupted, approve/deny wait, revert file change where available, stop managed process.

### Failure Coverage

- FC-001 is addressed by evidence packets for search/list results and deterministic file-visibility controllers.
- FC-002 is addressed by removing malformed model verifier output as a blocking gate.
- FC-003 is addressed by provider capability tiers, step deadlines, durable interruption, and relaunch recovery.
- FC-004 through FC-006 are addressed by strict provider tiers, native/strict structured adapters for full agent mode, and compatibility limits for text protocol.
- FC-007 is addressed by deterministic local-state controllers and evidence-aware synthesis rather than lexical deferral retries.
- FC-008 is addressed by bounded evidence/artifact selection instead of stale UI/tool-state packing.
- FC-009 is addressed by durable waits and app-owned side-effect execution.
- FC-010 is addressed by deterministic local-server controllers and explicit evidence requirements.
- FC-011 is addressed by generated-content validators, immutable approvals, and post-effect verification.
- FC-012 is addressed by UI projection from explicit run status rather than empty-answer/loading heuristics.

## Implementation Sprint Draft

The implementation sprint has been written in `workflow/backlog.md` as `AGENTR` - Agent Runtime Rearchitecture Implementation. It intentionally follows `DOCREV` so stale docs are removed before coding agents start the replacement.

High-level ticket sequence:

1. `AGENTR-001` Build durable agent run store and event schema.
2. `AGENTR-002` Add checkpointed runner and app-launch recovery.
3. `AGENTR-003` Build capability-tiered model gateway.
4. `AGENTR-004` Build permission policy and filtered tool catalog.
5. `AGENTR-005` Split side-effect drafts, approvals, execution, and rollback.
6. `AGENTR-006` Add evidence packets, artifacts, and deterministic local controllers.
7. `AGENTR-007` Replace chat UI bridge with durable run projection.
8. `AGENTR-008` Replace debug export and chat history with trace projections.
9. `AGENTR-009` Remove superseded AGENTV2 runtime paths and wire the new runtime.
10. `AGENTR-010` Add rearchitecture regression matrix and real-provider QA gates.

The first implementation ticket after documentation reset is `AGENTR-001`.
