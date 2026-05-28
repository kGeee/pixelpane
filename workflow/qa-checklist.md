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
- [ ] Chat routes through Agent Kernel V2.
- [ ] Capture/OCR context can still be created.
- [ ] Capture/OCR does not imply hidden live screen access.
- [ ] Local Mode is the default route.
- [ ] Cloud Mode is explicit and visibly labeled when enabled.
- [ ] Granted files/folders remain unavailable until the user grants them.
- [ ] Settings can open and show routing, model, file, history, update, and privacy controls.
- [ ] Saved chats do not persist screenshot/image pixels.

## AGENTV2 Runtime

Use this section for AGENTV2 manual QA and beta hardening.

- [x] Fixture models cover final answer, typed tool call, malformed output, empty output, repeated call, timeout, cancellation, approval, resume, and failure.
- [ ] Chat transcript contains only user messages and assistant messages.
- [ ] Tool calls, approvals, process status, evidence, receipts, errors, and cancellations are control-plane events.
- [ ] File reads/searches are limited to explicit grants.
- [ ] File writes are staged proposals and require confirmation.
- [ ] Finite commands have bounded timeout and output caps.
- [ ] Long-running processes/local servers use lifecycle APIs rather than repeated blocking commands.
- [ ] Terminal output, file content, OCR text, and image-derived text are treated as untrusted data.
- [ ] Final answers do not claim source/tool usage without explicit observations.
- [ ] Repeated no-op writes or same-command reruns stop or satisfy the task without blind repetition.

## AGENTV2 Regression Matrix

| Scenario | Fixture | Manual Real Provider |
|---|---|---|
| Plain final answer | Pass | Pending |
| Granted file read/search | Pass | Pending |
| Staged file write approval | Pass | Pending |
| Approval cancellation | Pass | Pending |
| Low-risk finite command | Pass | Pending |
| Long-running process/local server lifecycle | Pass | Pending |
| Repeated tool/command loop guard | Pass | Pending |
| Malformed/empty model output repair or failure | Pass | Pending |
| Timeout/no-progress handling | Pass | Pending |
| Control events excluded from transcript | Pass | Pending |
| Prompt-injection-like retrieved text remains untrusted | Pass | Pending |
| Local/cloud route preservation | Pass | Pending |

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
