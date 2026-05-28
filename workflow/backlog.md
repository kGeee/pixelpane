# Pixel Pane Backlog

Last updated: 2026-05-28

## Current Product

Pixel Pane is a local-first, notch-native assistant shell for macOS. The current UI, capture/OCR, file grants, settings shell, history shell, backend plumbing, and low-level terminal primitives are preserved while assistant execution routes through Agent Kernel V2.

## Status Values

- `Not Started`
- `In Progress`
- `Blocked`
- `In Review`
- `Done`

## Current Recommended Story

`AGENTV2-036` Introduce deterministic answerability preflight scaffold.

Reason: The accepted answerability direction is a deterministic, runtime-owned preflight traffic controller that classifies obvious local-state questions before the generic model loop, complementing the post-answer answerability guard. `AGENTV2-036` lands the behavior-neutral scaffold (planner type, shared `collectEvidence` helper, and the `continueTurn` routing branch) so `AGENTV2-037`-`AGENTV2-039` can light up one intent at a time. `AGENTV2-033` follows `AGENTV2-037` so the enriched copy-chat export can include the new preflight route traces.

## Current Stories

| ID | Story | Status | Depends On |
|---|---|---|---|
| `AGENTV2-001` | Inventory shell versus agent code | Done | Restart decision |
| `AGENTV2-002` | Delete runtime and duplicate runner paths | Done | `AGENTV2-001` |
| `AGENTV2-003` | Clean workflow and docs for the V2 rebuild | Done | `AGENTV2-001` |
| `AGENTV2-004` | Add a stub assistant path that preserves the UI shell | Done | `AGENTV2-002` |
| `AGENTV2-005` | Define the Agent Kernel V2 architecture brief | Done | `AGENTV2-004` |
| `AGENTV2-006` | Add fixture model contract and kernel harness | Done | `AGENTV2-005` |
| `AGENTV2-007` | Build session ledger V2 and task state machine | Done | `AGENTV2-006` |
| `AGENTV2-008` | Separate control events from chat transcript | Done | `AGENTV2-007` |
| `AGENTV2-009` | Add approval, cancellation, resume, and no-progress guards | Done | `AGENTV2-008` |
| `AGENTV2-010` | Define Tool Registry V2 and safety policy | Done | `AGENTV2-009` |
| `AGENTV2-011` | Add file and visual-context capabilities | Done | `AGENTV2-010` |
| `AGENTV2-012` | Add finite command capability | Done | `AGENTV2-010` |
| `AGENTV2-013` | Add long-running process and local server lifecycle capabilities | Done | `AGENTV2-012` |
| `AGENTV2-014` | Add evidence records and deterministic verification hooks | Done | `AGENTV2-010`, `AGENTV2-013` |
| `AGENTV2-015` | Define provider-neutral model adapter API | Done | `AGENTV2-009` |
| `AGENTV2-016` | Add native tool-call and minimal text protocol adapters | Done | `AGENTV2-015` |
| `AGENTV2-017` | Wire Apple, MLX, and OpenAI-compatible adapter paths | Done | `AGENTV2-016` |
| `AGENTV2-018` | Integrate notch chat with Agent Kernel V2 | Done | `AGENTV2-014`, `AGENTV2-017` |
| `AGENTV2-019` | Restore capture, grants, history, and approval UX on V2 | Done | `AGENTV2-018` |
| `AGENTV2-020` | Add V2 regression matrix and final cleanup | Done | `AGENTV2-019` |
| `AGENTV2-021` | Seed model requests with app context inventory | Done | `AGENTV2-020` |
| `AGENTV2-022` | Add model-driven planning and evidence gating | Done | `AGENTV2-021` |
| `AGENTV2-023` | Harden model output normalization and prevent protocol leakage | Done | `AGENTV2-022` |
| `AGENTV2-024` | Rebuild agent/UI boundary around typed runtime events | Done | `AGENTV2-023` |
| `AGENTV2-025` | Add strict provider protocol decoder and schema-rich tool contracts | Done | `AGENTV2-024` |
| `AGENTV2-026` | Add bounded tool-argument repair and safe protocol failure handling | Done | `AGENTV2-025` |
| `AGENTV2-027` | Rebuild chat export and persistence from typed ledger events | Done | `AGENTV2-024` |
| `AGENTV2-028` | Re-enable evidence planning on the typed boundary | Done | `AGENTV2-026` |
| `AGENTV2-029` | Harden real-provider QA failures for planning and model selection | Done | `AGENTV2-028` |
| `AGENTV2-030` | Document the agentic architecture in plain language | Done | `AGENTV2-029` |
| `AGENTV2-031` | Recover from incomplete staged-write tool calls | Done | `AGENTV2-030` |
| `AGENTV2-032` | Add capability-aware answerability guard | Done | `AGENTV2-031` |
| `AGENTV2-033` | Enrich copy-chat debug export for agent traces | Not Started | `AGENTV2-032` |
| `AGENTV2-034` | Bound model-call time and packed context memory | Done | `AGENTV2-032` |
| `AGENTV2-035` | Resume approved writes through the kernel | Done | `AGENTV2-034` |
| `AGENTV2-036` | Introduce deterministic answerability preflight scaffold | Not Started | `AGENTV2-035` |
| `AGENTV2-037` | Route obvious local-server questions through preflight | Not Started | `AGENTV2-036` |
| `AGENTV2-038` | Gate file-visibility preflight on grants and preserve writes | Not Started | `AGENTV2-036` |
| `AGENTV2-039` | Route managed-process status through preflight | Not Started | `AGENTV2-036` |
| `FOUND-008` | Decide telemetry vendor or continue deferring telemetry | Blocked | Product decision before beta |

