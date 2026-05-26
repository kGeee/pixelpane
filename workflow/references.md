# Implementation References

Last updated: 2026-05-26

Use this file when stories need platform/service-specific details. Prefer primary sources over blog posts.

## macOS Capture

- ScreenCaptureKit is the canonical framework for modern macOS screen capture.
- Current alpha code uses `SCScreenshotManager.captureImage(in:)`, which is simple for rectangle capture but requires macOS 15.2+.
- Product decision: alpha and v1 target macOS 15.2+. If the product later needs macOS 14/15.0 support, create a compatibility story using `SCContentFilter` and `SCStreamConfiguration.sourceRect`.

Primary references:

- Apple ScreenCaptureKit sample/docs: https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos
- Apple WWDC22 ScreenCaptureKit overview: https://developer.apple.com/videos/play/wwdc2022/10156/
- Apple WWDC23 ScreenCaptureKit screenshot capabilities: https://developer.apple.com/videos/play/wwdc2023/10136/

## OCR

- Use Vision `VNRecognizeTextRequest` for local OCR.
- Use accurate mode for normal captures unless performance requires a fast-mode option.
- Keep image data in memory by default.

Primary reference:

- Apple Vision text recognition API: https://developer.apple.com/documentation/vision/vnrecognizetextrequest

## Apple Foundation Models

- Use `FoundationModels.LanguageModelSession` for on-device text generation when Local Mode AI actions are enabled.
- Use `SystemLanguageModel.default.availability` before starting a local action so Pixel Pane can distinguish available, device-not-eligible, Apple Intelligence disabled, and model-not-ready states.
- Use `streamResponse(to:options:)` for partial result updates; the stream emits snapshots, not deltas, so UI state should replace the active response text with the latest snapshot content.
- Keep prompts concise. The current SDK exposes `SystemLanguageModel.contextSize` and token-count APIs on macOS 26.4, and Apple documents context-window errors through `LanguageModelSession.GenerationError.exceededContextWindowSize`.
- Do not call `logFeedbackAttachment` from normal app flows because it serializes session information intended for explicit Feedback Assistant reports.
- As of Xcode 26.4 / macOS SDK 26.4, the `FoundationModels` Swift interface exposes text prompts, guided generation, tools, streaming, availability, and token counting, but no `CGImage`, `NSImage`, image attachment, or other prompt image input surface. Treat true local image understanding as blocked until the product chooses a path.

Primary references:

- Apple Foundation Models framework: https://developer.apple.com/documentation/FoundationModels
- Apple `LanguageModelSession`: https://developer.apple.com/documentation/foundationmodels/languagemodelsession
- Apple `SystemLanguageModel`: https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel
- Apple `Prompt`: https://developer.apple.com/documentation/FoundationModels/Prompt
- Apple prompting guidance: https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model

## MLX Local Vision Runtime

- Use MLX/VLM as the optional local image-understanding runtime for Explain, Ask, and Debug when the user installs or selects a compatible local model.
- Current development-machine discovery:
  - `mlx_vlm.generate` exists at `/opt/homebrew/bin/mlx_vlm.generate`.
  - `mlx_lm.generate` exists at `/Users/nayak/Library/Python/3.13/bin/mlx_lm.generate`; GUI app runtime detection must search per-user Python bin directories because LaunchServices apps may not inherit the user's shell `PATH`.
  - `mlx-run35` was not found on PATH during the 2026-04-29 check.
  - Hugging Face cache includes `mlx-community/Qwen3.6-35B-A3B-6bit`.
- Recommended default model for the setup flow:
  - `mlx-community/Qwen3.6-35B-A3B-6bit`
  - Hugging Face tags it as `Image-Text-to-Text`, `MLX`, `Safetensors`, `qwen3_5_moe`, and `6-bit`.
  - Model card usage shows `python -m mlx_vlm.generate --model mlx-community/Qwen3.6-35B-A3B-6bit --prompt "Describe this image." --image <path_to_image>`.
  - Approximate model size shown by Hugging Face: 29.1 GB.
