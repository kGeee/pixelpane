# QA Checklist

Use this before marking major stories done.

## Build

- [x] Debug build succeeds.
- [x] No new warnings that indicate API or privacy issues.

```bash
PixelPane/Scripts/verify-debug-build.sh
```

## Current Shell

- [ ] Hover-open notch chat focuses the composer.
- [ ] Chat starts or resumes an assistant run through the current runtime path.
- [ ] Capture/OCR context can still be created.
- [ ] Capture/OCR does not imply hidden live screen access.
- [ ] Local Mode is the default route.
- [ ] Cloud Mode is explicit and visibly labeled when enabled.
- [ ] Granted files/folders remain unavailable until the user grants them.
- [ ] Settings can open and show routing, model, file, history, update, and privacy controls.
- [ ] Saved chats do not persist screenshot/image pixels.

## AGENTR Runtime

Use this section for the durable runtime rearchitecture.

- [x] Durable sessions, runs, steps, events, waits, evidence, artifacts, side effects, and trace records are written outside `UserDefaults`.
- [x] App relaunch restores pending waits and marks unsafe in-flight work interrupted.
- [x] Provider tiers gate full-agent, constrained, and plain-chat behavior.
- [x] Chat transcript contains only user-visible user and assistant messages.
- [x] Tool calls, approvals, process status, evidence, receipts, errors, and cancellations are control-plane events.
- [x] File reads/searches are limited to explicit grants.
- [x] File writes are staged proposals and require confirmation.
- [x] Risky commands, installs, network commands, privileged commands, and process control ask or deny through app policy.
- [x] Long-running processes/local servers use lifecycle APIs rather than repeated blocking commands.
- [x] Terminal output, file content, OCR text, and image-derived text are treated as untrusted data.
- [x] Final answers link to evidence IDs or artifact references where local state was used.
- [x] Repeated no-op writes or same-command reruns stop, reuse evidence, or satisfy the task without blind repetition.
- [x] Copy/export uses production-safe trace projection with redaction.

Automated AGENTR fixture coverage passed on 2026-05-29. Manual notch-shell and real-provider smoke checks remain product QA gates before beta.

## AGENTR Regression Matrix

| Scenario | Fixture | Manual Real Provider |
|---|---|---|
| FC-001 search found file but could not answer | Passed: `run-agent-rearchitecture-regression-fixture-tests.sh` | Required before beta |
| FC-002 correct local-state answer blocked by verifier | Passed: `run-agent-rearchitecture-regression-fixture-tests.sh` | Required before beta |
| FC-003 follow-up script modification hung local model | Passed: `run-agent-rearchitecture-regression-fixture-tests.sh` | Required before beta |
| FC-004 provider protocol JSON leaked as prose | Passed: `run-agent-rearchitecture-regression-fixture-tests.sh` | Required before beta |
| FC-005 malformed planning left UI thinking forever | Passed: `run-agent-rearchitecture-regression-fixture-tests.sh` | Required before beta |
| FC-006 incomplete write protocol surfaced schema errors | Passed: `run-agent-rearchitecture-regression-fixture-tests.sh` | Required before beta |
| FC-007 deferral answer despite available tools | Passed: `run-agent-rearchitecture-regression-fixture-tests.sh` | Required before beta |
| FC-008 stale context or full-ledger packing polluted answer | Passed: `run-agent-rearchitecture-regression-fixture-tests.sh` | Required before beta |
| FC-009 approved write bypassed runtime continuation | Passed: `run-agent-rearchitecture-regression-fixture-tests.sh` | Required before beta |
| FC-010 localhost routing was overconfident or hard-coded | Passed: `run-agent-rearchitecture-regression-fixture-tests.sh` | Required before beta |
| FC-011 generated script artifacts reached approval | Passed: `run-agent-rearchitecture-regression-fixture-tests.sh` | Required before beta |
| FC-012 trace/progress hid runtime failure state | Passed: `run-agent-rearchitecture-regression-fixture-tests.sh` | Required before beta |

Manual real-provider checks were not run in this non-interactive pass. They are recorded as beta gates for Tier A, Tier B, Tier C, pending approval, cancel/retry, reload recovery, trace copy, and no indefinite thinking.