## Sprint: `AGENTV2` - Model-Agnostic Agent Kernel Rebuild

Objective: rebuild Pixel Pane's agentic system around an app-owned runtime similar in spirit to mature coding-agent systems: the model proposes, the runtime validates, app-owned tools execute, observations return, and deterministic state decides whether to continue, block, or complete.

Design rules:

- Keep product policy in Swift, not in internal prose prompts.
- Permit minimal adapter prompts only for text-only models that lack native tool calling.
- Test the kernel against fixture models before wiring real providers.
- Treat approvals, tool calls, process status, receipts, and errors as control-plane events, not chat transcript content.
- Split finite commands from long-running processes and local server lifecycle.
- Enforce permissions, loop guards, evidence checks, and completion criteria in app code.
- Preserve the current UI shell until V2 can replace the runtime safely.

## Sprint 1 - Prune To A Stable Shell

Goal: remove stale architecture and preserve the useful native product shell.

### `AGENTV2-001` - Inventory Shell Versus Agent Code

Goal: classify current files and docs into keep, delete, or rewrite.

Acceptance:

- [x] Identify UI shell files to preserve: notch surface, capture/OCR, file grants, settings shell, history shell, local/cloud backend plumbing, and low-level terminal primitives.
- [x] Identify prompt-heavy runtime code, duplicate runner paths, semantic patch logic, dev scripts, and obsolete docs to delete.
- [x] Document the active shell boundary in `workflow/status.md` and `docs/architecture.md`.
- [x] Delete code classified as stale and not part of the future runtime.

Verification:

- No build required if only docs/workflow notes change.

Status: Done.

### `AGENTV2-002` - Delete Runtime And Duplicate Runner Paths

Goal: remove prompt-heavy runtime paths from the app.

Acceptance:

- [x] Remove prompt-heavy runner paths from the active assistant route.
- [x] Delete duplicate agent execution paths that compete with the new rebuild direction.
- [x] Keep a compile-safe stub where the current UI still needs an assistant entry point.
- [x] Preserve reusable low-level primitives such as file grants, capture context, backend clients, write proposals, and terminal policy.
- [x] Update imports/call sites so the app still builds.

Verification:

- `PixelPane/Scripts/verify-debug-build.sh` succeeds.

Status: Done.

### `AGENTV2-003` - Clean Workflow And Docs For The V2 Rebuild

Goal: remove stale guidance from `workflow/` and `docs/`.

Acceptance:

- [x] Delete or rewrite outdated action-rail and runtime planning text in `workflow/`.
- [x] Delete or rewrite stale architecture/product docs in `docs/`.
- [x] Keep only a compact source of truth for the V2 rebuild, durable product decisions, build commands, and active tickets.
- [x] Move still-valid durable decisions into `workflow/decisions.md`.
- [x] Ensure `workflow/status.md`, `workflow/backlog.md`, and `workflow/README.md` all point to the current V2 story.

Verification:

- Docs review only unless app files change.

Status: Done.

### `AGENTV2-004` - Add A Stub Assistant Path That Preserves The UI Shell

Goal: keep the app shippable while runtime execution is removed.

Acceptance:

- [x] The notch chat UI still opens and can show a clear temporary assistant-unavailable message.
- [x] Capture/OCR, file grants, settings, and history shell remain usable without runtime execution.
- [x] No stale tool approval or terminal prompt loops remain reachable through the stub.
- [x] The stub is clearly marked temporary and isolated from the V2 kernel.

Verification:

- `PixelPane/Scripts/verify-debug-build.sh` succeeds.
- Manual smoke: app launches and notch UI opens.

Status: Done.

## Sprint 2 - Build The Agent Kernel

Goal: create the new deterministic runtime using fixture models before any real model integration.

### `AGENTV2-005` - Define The Agent Kernel V2 Architecture Brief

Goal: create the implementation brief for the new kernel.

Acceptance:

- [x] Define the runtime boundary, session ledger, task state machine, event stream, approval lifecycle, model adapter boundary, tool boundary, and evidence boundary.
- [x] Define control-plane events versus chat transcript messages.
- [x] Define what minimal model adapter prompts may and may not contain.
- [x] Define non-goals for V2: no product policy in prompts, no hidden global memory, no terminal-as-process lifecycle shortcut.
- [x] Record the architecture restart decision in `workflow/decisions.md`.

Verification:

- Docs-only story unless helper types are added.

Status: Done.

### `AGENTV2-006` - Add Fixture Model Contract And Kernel Harness

Goal: test the kernel with deterministic fake models.

Acceptance:

- [x] Add fixture model adapters that return scripted final answers, tool calls, malformed output, empty output, repeated calls, and timeouts.
- [x] Add a pure Swift harness for kernel tests.
- [x] Ensure fixture models can assert the messages and tool schemas they receive.
- [x] No Apple, MLX, cloud, or Ollama path is required for this story.

Verification:

- Kernel harness passes.
- Debug build succeeds if app code changes.

Status: Done.

### `AGENTV2-007` - Build Session Ledger V2 And Task State Machine

Goal: make task progress explicit and inspectable.

Acceptance:

- [x] Define V2 session events for user message, assistant message, model call, tool proposal, tool result, approval, process status, evidence, block, failure, and completion.
- [x] Define task states such as planning, awaiting approval, running tool, observing, verifying, repairing, completed, blocked, canceled, and failed.
- [x] Persist only bounded text/metadata; do not persist screenshot/image pixels by default.
- [x] Add tests for new session isolation and state transitions.

Verification:

- Kernel harness passes.

Status: Done.

### `AGENTV2-008` - Separate Control Events From Chat Transcript

Goal: prevent approval/tool/process events from polluting model-visible conversation.

Acceptance:

- [x] Approval prompts, running banners, tool results, process status, cancellations, and receipts are stored as control events.
- [x] Chat transcript contains only user-authored messages and assistant-authored final/interactive messages.
- [x] Model context packing can include structured observations without pretending they were user turns.
- [x] Add regression coverage for the previous repeated "Allow terminal..." loop.

Verification:

- Kernel harness passes.

Status: Done.

### `AGENTV2-009` - Add Approval, Cancellation, Resume, And No-Progress Guards

Goal: make loop control app-owned.

Acceptance:

- [x] Add approval checkpoints for side-effect tools.
- [x] Add cancellation and resume semantics that do not create new chat turns.
- [x] Block repeated identical tool proposals after the same outcome.
- [x] Detect no-progress loops across fixture model responses.
- [x] Force synthesis or block when the model repeats an already-observed step.

Verification:

- Kernel harness covers approval, cancel, resume, duplicate tool call, repeated timeout, and no-progress cases.

Status: Done.

## Sprint 3 - Define Typed Capabilities

Goal: replace prompt-driven behavior with code-owned tools and evidence.

### `AGENTV2-010` - Define Tool Registry V2 And Safety Policy

Goal: create the typed capability registry and policy layer.

Acceptance:

- [x] Define tool schemas, input/output types, risk classes, scope requirements, and approval requirements.
- [x] Validate all tool calls in app code before execution.
- [x] Keep blocked tools blocked rather than repairable.
- [x] Add tests for malformed arguments, denied scope, blocked commands, and approval-required tools.

Verification:

- Kernel harness passes.

Status: Done.

### `AGENTV2-011` - Add File And Visual-Context Capabilities

Goal: restore local context tools without prompt-owned policy.

Acceptance:

- [x] Add file/folder list, search, read, and write proposal tools.
- [x] Enforce user grants for all file operations.
- [x] Add active visual/OCR context tool with transient image handling.
- [x] Confirm writes remain staged and approval-gated.
- [x] Add source records for all outputs.

Verification:

- Tool tests pass.

Status: Done.

### `AGENTV2-012` - Add Finite Command Capability

Goal: support bounded terminal commands that are expected to finish.

Acceptance:

- [x] Add a finite command tool with cwd validation, risk classification, timeout, output cap, and source records.
- [x] Require approval for risky commands, installs, network commands, privileged commands, and process control.
- [x] Treat empty output, non-zero exit, and timeout as distinct observations.
- [x] Add tests for low-risk command, risky approval, blocked command, timeout, and non-zero exit.

Verification:

- Tool tests pass.

Status: Done.

### `AGENTV2-013` - Add Long-Running Process And Local Server Lifecycle Capabilities

Goal: stop using finite terminal commands to manage dev servers.

Acceptance:

- [x] Add process start, status, stop, and output-tail capabilities.
- [x] Track PID, command, cwd, start time, stdout/stderr excerpt, and owner session.
- [x] Add local server lifecycle support with detected URL/port, listener check, and optional HTTP probe.
- [x] Do not kill a successfully started server just because a finite command timeout elapsed.
- [x] Add tests for "server prints localhost URL", "server stays running", "server stopped", and "duplicate start request".

Verification:

- Tool/process lifecycle tests pass.

Status: Done.