- Setup should also detect already-downloaded compatible models under `~/.cache/huggingface/hub/models--*` and prefer an installed compatible model over downloading a new one.
- Never auto-download large models. Show source repo, approximate disk size, license, local storage path, and a cancellation path before starting.
- Prefer invoking a small helper process or local server boundary for MLX inference rather than embedding Python directly in Swift. The helper should accept an image path or temporary in-memory export, prompt text, selected model ID/path, token budget, and return streamed or chunked text. Temporary image files, if needed for MLX tooling, must be deleted after the request.

Primary references:

- MLX-VLM GitHub: https://github.com/Blaizzy/mlx-vlm
- Hugging Face MLX docs: https://huggingface.co/docs/hub/en/mlx
- Recommended model card: https://huggingface.co/mlx-community/Qwen3.6-35B-A3B-6bit

## Model-Agnostic Assistant Harness

Research date: 2026-05-24. Updated 2026-05-26 for general terminal agent support, delegated write planning, current-session history boundaries, recent-file rewrite follow-ups, named-grant targeting, folder-list file follow-ups, and state-first recent source references. Use for `ASSIST-016` through `ASSIST-038`.

Product target:

- Pixel Pane should own the assistant tool layer. Models may request or imply tool use, but app code executes tools, validates permissions, packs context, and records sources.
- The harness must work for native tool-calling APIs, OpenAI-compatible local servers, MLX command/server paths, and weak user-selected local models that only return plain text.
- Model adapters should declare capabilities instead of branching feature behavior throughout the UI. Minimum capability fields: text chat, image input, native tool calling, structured-output reliability, streaming, context budget, local/cloud route, and image input format.
- Treat files, OCR text, images, and tool outputs as untrusted data. Retrieved content can inform answers but must not expand permissions, trigger writes, or override user/app instructions.

Tool-use conclusions:

- OpenAI, Anthropic, MCP, Hugging Face, and llama.cpp all describe tool/function calling as a loop where the model requests a tool and the application or server-side executor runs it. Pixel Pane should keep the executor deterministic and app-owned.
- Use JSON-schema-like tool definitions internally even when a model route cannot receive native tool schemas. This keeps tool names, inputs, outputs, source IDs, and validation consistent across adapters.
- Native tool calling is an optimization, not a requirement. For non-native local models, Pixel Pane should use deterministic intent routing for obvious app-state/file/write/image cases and a structured prompt fallback only where safe.
- For delegated local write tasks, the selected model should plan the draft content/target as structured JSON, while the app validates grant boundaries and stages the existing confirmation-gated write proposal. Avoid requiring the user to provide exact content when the prompt explicitly delegates that judgment to the assistant.
- Delegated write planning may include bounded prior turns from the active chat to resolve references like "these results" or "that output." It must not include hidden global history or auto-restored latest-chat content.
- Rewrite/format follow-ups for a recently staged or read file should remain model-agnostic: the app resolves the recent granted file, reads current content through Local Files, and asks the selected model only to return replacement content that is still grant-validated and confirmation-gated.
- Folder targeting for delegated writes and folder listings should be app-owned. If the user names or slightly mistypes a granted folder, Pixel Pane should resolve the intended grant before model generation or write staging, and constrain selected-model target paths to that grant before confirmation.
- Folder-listing observations should include visible child files as structured sources so follow-up references can route through the app-owned read tool before model generation. The selected model may reason over the read result, but it should not need to invent file paths from plain transcript text.
- Recent structured observations should take precedence over broad grant inventory and fresh file search. A question that points at "these files" or a named recent source should resolve from tool state first, then ask the selected model only when the app does not have an actionable observation.
- Tool outputs should be high-signal and source-aware: stable source IDs, display path, snippet/range/truncation metadata, and a short result body. Avoid dumping whole files unless the user explicitly asks and the context budget allows it.
- Terminal execution, when enabled, should remain an app-owned local tool rather than prompt-only behavior: run from existing local working directories, capture stdout/stderr/exit code with timeout/output caps, require confirmation for risky commands, and treat terminal output as untrusted data. File reads/writes still enforce the user-granted file boundary, but general system-inspection terminal commands do not need a file grant.