## TOOLC Tool Calling

- [x] Model tool calls are handled as control-plane steps, not visible assistant prose.
- [x] `list_grants`, `list_folder`, `search_files`, and `read_file` execute through app-owned local file tools.
- [x] Local file tool results record evidence/artifacts.
- [x] `stage_write_proposal` creates durable approval cards.
- [x] Approved writes execute exactly once through `AgentSideEffectController.executeApproved`.
- [x] Denied writes do not touch disk.
- [x] Tool result observations are passed back to the model before final answer.
- [x] Notch chat selects tool-capable mode for Tier A/Tier B providers with granted folders and falls back to plain chat for Tier C/no-tool contexts.

Automated TOOLC fixture coverage passed on 2026-05-29 via `PixelPane/Scripts/run-agent-tool-calling-fixture-tests.sh`. Manual real-provider checks remain required before beta.

## TOOLR Tool Reliability

- [x] Explicit `random-tests/...` paths resolve to the `random-tests` grant instead of a broad `pixel-pane` grant.
- [x] Preferred granted directories beat broad fallback grants for bare write targets.
- [x] Ambiguous relative write targets are rejected instead of silently choosing a grant.
- [x] Missing write parent folders are rejected before approval.
- [x] Text-protocol tool-call content preserves escaped newlines as real newlines.
- [x] Failed approved writes fail the durable run and show side-effect error diagnostics.
- [x] Trace export includes failed side-effect error summaries.

Automated TOOLR fixture coverage passed on 2026-05-29 via `run-agent-model-gateway-fixture-tests.sh`, `run-agent-permission-policy-fixture-tests.sh`, and `run-agent-tool-calling-fixture-tests.sh`. Manual real-provider checks should repeat the latest `docs/example-chats` prompts against the running notch shell.

## Capture Context Loop

- [ ] App launches as a menu-bar app.
- [ ] No Dock icon appears.
- [ ] Capture can be started from the menu bar.
- [ ] Overlay appears on every connected display.
- [ ] Escape cancels capture.
- [ ] Small selections are rejected.
- [ ] Region capture succeeds after Screen Recording permission is granted.
- [ ] OCR returns usable text for normal UI text.
- [ ] Result panel/notch assistant receives capture context.
- [ ] Copy copies result text.
- [ ] Global hotkey activates capture from any frontmost app.
- [ ] Pause / Resume Hotkey reflects in Settings status pill.
- [ ] Result panel shows source-type and detected-language pills.
- [ ] Panel placement remains visible and clamped to the display.
- [ ] Esc / Cmd-C / Cmd-W keyboard shortcuts work when the panel is focused.
- [ ] Second capture immediately after first does not freeze or crash.

## Privacy

- [ ] Capture is kept in memory in the normal flow.
- [ ] No screenshot files are created during capture.
- [ ] After a normal capture, close the panel and confirm the menu-bar "Show Last Result" path reopens text/OCR only, without image-aware context.
- [ ] File-system spot check: before and after a normal capture, run `find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'pixel-pane-*.png' -print` and confirm no new files appear.
- [ ] If MLX Vision is used, run `find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'pixel-pane-mlx-*.png' -print` after completion/cancel/failure and confirm temporary helper images were deleted.
- [ ] Cloud actions are clearly labeled before sending content.
- [ ] Local Mode disables cloud-only actions unless user explicitly allows cloud.

## Permissions

- [ ] Missing Screen Recording permission has actionable recovery text.
- [ ] Hotkey registration failure has actionable recovery text.
- [ ] Missing Accessibility permission has actionable recovery text only if a future `CGEventTap` path is enabled.
- [ ] Denying permissions does not crash the app.

## UI

- [ ] Light mode is usable.
- [ ] Dark mode is usable.
- [ ] Result text is selectable.
- [ ] Panel can be closed.
- [ ] Settings can be opened.

## Multi-Display

- [ ] Capture works on primary display.
- [ ] Capture works on secondary display.
- [ ] Panel appears on the correct display.

## Accessibility

- [ ] Menu items have clear labels.
- [ ] Buttons have labels.
- [ ] Keyboard-only path exists for capture.
- [ ] Reduced Motion does not break overlay/panel behavior.
