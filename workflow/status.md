# Pixel Pane Status

Last updated: 2026-05-28

## Product Focus

Pixel Pane is a local-first, notch-native assistant shell for macOS. The current UI shell is preserved while assistant execution now runs through an app-owned, model-agnostic runtime.

The immediate product priority is AGENTV2.

## Current Phase

AGENTV2 Sprint 5 hardening is complete through `AGENTV2-032`, with `AGENTV2-034` and `AGENTV2-035` also completed from manual QA. The preserved notch chat shell now routes through Agent Kernel V2, with typed tool execution, control-plane approvals, cancellation, history, grants, capture context, model-driven evidence planning, final-answer evidence gating, protocol-leak normalization, recoverable schema-validation failures, answerability deferral guarding, model-call deadlines, packed context memory, kernel-owned approved writes, and typed runtime/UI events connected to the app-owned runtime. The next planned increment adds a deterministic answerability preflight that classifies obvious local-state questions before the generic model loop.

Current recommended story: `AGENTV2-036` Introduce deterministic answerability preflight scaffold.

Why: The post-QA hardening tickets `AGENTV2-024` through `AGENTV2-035` are complete and verified. The next accepted increment is a deterministic, runtime-owned answerability preflight: a traffic controller that classifies obvious local-state questions before the generic model loop and pre-positions safe evidence, complementing the post-answer answerability guard. `AGENTV2-036` lands the behavior-neutral scaffold; `AGENTV2-037`-`AGENTV2-039` light up one intent at a time. `AGENTV2-033` is sequenced after `AGENTV2-037` so the enriched copy-chat export can include preflight route traces.

## Current App State

- Xcode project: `PixelPane/PixelPane.xcodeproj`.
- Build command:

```bash
PixelPane/Scripts/verify-debug-build.sh
```

- Last app verification: 2026-05-28, `PixelPane/Scripts/verify-debug-build.sh` succeeded after `AGENTV2-035`.
- Last kernel verification: 2026-05-28, `PixelPane/Scripts/run-agent-kernel-v2-fixture-tests.sh` passed after `AGENTV2-035`.
- Last planning update: 2026-05-28, `AGENTV2-035` routed approved writes through the kernel approval-resolution path and added script write preflight after QA showed a stuck Thinking state following an approved file write.
- Current known architecture problem: no active AGENTV2 architecture blocker is recorded after `AGENTV2-032`; continue debug-export and manual real-provider QA. The old prompt-heavy harness is deleted and should not be restored.

## Sprint 1 Completed

- Deleted runtime source, prompt-planning code, duplicate runtime view model, dev scripts, and stale QA docs.
- Reduced `AssistantHarness.swift` to shell state structs only.
- Removed agent run/session state from `ChatHistoryStore` and `ResultPanelView`.
- Temporarily added a chat stub in `ResultPanelView.sendAskQuestion()` so no stale tool approval or terminal loops were reachable before V2 integration.
- Rewrote docs/workflow around the AGENTV2 path.

## Active Roadmap

1. Sprint 1: Prune To A Stable Shell
   - `AGENTV2-001` Inventory shell versus agent code - Done
   - `AGENTV2-002` Delete runtime and duplicate runner paths - Done
   - `AGENTV2-003` Clean workflow and docs for the V2 rebuild - Done
   - `AGENTV2-004` Add a stub assistant path that preserves the UI shell - Done
2. Sprint 2: Build The Agent Kernel
   - `AGENTV2-005` Define the Agent Kernel V2 architecture brief - Done
   - `AGENTV2-006` Add fixture model contract and kernel harness - Done
   - `AGENTV2-007` Build session ledger V2 and task state machine - Done
   - `AGENTV2-008` Separate control events from chat transcript - Done
   - `AGENTV2-009` Add approval, cancellation, resume, and no-progress guards - Done
