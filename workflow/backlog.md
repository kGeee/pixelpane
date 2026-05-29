# Pixel Pane Backlog

Last updated: 2026-05-29

## Current Product

Pixel Pane is a local-first, notch-native assistant shell for macOS. The shell, capture/OCR path, file grants, settings, backend routing, and approval UX remain valuable. The active agent path is the `AGENTR` durable architecture selected by the architecture revision.

## Status Values

- `Not Started`
- `In Progress`
- `Blocked`
- `In Review`
- `Done`

## Current Recommended Story

None in the tool reliability sprint.

Reason: `TOOLR` is implemented and automated fixtures plus debug build pass. Remaining confidence work is live notch-shell QA with the real local provider and granted folders.

## Current Stories

| ID | Story | Status | Depends On |
|---|---|---|---|
| `ARCHREV-001` | Build the agent failure corpus | Done | User architecture revision request |
| `ARCHREV-002` | Map the current agent architecture end to end | Done | `ARCHREV-001` |
| `ARCHREV-003` | Research comparable agent platforms and extract standard patterns | Done | `ARCHREV-001` |
| `ARCHREV-004` | Audit runtime state, persistence, replay, and resumability | Done | `ARCHREV-002`, `ARCHREV-003` |
| `ARCHREV-005` | Audit model adapter contracts and provider failure handling | Done | `ARCHREV-002`, `ARCHREV-003` |
| `ARCHREV-006` | Audit tool, approval, permission, and side-effect boundaries | Done | `ARCHREV-002`, `ARCHREV-003` |
| `ARCHREV-007` | Audit evidence, observation packing, answerability, and verification | Done | `ARCHREV-002`, `ARCHREV-003` |
| `ARCHREV-008` | Audit UI/runtime integration and stuck-turn recovery | Done | `ARCHREV-002`, `ARCHREV-003` |
| `ARCHREV-009` | Produce remove, modify, add architecture findings | Done | `ARCHREV-004`, `ARCHREV-005`, `ARCHREV-006`, `ARCHREV-007`, `ARCHREV-008` |
| `ARCHREV-010` | Author the next implementation sprint from revision findings | Done | `ARCHREV-009` |
| `DOCREV-001` | Inventory every repository document for stale agent context | Done | `ARCHREV-009` |
| `DOCREV-002` | Delete deprecated documentation instead of preserving it | Done | `DOCREV-001` |
| `DOCREV-003` | Rewrite the focused architecture and workflow docs | Done | `DOCREV-002`, `ARCHREV-010` |
| `DOCREV-004` | Align repo instructions, backend docs, and code-adjacent docs | Done | `DOCREV-003` |
| `AGENTR-001` | Build durable agent run store and event schema | Done | `DOCREV-004`, `ARCHREV-010` |
| `AGENTR-002` | Add checkpointed runner and app-launch recovery | Done | `AGENTR-001` |
| `AGENTR-003` | Build capability-tiered model gateway | Done | `AGENTR-001` |
| `AGENTR-004` | Build permission policy and filtered tool catalog | Done | `AGENTR-001` |
| `AGENTR-005` | Split side-effect drafts, approvals, execution, and rollback | Done | `AGENTR-002`, `AGENTR-004` |
| `AGENTR-006` | Add evidence packets, artifacts, and deterministic local controllers | Done | `AGENTR-002`, `AGENTR-004` |
| `AGENTR-007` | Replace chat UI bridge with durable run projection | Done | `AGENTR-001`, `AGENTR-002` |
| `AGENTR-008` | Replace debug export and chat history with trace projections | Done | `AGENTR-001`, `AGENTR-007` |
| `AGENTR-009` | Remove superseded AGENTV2 runtime paths and wire the new runtime | Done | `AGENTR-003`, `AGENTR-005`, `AGENTR-006`, `AGENTR-007` |
| `AGENTR-010` | Add rearchitecture regression matrix and real-provider QA gates | Done | `AGENTR-009` |
| `TOOLC-001` | Add durable model-tool-result orchestration loop | Done | `AGENTR-010` |
| `TOOLC-002` | Add deterministic local file tool executors | Done | `TOOLC-001` |
| `TOOLC-003` | Wire file-write approvals to exactly-once execution and continuation | Done | `TOOLC-002` |
| `TOOLC-004` | Route notch chat through the tool-capable runtime mode | Done | `TOOLC-003` |
| `TOOLC-005` | Add tool-calling regression fixtures and review architecture | Done | `TOOLC-004` |
| `TOOLR-001` | Build canonical grant-aware path resolution | Done | `TOOLC-005` |
| `TOOLR-002` | Route policy and tool executors through the canonical resolver | Done | `TOOLR-001` |
| `TOOLR-003` | Preserve raw model protocol output before display formatting | Done | `TOOLR-002` |
| `TOOLR-004` | Tighten side-effect failure states and diagnostics | Done | `TOOLR-003` |
| `TOOLR-005` | Add regression coverage for the latest chat failures and review architecture | Done | `TOOLR-004` |
| `FOUND-008` | Decide telemetry vendor or continue deferring telemetry | Blocked | Product decision before beta |

