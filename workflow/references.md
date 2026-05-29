# Pixel Pane References

Last updated: 2026-05-29

Use this file for researched or externally inspired constraints that should guide implementation.

## AGENTR Runtime Direction

- Durable sessions, runs, steps, waits, evidence, side effects, artifacts, and trace records are the source of truth. Visible chat is a projection.
- Keep a provider-neutral runtime boundary: model adapters are replaceable, while Pixel Pane owns tool validation, permissions, approvals, side effects, evidence, and UI projection.
- Treat mature coding-agent systems as architectural inspiration only. Do not copy their prompts or preserve Pixel Pane's old runtime shape.
- Gate agent behavior by provider capability tier. Full agent mode requires native tool calls or strict structured output; plain chat providers can synthesize only.
- File access, terminal execution, local server lifecycle, receipts, errors, approvals, and cancellation are control-plane events. They should not be serialized as user chat turns.
- Fixture models and store/runner tests should be the first integration target. Real Apple, MLX, cloud, Ollama, and OpenAI-compatible adapters should not shape the runtime until fixture coverage proves the state machine.

## Architecture Revision Research Baseline

Use primary sources when executing `ARCHREV-003`. Keep the final research artifact compact and focused on patterns Pixel Pane can adopt.

- OpenAI Agents SDK:
  - Agents and runner orchestration: https://openai.github.io/openai-agents-python/agents/
  - Tracing for LLM generations, tool calls, handoffs, guardrails, and custom events: https://openai.github.io/openai-agents-python/tracing/
  - Tool guardrails: https://openai.github.io/openai-agents-js/guides/guardrails
  - Handoffs as tool-like delegation with schema validation: https://openai.github.io/openai-agents-python/handoffs/
- Anthropic Claude Code:
  - Tool and permission settings, allow/ask/deny rules, additional directories, and hooks: https://docs.anthropic.com/en/docs/claude-code/settings
  - MCP tool/resource integration and output limits: https://docs.anthropic.com/en/docs/claude-code/mcp
- LangGraph:
  - Durable execution, checkpointing, deterministic replay, resumability, and human-in-loop interruption: https://docs.langchain.com/oss/python/langgraph/durable-execution
- Microsoft AutoGen Core:
  - Runtime-managed agents, serializable messages, and runtime lifecycle: https://microsoft.github.io/autogen/stable/user-guide/core-user-guide/framework/agent-and-agent-runtime.html
  - Message and communication model: https://microsoft.github.io/autogen/stable/user-guide/core-user-guide/framework/message-and-communication.html
  - Tool agents and cancellation-aware tool calling: https://microsoft.github.io/autogen/dev/reference/python/autogen_core.tool_agent.html
- Google Agent Development Kit:
  - Sessions, events, state, and session lifecycle: https://google.github.io/adk-docs/sessions/session/
  - Runtime event loop: https://google.github.io/adk-docs/runtime/
  - Callback patterns for guardrails, state, logging, caching, and artifact handling: https://google.github.io/adk-docs/callbacks/design-patterns-and-best-practices/
- LlamaIndex Workflows:
  - Event-driven workflows and instrumentation: https://docs.llamaindex.ai/en/stable/module_guides/workflow/
  - Agent state and context: https://docs.llamaindex.ai/en/stable/understanding/agent/state/
  - Human-in-loop workflow events: https://docs.llamaindex.ai/en/stable/understanding/agent/human_in_the_loop/
- Goose / MCP local-agent architecture:
  - Extension/tool model: https://block.github.io/goose/docs/getting-started/using-extensions
  - Architecture overview: https://block.github.io/goose/docs/category/architecture-overview
- Cursor:
  - Dynamic context discovery: https://cursor.com/blog/dynamic-context-discovery
  - Background agents: https://docs.cursor.com/background-agents
  - Agent checkpoints: https://docs.cursor.com/agent/chat/checkpoints
  - Agent tools: https://docs.cursor.com/agent/tools
  - Long-running autonomous coding research: https://cursor.com/blog/scaling-agents
- Windsurf Cascade:
  - Cascade overview, plans, tools, checkpoints, and reverts: https://docs.windsurf.com/windsurf/cascade
  - Memories, rules, AGENTS.md, activation modes, and context budget: https://docs.windsurf.com/windsurf/cascade/memories

## macOS And Product Constraints

- The app remains macOS 15.2+ because screen capture uses the modern ScreenCaptureKit path already wired in the app.
- Direct distribution remains the target path with Developer ID and Sparkle.
- App sandbox remains disabled for local-first agent capabilities unless a future release decision changes distribution strategy.
- Local files require explicit user grants. Screenshots/images remain transient unless a future export feature says otherwise.
- Risky local effects require app-owned confirmation gates: writes, terminal commands, installs, network actions, privileged actions, and process control.

## Cloud Mode Constraints

- Cloud Mode is opt-in and routed through Pixel Pane's backend proxy.
- Provider keys never ship in the app.
- The backend is only a model route. It does not own local permissions, file access, terminal execution, write approval, source tracking, durable run state, evidence, side effects, or agent policy.