Open-source agent patterns reviewed:

- Cline exposes project file editing and terminal command execution as agent capabilities while keeping edits/commands visible and approval-aware. Pixel Pane should borrow the pattern of real terminal observations feeding the next assistant step, while keeping file reads/writes grant-checked and risky terminal commands confirmation-gated.
- OpenHands documents a structured action-observation tool system with schema validation, executors, tool registry, and terminal/file tools. Pixel Pane's Swift harness should keep the same separation: planner/request, validated executor, structured observation, and stored tool state.
- aider's editing docs emphasize model-specific edit formats such as whole-file and search/replace blocks. Pixel Pane should avoid trusting weak models to freehand edits directly; instead, it should parse/stage local write proposals and apply exact file mutations only after confirmation.
- OpenCode and pi both emphasize a model-agnostic coding-agent layer where providers are interchangeable and the agent runtime owns session state, file operations, terminal execution, and UI events. Pixel Pane should follow that split: Local/Cloud is only a model route, while the harness owns tools and observations.

File access conclusions:

- User-granted file/folder access remains the trust boundary. Permission checks must happen in the file tool executor, not in prompts.
- File tools should cover listing grants, searching grants, reading bounded text, explaining unavailable access, and staging write proposals.
- Confirmed writes stay local-only and confirmation-gated. Retrieved file content must never be able to cause a write without a visible user confirmation naming the exact target path.
- Because the app is currently Direct-distributed and not sandboxed, the app still needs to behave as if user grants are the product permission boundary.

Image context conclusions:

- Normalize active screenshots, user-selected images, and pasted/clipboard images into one `AssistantImageContext` path with typed parts: original image when available, OCR text when extracted, source label, privacy/routing flags, and transient storage metadata.
- Vision-capable routes can receive image input. Text-only routes should receive OCR/text fallback and clear labeling that image pixels were not analyzed.
- MLX-VLM command-line usage accepts image paths; any temporary image export must be cleaned up on success, cancellation, timeout, and error. Cloud image input remains gated by Cloud Mode and explicit route labeling.
- Chat history should continue to avoid persisting screenshot or attached-image pixels by default.

Context packing conclusions:

- Context packing should budget source groups separately: user question, system/tool instructions, prior chat turns, OCR, image OCR, file snippets, and tool results.
- Small local context windows should degrade by trimming or summarizing lower-priority sources, not by adding placeholder sections like "Files: none".
- Source boundaries should be visible in both prompts and UI metadata so retrieved content is clearly data, not instructions.

Session/history conclusions:

- The active chat session is the memory boundary for prompt packing and delegated write planning.
- Fresh assistant chats should start with no prior turns or tool state; saved chats can be restored only by explicit history selection.
- Capture-context chats may include the active capture/OCR context and same-session follow-ups without persisting screenshot pixels.

Safety conclusions:

- Prompt injection is a core risk whenever the assistant reads files, OCR, webpages, or images. Use defense in depth: least privilege, structured data/instruction separation, deterministic argument validation, human confirmation for side effects, and local audit metadata for blocked/downgraded actions.
- Do not rely on a model to decide whether it has file access or whether a file write is safe. The model can propose; the app checks.

Primary references:

- OpenAI function calling: https://developers.openai.com/api/docs/guides/function-calling
- OpenAI prompt injection overview: https://openai.com/safety/prompt-injections/
- Anthropic tool use, defining tools: https://platform.claude.com/docs/en/agents-and-tools/tool-use/define-tools
- Anthropic computer-use security considerations: https://platform.claude.com/docs/en/agents-and-tools/tool-use/computer-use-tool
- Model Context Protocol tools spec: https://modelcontextprotocol.io/specification/draft/server/tools
- Model Context Protocol security best practices: https://modelcontextprotocol.io/docs/tutorials/security/security_best_practices
- OWASP LLM Prompt Injection Prevention Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/LLM_Prompt_Injection_Prevention_Cheat_Sheet.html
- MLX-LM GitHub: https://github.com/ml-explore/mlx-lm
- MLX-VLM GitHub: https://github.com/Blaizzy/mlx-vlm
- Hugging Face chat templates and tool use: https://huggingface.co/docs/transformers/chat_extras
- Hugging Face multimodal chat templates: https://huggingface.co/docs/transformers/chat_templating_multimodal
- llama.cpp function calling: https://github.com/ggml-org/llama.cpp/blob/master/docs/function-calling.md
- Cline repository: https://github.com/cline/cline
- OpenHands tool system docs: https://docs.openhands.dev/sdk/arch/tool-system
- aider edit formats: https://aider.chat/docs/more/edit-formats.html
- OpenCode repository: https://github.com/opencode-ai/opencode
- pi agent harness repository: https://github.com/earendil-works/pi
- pi dashboard overview: https://pi-dashboard.dev/
- Apple macOS App Sandbox file access: https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox
- Apple security-scoped bookmark access: https://developer.apple.com/documentation/professional-video-applications/enabling-security-scoped-bookmark-and-url-access
- Apple `NSOpenPanel.canChooseDirectories`: https://developer.apple.com/documentation/appkit/nsopenpanel/canchoosedirectories
- Apple Vision `VNRecognizeTextRequest`: https://developer.apple.com/documentation/vision/vnrecognizetextrequest
- Apple Photos picker and `Transferable`: https://developer.apple.com/documentation/PhotoKit/bringing-photos-picker-to-your-swiftui-app

## Global Hotkey

- Product decision: alpha uses Carbon `RegisterEventHotKey` for the default `Command + Shift + Space` capture shortcut.
- The Carbon path should not require Accessibility permission for the default alpha shortcut.
- `CGEventTap` is deferred unless Carbon fails full-screen or foreground-app QA. If added later, treat Accessibility permission as required for the `CGEventTap` path.
- On macOS Sequoia, `RegisterEventHotKey` registrations using only Shift/Option are restricted; keep the default shortcut on Command + Shift + Space and reject unsupported combinations.

Primary references:

- Apple Developer Forums `RegisterEventHotKey` Sequoia modifier restriction: https://developer.apple.com/forums/thread/763878
- Apple `CGEvent.tapCreate`: https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)
- Apple `AXIsProcessTrustedWithOptions`: https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions

## Updates

- Direct distribution should use Developer ID signing, notarization, Sparkle, EdDSA update signing, and an appcast feed.
- Sparkle expects an appcast URL in app metadata and incrementing bundle versions.

Primary reference:

- Sparkle documentation: https://sparkle-project.org/documentation/

## Cloud AI Proxy

- The app must not ship Anthropic API keys.
- Backend should stream responses to the client using SSE or an equivalent streaming bridge.
- Anthropic Messages streaming uses server-sent events such as `message_start`, `content_block_delta`, `message_delta`, and `message_stop`.

Primary references:

- Anthropic streaming docs: https://platform.claude.com/docs/en/build-with-claude/streaming
- Cloudflare Workers streaming docs: https://developers.cloudflare.com/workers/runtime-apis/streams/

## Subscriptions

- RevenueCat should be entitlement-based.
- The app should check CustomerInfo entitlements to decide whether Pro/Student features are active.
- For Direct distribution, Stripe + RevenueCat is the current product direction; do not add StoreKit unless the distribution decision changes.

Primary references:

- RevenueCat docs: https://www.revenuecat.com/docs/
- RevenueCat SDK quickstart / entitlements: https://www.revenuecat.com/docs/getting-started/quickstart