## Historical Sprints

The old `AGENTV2` backlog was removed from active workflow context after the revision sprint. AGENTV2 names are historical audit input only; the active runtime is AGENTR.

## Sprint: `ARCHREV` - Agent Architecture Revision

Goal: revise the full agent architecture, research similar platforms, audit weak spots, and produce the replacement implementation sprint.

Status: Done.

Primary artifact: `workflow/agent-architecture-revision.md`.

## Sprint: `DOCREV` - Documentation Reset After Architecture Revision

Goal: remove stale and deprecated repository documentation, then rewrite only the focused docs needed to build the selected architecture.

Design rules:

- Include all repository documentation, not only `docs/` and `workflow/`.
- Delete obsolete docs over marking them deprecated.
- Keep remaining docs short, current, and directly useful for future agents.
- Do not keep historical architecture narratives unless they are active constraints.

### `DOCREV-001` - Inventory Every Repository Document For Stale Agent Context

Goal: identify every documentation file that can influence future agents.

Acceptance:

- [x] Inventory `docs/`, `workflow/`, root-level instructions, backend README files, script comments that act like docs, and any code-adjacent markdown/text docs.
- [x] Classify each document as keep, rewrite, delete, or generated/reference.
- [x] Flag docs that preserve stale assumptions, outdated implementation descriptions, completed-story noise, or deprecated architecture guidance.
- [x] Update `workflow/status.md` and this story status before finishing.

Verification:

- Docs/workflow review only.

Status: Done.

### `DOCREV-002` - Delete Deprecated Documentation Instead Of Preserving It

Goal: remove stale repository context so future agents do not consume it.

Acceptance:

- [x] Delete documents classified as delete by `DOCREV-001`.
- [x] Remove references to deleted documents from remaining docs and workflow files.
- [x] Do not create archive files unless a durable legal/release reason exists.
- [x] Update `workflow/status.md` and this story status before finishing.

Verification:

- `rg` confirms deleted doc names are not referenced by active docs.

Status: Done.

### `DOCREV-003` - Rewrite The Focused Architecture And Workflow Docs

Goal: replace broad or stale docs with a compact source of truth for the selected architecture.

Acceptance:

- [x] Rewrite the active architecture doc around the post-revision target architecture.
- [x] Rewrite workflow instructions so future agents start from the new implementation sprint, not AGENTV2 cleanup history.
- [x] Keep decisions in `workflow/decisions.md` compact and current.
- [x] Keep backlog/status focused on active and next work, with old completed sprint detail removed if it is no longer useful.
- [x] Update `workflow/status.md` and this story status before finishing.

Verification:

- Docs/workflow review only.

Status: Done.

### `DOCREV-004` - Align Repo Instructions, Backend Docs, And Code-Adjacent Docs

Goal: make every remaining doc agree with the selected architecture and product constraints.

Acceptance:

- [x] Update or delete backend, release, product, script, and code-adjacent docs that conflict with the architecture.
- [x] Ensure build, test, privacy, file-grant, local/cloud, and approval guidance is current.
- [x] Confirm future agents can read only the primary workflow docs and understand the active path.
- [x] Update `workflow/status.md` and this story status before finishing.

Verification:

- `rg` for stale architecture terms and deleted doc names returns no active conflicting guidance.

Status: Done.

## Sprint: `AGENTR` - Agent Runtime Rearchitecture Implementation

Goal: implement the selected post-revision architecture without preserving old AGENTV2 code that conflicts with reliability, durability, or context quality.