### `AGENTV2-014` - Add Evidence Records And Deterministic Verification Hooks

Goal: make claims depend on app-owned evidence.

Acceptance:

- [x] Define evidence records for file reads/writes, finite commands, processes, ports, HTTP probes, visual context, approvals, and model statements.
- [x] Verify common claims: file exists/changed, command ran, process is alive, port is listening, URL responds, build/test passed, task was canceled.
- [x] Block unsupported final claims or require a new tool step.
- [x] Add tests for server lifecycle evidence, write evidence, failed command diagnosis, and unsupported claims.

Verification:

- Evidence tests pass.

Status: Done.

## Sprint 4 - Add Thin Model Adapters

Goal: make real models interchangeable behind the V2 kernel.

### `AGENTV2-015` - Define Provider-Neutral Model Adapter API

Goal: isolate model providers from runtime policy.

Acceptance:

- [x] Define model request, response, streaming, tool-call, and capability types.
- [x] Include capability metadata for local/cloud route, native tool calling, text/image support, context/output limits, structured-output reliability, and streaming.
- [x] Keep runtime behavior independent of provider-specific model names.
- [x] Add adapter contract tests with fixture models.

Verification:

- Adapter tests pass.

Status: Done.

### `AGENTV2-016` - Add Native Tool-Call And Minimal Text Protocol Adapters

Goal: support both strong and weak model routes without product-policy prompts.

Acceptance:

- [x] Add native tool-call adapter path for providers that support tool calls.
- [x] Add minimal text-only protocol adapter for weak/local models.
- [x] The text protocol prompt only describes output format and available tool schema, not product policy.
- [x] Add structured parser, malformed-output handling, and one bounded repair boundary.
- [x] Add tests for valid tool call, final answer, malformed JSON, missing arguments, repeated calls, and timeout.

Verification:

- Adapter tests pass.

Status: Done.

### `AGENTV2-017` - Wire Apple, MLX, And OpenAI-Compatible Adapter Paths

Goal: reconnect available providers to the new adapter contract.

Acceptance:

- [x] Add Apple local text adapter if available.
- [x] Add MLX text adapter using existing backend plumbing where practical.
- [x] Add OpenAI-compatible/Ollama adapter stub or local endpoint path if available.
- [x] Preserve local/cloud privacy routing.
- [x] Record unsupported provider capabilities honestly.

Verification:

- Debug build succeeds.
- Adapter smoke tests pass where providers are installed/available.

Status: Done.

## Sprint 5 - Integrate, Verify, And Harden

Goal: wire the current UI onto V2, prove the architecture, and remove temporary scaffolding.

### `AGENTV2-018` - Integrate Notch Chat With Agent Kernel V2

Goal: make the visible chat use the new kernel.

Acceptance:

- [x] Send chat messages through Kernel V2.
- [x] Render assistant final messages from transcript events.
- [x] Render approvals, tools, process status, receipts, and errors from control events.
- [x] Keep control events out of model-visible chat transcript.
- [x] Preserve local model label and basic loading/cancel state.

Verification:

- Debug build succeeds.
- Manual smoke: plain chat and canceled task.

Status: Done.

### `AGENTV2-019` - Restore Capture, Grants, History, And Approval UX On V2

Goal: restore the expected Pixel Pane workflows.

Acceptance:

- [x] Restore file chips and grant context.
- [x] Restore capture-seeded chat with OCR/visual context.
- [x] Restore saved session reopen without hidden cross-chat memory.
- [x] Restore write approval and terminal/process approval UI.
- [x] Add visible clear chat history control if not already present.

Verification:

- Debug build succeeds.
- Manual QA: file read, confirmed write, canceled write, finite command, process start/stop, capture-seeded chat, saved chat reopen.

Status: Done.

### `AGENTV2-020` - Add V2 Regression Matrix And Final Cleanup

Goal: prove the rebuild across models and finish cleanup.

Acceptance:

- [x] Add cross-model regression matrix for fixture models and available real providers.
- [x] Cover repeated command loops, long-running server lifecycle, malformed model output, file writes, approval/cancel, evidence validation, prompt injection, and privacy routing.
- [x] Remove any temporary scaffolding that is no longer needed after AGENTV2 integration.
- [x] Finalize `docs/`, `workflow/`, Settings copy, QA checklist, and beta notes for V2.

Verification:

- Regression matrix artifact is updated.
- Debug build succeeds.
- Manual QA checklist is current.

Status: Done.

### `AGENTV2-021` - Seed Model Requests With App Context Inventory

Auto-created during manual AGENTV2 QA on 2026-05-28.

Goal: make real providers aware of currently granted local context before they answer.

Acceptance:

- [x] Add a provider-neutral model request inventory for local file/folder grants, visual context, allowed working directories, and recent write targets.
- [x] Keep the inventory as trusted app state, not user-authored transcript text.
- [x] Preserve retrieved file, OCR, terminal, and tool-output text as untrusted data.
- [x] Add fixture coverage that granted local context appears in the model request.

