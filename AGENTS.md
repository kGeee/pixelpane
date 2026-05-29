# Agent Instructions

This repo is built with long-running LLM assistance. Before doing any work, read:

1. `workflow/README.md`
2. `workflow/status.md`
3. `workflow/backlog.md`
4. `workflow/decisions.md`
5. `workflow/references.md` if the task touches macOS APIs, backend, updates, payments, or researched agent architecture specifics

## Project Layout

- Product docs: `docs/`
- Swift app: `PixelPane/`
- LLM workflow, story backlog, prompts, decisions, QA: `workflow/`

## Operating Rules

- Keep implementation changes inside `PixelPane/` unless the task is documentation/workflow.
- Keep tracking updates inside `workflow/`.
- Work one story ID at a time.
- Inspect relevant files before editing.
- Do not broaden scope into backend, auth, monetization, PDF import, browser automation, or expansion features unless the story asks for it.
- Treat AGENTV2 code as historical implementation/audit input. The active path is the `AGENTR` durable runtime.
- Record product or architecture decisions in `workflow/decisions.md`.
- Update `workflow/status.md` before finishing meaningful work.
- Update the story status in `workflow/backlog.md` before finishing meaningful work.

## Story Workflow

- If the user asks "where am I?", summarize `workflow/status.md` and the current statuses in `workflow/backlog.md`.
- If the user says "complete Epic N", complete only the next incomplete story in that epic, then report the next story.
- If the user says "complete STORY-ID", find that story in `workflow/backlog.md`, complete it, build, and update status/backlog.
- If a story is too large, split it into smaller checklist items inside `workflow/backlog.md` before implementation.

## Build Command

```bash
PixelPane/Scripts/verify-debug-build.sh
```

## Current Priority

Follow `workflow/status.md`. The current recommended story is listed under `Current Recommended Story`.