Design rules:

- Use `workflow/agent-architecture-revision.md` as the source of truth.
- Prefer a clean replacement over another patch layer when AGENTV2 structure conflicts with durable runs, provider tiers, policy-owned side effects, evidence packets, or UI projection.
- Keep the notch UI shell, local/cloud routing settings, local file grants, capture/OCR context, and product constraints unless a ticket explicitly replaces their integration boundary.
- Fixture tests come before real-provider confidence.
- Every implementation ticket must leave the repo in a buildable or explicitly isolated state.

### `AGENTR-001` - Build Durable Agent Run Store And Event Schema

Goal: create the durable local store that replaces transcript-only continuity for agent runs.

Focused research applied:

- LangGraph persistence/checkpoints and ADK sessions support separating thread/session state from run/step state.
- `ARCHREV-004` requires durable sessions, runs, steps, waits, artifacts, and relaunch recovery state.

Acceptance:

- [x] Add an Application Support backed `AgentRunStore` using SQLite metadata plus filesystem artifact blobs, or document and implement an equally durable local alternative.
- [x] Define records for sessions, runs, steps, events, waits, artifacts, evidence, side effects, and schema version/migrations.
- [x] Add append-only event APIs with stable `sessionID`, `runID`, `stepID`, `waitID`, `sideEffectID`, and sequence numbers.
- [x] Add projections for visible chat turns, active run status, pending waits, latest progress, evidence/artifact summaries, and trace export input.
- [x] Keep `ChatHistoryStore` as a legacy UI fallback only until `AGENTR-008` replaces it.
- [x] Add fixture tests for append, projection, reload, schema migration, artifact write/read, and interrupted active run detection.

Suggested Files:

- `PixelPane/PixelPane/AgentRuntime/`
- `PixelPane/PixelPane/App/`
- `PixelPane/Scripts/`

Verification:

- `PixelPane/Scripts/run-agent-run-store-fixture-tests.sh`
- `PixelPane/Scripts/verify-debug-build.sh`

Status: Done.

### `AGENTR-002` - Add Checkpointed Runner And App-Launch Recovery

Goal: replace the single in-memory agent loop with a small step runner that checkpoints every meaningful transition.

Focused research applied:

- LangGraph durable execution and LlamaIndex workflow events point to step-level checkpoints and interrupt/resume.
- `ARCHREV-004` and `ARCHREV-008` require explicit recovery for waiting, interrupted, completed, blocked, failed, and canceled runs.

Acceptance:

- [x] Add an `AgentRunner` that executes typed steps from the durable store instead of mutating only an in-memory ledger.
- [x] Define run statuses: draft, queued, running, waitingForApproval, waitingForUserInput, interrupted, completed, blocked, failed, canceled.
- [x] Checkpoint before and after route, model request, model response, tool request, tool result, wait creation, wait resolution, side-effect start, side-effect completion, validation, and terminal events.
- [x] Add watchdog/deadline handling that marks long model/tool steps interrupted with retry/cancel options.
- [x] Add app-launch recovery that restores pending waits and marks unsafe in-flight steps interrupted.
- [x] Add fixture tests for cancellation, timeout, relaunch during model call, relaunch during approval wait, and duplicate resume prevention.

Suggested Files:

- `PixelPane/PixelPane/AgentRuntime/`
- `PixelPane/PixelPane/App/AppState.swift`

Verification:

- `PixelPane/Scripts/run-agent-runner-fixture-tests.sh`
- `PixelPane/Scripts/run-agent-run-store-fixture-tests.sh`
- `PixelPane/Scripts/verify-debug-build.sh`

Status: Done.

### `AGENTR-003` - Build Capability-Tiered Model Gateway

Goal: replace the one-size-fits-all `AIBackend` bridge for agent work with provider adapters that expose honest capability tiers and typed failures.

Focused research applied:

- OpenAI Agents SDK and AutoGen model/tool boundaries depend on typed tool calls or strict structured outputs.
- `ARCHREV-005` requires full agent mode only for native/strict providers; best-effort text protocol is constrained.

Acceptance:

- [x] Add `AgentModelGateway` with provider tiers: Tier A full agent, Tier B constrained structured text, Tier C plain chat/synthesis.
- [x] Add typed provider failure taxonomy: unavailable, auth, rate-limited, context-too-large, timeout, canceled, empty-output, structured-output-invalid, tool-call-invalid, transport-error, provider-refusal, unknown.
- [x] Add deadline and cancellation metadata to every agent model request.
- [x] Add provider conformance fixtures for malformed output, empty output, timeout, cancellation, context overflow, unsupported tool mode, and repair-disabled behavior.
- [x] Keep legacy `AIBackend` for non-agent actions and constrained compatibility only.
- [x] Add or stub native/strict structured adapter boundaries for Pixel Pane Cloud and OpenAI-compatible routes before exposing Tier A tool loops.

Suggested Files:

- `PixelPane/PixelPane/AgentRuntime/`
- `PixelPane/PixelPane/AgentKernel/AgentKernelModelAdapterV2.swift`
- `PixelPane/PixelPane/Actions/`
- `PixelPane/PixelPane/API/`

Verification:

- 2026-05-29, `PixelPane/Scripts/run-agent-model-gateway-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/verify-debug-build.sh` succeeded.

Status: Done.

### `AGENTR-004` - Build Permission Policy And Filtered Tool Catalog

Goal: create the app-owned allow/ask/deny policy layer and expose only appropriate tools by run mode and provider tier.

Focused research applied:

- Claude Code settings/MCP docs show explicit allow/ask/deny permission rules and scoped tool access.
- `ARCHREV-006` requires policy-owned permissions and tool visibility filtering.

Acceptance:

- [x] Add `AgentPermissionPolicy` with allow, ask, deny decisions and typed reasons.
- [x] Add policy inputs for run mode, provider tier, local grants, tool spec, arguments, sensitive path rules, command class, network/process/write scopes, and user approvals.
- [x] Add default sensitive-file deny rules for `.env`, private keys, SSH keys, cloud credentials, signing keys, keychains, package-manager auth files, and hidden credential stores.
- [x] Add a deterministic safe-command allowlist; raw shell outside the allowlist must ask or deny.
- [x] Filter model-visible tool schemas by provider tier and run mode.
- [x] Add policy fixture tests for file read/search/write, raw shell, installs, network commands, process control, local server discovery, sensitive paths, and denied scopes.

Suggested Files:

- `PixelPane/PixelPane/AgentRuntime/`
- `PixelPane/PixelPane/AgentRuntime/AgentPermissionPolicy.swift`
- `PixelPane/PixelPane/AgentRuntime/`
- `PixelPane/PixelPane/App/LocalFileAccess.swift`

Verification:

- 2026-05-29, `PixelPane/Scripts/run-agent-permission-policy-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-model-gateway-fixture-tests.sh` passed after shared fixture-support update.
- 2026-05-29, `PixelPane/Scripts/run-agent-run-store-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-runner-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/verify-debug-build.sh` succeeded.

Status: Done.

### `AGENTR-005` - Split Side-Effect Drafts, Approvals, Execution, And Rollback

Goal: make local writes, terminal commands, and process actions app-owned, durable, and exactly-once.

Focused research applied:

- LangGraph human-in-loop interrupts and Windsurf/Cursor checkpoint behavior support durable waits and reversible write checkpoints.
- `ARCHREV-006` requires immutable approval artifacts and side-effect IDs.

Acceptance:

- [x] Split model-facing side-effect drafts from app-owned execution steps.
- [x] Add immutable approval artifacts for file changes, commands, process starts, and process stops.
- [x] Add durable waits for approvals with stable `waitID` and resume payloads.
- [x] Add side-effect records with `sideEffectID`, proposal hash, before snapshot/hash, after snapshot/hash, status, started/completed timestamps, and error details.
- [x] Add file write validation before approval, including cheap syntax/artifact checks for scripts where practical.
- [x] Add rollback/revert support for created/replaced/appended files and managed process starts where practical.
- [x] Add fixture tests for approve, deny, app relaunch while waiting, duplicate approval, failed write, rollback, command approval, process start/stop, and post-effect verification.

Suggested Files:

- `PixelPane/PixelPane/AgentRuntime/`
- `PixelPane/PixelPane/App/LocalFileAccess.swift`
- `PixelPane/PixelPane/AgentRuntime/AgentSideEffectController.swift`

Verification:

