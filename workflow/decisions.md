# Pixel Pane Decision Register

Last updated: 2026-05-28

This file records durable product and architecture decisions only. It is not a changelog and should not preserve sprint implementation details.

## Template

```md
## YYYY-MM-DD - Decision Title

Status: Proposed | Accepted | Rejected | Superseded

Decision:

Context:

Consequences:
```

## 2026-05-28 - Rebuild Agent Architecture As AGENTV2

Status: Accepted

Decision:
Pixel Pane will rebuild the agentic architecture from ground zero as AGENTV2. The native Mac shell stays; runtime code and dev scripts stay deleted until replaced by the new kernel. Product behavior belongs in typed Swift runtime and tool policy, not internal prose prompts.

Context:
Native QA exposed repeated approval loops and blurry boundaries between model output, approval UI, tool observations, and chat transcript. The architecture needs a deterministic app-owned runtime before real model providers are wired in again.

Consequences:
- Preserve notch chat, capture/OCR, local file grants, settings, history shell, model routing settings, and backend clients.
- Build the new kernel against fixture models first.
- Keep chat transcript separate from control-plane events such as approvals, tool calls, process status, evidence, errors, and receipts.
- Treat finite commands, long-running processes, and local server lifecycle as separate typed capabilities.
- Allow minimal adapter prompts only to express a tool-call protocol for text-only models.

## 2026-05-28 - Agent Kernel V2 Boundaries

Status: Accepted

Decision:
AGENTV2 uses a kernel boundary documented in `docs/agent-kernel-v2.md`. The kernel owns task state, the session ledger, model adapter calls, typed tool validation, approvals, evidence, cancellation, resume, and no-progress guards. SwiftUI/AppKit renders state but does not own the task loop.

Context:
Sprint 2 needs a code target that can be tested with fixture models before real providers are attached.

Consequences:
- Fixture models are the first implementation target.
- Chat transcript messages are separate from control-plane events.
- Typed tools and evidence records are required before provider integration.
- Text-only model prompts may describe protocol format, but not product policy.

## 2026-05-28 - Recoverable Tool-Call Validation Failures

Status: Accepted

Decision:
Known tool calls with incomplete, unknown, or malformed arguments may be treated as recoverable model mistakes when the requested tool is otherwise allowed to participate in the normal agent loop. The runtime records the validation failure as a failed control-plane tool result and gives the model another bounded chance to correct the call. The runtime must not execute the tool until the call validates.

Context:
Manual AGENTV2 QA showed local text models can omit required staged-write arguments and the app previously surfaced "The tool call is missing a required argument" as the assistant answer. That is a protocol-boundary failure: schema validation was correct, but the failure belonged inside the control plane, not in user-visible prose.

Consequences:
- Tool schema validation remains strict before execution.
- Recoverable validation failures are observations for the model, not assistant chat answers.
- Policy, permission, scope, safety, approval, and no-progress failures remain runtime-owned and may still block.
- Recovery must stay bounded by the existing loop guards and must not become a broad hidden repair system.

## 2026-05-28 - Answerability Deferral Guard

Status: Accepted

Decision:
Agent Kernel V2 should not accept a final answer that defers by saying the model cannot confirm something, needs to check something, or asks for pre-confirmation when typed runtime capabilities are available. The runtime records a hidden `answerability_guard` observation, continues the bounded tool loop, and lets the normal model/tool contract choose the next typed tool call. If the model repeats the deferral after that observation, the runtime blocks the turn as an agent failure.

Context:
Manual AGENTV2 QA showed the local model could answer "I cannot confirm..." while also saying it would need to probe the local server or check processes, even though the runtime had safe tools available. Another QA case showed the model asking whether to proceed with script creation after the user had already requested the file action. Both are agent-loop failures, not useful assistant answers.

Consequences:
- The guard is capability-aware through the offered tool schemas, not a hardcoded localhost-port or folder-name selector.
- The guard does not directly execute domain-specific tools; it feeds an observation back into the normal typed tool loop.
- Side-effect confirmation still belongs to the app approval UI, not to model pre-confirmation prose.
- This is an observable debug trace, not hidden chain-of-thought.

## 2026-05-28 - Bounded Model Context And Deadlines

Status: Accepted

Decision:
Agent Kernel V2 keeps the full session ledger for history, debug export, and auditability, but model requests receive a packed context: trusted app inventory, recent transcript continuity, and current-turn observations. Old tool observations from earlier turns are not repeatedly sent back to the model. Each model call also has a wall-clock deadline; a provider that does not answer in time produces a typed timeout failure instead of leaving the UI in Thinking indefinitely.

Context:
Manual QA showed a local model stuck in Thinking during a file-creation request, and the runtime was packing the full ledger into every model call. That allowed stale tool output to become implicit memory and increased prompt size over time.

Consequences:
- Full ledger retention remains available for copy-chat/debug export.
- Model-visible memory is bounded and task-focused.
- Current-turn evidence, answerability guard observations, and final-claim checks still remain model-visible.
- Slow or stuck providers fail through typed runtime events rather than hanging the panel.

