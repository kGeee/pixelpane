# Pixel Pane Decision Register

Last updated: 2026-05-29

This file records durable product and architecture decisions only. It is not a changelog.

## Product And Platform

### Direct Distribution

Status: Accepted

Pixel Pane targets direct macOS distribution with Developer ID signing, notarization, DMG packaging, and Sparkle updates.

Consequences:

- Keep app sandbox disabled unless a future distribution decision changes this.
- Keep hardened runtime enabled.
- Release operations must preserve signing and privacy constraints.

### macOS And Shell

Status: Accepted

Pixel Pane targets macOS 15.2+ and remains menu-bar/notch-first with `LSUIElement`.

Consequences:

- Preserve the native notch chat shell, capture/OCR foundation, settings, routing controls, and file grant UI.
- Do not broaden into browser automation, global app control, backend/auth/monetization, or expansion features unless a story explicitly says so.

### Local-First AI

Status: Accepted

Local Mode is the default. Cloud Mode is explicit opt-in and routes through the Pixel Pane backend proxy. Provider keys never ship in the macOS app.

Consequences:

- The backend is a model route, not the authority for local files, permissions, terminal execution, write approvals, or trace state.
- Screenshots, OCR text, prompts, answers, filenames, file contents, and model outputs are not logged by default.

### Local Context Safety

Status: Accepted

Local files require explicit user grants. Screenshots and attached image pixels remain transient unless a future explicit export feature says otherwise. Writes, raw shell commands, installs, network commands, privileged commands, and process-control actions require app-owned approval unless a narrow deterministic allow rule applies.

Consequences:

- Product policy belongs in app/runtime code, not hidden prompts.
- Terminal output, file content, OCR text, and image-derived text are untrusted input.

## Agent Architecture

### Full Architecture Revision

Status: Accepted

AGENTV2 hardening is paused. The selected path is the `AGENTR` durable agent runtime rearchitecture.

Consequences:

- AGENTV2 is code under audit, not the target architecture.
- Current AGENTV2 code may be deleted or replaced when it conflicts with `AGENTR`.
- Stale docs should be deleted instead of preserved.

### Durable Runs Are Source Of Truth

Status: Accepted

Agent execution will be stored as durable sessions, runs, steps, waits, events, evidence, side effects, and artifacts. Visible chat history is a projection.

Consequences:

- `UserDefaults` transcript persistence is not enough for agent continuity.
- Runtime events must be checkpointed before and after model calls, tool calls, approval waits, approval resolutions, side effects, validation, and terminal events.
- App relaunch recovery must explicitly handle waiting, interrupted, completed, blocked, failed, and canceled runs.
- The implementation should use an Application Support backed store, preferably SQLite plus artifact files.

### Provider Capability Tiers

Status: Accepted

Agent behavior is gated by provider capability tier.

- Tier A: native tool calls or strict structured output; full agent.
- Tier B: constrained structured text; low-risk read/proposal workflows after fixture proof.
- Tier C: plain chat/synthesis only.

Consequences:

- Best-effort text protocol is compatibility, not the default full-agent control plane.
- Plain chat providers cannot control tools, approvals, side effects, or final verification.
- Provider failures must be typed.

### Gateway Normalizes Provider Protocol Output

Status: Accepted

`AgentModelGateway` owns protocol normalization before validation and UI projection. Provider responses that contain strict JSON/tool protocol text must become typed events or typed failures before any assistant prose is projected.

Consequences:

- Raw protocol JSON must not leak into visible assistant messages.
- Malformed structured output is a provider/runtime failure, not normal chat content.
- Provider conformance tests must cover native tools, structured text, plain chat, malformed output, and unsupported tool mode.

### Durable Tool Orchestration

Status: Accepted

Model tool calls must run through AGENTR's app-owned orchestration loop. The loop exposes filtered tool schemas, receives typed tool calls, executes deterministic app tools, records evidence or approval waits, returns observations to the model, and repeats until final answer or terminal failure.

Consequences:

- Tool calls, tool results, approvals, side effects, and evidence remain control-plane records.
- The notch chat may use Tier A full-agent mode or Tier B constrained structured text when provider and policy allow tools.
- Tier C and no-tool contexts remain plain chat.
- UI approval actions must execute approved side effects exactly once and resume or complete the durable run.

### Canonical Local Path Resolution

Status: Accepted

Local file tools and permission policy share one canonical resolver for granted file paths.

Consequences:

- Explicit grant-name references and preferred granted directories take priority over broad folder fallbacks.
- Ambiguous relative paths are rejected instead of silently choosing the first broad grant.
- Write proposals validate their parent directory before creating approval waits.
- Policy and execution must not grow separate path-resolution logic.

### Raw Protocol Before Display Formatting

Status: Accepted

Model output used for tool protocol parsing remains raw until `AgentModelGateway` normalizes it into typed final-answer or tool-call events.

Consequences:

- `ModelOutputFormatter` and display text normalization are for user-visible prose only.
- Text-protocol tool calls must preserve JSON escapes such as `\n` before parsing.
- Backend bridges should provide raw model text alongside formatted display text when both are available.

### App Policy Owns Side Effects

Status: Accepted

The model may draft side-effect requests, but Pixel Pane's policy engine owns permission decisions, durable approval waits, execution, verification, and recovery.

Consequences:

- Add declarative allow/ask/deny policy.
- Execute approved file writes, commands, and process actions from immutable approval artifacts with stable side-effect IDs.
- Add pre-effect validation, before/after snapshots or hashes, post-effect verification, and rollback/revert where practical.
- Filter model-visible tools by run mode and provider tier.
- Reject generated-content artifacts, such as Python newline-marker corruption, before approval.

### Evidence Packets Drive Local-State Answers

Status: Accepted

Structured evidence packets and deterministic local-state controllers are the default for answerable local questions.

Consequences:

- Every local-state tool result creates structured evidence or an artifact reference.
- Model-visible context includes answer-critical fields such as paths, URLs, ports, commands, status, and source IDs.
- Model-based final-claim declaration may be advisory, but malformed verifier output must not block an answer supported by deterministic evidence.
- Final answers should link to evidence IDs in the run trace.

### Notch UI Projects Durable Run State

Status: Accepted

The notch chat UI will project durable run state. UI code sends intents; the runtime/store owns run state, waits, progress, terminal status, and trace records.

Consequences:

- Add an `AgentRunViewModel` or equivalent projection layer.
- Render explicit run status instead of inferring "Thinking" from empty answer text.
- Approval cards, progress rows, terminal states, and trace export come from typed run events.
- Delete temporary debug export after durable trace export exists.
