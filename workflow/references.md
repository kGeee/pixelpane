# Pixel Pane References

Last updated: 2026-05-28

Use this file for researched or externally inspired constraints that should guide implementation.

## AGENTV2 Runtime Direction

- Keep a provider-neutral runtime boundary: model adapters are replaceable, while Pixel Pane owns session state, tool validation, permissions, approvals, observations, evidence, and UI events.
- Treat mature coding-agent systems as architectural inspiration only. Do not copy their prompts or preserve Pixel Pane's deleted runtime.
- Native tool-calling providers and text-only local models should both flow into the same typed runtime contract. Text-only adapters may use minimal protocol-format prompts, but product behavior must live in Swift.
- File access, terminal execution, local server lifecycle, receipts, errors, approvals, and cancellation are control-plane events. They should not be serialized as user chat turns.
- Fixture models should be the first integration target. Real Apple, MLX, cloud, Ollama, and OpenAI-compatible adapters should not shape the kernel until fixture coverage proves the state machine.

## macOS And Product Constraints

- The app remains macOS 15.2+ because screen capture uses the modern ScreenCaptureKit path already wired in the app.
- Direct distribution remains the target path with Developer ID and Sparkle.
- App sandbox remains disabled for local-first agent capabilities unless a future release decision changes distribution strategy.
- Local files require explicit user grants. Screenshots/images remain transient unless a future export feature says otherwise.
- Risky local effects require app-owned confirmation gates: writes, terminal commands, installs, network actions, privileged actions, and process control.

## Cloud Mode Constraints

- Cloud Mode is opt-in and routed through Pixel Pane's backend proxy.
- Provider keys never ship in the app.
- The backend is only a model route. It does not own local permissions, file access, terminal execution, write approval, source tracking, or AGENTV2 policy.