Verification:

- `PixelPane/Scripts/run-agent-kernel-v2-fixture-tests.sh` passes.
- `PixelPane/Scripts/verify-debug-build.sh` succeeds.

Status: Done.

### `AGENTV2-022` - Add Model-Driven Planning And Evidence Gating

Auto-created during AGENTV2 architecture documentation on 2026-05-28.

Goal: keep behavior model-driven while preventing unsupported final answers about local state.

Acceptance:

- [x] Add a structured planning/evidence-needs step before final synthesis.
- [x] Let the model infer evidence needs from vague user phrasing rather than keyword routes.
- [x] Map evidence needs to available capabilities in runtime code.
- [x] Auto-run safe read-only observations when policy permits.
- [x] Require approval for side-effect evidence collection or execution.
- [x] Gate final claims about files, commands, processes, ports, URLs, writes, and task completion against ledger evidence.
- [x] Add fixture coverage for vague local-state prompts that do not use exact words like "port".

Verification:

- `PixelPane/Scripts/run-agent-kernel-v2-fixture-tests.sh` passes.
- `PixelPane/Scripts/verify-debug-build.sh` succeeds.
- Manual QA covers real local model behavior for vague local-state questions. Deferred to manual AGENTV2 QA and beta hardening; fixture coverage now exercises the runtime behavior.

Status: Done.

### `AGENTV2-023` - Harden Model Output Normalization And Prevent Protocol Leakage

Auto-created during manual AGENTV2 QA on 2026-05-28.

Goal: prevent provider text that is actually protocol JSON from ever becoming user-visible assistant prose.

Acceptance:

- [x] Add a shared model-output normalization layer for adapter events.
- [x] Convert protocol-shaped text tool calls into typed `toolCall` events before transcript handling.
- [x] Preserve normal user-facing prose and legitimate non-protocol JSON answers.
- [x] Ensure protocol JSON cannot be appended as an assistant transcript message.
- [x] Recover structurally when a real provider emits a tool call as final text during normal synthesis.
- [x] Add fixture coverage for the observed `port 8000 ?` leakage case.

Verification:

- `PixelPane/Scripts/run-agent-kernel-v2-fixture-tests.sh` passes.
- `PixelPane/Scripts/verify-debug-build.sh` succeeds.

Status: Done.

### `AGENTV2-024` - Rebuild Agent/UI Boundary Around Typed Runtime Events

Auto-created during manual AGENTV2 QA on 2026-05-28.

Goal: make it impossible for raw provider text or protocol JSON to become user-visible chat content.

Acceptance:

- [x] Replace raw `assistantMessage: String?` runtime output with typed UI events.
- [x] Add a `finalMessage` event that is the only source for assistant prose bubbles.
- [x] Emit approval, tool, block, failure, and completion state as typed runtime events.
- [x] Keep protocol/tool/control payloads out of transcript-visible strings.
- [x] Update the panel to render only typed final/control events from the runtime result.
- [x] Add regression coverage that protocol JSON returned as final text cannot populate an ask-turn answer.

Verification:

- `PixelPane/Scripts/run-agent-kernel-v2-fixture-tests.sh` passes.
- `PixelPane/Scripts/verify-debug-build.sh` succeeds.

Status: Done.

### `AGENTV2-025` - Add Strict Provider Protocol Decoder And Schema-Rich Tool Contracts

Auto-created during manual AGENTV2 QA on 2026-05-28.

Goal: make the provider boundary parse typed protocol output against complete tool schemas rather than weak required-name summaries.

Acceptance:

- [x] Add one strict protocol decoder for all provider text output.
- [x] Expose full argument names, required flags, types, and summaries to text-protocol providers.
- [x] Reject unknown tools and invalid argument names before runtime execution.
- [x] Preserve legitimate non-protocol JSON as user prose when no protocol envelope is present.
- [x] Add fixture coverage for malformed JSON, unknown tool names, and extra/incorrect arguments.

Verification:

- `PixelPane/Scripts/run-agent-kernel-v2-fixture-tests.sh` passes.
- `PixelPane/Scripts/verify-debug-build.sh` succeeds.

Status: Done.

### `AGENTV2-026` - Add Bounded Tool-Argument Repair And Safe Protocol Failure Handling

Auto-created during manual AGENTV2 QA on 2026-05-28.

Goal: recover from common model tool-call shape mistakes without exposing raw protocol payloads.

Acceptance:

- [x] Add explicit bounded repairs for known-safe argument aliases such as `path` to `targetPath` for staged writes.
- [x] Infer safe defaults only when the tool policy allows it, such as `operation: create` for a new staged file proposal.
- [x] Keep unrepaired malformed tool calls blocked with safe user-facing summaries.
- [x] Never display the raw malformed protocol payload in chat, export, or active text.
- [x] Add fixture coverage for the observed `stage_write_proposal` JSON with `path`.

