# AgentRuntime

Stateful, durable agent execution engine. Handles multi-turn model requests, local tool calls, user approval gates, evidence collection, permission policy, and persistent storage. This is the largest and most complex subsystem.

## Conceptual model

```
AgentRuntime  (top-level, holds config + active run registry)
    └── AgentRunner  (one per run; drives the step loop)
            ├── AgentModelRouter      → picks which model to use
            ├── AgentToolOrchestrator → tool-call loop + approval waits
            │       ├── AgentPermissionPolicy   → allow / ask / deny
            │       ├── AgentLocalToolExecutor  → executes approved tools
            │       ├── AgentEvidenceRecorder   → persists evidence
            │       └── AgentSideEffectController → file writes, processes
            └── AgentRunStore  (SQLite, durable across restarts)
```

## Files

| File | Purpose |
|---|---|
| `AgentRuntime.swift` | Top-level orchestrator. Creates runners, manages active run registry, exposes the public API consumed by `AppState`. |
| `AgentRunner.swift` | Executes one agent run: route → model request → tool loop → repeat until done or cancelled. Enforces step timeouts. |
| `AgentRunStore.swift` | Actor-isolated main store. Manages sessions, runs, steps, evidence, side effects, and artifacts. All mutations go through here. |
| `AgentRunStorePersistence.swift` | SQLite schema and migration logic backing `AgentRunStore`. |
| `AgentRunTypes.swift` | Core value types: run status, step kinds, message roles, artifact types, approval/wait records. |
| `AgentRunViewModel.swift` | `ObservableObject` projecting live run state for SwiftUI. The panel reads this. |
| `AgentModelRouter.swift` | Pure routing policy. Given the task frame and user preferences, selects a single `(providerKind, model)` pair for the run. No I/O. |
| `AgentModelGateway.swift` | Probes a model for tool-call capability and output-format conformance before the first run. Results are cached. |
| `AgentToolOrchestrator.swift` | Actor driving the inner tool-calling loop: sends model requests, parses tool calls, gates on permissions, executes, backfills evidence, repeats. |
| `AgentToolCatalog.swift` | Authoritative list of every tool: name, description, parameter schema, risk level, and which permission modes allow it. |
| `AgentToolContracts.swift` | Typed parameter definitions and path-role annotations for each tool. Used by the executor and evidence planner. |
| `AgentToolLoopController.swift` | Pure loop-control logic: repeated-call detection, max-iteration cap, no-progress detection. No I/O. |
| `AgentPermissionPolicy.swift` | Decides `allow / ask / deny` for each tool invocation based on the operation kind, path sensitivity, user grants, and the run's permission mode. |
| `AgentPermissionTypes.swift` | Permission modes (`plainChat`, `readOnly`, `proposalOnly`, `fullAgent`), operation kinds, scopes, and decision types. |
| `AgentLocalToolExecutor.swift` | Executes approved tool calls: file reads, directory listings, file writes (via side-effect controller), and shell commands. Returns bounded output. |
| `AgentSideEffectController.swift` | Manages file-write and process-start side effects through a proposal → approval → execute → rollback lifecycle. |
| `AgentEvidencePackets.swift` | All evidence kinds (`fileGrant`, `fileRead`, `folderList`, `commandOutput`, `processSnapshot`, …) and the requirement types they satisfy. |
| `AgentEvidenceRecorder.swift` | Actor that deduplicates (SHA-256) and persists evidence to the run store. |
| `AgentEvidenceController.swift` | Verifies whether collected evidence actually supports the claims in a proposed final answer before the agent is allowed to respond. |
| `AgentFinalAnswerSupportRecorder.swift` | Records which claims are backed by evidence; consulted by `AgentEvidenceController`. |
| `AgentLocalEvidencePlanner.swift` | Plans preflight evidence requirements based on task entities (paths, processes) before the model's first turn. |
| `AgentLocalPathResolver.swift` | Resolves and validates file/folder paths: checks grants, physical existence, write targets, and produces failure reasons with candidate suggestions. |
| `AgentRunTaskClassification.swift` | Classifies a task into kinds (`plainChat`, `temporalQuery`, `fileRead`, `fileWrite`, …) and resolves relative temporal references. |
| `AgentRunTraceExport.swift` | Exports a complete agent run as a human-readable Markdown document (messages, tool calls, evidence, decisions). |
| `AgentRunMetadataAccess.swift` | Typed accessors (`string`, `int`, `bool`) for the metadata dictionaries attached to run steps and evidence records. |
| `AgentTaskFrame.swift` | App-supplied context for a run: active file grants, write targets, reference text, and the user's question. |

## Adding a new tool

1. **Catalog entry** — add a `AgentToolSpec` to `AgentToolCatalog`. Set the name, description, parameter schema, `OperationKind`, and `RiskLevel`. Mark which `PermissionMode`s allow it.
2. **Contract** — add a typed parameter struct to `AgentToolContracts` if the tool takes structured arguments.
3. **Executor case** — add a `case` in `AgentLocalToolExecutor.execute(tool:)`. Return an `AgentToolResult` with bounded output.
4. **Evidence** (optional) — if the tool produces verifiable output, add an `AgentEvidencePacket` kind and emit it from the executor.

## Permission modes

| Mode | What the agent can do |
|---|---|
| `plainChat` | Text answers only; no tool calls |
| `readOnly` | File reads and directory listings |
| `proposalOnly` | Proposes writes/commands; user must approve each |
| `fullAgent` | Executes approved operations autonomously |

The active mode is set in `AppState` and passed to each run via `AgentTaskFrame`.
