# AgentKernel

Adapter layer between the app's `AIBackend` protocol and the agent runtime's model protocol. The kernel translates heterogeneous backend responses into a single normalised stream of agent events (text tokens, tool calls, final answers).

`AgentRuntime` only knows about `AgentKernelModelAdapter` — it never talks to `AIBackend` directly.

## Files

| File | Purpose |
|---|---|
| `AgentKernelModelAdapter.swift` | Protocol defining the streaming interface the agent runtime uses: `stream(request:) -> AsyncThrowingStream<AgentKernelModelEvent, Error>`. |
| `AgentKernelTypes.swift` | Enums shared across adapters: provider kind, response modality, tool mode (native vs. text protocol), and streaming event types. |
| `AgentKernelModelOutputNormalizer.swift` | Decodes the text protocol (JSON-encoded tool calls and final answers embedded in plain text) from model output. Has fallback/repair paths for models that format inconsistently. |
| `AgentKernelAIBackendAdapter.swift` | Wraps any `AIBackend` into `AgentKernelModelAdapter`. Supports both native tool-call responses and the text protocol, with a single repair attempt on malformed output. |
| `AgentKernelCloudChatAdapter.swift` | Specialisation for the Pixel Pane Cloud backend. Prepends the text-protocol preamble and applies cloud-specific repair logic. |
| `AgentKernelMLXNativeToolAdapter.swift` | Wraps the MLX backends. Attempts native tool-call parsing first; falls back to `AgentKernelAIBackendAdapter` for plain-text responses. |
| `AgentKernelOpenAICompatibleAdapter.swift` | Adapter for any OpenAI-compatible endpoint (local or remote). Accepts an optional API key and base URL. |
| `AgentKernelProtocolAdapters.swift` | `NativeToolCallAdapter` enforces structured tool-call wrapping. General protocol decoders shared by multiple adapters. |
| `AgentKernelProviderAdapterCatalog.swift` | Factory: given a provider kind and an `AIBackend`, returns the right `AgentKernelModelAdapter`. The agent runtime calls this to build its model connection. |
| `FixtureAgentKernelAdapter.swift` | Scripted adapter for unit tests. Returns pre-baked response sequences without any real model. |

## How adapters are selected

`AgentKernelProviderAdapterCatalog` maps `AgentKernelProviderKind` → adapter. The provider kind is set by `AgentModelRouter` based on the routing decision (local text, local vision, cloud, Apple FM, etc.).

## Adding an adapter for a new provider

1. Conform to `AgentKernelModelAdapter`.
2. Translate the provider's streaming format into `AgentKernelModelEvent` values (`.token`, `.toolCall`, `.finalAnswer`, `.done`).
3. Add a case to `AgentKernelProviderKind` and wire it in `AgentKernelProviderAdapterCatalog`.
