# Agent Kernel V2 Architecture

Last updated: 2026-05-28

Agent Kernel V2 is Pixel Pane's app-owned assistant runtime. The old prompt-heavy harness has been deleted; the notch chat now routes through V2 using a session ledger, provider-neutral model adapters, typed tools, approvals, runtime guards, and evidence records.

The current implementation lives in `PixelPane/PixelPane/AgentKernel/`.

## Current Shape

The active chat path is:

1. `ResultPanelView` builds an `AgentKernelChatContextV2` from the current chat ledger, user message, local file grants, visual context, allowed working directories, recent write targets, and output budget.
2. `AgentKernelChatRuntimeV2` appends the user message to the ledger and starts a bounded model/tool loop.
3. The runtime prepends an `app_context_inventory` system message to each model request. This inventory lists trusted app state: granted files/folders, active visual context, allowed working directories, and recent write targets.
4. The runtime asks the model for structured evidence needs before final synthesis.
5. The runtime maps declared evidence needs to typed capabilities.
6. Read-only observations execute immediately. Side-effect observations return pending approval UI state.
7. The selected model adapter receives transcript messages, observation messages, the context inventory, and available tool schemas.
8. The model returns either a final answer or a typed tool call.
9. `AgentKernelModelOutputNormalizerV2` normalizes protocol-shaped final text into typed events before transcript handling.
10. The runtime validates tool calls against schema, scope, risk, approval policy, and no-progress guards.
11. Tool outputs become control-plane events and source/evidence records, not user-authored chat turns.
12. Before accepting a final answer, the runtime asks the model to declare verifiable local-state claims and gates those claims against ledger evidence.
13. The runtime loops until a final answer, pending approval, block, failure, cancel, or tool-step limit.

## Runtime Boundary

`AgentKernelChatRuntimeV2` owns:

- task loop and tool-step budget;
- session ledger updates;
- model adapter request construction;
- app context inventory injection;
- evidence-needs planning requests;
- runtime mapping from evidence needs to capabilities;
- model-output normalization before transcript writes;
- tool registry construction;
- typed tool validation and execution dispatch;
- approval request and approval resolution;
- final-claim extraction and evidence gating;
- cancellation integration from the UI;
- no-progress and duplicate-call guards;
- assistant state patches for the existing UI/export surfaces.

The kernel does not own SwiftUI/AppKit rendering, capture UI, settings UI, file picker UI, provider internals, release/update logic, billing, or packaging.

## Session Ledger

`AgentKernelSessionLedgerV2` is the append-only task record. It stores bounded text and metadata, not screenshot or attached-image pixels by default.

Transcript events:

- `userMessage`
- `assistantMessage`

Control-plane events:

- `modelCall`
- `modelResponse`
- `toolProposal`
- `toolResult`
- `approvalRequested`
- `approvalResolved`
- `processStatus`
- `evidenceRecorded`
- `taskBlocked`
- `taskFailed`
- `taskCanceled`
- `taskCompleted`

Only transcript events become normal chat messages. Control events may be packed back to the model as structured observations, but they must not be replayed as fake user turns. This is the guardrail that prevents loops like repeated "Allow terminal..." messages.

## App Context Inventory

Every model request currently starts with an app-generated system message named `app_context_inventory`.

It includes:

- `available_local_grants`: current granted files/folders;
- `active_visual_context`: screenshot/attachment/clipboard context metadata and bounded OCR excerpt;
- `allowed_working_directories`: directories where command/process tools may run;
- `recent_write_targets`: paths from pending or recent staged writes.

This inventory is trusted app state. Retrieved file contents, OCR text, terminal output, and tool output remain untrusted observations.

The inventory is deliberately generic. It is not hardcoded to website folders, port checks, or any user phrasing. It exists so models know what local context Pixel Pane has before they answer.

## Model Adapter Boundary

Model adapters implement `AgentKernelModelAdapterV2`.

Provider metadata includes:

- provider kind: fixture, Apple local, MLX local, OpenAI-compatible, Pixel Pane Cloud, or custom;
- route: local or cloud;
- input/output modalities;
- tool-calling mode: none, native, or text protocol;
- structured output reliability;
- streaming mode;
- context/output limits;
- availability and unavailable reason.

Current adapter paths:

- `FixtureAgentKernelAdapterV2` for deterministic tests.
- `AgentKernelAIBackendAdapterV2` bridges existing Apple, MLX, hybrid local, and Pixel Pane Cloud `AIBackend` implementations.
- `AgentKernelOpenAICompatibleAdapterV2` targets local OpenAI-compatible endpoints such as Ollama-compatible `/v1/chat/completions`.
- `AgentKernelProviderAdapterCatalogV2` constructs Apple, MLX, Pixel Pane Cloud, and local OpenAI-compatible adapter variants.

Text-only providers use `AgentKernelTextProtocolPromptBuilderV2`, which asks for one JSON object: either `final_answer` or `tool_call`. This prompt describes protocol format and tool schemas only. Product policy, permission rules, approval rules, retry rules, and completion criteria belong in Swift.

`AgentKernelModelOutputNormalizerV2` is the final shared boundary for provider output. If a provider emits protocol-shaped JSON as final text, such as `{"type":"tool_call", ...}`, the runtime converts it to a typed tool event or rejects it before any assistant transcript write. Non-protocol JSON remains valid user-facing prose.

## Tool Registry

`AgentKernelToolRegistryV2` validates all tool calls before execution.

Validation checks:

- tool exists;
- arguments match the schema;
- required arguments are present;
- requested scope is available;
- deny rules do not match;
- duplicate/no-progress guards allow the call;
- approval policy is satisfied or returns an approval request.

Tool schemas are exposed to the model, but the runtime remains the authority.

## Current Tools

### Local Context

Implemented in `AgentKernelLocalContextToolsV2`.

- `list_grants`: list active granted files/folders.
- `list_folder`: list a granted folder, or grants when no path is supplied.
- `search_files`: search text-like files inside granted locations.
- `read_file`: read bounded text from a granted file.
- `stage_write_proposal`: stage create/replace/append inside a granted location; never writes directly.
- `describe_visual_context`: describe active screenshot/image/OCR context without persisting pixels.

File reads and searches are limited to explicit local grants. Writes are staged as `LocalFileWriteProposal` and require visible approval before `ResultPanelView` executes them through the existing write executor.

### Finite Commands

Implemented in `AgentKernelFiniteCommandToolV2`.

- `run_finite_command`: run a bounded `/bin/zsh -lc` command expected to finish.

The command tool validates working directory scope, applies timeout and output caps, classifies risky commands, blocks destructive patterns, and requires approval for privileged, install/package-execution, network, process-control, and file-mutation patterns. Low-risk commands are allowed without approval.

### Process Lifecycle

Implemented in `AgentKernelProcessLifecycleToolV2`.

- `start_process`: start a long-running local process with lifecycle tracking.
- `process_status`: inspect a managed process.
- `tail_process_output`: read bounded stdout/stderr tail.
- `stop_process`: stop a managed process.
- `probe_local_server`: probe a localhost URL or TCP port for listener and HTTP-response evidence.

Process start/stop are side-effect actions and require approval. Status and tail reads are read-only. Managed processes are tracked by process ID, owner session ID, command, working directory, PID, status, exit code, and bounded output tails. Output is scanned for localhost URLs so local server URLs can be surfaced when a process announces one.

Localhost probes are read-only and restricted to loopback URLs or explicit local TCP ports.

## Approvals

Side-effect tools return `AgentKernelPendingApprovalV2` rather than executing immediately.

Approval requests include:

- approval ID;
- tool call ID;
- tool name;
- risk class;
- reason;
- display summary;
- operation preview when available.

Approval resolution is a control event. The UI no longer inserts fake user messages such as "Allow terminal..." when approving or canceling. Approving resumes the same task. Denying records cancellation and returns a clear assistant message.

## Evidence

`AgentKernelEvidenceVerifierV2` defines evidence and claim types for files, writes, commands, managed processes, local server probes, visual context, approvals, model statements, and task lifecycle.

Current evidence factories exist for:

- file reads;
- staged write proposals;
- completed file writes;
- finite commands;
- managed processes;
- local server probes;
- visual context;
- approvals and task lifecycle.

`AgentKernelEvidencePlannerV2` adds two structured model-owned declarations around the normal loop:

1. `declare_evidence_needs`: the model declares the deterministic evidence it needs from vague or explicit user phrasing.
2. `declare_final_claims`: the model declares verifiable local-state claims made by a candidate final answer.

The runtime maps evidence needs to typed tools, executes safe read-only observations immediately, routes side-effect needs through existing approvals, and verifies final claims with `AgentKernelEvidenceVerifierV2` before accepting the answer.

## Runtime Guards

`AgentKernelRuntimeGuardsV2` currently handles:

- approval decision based on risk and policy;
- duplicate tool call detection after the same result was observed;
- repeated model response detection;
- force-synthesis/block when the model repeats an already-observed step;
- cancel/resume ledger helpers.

These guards are generic loop and safety controls. They are not scenario-specific intent routing.

## UI Integration

`ResultPanelView` owns the SwiftUI/AppKit presentation and bridges V2 results back into the existing UI state:

- ask turns and visible assistant answers;
- pending file write approval card;
- pending terminal/process approval card;
- assistant tool state and export state;
- saved chat sessions;
- clear chat history control;
- cancellation from the Send/Cancel button.

The UI creates `AgentKernelChatContextV2` from current app state and applies `AgentKernelAssistantStatePatchV2` after each runtime result.

## Non-Goals

- No product policy in internal prompts.
- No hidden global memory.
- No chat transcript pollution with approval/tool/process events.
- No silent file writes.
- No unrestricted terminal execution.
- No continuous screen recording or screenshot persistence.
- No terminal-as-process-lifecycle shortcut for long-running tasks.

## Regression Matrix

| Scenario | Fixture Coverage | Real Provider Manual QA |
|---|---|---|
| Plain final answer | Covered | Required before beta |
| App context inventory includes granted local context | Covered | Required before beta |
| Read-only granted file context | Covered | Required before beta |
| Staged file write and approval | Covered | Required before beta |
| Canceled write or command approval | Covered | Required before beta |
| Low-risk finite command | Covered | Required before beta |
| Long-running process/local server lifecycle | Covered at capability level | Required before beta |
| Repeated command/tool loop | Covered | Required before beta |
| Malformed or empty model output | Covered | Required before beta |
| Timeout/no-progress handling | Covered | Required before beta |
| Control events excluded from transcript | Covered | Required before beta |
| Prompt-injection-like tool output treated as untrusted | Covered through policy and evidence tests | Required before beta |
| Local/cloud privacy route preservation | Covered through adapter mapping | Required before beta |
| Model-driven evidence planning | Covered | Required before beta |
| Protocol-shaped model output does not leak into transcript | Covered | Required before beta |
