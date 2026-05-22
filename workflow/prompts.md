# LLM Prompt Cookbook

Use these prompts to keep long-running Claude/Codex sessions consistent.

## Start A New Work Session

```text
You are helping me build Pixel Pane.

Before doing work:
1. Read workflow/README.md.
2. Read workflow/status.md.
3. Read workflow/backlog.md.
4. Find the story ID I provide.
5. Read workflow/references.md if the story touches macOS APIs, backend, updates, payments, or cloud AI.
6. Inspect relevant files before editing.

Rules:
- Keep changes scoped to the story.
- Do not rewrite unrelated docs.
- Do not add backend/auth/payment work unless the story asks for it.
- Build with:
  xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build
- Update workflow/status.md before finishing.
- Update workflow/backlog.md before finishing.
- Record any product/architecture decision in workflow/decisions.md.

Story:
[paste story ID here]
```

## Complete One Story

```text
Complete STORY-ID.

Follow AGENTS.md/CLAUDE.md.
Read workflow/status.md and workflow/backlog.md.
Work only on STORY-ID.
Build the app.
Update workflow/status.md and workflow/backlog.md.
Tell me what changed, verification, blockers, and the next best story.
```

## Start Working (Autonomous)

```text
Start working.

Follow CLAUDE.md and the "Autonomous Mode" section of workflow/README.md.
Read workflow/status.md and workflow/backlog.md.
Work the current recommended story to In Review, build, update workflow/status.md and workflow/backlog.md, then continue to the next story.
Stop when human intervention is required: architectural/product decision, missing credentials/permissions/vendor choice, manual QA only I can do, blocked story, or ambiguous next step.
If you discover work that is out of scope, create a new story in the right epic per the Auto-Created Stories rule.
When you stop, report: stories completed, what triggered the stop, and exactly what you need from me.
```

## Complete The Next Story In An Epic

```text
Complete the next incomplete story in Epic N.

Follow AGENTS.md/CLAUDE.md.
Use workflow/backlog.md to pick the next story.
Do not complete the whole epic in one pass.
Build the app.
Update workflow/status.md and workflow/backlog.md.
```

## Explain Where I Am

```text
Tell me where I am in the Pixel Pane project.

Read workflow/status.md and workflow/backlog.md.
Summarize:
- current phase
- active epic
- current recommended story
- stories in review/done
- blockers/open decisions
- what I should ask you to do next
Do not edit files.
```

## Ask For A Plan Only

```text
Read workflow/README.md, workflow/status.md, workflow/backlog.md, and this story.
Do not edit files yet.
Give me a concise implementation plan, risks, and any decisions you need from me.

Story:
[paste story ID here]
```

## Continue A Previous Task

```text
Continue the current Pixel Pane task.

First read:
- workflow/README.md
- workflow/status.md
- workflow/backlog.md

Then inspect the files changed in the last session.
Continue from the current state, do not restart.
Build when done and update workflow/status.md and workflow/backlog.md.
```

## Debug A Failure

```text
Debug this Pixel Pane failure.

Read workflow/README.md and workflow/status.md first.
Do not make broad refactors.
Find the smallest fix that preserves the current architecture.
After fixing, run:
  xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build

Failure:
[paste error/log here]
```

## Review A Completed Story

```text
Review this completed Pixel Pane story from a code-review stance.

Prioritize:
- bugs
- regressions
- missing acceptance criteria
- privacy mistakes
- architecture drift
- missing verification

Read:
- workflow/README.md
- workflow/status.md
- workflow/backlog.md
- the relevant story
- changed files

Report findings first, then summary.
Do not edit files unless I ask.
```

## Split A Large Epic Into Smaller Stories

```text
Read workflow/README.md, workflow/status.md, and workflow/backlog.md.
Review Epic N and split any oversized stories into smaller story IDs.

Each story should include:
- goal
- scope
- acceptance criteria
- suggested files
- verification
- blockers/decisions

Keep stories small enough for one focused coding session.
```

## End Of Session Checklist

Ask the LLM to complete this before ending:

```text
Before you finish:
1. Build the app or document why you could not.
2. Update workflow/status.md.
3. Update workflow/backlog.md story status/checklist.
4. Add any decision to workflow/decisions.md.
5. Tell me the next best story.
```