- 2026-05-29, `PixelPane/Scripts/run-agent-side-effect-controller-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-run-store-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-runner-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-permission-policy-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-model-gateway-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/verify-debug-build.sh` succeeded.

Status: Done.

### `AGENTR-006` - Add Evidence Packets, Artifacts, And Deterministic Local Controllers

Goal: make local-state answers reliable by giving the model and verifier structured evidence rather than lossy summaries.

Focused research applied:

- Cursor dynamic context discovery supports artifact-backed context instead of stuffing all tool output into prompts.
- `ARCHREV-007` requires evidence packets and deterministic local-state controllers.

Acceptance:

- [x] Add `EvidencePacket` and artifact records for file grants, folder lists, file search, file reads, command output, localhost discovery, process state, visual context, approvals, writes, and terminal states.
- [x] Ensure every local-state tool result creates evidence or an artifact reference.
- [x] Add deterministic controllers for file visibility/search, localhost/site/port status, command/write/process status, cancellation, and completion.
- [x] Replace blocking model final-claim verification with deterministic support checks and advisory model verification only where useful.
- [x] Add final answer support records linking visible answers to evidence IDs.
- [x] Add fixture tests for FC-001, FC-002, FC-007, FC-010, and stale-context avoidance.

Suggested Files:

- `PixelPane/PixelPane/AgentRuntime/`
- `PixelPane/PixelPane/AgentRuntime/AgentEvidencePackets.swift`
- `PixelPane/PixelPane/AgentRuntime/`

Verification:

- 2026-05-29, `PixelPane/Scripts/run-agent-evidence-packets-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-side-effect-controller-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-run-store-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-runner-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-permission-policy-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-model-gateway-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/verify-debug-build.sh` succeeded.

Status: Done.

### `AGENTR-007` - Replace Chat UI Bridge With Durable Run Projection

Goal: make `ResultPanelView` render agent runs instead of owning agent execution state.

Focused research applied:

- ADK runtime/event loop and OpenAI tracing patterns support UI projection from runtime events.
- `ARCHREV-008` requires typed run projection and explicit stuck-turn states.

Acceptance:

- [x] Add an `AgentRunViewModel` or equivalent projection layer that observes `AgentRunStore`.
- [x] Replace direct `runTurn`/`resolveApproval` calls in `ResultPanelView` with intents: start run, cancel run, approve wait, deny wait, retry interrupted step, load session.
- [x] Render explicit run statuses instead of inferring thinking from empty answer text.
- [x] Render typed approval/proposal cards for file changes, commands, and process actions.
- [x] Add UI recovery controls for interrupted runs and restored pending waits.
- [x] Keep the notch UI shell and existing chat ergonomics while moving state ownership out of the view.

Suggested Files:

- `PixelPane/PixelPane/Panel/ResultPanelView.swift`
- `PixelPane/PixelPane/Panel/`
- `PixelPane/PixelPane/AgentRuntime/`

Verification:

- Focused UI/unit tests where available.
- Manual smoke test for send, cancel, pending approval, approval resume, and reload.
- Debug build still succeeds.

Status: Done.

### `AGENTR-008` - Replace Debug Export And Chat History With Trace Projections

Goal: make chat history and copy/export read from durable run events instead of reconstructing from UI state.

Focused research applied:

- OpenAI tracing and Cursor artifact patterns support durable trace export with redaction.
- `ARCHREV-004` and `ARCHREV-008` require chat history as projection and deletion of temporary debug export.

Acceptance:

- [x] Replace `ChatHistoryStore` agent continuity with projections from `AgentRunStore`.
- [x] Add production-safe trace export with session/run IDs, ordered events, evidence IDs, artifacts, provider diagnostics, and redaction.
- [x] Delete the temporary AGENTV2 debug export path after trace export covers the useful diagnostics.
- [x] Add migration or compatibility behavior for old saved chat turns where needed.
- [x] Add tests for chat projection, reload, export redaction, and missing artifact handling.

Suggested Files:

- `PixelPane/PixelPane/App/ChatHistoryStore.swift`
- `PixelPane/PixelPane/Panel/ResultPanelView.swift`
- `PixelPane/PixelPane/AgentRuntime/`

Verification:

- Projection/export tests pass.
- Temporary debug-export marker search returns no production source references.
- Debug build still succeeds.

Status: Done.

