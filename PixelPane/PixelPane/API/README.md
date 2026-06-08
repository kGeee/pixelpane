# API

Pixel Pane Cloud backend client. Only active when the user selects Cloud Mode in Settings.

## Files

| File | Purpose |
|---|---|
| `CloudAIBackend.swift` | Conforms to `AIBackend`. Sends requests to the Pixel Pane Cloud Worker (`/v1/stream`), streaming SSE events back as `AIBackendEvent` values. Respects the user's image-context and location-sharing opt-ins. |
| `CloudAuthTokenProvider.swift` | Obtains a bearer token from the Cloud API using the device's stable identifier. Caches the token in the Keychain (with a per-launch fallback) so it isn't re-fetched every request. |

## Cloud backend

The Worker source lives in `PixelPane/Backend/`. It proxies requests to Anthropic, keeps the API key server-side, and enforces a free-tier daily quota via Cloudflare KV. See `PixelPane/Backend/README.md` for setup instructions.

## Privacy

The backend never receives OCR text or screenshots unless the user explicitly opts in to image context in Settings. Location is obfuscated to city level before being sent.

## Extension points

- **Custom cloud endpoint** — `CloudAIBackend` reads `baseURL` from `AIRoutingSettings`; point it at a self-hosted Worker to use your own quota or model.
- **Auth scheme** — replace `CloudAuthTokenProvider` to implement a different authentication flow (e.g. user accounts, OAuth).