3. Sprint 3: Define Typed Capabilities
   - `AGENTV2-010` Define Tool Registry V2 and safety policy - Done
   - `AGENTV2-011` Add file and visual-context capabilities - Done
   - `AGENTV2-012` Add finite command capability - Done
   - `AGENTV2-013` Add long-running process and local server lifecycle capabilities - Done
   - `AGENTV2-014` Add evidence records and deterministic verification hooks - Done
4. Sprint 4: Add Thin Model Adapters
   - `AGENTV2-015` Define provider-neutral model adapter API - Done
   - `AGENTV2-016` Add native tool-call and minimal text protocol adapters - Done
   - `AGENTV2-017` Wire Apple, MLX, and OpenAI-compatible adapter paths - Done
5. Sprint 5: Integrate, Verify, And Harden
   - `AGENTV2-018` Integrate notch chat with Agent Kernel V2 - Done
   - `AGENTV2-019` Restore capture, grants, history, and approval UX on V2 - Done
   - `AGENTV2-020` Add V2 regression matrix and final cleanup - Done
   - `AGENTV2-021` Seed model requests with app context inventory - Done
   - `AGENTV2-022` Add model-driven planning and evidence gating - Done
   - `AGENTV2-023` Harden model output normalization and prevent protocol leakage - Done
   - `AGENTV2-024` Rebuild agent/UI boundary around typed runtime events - Done
   - `AGENTV2-025` Add strict provider protocol decoder and schema-rich tool contracts - Done
   - `AGENTV2-026` Add bounded tool-argument repair and safe protocol failure handling - Done
   - `AGENTV2-027` Rebuild chat export and persistence from typed ledger events - Done
   - `AGENTV2-028` Re-enable evidence planning on the typed boundary - Done
   - `AGENTV2-029` Harden real-provider QA failures for planning and model selection - Done
   - `AGENTV2-030` Document the agentic architecture in plain language - Done
   - `AGENTV2-031` Recover from incomplete staged-write tool calls - Done
6. Sprint 6: Remaining Agentic Hardening
   - `AGENTV2-032` Add capability-aware answerability guard - Done
   - `AGENTV2-033` Enrich copy-chat debug export for agent traces - Not Started
   - `AGENTV2-034` Bound model-call time and packed context memory - Done
   - `AGENTV2-035` Resume approved writes through the kernel - Done
7. Sprint 7: Deterministic Answerability Preflight
   - `AGENTV2-036` Introduce deterministic answerability preflight scaffold - Not Started
   - `AGENTV2-037` Route obvious local-server questions through preflight - Not Started
   - `AGENTV2-038` Gate file-visibility preflight on grants and preserve writes - Not Started
   - `AGENTV2-039` Route managed-process status through preflight - Not Started

## Durable Decisions

- Direct distribution with Developer ID and Sparkle.
- macOS 15.2+ minimum.
- App is menu-bar/notch-first and configured as `LSUIElement`.
- App sandbox is disabled for Direct distribution and local-agent capabilities.
- Local-first AI is the default; Cloud Mode is opt-in.
- One Cloud Mode toggle covers cloud-capable text and image context.
- Cloud backend is a Pixel Pane Cloudflare Worker proxy; provider keys never ship in the app.
- Local files are accessible only through explicit user grants.
- Screenshots/images remain transient unless a future explicit export feature says otherwise.
- Local writes, risky terminal commands, installs, network commands, privileged commands, and process-control actions require confirmation.
- For V2, product policy belongs in Swift/runtime code. Minimal model prompts may describe protocol format, but should not encode product behavior.
- Fixture models should prove the kernel before real Apple, MLX, cloud, Ollama, or OpenAI-compatible providers shape the architecture.

See `workflow/decisions.md` for the compact decision register.

## Open Decisions

- Telemetry remains deferred. If revisited, it must be opt-in and exclude screenshots, OCR text, prompts, answers, clipboard contents, and file contents.
- Beta packaging and release operations still need final manual verification before distribution.

## Notes For Next Agent