### `AGENTR-009` - Remove Superseded AGENTV2 Runtime Paths And Wire The New Runtime

Goal: finish the replacement by deleting incompatible AGENTV2 runtime paths and routing the app through the new architecture.

Focused research applied:

- `ARCHREV-009` says this is a rearchitecture, not another AGENTV2 patch layer.
- All previous AGENTR tickets define the replacement boundaries needed before deletion.

Acceptance:

- [x] Route assistant send/cancel/approve/retry/load/export through the new runtime/store/projection stack.
- [x] Delete or shrink superseded AGENTV2 files that conflict with the new ownership model.
- [x] Keep reusable data types only if they now live under the correct store/runner/policy/tool/evidence boundary.
- [x] Remove stale text-protocol full-agent paths from normal execution.
- [x] Confirm no active code path relies on transcript-only runtime state or UI-owned approval state.
- [x] Update workflow/status/backlog to make `AGENTR-010` current.

Suggested Files:

- `PixelPane/PixelPane/AgentKernel/`
- `PixelPane/PixelPane/AgentRuntime/`
- `PixelPane/PixelPane/Panel/ResultPanelView.swift`

Verification:

- 2026-05-29, `PixelPane/Scripts/verify-debug-build.sh` succeeded.
- 2026-05-29, all AGENTR fixture scripts passed after deletion of the superseded AGENTV2 runtime.
- Manual smoke test is deferred to `AGENTR-010` real-provider QA.

Status: Done.

### `AGENTR-010` - Add Rearchitecture Regression Matrix And Real-Provider QA Gates

Goal: prove the new architecture fixes the captured failures before calling the rearchitecture complete.

Focused research applied:

- Mature agent runtimes rely on traces, conformance tests, and provider capability gates instead of trusting one happy path.
- The failure corpus FC-001 through FC-012 is the acceptance baseline.

Acceptance:

- [x] Add fixtures for FC-001 through FC-012.
- [x] Add provider-tier conformance tests for Tier A, Tier B, and Tier C behavior.
- [x] Add store recovery tests for app relaunch during model call, tool call, approval wait, side-effect execution, and managed process ownership.
- [x] Add UI/manual QA checklist for notch progress, pending approvals, cancel/retry, reload, copy trace, and no indefinite thinking.
- [x] Run the app build and all available agent fixture scripts.
- [x] Update workflow status/backlog and decisions if any architecture change is needed after verification.

Suggested Files:

- `PixelPane/Scripts/`
- `PixelPane/PixelPaneTests/` if available
- `workflow/`

Verification:

- 2026-05-29, `PixelPane/Scripts/run-agent-run-store-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-runner-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-model-gateway-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-permission-policy-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-side-effect-controller-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-evidence-packets-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-run-view-model-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-trace-export-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-rearchitecture-regression-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/verify-debug-build.sh` succeeded.
- Manual real-provider and notch-shell QA checklist recorded in `workflow/qa-checklist.md` as beta gates.

Status: Done.

## Sprint: `TOOLC` - Durable Tool Calling Integration

Goal: make the live AGENTR path execute model tool calls through app-owned local tools, evidence, approvals, and continuation instead of returning plain-chat refusals or shell suggestions.

Research applied:

- OpenAI and Anthropic tool APIs use a repeated loop: expose tool schemas, receive a tool call, execute application code, return tool results, and continue until a final answer.
- LangGraph durable execution and human-in-the-loop patterns require checkpointing tool effects and resuming after approval rather than running side effects from UI state.

Design rules:

- Do not revive AGENTV2 tool state or transcript-driven execution.
- Tool calls are control-plane events; only final user-facing answers become assistant messages.
- Read-only local tools may execute deterministically when grants and policy allow them.
- Writes must be staged, approved, executed exactly once, recorded as evidence, then continued.
- Provider tier decides whether the run uses Tier A full agent, Tier B constrained structured text, or Tier C plain chat.

### `TOOLC-001` - Add Durable Model-Tool-Result Orchestration Loop

Goal: replace the current one-shot model request with a bounded loop that can process tool calls and continue.

Acceptance:

- [x] Add a runtime orchestrator that calls `AgentModelGateway`, handles `toolCall` events, appends tool request/result steps, and repeats with tool-result context.
- [x] Enforce max iteration, timeout, cancellation, malformed-output, unsupported-tool, and no-final-answer terminal paths.
- [x] Keep visible chat projection limited to user messages and final assistant answers.
- [x] Add progress and trace events for model requests, tool requests, tool results, failures, and terminal status.

