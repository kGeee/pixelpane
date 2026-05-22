type Action = "translate" | "explain" | "simplify" | "ask" | "chat" | "study" | "menu" | "debug";
type Role = "user" | "assistant";

interface Env {
  ANTHROPIC_API_KEY: string;
  ANTHROPIC_MODEL?: string;
  APP_AUTH_SECRET?: string;
  DEV_APP_TOKEN?: string;
  FREE_DAILY_LIMIT?: string;
  RATE_LIMIT_KV?: KVNamespace;
}

interface PixelPaneRequest {
  schema_version: string;
  action: Action;
  capture: {
    source_type: string;
    ocr_text: string;
    detected_language?: string;
    created_at?: string;
  };
  target_language?: string;
  question?: string;
  conversation?: Array<{ role: Role; content: string }>;
  image?: {
    mime_type: "image/png" | "image/jpeg";
    data_base64: string;
    user_consented: boolean;
  };
  client_context?: {
    app_version?: string;
    platform?: string;
    locale?: string;
    timezone?: string;
    cloud_mode?: boolean;
  };
  limits?: {
    max_output_tokens?: number;
  };
}

interface AuthIdentity {
  subject: string;
  plan: "free" | "pro";
}

interface TokenRequest {
  schema_version: string;
  device_id: string;
  client_context?: {
    app_version?: string;
    platform?: string;
    locale?: string;
    timezone?: string;
  };
}

const schemaVersion = "2026-04-29";
const actionsWithImage = new Set<Action>(["explain", "ask", "study", "menu", "debug"]);
const encoder = new TextEncoder();

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const requestID = request.headers.get("X-PixelPane-Request-ID") ?? crypto.randomUUID();

    try {
      if (request.method !== "POST") {
        return jsonError("invalid_request", "Use POST for Pixel Pane action endpoints.", requestID, 405);
      }

      const pathname = new URL(request.url).pathname;
      if (isTokenPath(pathname)) {
        return issueToken(request, env, requestID);
      }

      const action = actionFromPath(pathname);
      if (!action) {
        return jsonError("invalid_request", "Unknown Pixel Pane endpoint.", requestID, 404);
      }

      const identity = await authenticate(request, env);
      if (!identity) {
        return jsonError("unauthorized", "A valid Pixel Pane app token is required.", requestID, 401);
      }

      const payload = await readPayload(request);
      const validationError = validateRequest(action, payload);
      if (validationError) {
        return jsonError(validationError.code, validationError.message, requestID, validationError.status);
      }

      const quota = await consumeQuota(env, identity);
      if (!quota.allowed) {
        return jsonError("rate_limited", "Cloud action limit reached.", requestID, 429, 3600);
      }

      return streamAnthropic(action, payload, env, identity, quota, requestID);
    } catch {
      return jsonError("server_error", "Cloud proxy failed before streaming.", requestID, 500);
    }
  }
};

