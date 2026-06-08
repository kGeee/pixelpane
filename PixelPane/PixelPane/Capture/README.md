# Capture

Screen region selection UI and `ScreenCaptureKit`-based image capture.

## Files

| File | Purpose |
|---|---|
| `CaptureSelection.swift` | Plain struct holding the screen, screen rect, and the exact capture rect chosen by the user. Passed downstream to the OCR and AI pipeline. |
| `OverlayCoordinator.swift` | Creates a borderless, full-screen `NSWindow` on every connected display and installs `RegionSelectorView` in it. Tears down all overlays after selection or cancellation. |
| `RegionSelectorView.swift` | SwiftUI drag-to-select view. Draws the selection rect with a semi-transparent overlay, shows dimension labels, and reports the final rect on mouse up. |
| `ScreenCapturer.swift` | Uses `SCShareableContent` + `SCScreenshotManager` to capture a `CGImage` from the chosen rect. Checks screen recording permission before attempting capture. |

## Extension points

- **Multi-region capture** — `CaptureSelection` currently holds one rect; extend it to an array and update `OverlayCoordinator` to accumulate selections.
- **Window/app capture** — `ScreenCapturer` uses a rect filter; swap it for an `SCWindow` or `SCRunningApplication` filter to capture by window or app instead.
- **Selection UI** — all visual feedback is in `RegionSelectorView`; it's a self-contained SwiftUI view with no external dependencies.