Verification:

- `PixelPane/Scripts/run-agent-kernel-v2-fixture-tests.sh` passes.
- `PixelPane/Scripts/verify-debug-build.sh` succeeds.

Status: Done.

### `AGENTV2-027` - Rebuild Chat Export And Persistence From Typed Ledger Events

Auto-created during manual AGENTV2 QA on 2026-05-28.

Goal: ensure saved chat and export output are projections of typed transcript/control events, not raw active text.

Acceptance:

- [x] Export conversation text from transcript final-message events only.
- [x] Export tool state from typed control events separately.
- [x] Exclude raw provider protocol JSON from active text snapshots.
- [x] Persist ask turns from typed runtime results rather than direct model/provider strings.
- [x] Add fixture or unit coverage for export without protocol leakage.

Verification:

- `PixelPane/Scripts/run-agent-kernel-v2-fixture-tests.sh` passes.
- `PixelPane/Scripts/verify-debug-build.sh` succeeds.

Status: Done.

### `AGENTV2-028` - Re-enable Evidence Planning On The Typed Boundary

Auto-created during manual AGENTV2 QA on 2026-05-28.

Goal: keep model-driven evidence planning, but only after tool calls and final prose travel through the typed runtime boundary.

Acceptance:

- [x] Re-check evidence planning and final-claim passes against the strict decoder.
- [x] Ensure planning tool declarations are never rendered as assistant prose.
- [x] Ensure final-claim verification failures produce safe typed block events.
- [x] Add regression coverage for vague local-state questions and explicit port probes on the typed boundary.

Verification:

- `PixelPane/Scripts/run-agent-kernel-v2-fixture-tests.sh` passes.
- `PixelPane/Scripts/verify-debug-build.sh` succeeds.

Status: Done.

### `AGENTV2-029` - Harden Real-Provider QA Failures For Planning And Model Selection

Auto-created during manual AGENTV2 QA and beta hardening on 2026-05-28.

Goal: fix observed real-provider failures where malformed evidence planning became the visible assistant answer and MLX model changes did not reliably reach the active local runtime.

Acceptance:

- [x] Malformed evidence-planning output is recorded as a control-plane failure and the turn continues through the normal typed tool loop.
- [x] User-visible chat does not show `malformed_evidence_plan` as the answer for ordinary local-context questions.
- [x] MLX text runtime cache invalidates when the selected model changes.
- [x] Successful MLX setup checks refresh the presented panel and switch the active route to Local.
- [x] Local text backend labels distinguish Apple Foundation Models from MLX Text by provider, not just availability.

Verification:

- `PixelPane/Scripts/run-agent-kernel-v2-fixture-tests.sh` passes.
- `PixelPane/Scripts/verify-debug-build.sh` succeeds.

Status: Done.

### `AGENTV2-030` - Document The Agentic Architecture In Plain Language

Auto-created during manual AGENTV2 QA and architecture hardening on 2026-05-28.

Goal: create a simple but complete source-of-truth document explaining the full agentic platform architecture.

Acceptance:

- [x] Review the active workflow, architecture docs, decisions, and Agent Kernel V2 implementation before writing.
- [x] Create `docs/agentic-architecture.txt`.
- [x] Explain the native shell, app context inventory, Agent Kernel V2, typed capabilities, model adapters, ledger, approvals, evidence, persistence, local/cloud routing, settings, privacy, and safety model without code.
- [x] Explain the remaining answerability weakness and why it is a runtime policy problem, not a one-off prompt bug.
- [x] Keep the document understandable, concise, and high signal.

Verification:

- Docs review completed.

Status: Done.

### `AGENTV2-031` - Recover From Incomplete Staged-Write Tool Calls

Auto-created during manual AGENTV2 QA and beta hardening on 2026-05-28.

Goal: prevent incomplete model write tool calls from surfacing as user-visible schema errors when the runtime can safely feed the validation failure back into the agent loop.

Acceptance:

- [x] Preserve known protocol-shaped tool calls with missing required arguments so runtime validation can handle them.
- [x] Record missing or malformed tool arguments as failed control-plane tool results when the failure is recoverable.
- [x] Continue the bounded runtime loop after a recoverable validation failure so the model can retry with complete arguments.
- [x] Keep incomplete staged-write schema errors out of visible assistant prose.
- [x] Add regression coverage for an incomplete `stage_write_proposal` followed by a complete retry that reaches pending write approval.

Verification:

- `PixelPane/Scripts/run-agent-kernel-v2-fixture-tests.sh` passes.
- `PixelPane/Scripts/verify-debug-build.sh` succeeds.

Status: Done.

### `AGENTV2-032` - Add Capability-Aware Answerability Guard

Auto-created during manual AGENTV2 QA and architecture hardening on 2026-05-28.

Goal: stop accepting final answers that defer local evidence or requested file actions when the runtime has available typed capabilities.