function isTokenPath(pathname: string): boolean {
  return pathname.replace(/^\/v1\//, "").replace(/^\//, "").replace(/\/$/, "") === "auth/token";
}

function actionFromPath(pathname: string): Action | undefined {
  const segment = pathname.replace(/^\/v1\//, "").replace(/^\//, "").replace(/\/$/, "");
  return isAction(segment) ? segment : undefined;
}

async function issueToken(request: Request, env: Env, requestID: string): Promise<Response> {
  if (!env.APP_AUTH_SECRET) {
    return jsonError("server_error", "App auth secret is not configured.", requestID, 500);
  }

  const payload = await request.json<TokenRequest>();
  if (payload.schema_version !== schemaVersion || !isValidDeviceID(payload.device_id)) {
    return jsonError("invalid_request", "A valid anonymous device ID is required.", requestID, 400);
  }

  const issuedAt = Math.floor(Date.now() / 1000);
  const expiresAt = issuedAt + 24 * 60 * 60;
  const token = await signHMACToken(
    {
      sub: payload.device_id,
      device_id: payload.device_id,
      plan: "free",
      iat: issuedAt,
      exp: expiresAt
    },
    env.APP_AUTH_SECRET
  );

  return Response.json(
    {
      schema_version: schemaVersion,
      token,
      token_type: "Bearer",
      expires_at: new Date(expiresAt * 1000).toISOString(),
      device_id: payload.device_id
    },
    {
      headers: {
        "cache-control": "no-store",
        "x-pixelpane-request-id": requestID
      }
    }
  );
}

function isValidDeviceID(deviceID: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(deviceID);
}

function isAction(value: string): value is Action {
  return ["translate", "explain", "simplify", "ask", "chat", "study", "menu", "debug"].includes(value);
}

async function readPayload(request: Request): Promise<PixelPaneRequest> {
  if (!request.headers.get("content-type")?.includes("application/json")) {
    throw new Error("Expected JSON.");
  }

  return await request.json<PixelPaneRequest>();
}

function validateRequest(action: Action, payload: PixelPaneRequest): { code: string; message: string; status: number } | undefined {
  if (payload.schema_version !== schemaVersion || payload.action !== action) {
    return { code: "invalid_request", message: "Request schema or action does not match the endpoint.", status: 400 };
  }

  if (action !== "chat" && !payload.capture?.ocr_text?.trim()) {
    return { code: "empty_ocr_text", message: "No OCR text was provided.", status: 400 };
  }

  if (action === "translate" && !payload.target_language?.trim()) {
    return { code: "invalid_request", message: "Translate requires a target language.", status: 400 };
  }

  if ((action === "ask" || action === "chat") && !payload.question?.trim()) {
    return { code: "invalid_request", message: "Chat requires a question.", status: 400 };
  }

  if (payload.image) {
    if (!actionsWithImage.has(action)) {
      return { code: "image_not_allowed", message: "This endpoint does not accept image payloads.", status: 400 };
    }

    if (!payload.image.user_consented) {
      return { code: "image_not_allowed", message: "Image upload requires explicit user consent.", status: 400 };
    }

    if (!["image/png", "image/jpeg"].includes(payload.image.mime_type)) {
      return { code: "invalid_request", message: "Image must be PNG or JPEG.", status: 400 };
    }

    if (decodedBase64Size(payload.image.data_base64) > 5 * 1024 * 1024) {
      return { code: "payload_too_large", message: "Image payload is too large.", status: 413 };
    }
  }

  return undefined;
}

async function authenticate(request: Request, env: Env): Promise<AuthIdentity | undefined> {
  const token = request.headers.get("authorization")?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) {
    return undefined;
  }

  if (env.DEV_APP_TOKEN && token === env.DEV_APP_TOKEN) {
    return { subject: "dev-device", plan: "free" };
  }

  if (!env.APP_AUTH_SECRET) {
    return undefined;
  }

  return verifyHMACToken(token, env.APP_AUTH_SECRET);
}

async function verifyHMACToken(token: string, secret: string): Promise<AuthIdentity | undefined> {
  const parts = token.split(".");
  if (parts.length !== 3) {
    return undefined;
  }

  const [encodedHeader, encodedPayload, encodedSignature] = parts;
  const signatureInput = `${encodedHeader}.${encodedPayload}`;
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"]
  );
  const signature = base64URLDecode(encodedSignature);
  const isValid = await crypto.subtle.verify("HMAC", key, signature, encoder.encode(signatureInput));
  if (!isValid) {
    return undefined;
  }

  const payload = JSON.parse(new TextDecoder().decode(new Uint8Array(base64URLDecode(encodedPayload)))) as {
    sub?: string;
    device_id?: string;
    plan?: string;
    exp?: number;
  };

  if (payload.exp && payload.exp < Math.floor(Date.now() / 1000)) {
    return undefined;
  }

  const subject = payload.sub ?? payload.device_id;
  if (!subject) {
    return undefined;
  }

  return { subject, plan: payload.plan === "pro" ? "pro" : "free" };
}

async function signHMACToken(payload: Record<string, unknown>, secret: string): Promise<string> {
  const header = base64URLEncode(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const body = base64URLEncode(JSON.stringify(payload));
  const signatureInput = `${header}.${body}`;
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(signatureInput));
  return `${signatureInput}.${base64URLEncode(signature)}`;
}

async function consumeQuota(
  env: Env,
  identity: AuthIdentity
): Promise<{ allowed: boolean; remaining: number; resetAt: string }> {
  const limit = Math.max(0, Number.parseInt(env.FREE_DAILY_LIMIT ?? "10", 10));
  const resetAt = nextUTCMidnight();
  if (identity.plan === "pro") {
    return { allowed: true, remaining: Number.MAX_SAFE_INTEGER, resetAt };
  }

  if (!env.RATE_LIMIT_KV) {
    return { allowed: true, remaining: Math.max(0, limit - 1), resetAt };
  }

  const key = `quota:${new Date().toISOString().slice(0, 10)}:${identity.subject}`;
  const current = Number.parseInt((await env.RATE_LIMIT_KV.get(key)) ?? "0", 10);
  if (current >= limit) {
    return { allowed: false, remaining: 0, resetAt };
  }

  const next = current + 1;
  await env.RATE_LIMIT_KV.put(key, String(next), { expirationTtl: secondsUntilNextUTCMidnight() });
  return { allowed: true, remaining: Math.max(0, limit - next), resetAt };
}