Verification:

- 2026-05-29, `PixelPane/Scripts/run-agent-tool-calling-fixture-tests.sh` passed.

Status: Done.

### `TOOLC-002` - Add Deterministic Local File Tool Executors

Goal: implement the local read tools exposed by `AgentToolCatalog`.

Acceptance:

- [x] Execute `list_grants`, `list_folder`, `search_files`, and `read_file` from app code.
- [x] Convert `LocalFileGrant` records into AGENTR policy grants for read-only execution.
- [x] Enforce grant boundaries, sensitive path denies, bounded file sizes, skipped folders, and text-only reads.
- [x] Record evidence/artifacts for every read tool result.

Verification:

- 2026-05-29, `PixelPane/Scripts/run-agent-tool-calling-fixture-tests.sh` passed.

Status: Done.

### `TOOLC-003` - Wire File-Write Approvals To Exactly-Once Execution And Continuation

Goal: make `stage_write_proposal` usable from live agent runs.

Acceptance:

- [x] Convert model `stage_write_proposal` tool calls into `AgentSideEffectController.stage` proposals.
- [x] Expose pending approvals through existing projection cards.
- [x] On approval, call `AgentSideEffectController.executeApproved` exactly once and record side-effect evidence.
- [x] Continue the run after approval with a tool-result context packet.
- [x] Denial blocks or continues with a denied tool result without writing.

Verification:

- 2026-05-29, `PixelPane/Scripts/run-agent-tool-calling-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-side-effect-controller-fixture-tests.sh` passed.

Status: Done.

### `TOOLC-004` - Route Notch Chat Through The Tool-Capable Runtime Mode

Goal: make normal assistant messages choose a tool-capable mode when the provider and grants support it.

Acceptance:

- [x] Select provider tier from `AgentModelGateway`.
- [x] Build visible tool schemas from `AgentToolCatalog` using run mode, provider tier, local grants, and scopes.
- [x] Use constrained structured text for Tier B read/proposal tasks and full agent for Tier A where available.
- [x] Fall back to plain chat for Tier C or no-tool contexts with clear capability messaging.
- [x] Preserve capture/OCR and image context behavior.

Verification:

- 2026-05-29, `PixelPane/Scripts/run-agent-tool-calling-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/verify-debug-build.sh` succeeded.

Status: Done.

### `TOOLC-005` - Add Tool-Calling Regression Fixtures And Review Architecture

Goal: prove the missing tool-call path is fixed and the implementation matches AGENTR decisions.

Acceptance:

- [x] Add regression fixtures for listing granted folder contents, answering from a website repo, writing a short story to a granted folder, and approval resume.
- [x] Verify no raw protocol JSON, shell suggestions, or model refusals are accepted when an app tool can satisfy the request.
- [x] Run all agent fixture scripts and debug build.
- [x] Update workflow status/backlog/decisions and QA checklist.

Verification:

- 2026-05-29, `PixelPane/Scripts/run-agent-run-store-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-runner-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-model-gateway-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-permission-policy-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-side-effect-controller-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-evidence-packets-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-run-view-model-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-trace-export-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-rearchitecture-regression-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-tool-calling-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/verify-debug-build.sh` succeeded.

Status: Done.

## Sprint: `TOOLR` - Tool Reliability Hardening

Goal: fix the live tool-call failures from `docs/example-chats` without weakening the AGENTR architecture.

Failure evidence:

- Tool calls and approvals are working, but relative write targets such as `random-tests/short_story.txt` resolve under the broad `pixel-pane` grant instead of the explicit `random-tests` grant.
- MLX/text-protocol responses are display-normalized before control-plane parsing, corrupting escaped newlines into literal ` n` content.
- Failed side effects are reported too optimistically and can still end as completed runs with only an explanatory final answer.

Design rules:

- Resolve local paths through one canonical runtime component shared by policy and execution.
- Prefer explicit grant names and preferred granted directories before broad folder fallbacks.
- Validate write parents before user approval so approval cards do not propose impossible writes.
- Keep model protocol output raw until it is parsed into typed events; display formatting belongs only on user-visible prose.
- Failed approved side effects must produce clear failed/blocked durable state and trace diagnostics.

