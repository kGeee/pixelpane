# QA Checklist

Use this before marking major stories done.

## Build

- [ ] Debug build succeeds.
- [ ] No new warnings that indicate deprecated APIs or privacy issues.

```bash
xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build
```

## Core Loop — Validated 2026-04-29 (CORE-010)

- [x] App launches as a menu-bar app.
- [x] No Dock icon appears.
- [x] Capture can be started from the menu bar.
- [x] Overlay appears on every connected display.
- [x] Escape cancels capture.
- [x] Small selections are rejected.
- [x] Region capture succeeds after Screen Recording permission is granted.
- [x] OCR returns usable text for normal UI text.
- [x] Result panel appears near selection.
- [x] Copy copies result text.
- [x] Global Cmd+Shift+Space hotkey activates capture from any frontmost app (CORE-007).
- [x] Pause / Resume Hotkey reflects in Settings status pill (CORE-007).
- [x] Result panel shows source-type and detected-language pills (CORE-008).
- [x] Panel placement cascades right → below → left → above → center clamped to visible frame (CORE-009).
- [x] Esc / Cmd-C / Cmd-W keyboard shortcuts work when the panel is focused (CORE-009).
- [x] Second capture immediately after first does not freeze or crash (overlay coordinator regression fixed 2026-04-29).

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
