# Pixel Pane

Pixel Pane is a local-first, notch-native assistant shell for macOS. It keeps capture/OCR, explicit file grants, local/cloud routing, and confirmation-based side effects inside the native app.

Current engineering state: the unreliable pre-rearchitecture agent path has been replaced by the `AGENTR` durable runtime described in `docs/architecture.md` and `workflow/agent-architecture-revision.md`.

## Start Here

- Agent workflow: `workflow/README.md`
- Current status: `workflow/status.md`
- Active backlog: `workflow/backlog.md`
- Product architecture: `docs/architecture.md`
- Backend contract: `docs/backend-api.md`

## Build

```bash
PixelPane/Scripts/verify-debug-build.sh
```
