# Claude Project Instructions

This project is designed to be built with Claude/Codex over many sessions.

Before making changes, read:

1. `workflow/README.md`
2. `workflow/status.md`
3. `workflow/backlog.md`
4. `workflow/references.md` when the task depends on platform/service specifics

## Key Paths

- `PixelPane/` contains the Xcode/macOS app.
- `docs/` contains product and architecture docs.
- `workflow/` contains the active build process, story backlog, prompts, status, decisions, references, and QA checklist.

## Rules For Work Sessions

- Work only on the selected story ID unless blocked.
- Inspect relevant code before editing.
- Keep unrelated refactors out of story work.
- Build after meaningful code changes:

```bash
xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build
```

- Update `workflow/status.md` before ending a session.
- Update the relevant story status in `workflow/backlog.md` before ending a session.
- Add any major decision to `workflow/decisions.md`.

## Story Workflow

- If asked "where am I?", answer from `workflow/status.md` and `workflow/backlog.md`.
- If asked to "start working" (or "begin", "keep going", "continue working" with no specific story), enter autonomous mode per `workflow/README.md` "Autonomous Mode": work the current recommended story to In Review, then continue to the next story, stopping only when human intervention is required.
- If asked to complete an epic, complete the next incomplete story in that epic, not the whole epic in one pass.
- If asked to complete a story, find the story by ID in `workflow/backlog.md` and follow its acceptance criteria.
- If a decision blocks the story, mark it `Blocked`, document the decision needed, and stop.
- If during a story you discover meaningful work that is out of scope (real bug, follow-up refactor, missing QA/docs, implied decision), add a new story to the right epic in `workflow/backlog.md` per the auto-created stories rule in `workflow/README.md`.

## Current State

Use `workflow/status.md` as the source of truth for current progress, open decisions, and the next best story.
