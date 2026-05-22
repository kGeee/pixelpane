# Pixel Pane Backend

Cloudflare Workers proxy for Pixel Pane Cloud Mode. The Worker implements the `/v1` contract in `docs/backend-api.md`, keeps the Anthropic API key server-side, requires a Pixel Pane app token, normalizes Anthropic streaming into Pixel Pane SSE events, and uses KV for free-tier daily quota.

## Local Commands

```bash
npm install
npm run typecheck
npx wrangler deploy --dry-run
```

## Required Cloudflare Setup

1. Create a KV namespace for daily quota and replace the placeholder IDs in `wrangler.toml`.
2. Configure secrets:

```bash
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put APP_AUTH_SECRET
```

3. Optional for local/dev smoke tests only:

```bash
npx wrangler secret put DEV_APP_TOKEN
```

`DEV_APP_TOKEN` is accepted as a static bearer token when present. Production clients should use HMAC app tokens issued by the `FOUND-005` auth-token flow.

## Privacy Rules

- Do not log OCR text, screenshots, prompts, questions, or model output.
- `X-PixelPane-Request-ID` is safe to log because the app generates it as a random UUID per action attempt.
- Provider keys stay in Worker secrets only; the macOS app never stores them.
