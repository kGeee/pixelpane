# Pixel Pane

Pixel Pane is a local-first, notch-native assistant shell for macOS. It keeps capture/OCR, explicit file grants, local/cloud routing, and confirmation-based side effects inside the native app.

Current engineering state: the app runs through the `AGENTR` durable runtime. Local agent instructions, workflow notes, and architecture docs live only in this checkout and are intentionally ignored by git.

## Start Here

- App source: `PixelPane/`
- Local-only agent context: `AGENTS.md`, `docs/`, `workflow/`, `.claude/`

## Build

```bash
PixelPane/Scripts/verify-debug-build.sh
```