async function streamAnthropic(
  action: Action,
  payload: PixelPaneRequest,
  env: Env,
  identity: AuthIdentity,
  quota: { remaining: number; resetAt: string },
  requestID: string
): Promise<Response> {
  if (!env.ANTHROPIC_API_KEY) {
    return jsonError("server_error", "Anthropic API key is not configured.", requestID, 500);
  }

  const upstream = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01"
    },
    body: JSON.stringify({
      model: env.ANTHROPIC_MODEL ?? "claude-sonnet-4-6",
      max_tokens: clamp(payload.limits?.max_output_tokens ?? 2048, 64, 4096),
      stream: true,
      system: systemPrompt(action),
      messages: buildMessages(action, payload)
    })
  });

  const upstreamBody = upstream.body;
  if (!upstream.ok || !upstreamBody) {
    const code = upstream.status === 429 ? "provider_overloaded" : "provider_error";
    return jsonError(code, "Cloud model request failed.", requestID, upstream.status === 429 ? 529 : 502);
  }

  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      controller.enqueue(sse("meta", {
        request_id: requestID,
        action,
        model: env.ANTHROPIC_MODEL ?? "server-configured",
        plan: identity.plan,
        remaining_cloud_actions: quota.remaining,
        reset_at: quota.resetAt
      }));

      const reader = upstreamBody.getReader();
      const decoder = new TextDecoder();
      let buffer = "";
      let accumulated = "";
      let inputTokens = 0;
      let outputTokens = 0;
      let stopReason = "end_turn";

      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) {
            break;
          }

          buffer += decoder.decode(value, { stream: true });
          const events = splitSSEEvents(buffer);
          buffer = events.remainder;

          for (const event of events.complete) {
            const data = parseSSEData(event);
            if (!data) {
              continue;
            }

            const parsed = JSON.parse(data) as AnthropicStreamEvent;
            if (parsed.type === "content_block_delta" && parsed.delta.type === "text_delta") {
              accumulated += parsed.delta.text;
              controller.enqueue(sse("snapshot", { text: accumulated }));
            } else if (parsed.type === "message_delta") {
              stopReason = parsed.delta.stop_reason ?? stopReason;
              outputTokens = parsed.usage?.output_tokens ?? outputTokens;
            } else if (parsed.type === "message_start") {
              inputTokens = parsed.message.usage.input_tokens ?? inputTokens;
              outputTokens = parsed.message.usage.output_tokens ?? outputTokens;
            } else if (parsed.type === "error") {
              controller.enqueue(sse("error", {
                error: {
                  code: "provider_error",
                  message: "Cloud model stream failed.",
                  request_id: requestID
                }
              }));
              controller.close();
              return;
            }
          }
        }

        if (buffer.trim()) {
          const data = parseSSEData(buffer);
          if (data) {
            const parsed = JSON.parse(data) as AnthropicStreamEvent;
            if (parsed.type === "content_block_delta" && parsed.delta.type === "text_delta") {
              accumulated += parsed.delta.text;
              controller.enqueue(sse("snapshot", { text: accumulated }));
            } else if (parsed.type === "message_delta") {
              stopReason = parsed.delta.stop_reason ?? stopReason;
              outputTokens = parsed.usage?.output_tokens ?? outputTokens;
            } else if (parsed.type === "message_start") {
              inputTokens = parsed.message.usage.input_tokens ?? inputTokens;
              outputTokens = parsed.message.usage.output_tokens ?? outputTokens;
            } else if (parsed.type === "error") {
              controller.enqueue(sse("error", {
                error: {
                  code: "provider_error",
                  message: "Cloud model stream failed.",
                  request_id: requestID
                }
              }));
              controller.close();
              return;
            }
          }
        }

        controller.enqueue(sse("done", {
          stop_reason: stopReason,
          input_tokens: inputTokens,
          output_tokens: outputTokens
        }));
        controller.close();
      } catch {
        controller.enqueue(sse("error", {
          error: {
            code: "provider_error",
            message: "Cloud model stream interrupted.",
            request_id: requestID
          }
        }));
        controller.close();
      }
    }
  });

  return new Response(stream, {
    headers: {
      "content-type": "text/event-stream; charset=utf-8",
      "cache-control": "no-store",
      "x-pixelpane-request-id": requestID
    }
  });
}

type AnthropicStreamEvent =
  | { type: "message_start"; message: { usage: { input_tokens?: number; output_tokens?: number } } }
  | { type: "content_block_delta"; delta: { type: "text_delta"; text: string } }
  | { type: "message_delta"; delta: { stop_reason?: string }; usage?: { output_tokens?: number } }
  | { type: "message_stop" }
  | { type: "error" };