## 2026-05-28 - Kernel-Owned Approved Writes

Status: Accepted

Decision:
Approved local file writes belong to the Agent Kernel V2 tool execution path. The UI may render the pending write and collect the user's approval, but it must resume the runtime with that approval instead of writing the file directly. The runtime executes the approved write, records the tool result and file-write evidence, and then continues the same agent loop.

Context:
Manual QA showed a stuck Thinking state after a staged write was approved. The write evidence appeared in the ledger, but the UI had executed the write outside the normal runtime continuation path. That split ownership made it possible for the panel loading state and model loop to diverge.

Consequences:
- Approved writes, terminal commands, and other side-effect tools follow the same approval-resolution model.
- The UI remains a renderer and input collector rather than a second tool runner.
- Completed writes are model-visible observations in the same turn, so the agent can continue to run or verify the created artifact.
- Script write proposals may be preflighted before approval; malformed generated scripts become recoverable tool observations rather than user approval prompts.

## 2026-05-28 - Deterministic Answerability Preflight

Status: Accepted

Decision:
Agent Kernel V2 will add a deterministic, runtime-owned preflight that runs on the user turn before the generic model loop. It classifies obvious local-state intents (localhost/port status, file visibility/read/search, managed process status, build/test, visual context) from the user message, current grants, and the ledger. When classification is nearly certain, the preflight either pre-positions safe evidence by reusing the existing evidence-need to tool mapping, or returns a typed blocked event when the needed scope or target is missing. Ambiguous intents fall back to the existing model-driven evidence planning and generic loop. The preflight does not replace the post-answer answerability guard, the final-claim verifier, the tool registry, the approval flow, or the ledger projection.

Context:
Evidence planning is itself a model pass, and the answerability guard only runs after a final answer has already hedged. There is no deterministic step that recognizes an obvious local-state question and gathers the right evidence before the model loop. This is the answerability weakness documented in `docs/agentic-architecture.txt` sections 14 and 27. The work is scheduled as stories AGENTV2-036 through AGENTV2-039 and starts behavior-neutral before each intent is enabled.

Consequences:
- The preflight is high precision and low recall: it only short-circuits when nearly certain, and ambiguous cases defer to today's behavior.
- It adds no new tool dispatch; it emits the same typed evidence needs the model planner already produces.
- Missing scope or an unknown target produces a typed blocked event rather than a model hedge.
- The preflight routing decision is a control-plane observation, never assistant prose.
- Side-effect confirmation still belongs to the approval UI; write intent stays on the staged-approval path.

## 2026-05-27 - Notch Chat Is The Primary Surface

Status: Accepted

Decision:
Pixel Pane opens as a hover-expanded notch assistant. Plain chats can start without capture context. Captures create contextual turns from selected screen regions.

Context:
The notch surface better matches the desired always-nearby assistant experience than a conventional floating result panel or action rail.

Consequences:
- Assistant UI work should optimize compact notch ergonomics.
- New chat, history, files, local/cloud routing, and context controls belong in or near the notch composer.
- Capture is context for the assistant rather than the whole product.

## 2026-04-29 - Local-First AI Default

Status: Accepted

Decision:
Pixel Pane defaults to local execution. Cloud Mode is explicit opt-in.

Context:
The privacy promise is central: screenshots, OCR, local files, and terminal observations should stay on the Mac unless the user explicitly chooses cloud routing.

Consequences:
- Cloud Mode is a single user-visible setting for cloud-capable text and image context.
- Cloud requests receive only explicitly packed context.
- Deterministic app-owned behavior is preferred for permissions, tool state, and safety because local model quality varies.

## 2026-05-21 - Explicit User Grants For Local Files

Status: Accepted

Decision:
The assistant may read, search, or write only through files and folders explicitly granted by the user.

Context:
The assistant needs local context to be useful, but broad invisible file access would break the product's trust model.

Consequences:
- File reads, searches, snippets, and write proposals enforce grants in app code.
- Cloud Mode may receive local snippets only after explicit routing choice.
- Recent file/folder metadata may help follow-ups, but grants remain the permission boundary.

## 2026-05-21 - Confirmed Local Writes

Status: Accepted

Decision:
Pixel Pane may create or edit local files only by staging a visible proposal inside a user-granted location and receiving user confirmation.

Context:
Agentic workflows need file writes, but model output must not directly mutate local files.

Consequences:
- Confirmation UI must name the exact target path and summarize or show the content/change.
- Cancel leaves the file system unchanged.
- Running a newly created script requires separate confirmation.

## 2026-05-24 - Bounded Local Commands

Status: Accepted

Decision:
Terminal and process capabilities must be app-owned, bounded, observable, and policy-gated.

Context:
An agentic desktop assistant needs local feedback for builds, tests, dev servers, process checks, repo inspection, and system questions.

