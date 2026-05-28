# Pixel Pane LLM Workflow

This folder is the operating system for building Pixel Pane with coding agents. Start every long-running session here before touching code.

## Current Project State

- Product docs live in `docs/`, but the current product direction is tracked here in `workflow/`.
- Swift app lives in `PixelPane/`.
- Pixel Pane is a local-first, notch-native assistant shell for macOS.
- Assistant execution now routes through Agent Kernel V2.
- AGENTV2 is app-owned and model-agnostic, with product policy in Swift rather than internal prose prompts.
- Current Xcode target is macOS 15.2+ because the capture foundation uses `SCScreenshotManager.captureImage(in:)`.

## Start Here Each Session

1. Read this file.
2. Read `workflow/status.md`.
3. Read `workflow/backlog.md`.
4. Pick one story ID from the backlog.
5. Read `workflow/decisions.md` when product direction, safety, local/cloud routing, files, terminal, distribution, or privacy matters.
6. Read the product docs when the story needs product, release, architecture, or backend details:
   - `docs/architecture.md`
   - `docs/backend-api.md`
   - `docs/prd.md`
   - `docs/project-brief.md`
   - `docs/release.md`
7. Read `workflow/references.md` if the story touches macOS APIs, local runtimes, backend, updates, payments, terminal execution, or researched specifics.
8. Inspect the relevant Swift files before editing.
9. Keep changes scoped to the story.
10. Build with the local verification wrapper:

```bash
PixelPane/Scripts/verify-debug-build.sh
```

Or run the underlying Xcode build directly:

```bash
xcodebuild -project PixelPane/PixelPane.xcodeproj -scheme PixelPane -configuration Debug build
```

11. Update `workflow/status.md` and `workflow/backlog.md` before ending the session.

## How To Use Stories With LLMs

You should be able to say:

```text
Complete AGENTV2-005.
```

or:

```text
Complete the next story in the current roadmap.
```

The agent should find the story in `workflow/backlog.md`, complete only that story, build, update the backlog/status, and tell you what is next.

If you paste instructions manually, use:

```text
Use workflow/README.md, workflow/status.md, and workflow/backlog.md as operating context.
Work only on this story unless you find a blocker.
Before editing, inspect the relevant code.
After editing, build the app and update workflow/status.md and workflow/backlog.md with what changed, verification, blockers, and next suggested story.
Do not rewrite unrelated docs or refactor unrelated code.
```

For large stories, ask the LLM to split it into checklist items in `workflow/backlog.md` first.

## Story Status Values

Use these exact values in `workflow/backlog.md`:

- `Not Started`
- `In Progress`
- `Blocked`
- `In Review`
- `Done`

## Definition Of Done

A story is done only when:

- Acceptance criteria are implemented or explicitly deferred.
- The app builds, or the failure is documented with the exact reason.
- User-facing behavior is described in `workflow/status.md`.
- Any architectural decision made during the work is recorded in `workflow/decisions.md`.
- The next recommended story is listed.
- `workflow/backlog.md` has the updated story status.

## Agent Handoff Format

At the end of every meaningful work session, update `workflow/status.md` with:

- What changed
- Files changed
- Verification
- Current blockers
- Next best task
- Notes for the next agent

This avoids losing context when conversations get long or switch between agents.

## Answering "Where Am I?"

When asked where the project stands, an agent should read `workflow/status.md` and `workflow/backlog.md`, then answer:

- current phase
- current recommended story
- stories in review/done
- blockers/open decisions
- exact next command or prompt to use

## Autonomous Mode ("Start Working")

When the user says "start working", "begin", "keep going", or similar without naming a story, work continuously until a stop condition is reached.

### Loop

1. Read `workflow/status.md` and `workflow/backlog.md`.
2. Pick the current recommended story from `workflow/status.md`. If none, pick the next `Not Started` story in the active roadmap. If that is ambiguous, stop and ask.
3. Complete the story per the Definition Of Done.
4. Build the app.
5. Update `workflow/status.md` and `workflow/backlog.md`.
6. Pick the next story and repeat.

### Stop Conditions

Stop and report to the user when any of these are true:

- An architectural or product decision is needed that should be recorded in `workflow/decisions.md`. Record it as `Proposed`, mark the story `Blocked`, and stop.
- The story requires user-only input: permissions, secrets, signing keys, hosting choices, vendor selection, billing config.
- Manual QA on the user's machine is the only way to verify the story (e.g., resetting TCC permissions, testing on a fresh Mac, multi-display tests requiring specific hardware).
- A build failure cannot be fixed without a non-trivial tradeoff.
- The next candidate story has status `Blocked` or its body lists an unresolved Blocker/Decision.
- There is no obvious next story.

When stopping, report concisely: stories completed in this run, what triggered the stop, and the exact decision or input needed from the user.

### Auto-Created Stories

If during work you discover something worth tracking that is out of scope for the current story, add a new story rather than expanding scope. Examples: a real bug unrelated to current acceptance criteria, a follow-up refactor that is not strictly required, missing QA/docs that warrant their own checklist, an implied decision the user should make later.

Rules:

- Use the appropriate existing ID prefix and the next available number (e.g., `AGENTV2-021`).
- Add a row to the current story table and a story section below following `workflow/story-template.md`.
- In the story body, add a line: `Auto-created during <STORY-ID> on YYYY-MM-DD.`
- Default status `Not Started`. Use `Blocked` if it needs a decision and document the decision under Blockers / Decisions.
- Do not auto-create stories for trivial cleanups you can do inline within scope, or for speculative future features that the user has not asked for.

### Single-Story Mode

`Complete STORY-ID` keeps its existing behavior — that runs only one story and stops. Autonomous mode is opt-in via "start working".

## Architectural Decisions

If a decision affects product scope, minimum OS, privacy behavior, backend ownership, distribution, or pricing, record it in `workflow/decisions.md`.

Do not hide major decisions inside chat history.

## Recommended Build Order

1. Prune to a stable shell
2. Build the AGENTV2 kernel with fixture models
3. Define typed capabilities
4. Add thin model adapters
5. Integrate, verify, and harden

The goal is to validate a deterministic local-first runtime before commercial or expansion features.
