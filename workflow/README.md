# Pixel Pane Workflow

Last updated: 2026-05-29

This folder is the active operating context for long-running coding-agent work.

## Start Here

1. Read `workflow/status.md`.
2. Read `workflow/backlog.md`.
3. Read `workflow/decisions.md` when touching architecture, files, terminal/process behavior, local/cloud routing, privacy, release, or permissions.
4. Read `workflow/references.md` only when external research or platform specifics matter.
5. Read `docs/architecture.md` for the current agent architecture.
6. Inspect relevant code before editing.
7. Work one story ID at a time.
8. Update `workflow/status.md` and `workflow/backlog.md` before finishing meaningful work.

## Current Direction

The AGENTR durable runtime is the active architecture. AGENTV2 implementation names are historical audit context only.

The rearchitecture sprint is complete. The remaining pre-beta gates are manual notch-shell and real-provider checks recorded in `workflow/qa-checklist.md`.

## Build

Use the wrapper:

```bash
PixelPane/Scripts/verify-debug-build.sh
```

The underlying Xcode build is:

```bash
xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build
```

## Story Workflow

- If the user asks "where am I?", summarize `workflow/status.md` and current story statuses in `workflow/backlog.md`.
- If the user says "complete STORY-ID", complete that story, verify as required, and update workflow files.
- If a story is too large, split it in `workflow/backlog.md` before implementation.
- If a new meaningful follow-up appears, add it to the active sprint instead of burying it in prose.
- Do not preserve stale docs or obsolete code just because they existed before; this beta can delete and replace old architecture.

## Active Architecture Sources

- Current architecture: `docs/architecture.md`
- Revision findings: `workflow/agent-architecture-revision.md`
- Decisions: `workflow/decisions.md`
- Current work: `workflow/status.md` and `workflow/backlog.md`
