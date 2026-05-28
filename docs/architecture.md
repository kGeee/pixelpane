# Pixel Pane Architecture

Last updated: 2026-05-28

Pixel Pane now uses Agent Kernel V2 for assistant execution. The native product shell stayed in place while the old prompt-heavy harness was deleted and replaced with an app-owned runtime.

## Preserved Shell

- SwiftUI/AppKit notch and floating panel UI in `PixelPane/PixelPane/Panel/`.
- Screen capture and OCR foundations in `PixelPane/PixelPane/Capture/` and `PixelPane/PixelPane/OCR/`.
- Settings, local file grants, chat history shell, routing settings, and local/cloud backend clients.
- Low-level file write proposal/executor primitives and terminal policy primitives that can be reused by typed V2 tools.

## Removed Runtime

Runtime implementation code, prompt-planning code, dev scripts, and QA notes were deleted during Sprint 1.

The old runtime should remain deleted. The active chat surface routes through Agent Kernel V2 rather than any temporary stub or prompt-planning path.

## Active Direction

AGENTV2 is an app-owned runtime:

- Models produce final text or typed tool proposals.
- Swift validates permissions, tool schemas, risk, evidence, approvals, and loop budgets.
- Tool calls, approvals, terminal process state, evidence, and errors are control-plane events, not user-visible chat turns.
- Fixture model adapters prove runtime behavior before Apple, MLX, cloud, Ollama, or OpenAI-compatible providers are wired in.
- Product behavior belongs in Swift/runtime code. Minimal text-model prompts may describe protocol shape only.

The active implementation brief is `docs/agent-kernel-v2.md`.
