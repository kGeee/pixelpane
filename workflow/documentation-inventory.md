# Documentation Inventory

Last updated: 2026-05-29

This inventory was created by `DOCREV-001`. It classifies repository documentation by whether it should be kept, rewritten, or deleted before the `AGENTR` implementation sprint starts.

## Delete

The files in this class were deleted in `DOCREV-002`; their useful evidence has been folded into `workflow/agent-architecture-revision.md` or the new `AGENTR` sprint.

| Deleted class | Reason |
|---|---|
| Old AGENTV2 architecture docs | Long stale architecture narratives superseded by durable-run architecture decisions. |
| Captured chat failure exports | Failure corpus inputs now summarized as FC-001 through FC-012. |
| Old standalone product research report | Stale citation markup and not active workflow context. |
| Unrelated generated story artifact | Not project documentation or runtime fixture source. |
| Duplicate root agent instruction file | Keep a single root instruction source in `AGENTS.md`. |

## Rewrite

These files remain useful but must be rewritten or compacted around the post-revision architecture.

| File | Rewrite focus |
|---|---|
| `AGENTS.md` | Updated root operating instructions, build command, and current workflow wording. |
| `README.md` | Replaced stub with a compact project overview and links to active docs. |
| `docs/architecture.md` | Rewritten around durable run store, checkpointed runner, provider tiers, policy-owned side effects, evidence packets, and UI projection. |
| `docs/project-brief.md` | Rewritten around the product shell, local-first constraints, and rearchitecture success definition. |
| `docs/prd.md` | Rewritten around current product/runtime requirements for `AGENTR`. |
| `docs/backend-api.md` | Updated to describe the backend as a model route under the new agent runtime. |
| `docs/release.md` | Kept release baseline and aligned runtime QA wording. |
| `PixelPane/Backend/README.md` | Updated backend privacy and local-runtime ownership notes. |
| `workflow/README.md` | Rewritten start-here flow for post-revision work. |
| `workflow/status.md` | Compacted to current state: `DOCREV` active, `AGENTR` next, AGENTV2 history as audit-only. |
| `workflow/backlog.md` | Compacted completed AGENTV2 detail; keeps `DOCREV`, `AGENTR`, and only necessary audit references. |
| `workflow/decisions.md` | Current and compact. |
| `workflow/references.md` | Updated to `AGENTR` runtime direction and kept researched source links. |
| `workflow/qa-checklist.md` | Rewritten around durable run, provider tier, evidence packet, approval/recovery, and UI projection QA. |

## Keep

These files are currently useful as-is or should remain as active reference during implementation.

| File | Reason |
|---|---|
| `workflow/agent-architecture-revision.md` | Current source of truth for architecture findings until `AGENTR` is implemented and the active architecture doc is rewritten. |
| `workflow/story-template.md` | Generic workflow template; still valid. |

## Code-Adjacent Notes

- The current agent fixture scripts are not docs, but their names and comments preserve AGENTV2 framing. Handle them in `AGENTR-010` or earlier if fixture infrastructure is replaced.
- `PixelPane/PixelPane/AgentKernel/AgentKernelDebugExportV2.swift` is source code, not documentation, but it contains an explicit temporary debug-export marker. Delete it in `AGENTR-008` after durable trace export exists.