Consequences:
- Finite commands have timeouts and output caps.
- Risky/destructive/process-control/install/network/privileged/system-affecting commands require visible confirmation or are blocked.
- Long-running processes and local servers need explicit lifecycle handling rather than repeated blocking commands.
- Terminal output is untrusted data.

## 2026-05-24 - Source-Aware Context

Status: Accepted

Decision:
Retrieved file, OCR, image-derived, terminal, and tool-output text must be carried as source-labeled untrusted context.

Context:
The assistant needs reliable follow-ups across local and cloud models, but retrieved content can contain hostile instructions.

Consequences:
- Screenshot pixels are not persisted in chat history.
- Context budgets should adapt by route capability.
- The assistant must not claim it used a source or tool unless an explicit observation exists.

## 2026-05-26 - Fresh Chats Do Not Auto-Restore Prior Sessions

Status: Accepted

Decision:
Fresh assistant chats start with empty turns and tool state. Saved chats return only by explicit user selection.

Context:
Auto-restoring the latest saved session created hidden global memory and confused file/write follow-ups.

Consequences:
- New Chat means a clean working context.
- Current-session observations may still ground follow-ups.
- History remains useful, but recall is explicit.

## 2026-05-27 - Alpha Chat History May Reset

Status: Accepted

Decision:
During the AGENTV2 migration, existing alpha saved chat history may be reset instead of migrated if preserving it adds disproportionate complexity. The app should provide a clear user-visible Settings control to delete saved chat history.

Context:
The current chat persistence predates the planned per-chat session event ledger. The user accepted losing existing alpha chats, but wants an explicit way to clear history going forward.

Consequences:
- Session deletion and clear-all behavior should be part of the new persistence design.
- Screenshot/image pixels still must not be persisted.

## 2026-04-28 - Direct Distribution

Status: Accepted

Decision:
Pixel Pane targets Direct distribution using Developer ID signing and Sparkle updates.

Context:
The app needs global hotkey behavior, screen capture permissions, local model/runtime integration, file grants, terminal execution, and non-sandboxed agent capabilities that do not fit cleanly with Mac App Store constraints.

Consequences:
- App sandbox is disabled.
- Releases need notarized DMGs and Sparkle update feeds.
- Future payments should use direct-distribution-compatible vendors, not StoreKit-only assumptions.

## 2026-04-28 - Minimum macOS

Status: Accepted

Decision:
Pixel Pane alpha and v1 target macOS 15.2+.

Context:
The selected-region capture path uses `SCScreenshotManager.captureImage(in:)`, available on macOS 15.2+.

Consequences:
- No macOS 14 or macOS 15.0/15.1 support is planned for alpha/v1.
- QA, docs, and release requirements should state macOS 15.2+.

## 2026-04-29 - Cloud Proxy And Secret Ownership

Status: Accepted

Decision:
Cloud Mode uses a Pixel Pane backend proxy in front of provider APIs. Provider keys, app auth secrets, signing secrets, payment secrets, and update-signing secrets never ship in the app or repository.

Context:
Cloud Mode needs streaming model quality without exposing provider credentials or logging user content by default.

Consequences:
- The macOS app talks to Pixel Pane `/v1` endpoints.
- The app stores only anonymous device identity and Pixel Pane auth/session tokens in Keychain.
- Production logs may include operational metadata, but not screenshots, OCR text, prompts, answers, filenames, file contents, or clipboard contents by default.

## 2026-05-21 - Screenshot And Image Retention

Status: Accepted

Decision:
Screenshots and user-attached image pixels are transient. Chat history may store text, bounded metadata, OCR/source summaries, and tool state, but not screenshot/image pixels.

Context:
The assistant benefits from capture and image context, but persistent image storage would weaken the privacy story.

Consequences:
- Active chats may hold image context in memory.
- Last-result and saved-chat features must avoid retaining captured image pixels.
- Temporary image files for local vision must be cleaned up.

## 2026-05-18 - Telemetry Deferred

Status: Accepted

Decision:
Telemetry is deferred for now.

Context:
Analytics are not necessary for the current alpha. Reliability work can proceed through manual QA and user feedback.

Consequences:
- No analytics SDK should be added during the current alpha.
- If telemetry is revisited before beta, it must be opt-in and exclude screenshots, OCR text, prompts, answers, clipboard contents, filenames, and file contents.

## 2026-05-28 - Evidence Planning Failure Policy

Status: Accepted

Decision:
Agent Kernel V2 treats evidence planning as an auxiliary planning pass. Malformed, timed-out, or otherwise unusable evidence-plan output is recorded as a control-plane failure and the turn continues through the normal typed tool loop. Final-claim verification remains a stricter gate before user-visible final answers.

Context:
Manual AGENTV2 QA showed the Local Apple Model could return malformed evidence-planning output for ordinary local-context questions such as "do you see my personal website?", which previously surfaced as the assistant answer.

Consequences:
- Planner-format issues should not become user-visible chat answers.
- Normal tool handling can still collect evidence after a planner failure.
- Final answers that make unsupported local-state claims can still be blocked by deterministic evidence verification.