Acceptance:

- [x] Detect final answers that defer with phrases like "cannot confirm" or "would you like me to proceed" while typed runtime capabilities are available.
- [x] Record a hidden `answerability_guard` control-plane observation and continue the bounded tool loop instead of showing the deferral as assistant prose.
- [x] Block the turn if the model repeats the same deferral after the guard observation.
- [x] Keep capability awareness based on the offered tool schemas rather than hardcoding a specific localhost port, folder name, or file action.
- [x] Add fixture coverage for deferred localhost status and deferred staged-write/script creation behavior.

Verification:

- `PixelPane/Scripts/run-agent-kernel-v2-fixture-tests.sh` passes.
- `PixelPane/Scripts/verify-debug-build.sh` succeeds.

Status: Done.

### `AGENTV2-033` - Enrich Copy-Chat Debug Export For Agent Traces

Auto-created during `AGENTV2-032` on 2026-05-28.

Goal: make the temporary copy-chat debug export more useful for diagnosing agent behavior without exposing hidden chain-of-thought.

Acceptance:

- [ ] Include observable model request metadata such as route, backend label, request purpose, response format, tool names offered, and output diagnostics when available.
- [ ] Include typed model events with safe summaries: final answer text, tool call name, arguments, and tool-call reason.
- [ ] Include validation outcomes, recoverable failures, answerability-guard interventions, evidence records with metadata, and final-claim declarations in a readable order.
- [ ] Explicitly label this as an observable debug trace, not the model's private hidden reasoning.
- [ ] Keep screenshots, image pixels, file contents, and long terminal output bounded or omitted according to existing privacy/export rules.

Verification:

- Manual copy-chat export review from an agent turn that uses tools.
- `PixelPane/Scripts/verify-debug-build.sh` succeeds if app code changes.

Status: Not Started.

### `AGENTV2-034` - Bound Model-Call Time And Packed Context Memory

Auto-created during manual AGENTV2 QA and beta hardening on 2026-05-28.

Goal: prevent stuck local model calls and stop old tool observations from being repeatedly packed into future model requests.

Acceptance:

- [x] Add a hard per-model-call deadline so stuck provider calls return a typed timeout failure instead of leaving the UI in Thinking indefinitely.
- [x] Use packed model context for runtime calls: recent transcript plus current-turn observations, not every control event from the full chat ledger.
- [x] Keep the full ledger available for history/export/debug while reducing what is sent back to the model.
- [x] Preserve current-turn tool observations so evidence planning, answerability retries, and final-answer verification still work.
- [x] Add fixture coverage for delayed model responses and old observation-memory replay.

Verification:

- `PixelPane/Scripts/run-agent-kernel-v2-fixture-tests.sh` passes.
- `PixelPane/Scripts/verify-debug-build.sh` succeeds.

Status: Done.

### `AGENTV2-035` - Resume Approved Writes Through The Kernel

Auto-created during manual AGENTV2 QA and beta hardening on 2026-05-28.

Goal: prevent approved staged writes from bypassing the runtime loop and leaving the chat stuck in Thinking.

Acceptance:

- [x] Route confirmed file-write approvals through `AgentKernelChatRuntimeV2.resolveApproval` instead of executing writes directly in the UI.
- [x] Execute approved staged writes inside the kernel tool path, record a completed tool result, and record file-write evidence.
- [x] Continue the same agent loop after an approved write so the model can answer, run, or verify follow-up work from current-turn observations.
- [x] Remove the stale loading state when write approval state is missing or canceled.
- [x] Preflight likely script write proposals before approval and feed obvious malformed generated scripts back to the model as recoverable tool observations.
- [x] Add fixture coverage for approved-write resume and script preflight retry behavior.

Verification:

- `PixelPane/Scripts/run-agent-kernel-v2-fixture-tests.sh` passes.
- `PixelPane/Scripts/verify-debug-build.sh` succeeds.

Status: Done.

## Sprint 7 - Deterministic Answerability Preflight

Goal: add a deterministic, runtime-owned preflight traffic controller that classifies obvious local-state questions before the generic model loop, pre-positions safe evidence through existing typed tools, returns typed blocked events for missing scope or unknown targets, and otherwise falls back to existing model-driven evidence planning. This complements the post-answer answerability guard rather than replacing it.

Design rules:

- High precision, low recall: only short-circuit when classification is nearly certain; otherwise fall through to the existing path.
- Reuse the existing evidence-need to tool mapping (`AgentKernelEvidencePlannerV2.toolCall(for:context:)`); add no new tool dispatch.
- Record the preflight route as a control-plane tool-result observation; never as transcript or assistant prose.
- Preserve the evidence planner, answerability guard, final-claim verifier, tool registry, approval flow, and ledger projection.

### `AGENTV2-036` - Introduce Deterministic Answerability Preflight Scaffold

Created from the answerability preflight planning review on 2026-05-28.