function buildMessages(action: Action, payload: PixelPaneRequest): Array<Record<string, unknown>> {
  const messages: Array<Record<string, unknown>> = [];

  if (action === "ask" || action === "chat") {
    for (const turn of payload.conversation ?? []) {
      messages.push({ role: turn.role, content: turn.content });
    }
  }

  const prompt = userPrompt(action, payload);
  if (payload.image) {
    messages.push({
      role: "user",
      content: [
        { type: "text", text: prompt },
        {
          type: "image",
          source: {
            type: "base64",
            media_type: payload.image.mime_type,
            data: payload.image.data_base64
          }
        }
      ]
    });
  } else {
    messages.push({ role: "user", content: prompt });
  }

  return messages;
}

function systemPrompt(action: Action): string {
  const shared = "You are Pixel Pane, a concise assistant for screen captures. Do not mention hidden policies. Answer only from the provided OCR text and optional image context.";
  const prompts: Record<Action, string> = {
    translate: `${shared} Translate accurately and preserve formatting when useful.`,
    explain: `${shared} Explain what the user captured in practical terms.`,
    simplify: `${shared} Rewrite the captured text more simply while preserving meaning.`,
    ask: `${shared} Answer the user's follow-up using the capture and prior turns.`,
    chat: "You are Pixel Pane, a concise native Mac assistant. Answer general user questions directly. Do not expect OCR text, screenshots, or image context unless they are explicitly provided.",
    study: `${shared} Teach the captured material with compact definitions and examples.`,
    menu: `${shared} Explain menu items with translation and cultural context where useful.`,
    debug: `${shared} Help debug technical text, logs, errors, or code. Prefer concrete fixes.`
  };
  return prompts[action];
}

function userPrompt(action: Action, payload: PixelPaneRequest): string {
  const language = payload.capture.detected_language ? `Detected language: ${payload.capture.detected_language}\n` : "";
  const text = `OCR text:\n${payload.capture.ocr_text}`;

  switch (action) {
    case "translate":
      return `${language}Translate to ${payload.target_language}.\n\n${text}`;
    case "simplify":
      return `${language}Simplify this text for a general reader.\n\n${text}`;
    case "ask":
      return `${language}${text}\n\nQuestion: ${payload.question}`;
    case "chat":
      if (payload.capture.ocr_text.trim().length > 0) {
        return `Context:\n${payload.capture.ocr_text}\n\nQuestion: ${payload.question}`;
      }
      return `Question: ${payload.question}`;
    case "study":
      return `${language}Explain this as study material. Include key terms and likely confusion points.\n\n${text}`;
    case "menu":
      return `${language}Translate and explain this menu text. Include cultural notes only when helpful.\n\n${text}`;
    case "debug":
      return `${language}Analyze this technical capture and suggest likely fixes.\n\n${text}`;
    case "explain":
      return `${language}Explain this capture clearly and concisely.\n\n${text}`;
  }
}

function sse(event: string, data: unknown): Uint8Array {
  return encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
}

function splitSSEEvents(buffer: string): { complete: string[]; remainder: string } {
  const parts = buffer.split(/\r?\n\r?\n/);
  return {
    complete: parts.slice(0, -1),
    remainder: parts.at(-1) ?? ""
  };
}

function parseSSEData(event: string): string | undefined {
  return event
    .split(/\r?\n/)
    .map((line) => line.trimEnd())
    .filter((line) => line.startsWith("data:"))
    .map((line) => line.slice(5).trimStart())
    .join("\n") || undefined;
}

function jsonError(code: string, message: string, requestID: string, status: number, retryAfterSeconds?: number): Response {
  return Response.json(
    {
      error: {
        code,
        message,
        retry_after_seconds: retryAfterSeconds,
        request_id: requestID
      }
    },
    {
      status,
      headers: {
        "cache-control": "no-store",
        "x-pixelpane-request-id": requestID
      }
    }
  );
}

function base64URLDecode(value: string): ArrayBuffer {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(normalized.length + ((4 - (normalized.length % 4)) % 4), "=");
  return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0)).buffer;
}

function base64URLEncode(value: string | ArrayBuffer): string {
  const bytes = typeof value === "string" ? encoder.encode(value) : new Uint8Array(value);
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function decodedBase64Size(value: string): number {
  const padding = value.endsWith("==") ? 2 : value.endsWith("=") ? 1 : 0;
  return Math.floor((value.length * 3) / 4) - padding;
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function nextUTCMidnight(): string {
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1)).toISOString();
}

function secondsUntilNextUTCMidnight(): number {
  return Math.max(60, Math.floor((Date.parse(nextUTCMidnight()) - Date.now()) / 1000));
}