### `TOOLR-001` - Build Canonical Grant-Aware Path Resolution

Goal: create a single runtime resolver for local file grants.

Acceptance:

- [x] Add a resolver that returns the resolved URL, matched grant, and failure reason.
- [x] Support absolute paths, exact grant-name paths, preferred directory paths, file grants, and broad fallback paths in deterministic priority order.
- [x] Prefer `/Users/nayak/Documents/random-tests/short_story.txt` over `/Users/nayak/Documents/pixel-pane/random-tests/short_story.txt` when `random-tests` is an explicit grant.
- [x] Reject ambiguous or ungranted paths instead of silently choosing the first broad grant.

Verification:

- 2026-05-29, `PixelPane/Scripts/run-agent-permission-policy-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-tool-calling-fixture-tests.sh` passed.

Status: Done.

### `TOOLR-002` - Route Policy And Tool Executors Through The Canonical Resolver

Goal: remove duplicate path resolution behavior between permission checks and execution.

Acceptance:

- [x] `AgentPermissionPolicy` uses the canonical resolver for file read/list/write decisions.
- [x] `AgentLocalToolExecutor` uses the same resolver for `list_folder`, `read_file`, and `stage_write_proposal`.
- [x] Write proposals validate the parent directory before creating an approval wait.
- [x] Trace/progress messages report the real resolved target and policy failure reason.

Verification:

- 2026-05-29, `PixelPane/Scripts/run-agent-permission-policy-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-tool-calling-fixture-tests.sh` passed.

Status: Done.

### `TOOLR-003` - Preserve Raw Model Protocol Output Before Display Formatting

Goal: prevent display normalization from corrupting structured tool protocol output.

Acceptance:

- [x] Agent protocol parsing receives raw provider text, not `ModelOutputFormatter` display text.
- [x] Existing user-visible plain chat formatting is preserved.
- [x] Text-protocol tool calls containing escaped newlines parse into content with real newline characters.
- [x] The fix covers MLX one-shot and MLX server paths used by the AI backend bridge.

Verification:

- 2026-05-29, `PixelPane/Scripts/run-agent-model-gateway-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/verify-debug-build.sh` succeeded.

Status: Done.

### `TOOLR-004` - Tighten Side-Effect Failure States And Diagnostics

Goal: make approved side-effect failures explicit and non-misleading.

Acceptance:

- [x] Approval continuation reports failed side-effect status when execution fails.
- [x] Failed approved writes do not emit success progress text.
- [x] Runs with failed approved writes end as failed or blocked unless a later tool successfully satisfies the original action.
- [x] Trace export includes side-effect error summaries for failed side effects.

Verification:

- 2026-05-29, `PixelPane/Scripts/run-agent-tool-calling-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-trace-export-fixture-tests.sh` passed.

Status: Done.

### `TOOLR-005` - Add Regression Coverage For The Latest Chat Failures And Review Architecture

Goal: prove the live `docs/example-chats` failure shapes are fixed.

Acceptance:

- [x] Add fixtures for broad-plus-specific grants resolving `random-tests`.
- [x] Add fixtures for text-protocol newline content.
- [x] Add fixtures for nonexistent parent rejection before approval.
- [x] Add fixtures for failed side-effect state projection and trace diagnostics.
- [x] Run all affected agent fixtures and the debug build.
- [x] Update workflow status, QA checklist, and architecture notes.

Verification:

- 2026-05-29, `PixelPane/Scripts/run-agent-run-store-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-runner-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-model-gateway-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-permission-policy-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-side-effect-controller-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-evidence-packets-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-run-view-model-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-trace-export-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-rearchitecture-regression-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/run-agent-tool-calling-fixture-tests.sh` passed.
- 2026-05-29, `PixelPane/Scripts/verify-debug-build.sh` succeeded.

Status: Done.

## Non-Agent Backlog

### `FOUND-008` - Decide Telemetry Vendor Or Continue Deferring Telemetry

Goal: avoid vague analytics work before beta.

Acceptance:

- [x] Current decision is to defer telemetry.
- [ ] If revisited, event schema excludes screenshots, OCR text, prompts, answers, clipboard contents, and file contents.
- [ ] Telemetry remains opt-in.

Status: Blocked.
