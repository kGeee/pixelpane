# Panel

The notch-attached result and chat UI. Everything the user sees after a capture lives here.

## Files

| File | Purpose |
|---|---|
| `ResultPanelController.swift` | `NSPanel` lifecycle. Positions the panel below the notch, installs SwiftUI content, and handles show/hide/close. |
| `ResultPanelView.swift` | Root SwiftUI view. Orchestrates the action bar, active agent run, chat history, and file-access prompts. The main composition point for the panel. |
| `ResultPanelState.swift` | View models for chat sessions, individual conversation turns, pending approvals, and run metadata. These are the data structures `ResultPanelView` renders. |
| `ResultPanelContainers.swift` | Visual shell: glass blur container, notch-dimension metrics, and the outer rounded frame. |
| `ResultPanelControls.swift` | Reusable UI atoms: action buttons, chips, badges, the chat input field, menus, and icon buttons. |
| `ResultPanelStatusViews.swift` | Specialised status displays: recovery prompt, typing indicator, approval request, agent run progress, thinking animation, and terminal output. |
| `ResultPanelTranscriptViews.swift` | Chat transcript rendering: individual turns (user/assistant), file-linked text spans, flow layout for chips, model stats footer, and the capture image thumbnail. |
| `PanelActionState.swift` | Enum of all available actions (`extractText`, `translate`, `explain`, `simplify`, `debugCode`, `ask`, `chat`) with their display title and SF Symbol icon. |
| `CaptureResult.swift` | Immutable value type passed into the panel: captured `CGImage`, OCR text, detected language, technical score, and capture timestamp. |
| `RecoveryIssue.swift` | Typed issues (screen recording permission missing, hotkey conflict) with titles, body copy, and recovery action labels. |
| `RecoveryPanelView.swift` | Full-panel view shown instead of results when a blocking issue (e.g. screen recording denied) needs to be resolved first. |
| `MoonPhaseIndicator.swift` | Animated loading indicator that morphs through moon-phase glyphs while inference is running. Brand element. |

## Adding a new action

1. Add a case to `PanelActionState` with a `title` and `systemImage`.
2. Handle the new case in `ResultPanelView` — either call an `AppState` method directly or launch an agent run.
3. The action bar renders all cases automatically; no additional wiring needed for it to appear.

## Panel positioning

`ResultPanelController` reads notch metrics from `ResultPanelContainers` to place the panel. If the notch position or panel width needs to change, edit the constants there.

## Approval UI

When the agent requests a dangerous operation, `AgentRunViewModel` publishes a pending approval. `ResultPanelStatusViews.approvalView` renders it with Allow / Deny buttons that call back into `AgentRuntime`.
