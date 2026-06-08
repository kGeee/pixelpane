# Actions

AI backends, the model catalog, local model download, and the runtime installer. This folder owns everything related to *how* inference happens; it does not own the agent loop (that's `AgentRuntime/`).

## Files

| File | Purpose |
|---|---|
| `AIBackend.swift` | Core protocol. Every backend conforms to this. Defines `stream(request:)` for streaming text/image responses and `capabilityStatus()` for reporting what the backend can do right now. |
| `HybridLocalAIBackend.swift` | Default local backend. Routes between Apple Foundation Models (if available) and MLX text/vision based on the request modality and what's installed. |
| `AppleFoundationModelsBackend.swift` | Wraps Apple's on-device `FoundationModels` framework. Handles validation errors and converts the streaming response into `AIBackend` events. |
| `MLXTextBackend.swift` | Sends text requests to a warm Python `mlx_lm` server process managed by `MLXTextServerManager`. |
| `MLXTextServerManager.swift` | Actor that keeps a single `mlx_lm` server process alive with an idle timeout. Serialises requests and restarts the process on failure. |
| `MLXVisionBackend.swift` | Spawns a short-lived Python `mlx_vlm` process per request for image + text inference, streaming stdout back as events. |
| `MLXVisionModelSetup.swift` | `MLXModelCatalog` — the five tiered Qwen3 models with disk/memory requirements. `MLXModelCatalog.recommended(for:)` picks the best fit for the current machine. |
| `MLXVisionRuntimeDetector.swift` | Scans the filesystem for installed MLX models and the Python runtime. Returns capability statuses consumed by `AppState` and the Settings UI. |
| `HardwareProfile.swift` | Read-only snapshot of unified memory, chip brand, and free disk. Injected into `MLXModelCatalog.recommended(for:)` and displayed in Settings. |
| `ModelDownloader.swift` | Downloads a Hugging Face model repo over HTTPS (no Python required) into the standard `~/.cache/huggingface/hub/` layout. Reports per-byte progress and supports cancellation. |
| `MLXRuntimeInstaller.swift` | Runs `python3 -m pip install mlx-lm mlx-vlm huggingface_hub` in a child process. Falls back to a copyable command if `python3` isn't found. |
| `SmartDefaultActionSelector.swift` | Maps classifier output + language detection to the `PanelActionState` case that should be pre-selected when a result first appears. |
| `ExtractTextAction.swift` | Trivial action that returns the captured OCR text as-is, with no model call. |
| `AssistantHarness.swift` | Structures for image context (OCR text, source labels) and the tool name enum used by the agent. |
| `ModelDisplayTextNormalizer.swift` | Strips or escapes markdown, math delimiters, and escape sequences that would render badly in the panel. |
| `ModelOutputFormatter.swift` | Parses raw model output into display segments: reasoning blocks, answer text, and per-token stats. |

## Adding a new AI backend

1. Create a file conforming to `AIBackend`.
2. Implement `stream(request:)` — yield `.text(String)` events and finish with `.done`.
3. Implement `capabilityStatus()` — return `.available`, `.unavailable(reason:)`, or `.checking`.
4. Register it in `HybridLocalAIBackend` (or wire it directly from `AppState` for a custom routing path).
5. If the backend needs its own tool-call format, add an adapter in `AgentKernel/`.

## Adding a model tier

Add an `MLXModelTier` entry to the `tiers` array in `MLXModelCatalog` (`MLXVisionModelSetup.swift`). Set `minUnifiedMemoryBytes` to the floor below which the model is too slow to be useful, and `approximateDiskSizeBytes` to the Hugging Face repo size. The recommendation algorithm picks the largest tier the machine can fit automatically.