Goal: land the behavior-neutral runtime scaffold for the preflight traffic controller before any routing behavior changes.

Acceptance:

- [ ] Add `AgentKernelPreflightPlannerV2` (pure, `Sendable`) that returns `.unclassified` for all inputs, plus an `AgentKernelPreflightRouteV2` enum (`deterministic`, `blocked`, `unclassified`) and an `AgentKernelPreflightIntentV2` enum used for route-trace metadata.
- [ ] Extract the evidence-need execution tail of `planAndCollectEvidence` into a shared `collectEvidence(needs:context:ledger:patch:)` and call it from the existing model-driven planner with no behavior change.
- [ ] Wire a three-way preflight branch into `continueTurn` under the existing `shouldPlanEvidence` gate, before `planAndCollectEvidence`.
- [ ] Record a `preflight_router` control-plane tool-result observation only for non-unclassified routes (none today) and add an export projection that keeps it out of assistant prose.
- [ ] Observable behavior is identical to today: all existing fixture scenarios pass unchanged, including a new "ambiguous task still uses the generic model loop" scenario.

Verification:

- `PixelPane/Scripts/run-agent-kernel-v2-fixture-tests.sh` passes.
- `PixelPane/Scripts/verify-debug-build.sh` succeeds.

Status: Not Started.

### `AGENTV2-037` - Route Obvious Local-Server Questions Through Preflight

Created from the answerability preflight planning review on 2026-05-28.

Goal: deterministically position a localhost probe for obvious local-server questions, and return a typed clarification when the target is unknown.

Acceptance:

- [ ] Classify local-server intent from the user message and ledger; an explicit port, localhost, or loopback URL, or a ledger-recoverable bound port, routes to a `localServerProbe` evidence need.
- [ ] A local-server question with no recoverable target returns a typed `.blocked` event (for example `local_server_target_unknown`) that asks for the port or URL rather than a model hedge.
- [ ] The generic loop still synthesizes the final answer from the probe evidence, and the post-answer answerability guard is not required on the happy path.
- [ ] Non-loopback targets fall through to `.unclassified`.
- [ ] Add fixture coverage for "is my website running on port 8000" routing to `probe_local_server`, and for a no-target localhost question producing a typed blocked clarification (not a "cannot confirm" hedge).

Verification:

- `PixelPane/Scripts/run-agent-kernel-v2-fixture-tests.sh` passes.
- `PixelPane/Scripts/verify-debug-build.sh` succeeds.

Status: Not Started.

### `AGENTV2-038` - Gate File-Visibility Preflight On Grants And Preserve Writes

Created from the answerability preflight planning review on 2026-05-28.

Goal: route obvious file-visibility questions to existing file tools when grants exist, return a typed missing-scope block when they do not, and keep write requests on the staged-approval path.

Acceptance:

- [ ] File read/list/search intent with granted file-read scope routes to the matching `fileRead`, `folderListing`, or `fileSearch` evidence need.
- [ ] The same intent with no granted file-read scope returns a typed `.blocked` event (for example `file_visibility_needs_grant`) instead of a vague answer.
- [ ] Write or mutation intent stays `.unclassified` so the model drafts content and the existing `stage_write_proposal` approval path runs unchanged.
- [ ] Ambiguous file phrasing without a path or grant stays `.unclassified` rather than blocked.
- [ ] Add fixture coverage for no-grant visibility (blocked), with-grant visibility (file tools run), and a write request reaching staged approval.

Verification:

- `PixelPane/Scripts/run-agent-kernel-v2-fixture-tests.sh` passes.
- `PixelPane/Scripts/verify-debug-build.sh` succeeds.

Status: Not Started.

### `AGENTV2-039` - Route Managed-Process Status Through Preflight

Created from the answerability preflight planning review on 2026-05-28.

Goal: deterministically check managed-process status when a managed process is known, without over-blocking when it is not.

Acceptance:

- [ ] Recover the most recent managed process ID from ledger control events; when present, a process-status question routes to a `processStatus` evidence need.
- [ ] When no managed process is known, the question falls through to `.unclassified`.
- [ ] No granted process-control scope falls through to `.unclassified` rather than blocking.
- [ ] Add fixture coverage for a process-status question with a ledger-known managed process routing to `process_status`.

Verification:

- `PixelPane/Scripts/run-agent-kernel-v2-fixture-tests.sh` passes.
- `PixelPane/Scripts/verify-debug-build.sh` succeeds.

Status: Not Started.

## Non-Agent Backlog

### `FOUND-008` - Decide Telemetry Vendor Or Continue Deferring Telemetry

Goal: avoid vague analytics work before beta.

Acceptance:

- [x] Current decision is to defer telemetry.
- [ ] If revisited, event schema excludes screenshots, OCR text, prompts, answers, clipboard contents, and file contents.
- [ ] Telemetry remains opt-in.

Status: Blocked.