- Start with `AGENTV2-036`, then `AGENTV2-037`; sequence `AGENTV2-033` after `AGENTV2-037`, then continue with `AGENTV2-038` and `AGENTV2-039` plus manual AGENTV2 QA and beta hardening.
- Keep implementation changes inside `PixelPane/` and tracking updates inside `workflow/`.
- Do not bring back the old prompt-heavy harness or chat-control event mixing.
- V2 model requests include a runtime-generated app context inventory for grants, visual context, allowed working directories, and recent write targets.
- `AGENTV2-022` now asks the model to declare evidence needs before synthesis, maps those needs to runtime capabilities, and verifies declared final claims against ledger evidence.
- `AGENTV2-023` normalizes protocol-shaped final text before it can become assistant prose, including the observed `port 8000 ?` leak.
- `AGENTV2-024` removed the raw `assistantMessage` result from the runtime/UI boundary; chat now renders typed `finalMessage`, `blocked`, `failed`, and `canceled` events, and malformed protocol JSON gets a safe typed failure summary instead of visible raw payload text.
- `AGENTV2-025` carries full argument schemas to text-protocol providers and uses one strict decoder for protocol-shaped text.
- `AGENTV2-026` repairs only known-safe staged-write aliases (`path` to `targetPath`) and defaults `operation` to `create` only when target and content are present.
- `AGENTV2-027` projects chat export and history persistence from typed ledger transcript/control events and omits Ask active-text snapshots from debug export.
- `AGENTV2-028` verifies evidence planning/final-claim control calls stay out of assistant prose and explicit port probes complete through typed events.
- `AGENTV2-029` records malformed evidence-planning output as a control-plane failure, continues through normal typed tool handling, refreshes the presented panel after MLX setup checks, and invalidates the MLX text runtime cache when the selected model changes.
- `AGENTV2-030` added `docs/agentic-architecture.txt`, a plain-language source of truth for the agentic platform architecture.
- `AGENTV2-031` treats known incomplete or malformed tool calls as recoverable validation failures when safe, records a failed tool-result observation, and lets the model retry without surfacing schema errors as assistant prose.
- `AGENTV2-032` rejects deferral answers such as "I cannot confirm" or pre-confirmation questions when runtime tools are available, records a hidden `answerability_guard` observation, continues the bounded typed tool loop, and blocks repeat deferrals.
- `AGENTV2-033` should enrich copy-chat debug export with observable model/tool/evidence/guard traces. It must not expose hidden chain-of-thought; label the output as an observable debug trace.
- `AGENTV2-034` adds a per-model-call timeout and packs model context as recent transcript plus current-turn observations only, so old tool output is retained in the ledger but not repeatedly sent back to the model.
- `AGENTV2-035` moves approved staged-write execution into `AgentKernelChatRuntimeV2.resolveApproval`, so the UI only collects approval and the kernel records completed file-write evidence before continuing the same turn. It also preflights likely script writes before asking the user to approve malformed generated code.
- 2026-05-28 hotfix: the notch chat composer now gives its editable text field the full available row width before padding, preventing premature wrapping while typing short prompts.
- The deterministic answerability preflight (`AGENTV2-036`-`AGENTV2-039`) is the accepted next increment. It is a runtime-owned classifier in `continueTurn` (under `shouldPlanEvidence`, before `planAndCollectEvidence`) that routes obvious local-state intents to existing typed tools via `AgentKernelEvidencePlannerV2.toolCall(for:context:)`, returns typed blocked events for missing scope or unknown targets, and falls back to the existing evidence planner for ambiguous intents. It must stay high-precision/low-recall and must not replace the answerability guard, final-claim verifier, registry, approval flow, or ledger projection. See `workflow/decisions.md` (2026-05-28 Deterministic Answerability Preflight) and `docs/agentic-architecture.txt` sections 14 and 27.
- `AGENTV2-036` is behavior-neutral scaffolding: the planner returns `.unclassified` for all inputs, and a shared `collectEvidence` helper is extracted from `planAndCollectEvidence`. Each later story enables exactly one intent and can roll back by returning `.unclassified` again.
