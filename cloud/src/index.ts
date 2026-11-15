// Hlas Cloud Worker.
//
// Stripe owns billing; this Worker only answers "may this license key
// dictate right now?" and forwards audio to Groq on our key.
//
//   GET  /welcome?session_id=cs_...   post-checkout page with the license key
//   GET  /portal?session_id=cs_...    redirect to the Stripe customer portal
//   POST /stripe/webhook              keeps `customers.entitled` in sync
//   POST /v1/audio/transcriptions     OpenAI-compatible, Bearer license key
//   POST /v1/chat/completions         OpenAI-compatible (Smart text)
//   GET  /v1/account                  license status for the app
//   POST /v1/portal                   customer portal URL for the app
//   POST /v1/auth/email/start|verify  e-mail sign-in (needs EMAIL binding)
//   POST /v1/trial                    free trial key for one install, no card
//   POST /v1/event                    anonymous funnel counter (web + apps)
//   GET  /recover                     lost-key page (e-mail code, needs EMAIL)
//   cron 00:15 UTC                    daily report and health check

import { newLicenseKey, normalizeLicenseKey, open, seal, sha256Hex, sixDigitCode, verifyStripeSignature } from "./crypto";
import { noticePage, recoverPage, welcomePage } from "./pages";
import { customerEmail, getCheckoutSession, isEntitled, periodEnd, portalSession, StripeError } from "./stripe";

export interface Env {
  DB: D1Database;
  EMAIL?: { send(message: { to: string; from: { email: string; name: string }; subject: string; text: string; html: string }): Promise<unknown> };
  PUBLIC_URL: string;
  PORTAL_RETURN_URL: string;
  ENTITLEMENT_KEY: string;
  DAILY_AUDIO_SECONDS: string;
  TRANSCRIBE_MODEL: string;
  SMART_TEXT_MODEL: string;
  EMAIL_FROM: string;
  TRIAL_DAYS: string;
  TRIAL_DAILY_AUDIO_SECONDS: string;
  MAX_DEVICES: string;
  ALERT_DAILY_AUDIO_SECONDS: string;
  ALERT_WEBHOOK_URL?: string;
  STRIPE_SECRET_KEY: string;
  STRIPE_WEBHOOK_SECRET: string;
  GROQ_API_KEY: string;
  LICENSE_ENC_KEY: string;
  // Test overrides only.
  STRIPE_API_BASE?: string;
  GROQ_API_BASE?: string;
}

const now = () => Math.floor(Date.now() / 1000);
const today = () => new Date().toISOString().slice(0, 10);
const isTrial = (customer: string) => customer.startsWith("trial_");

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

/** OpenAI-style error envelope so the apps' existing error mapping applies. */
function apiError(status: number, code: string, message: string): Response {
  return json({ error: { code, message } }, status);
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const route = `${request.method} ${url.pathname}`;
    try {
      if (request.method === "OPTIONS") return cors(new Response(null, { status: 204 }));
      switch (route) {
        case "GET /": return json({ service: "hlas-cloud", ok: true });
        case "GET /recover": return recoverPage(!!(env.EMAIL && env.EMAIL_FROM));
        case "POST /v1/trial": return await trial(request, env);
        case "POST /v1/event": return cors(await event(request, env));
        case "GET /welcome": return await welcome(url, env);
        case "GET /portal": return await portalFromSession(url, env);
        case "GET /account": return noticePage("Hotovo", "Můžeš zavřít tuto stránku a vrátit se do Hlasu.");
        case "POST /stripe/webhook": return await webhook(request, env);
        case "POST /v1/audio/transcriptions": return await transcribe(request, env, ctx);
        case "POST /v1/chat/completions": return await chat(request, env);
        case "GET /v1/account": return await account(request, env);
        case "POST /v1/portal": return await portalForLicense(request, env);
        case "POST /v1/auth/email/start": return cors(await emailStart(request, env));
        case "POST /v1/auth/email/verify": return cors(await emailVerify(request, env));
      }
      return apiError(404, "not_found", "Not found");
    } catch (err) {
      console.error(route, err instanceof Error ? err.stack : err);
      if (err instanceof StripeError) return apiError(502, "stripe_error", "Billing service unavailable");
      return apiError(500, "internal_error", "Internal error");
    }
  },

  async scheduled(_controller: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(dailyReport(env));
  },
};

/** The web pages on hlas.dev call /v1/event and /recover's API cross-origin. */
function cors(res: Response): Response {
  const out = new Response(res.body, res);
  out.headers.set("Access-Control-Allow-Origin", "*");
  out.headers.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  out.headers.set("Access-Control-Allow-Headers", "Content-Type");
  return out;
}

// ---------------------------------------------------------------- customers

async function syncCustomer(env: Env, customer: string, email?: string | null): Promise<boolean> {
  const [entitled, end, mail] = await Promise.all([
    isEntitled(env, customer),
    periodEnd(env, customer),
    email === undefined ? customerEmail(env, customer) : Promise.resolve(email),
  ]);
  await env.DB.prepare(
    `INSERT INTO customers (stripe_customer_id, email, entitled, period_end, updated_at)
     VALUES (?1, ?2, ?3, ?4, ?5)
     ON CONFLICT(stripe_customer_id) DO UPDATE SET
       email = COALESCE(?2, email), entitled = ?3, period_end = ?4, updated_at = ?5`,
  ).bind(customer, mail?.toLowerCase() ?? null, entitled ? 1 : 0, end, now()).run();
  return entitled;
}

/** The customer's license key, created on first use. */
async function licenseFor(env: Env, customer: string): Promise<string> {
  const row = await env.DB.prepare(
    "SELECT key_enc FROM licenses WHERE stripe_customer_id = ? AND revoked_at IS NULL ORDER BY created_at LIMIT 1",
  ).bind(customer).first<{ key_enc: string }>();
  if (row) return open(row.key_enc, env.LICENSE_ENC_KEY);
  const key = newLicenseKey();
  await env.DB.prepare(
    "INSERT INTO licenses (key_hash, stripe_customer_id, key_enc, created_at) VALUES (?, ?, ?, ?)",
  ).bind(await sha256Hex(key), customer, await seal(key, env.LICENSE_ENC_KEY), now()).run();
  return key;
}

interface Licensee { stripe_customer_id: string; email: string | null; entitled: number; period_end: number | null; key_hash: string }

async function licensee(request: Request, env: Env): Promise<Licensee | null> {
  const auth = request.headers.get("Authorization") ?? "";
  const key = normalizeLicenseKey(auth.replace(/^Bearer\s+/i, ""));
  if (!key) return null;
  return env.DB.prepare(
    `SELECT c.stripe_customer_id, c.email, c.entitled, c.period_end, l.key_hash
       FROM licenses l JOIN customers c ON c.stripe_customer_id = l.stripe_customer_id
      WHERE l.key_hash = ? AND l.revoked_at IS NULL`,
  ).bind(await sha256Hex(key)).first<Licensee>();
}

/** 401 for an unknown key, 402 for a lapsed subscription (the apps explain both). */
async function requireActive(request: Request, env: Env): Promise<Licensee | Response> {
  const who = await licensee(request, env);
  if (!who) return apiError(401, "invalid_license", "Unknown Hlas Cloud license key");
  if (isTrial(who.stripe_customer_id) && (who.period_end ?? 0) < now()) {
    return apiError(402, "trial_ended", "Hlas Cloud trial has ended");
  }
  if (!who.entitled) return apiError(402, "subscription_inactive", "Hlas Cloud subscription is not active");
  const device = request.headers.get("X-Hlas-Device");
  if (device && !(await deviceAllowed(env, who.key_hash, device))) {
    return apiError(403, "too_many_devices", "This Hlas Cloud license is in use on too many computers");
  }
  return who;
}

/** At most MAX_DEVICES installs per license within 30 days. Old app versions send no header. */
async function deviceAllowed(env: Env, keyHash: string, device: string): Promise<boolean> {
  const deviceHash = await sha256Hex(`device:${device.slice(0, 200)}`);
  const known = await env.DB.prepare("SELECT 1 FROM license_devices WHERE key_hash = ? AND device_hash = ?")
    .bind(keyHash, deviceHash).first();
  if (!known) {
    const active = await env.DB.prepare("SELECT COUNT(*) AS n FROM license_devices WHERE key_hash = ? AND last_seen > ?")
      .bind(keyHash, now() - 30 * 86400).first<{ n: number }>();
    if ((active?.n ?? 0) >= Number(env.MAX_DEVICES || 5)) return false;
  }
  await env.DB.prepare(
    `INSERT INTO license_devices (key_hash, device_hash, last_seen) VALUES (?1, ?2, ?3)
     ON CONFLICT(key_hash, device_hash) DO UPDATE SET last_seen = ?3`,
  ).bind(keyHash, deviceHash, now()).run();
  return true;
}

// ---------------------------------------------------------------- checkout

async function sessionFromQuery(url: URL, env: Env) {
  const id = url.searchParams.get("session_id") ?? "";
  if (!/^cs_(live|test)_[A-Za-z0-9]+$/.test(id)) return null;
  const session = await getCheckoutSession(env, id).catch((e) => {
    if (e instanceof StripeError && e.status === 404) return null;
    throw e;
  });
  if (!session || session.status !== "complete" || !session.customer) return null;
  if (session.metadata?.app !== "hlas") return null;
  return session;
}

async function welcome(url: URL, env: Env): Promise<Response> {
  const session = await sessionFromQuery(url, env);
  if (!session) return noticePage("Platbu jsme nenašli", "Odkaz je neplatný nebo platba ještě neproběhla. Zkus stránku za chvíli obnovit.", 404);
  const customer = session.customer!;
  await syncCustomer(env, customer, session.customer_details?.email ?? null);
  const key = await licenseFor(env, customer);
  await count(env, "welcome");
  return welcomePage(key, session.customer_details?.email ?? null, `/portal?session_id=${encodeURIComponent(session.id)}`);
}

async function portalFromSession(url: URL, env: Env): Promise<Response> {
  const session = await sessionFromQuery(url, env);
  if (!session) return noticePage("Odkaz vypršel", "Spravuj předplatné přes aplikaci Hlas nebo přihlášení do zákaznického portálu.", 404);
  return Response.redirect(await portalSession(env, session.customer!, env.PORTAL_RETURN_URL), 303);
}

// ---------------------------------------------------------------- webhook

async function webhook(request: Request, env: Env): Promise<Response> {
  const payload = await request.text();
  if (!(await verifyStripeSignature(payload, request.headers.get("Stripe-Signature"), env.STRIPE_WEBHOOK_SECRET))) {
    return apiError(400, "bad_signature", "Invalid signature");
  }
  const event = JSON.parse(payload) as { id: string; type: string; data: { object: any } };
  const seen = await env.DB.prepare("INSERT OR IGNORE INTO webhook_events (id, received_at) VALUES (?, ?)")
    .bind(event.id, now()).run();
  if (!seen.meta.changes) return json({ received: true, duplicate: true });

  const obj = event.data.object;
  try {
    switch (event.type) {
      case "checkout.session.completed":
        if (obj.metadata?.app === "hlas" && obj.customer) {
          await syncCustomer(env, obj.customer, obj.customer_details?.email ?? null);
          await count(env, "purchase");
        }
        break;
      case "customer.subscription.created":
      case "customer.subscription.updated":
      case "customer.subscription.deleted":
      case "customer.subscription.paused":
      case "customer.subscription.resumed":
      case "entitlements.active_entitlement_summary.updated":
        // Always re-read from Stripe: events can arrive out of order.
        if (obj.customer) await syncCustomer(env, obj.customer);
        if (event.type === "customer.subscription.deleted") await count(env, "cancel");
        break;
      case "customer.updated":
        await env.DB.prepare("UPDATE customers SET email = ?, updated_at = ? WHERE stripe_customer_id = ?")
          .bind(obj.email?.toLowerCase() ?? null, now(), obj.id).run();
        break;
    }
  } catch (err) {
    // Let Stripe retry: forget the event id so the retry is processed.
    await env.DB.prepare("DELETE FROM webhook_events WHERE id = ?").bind(event.id).run();
    throw err;
  }
  return json({ received: true });
}

// ---------------------------------------------------------------- proxy

/** Rough audio length from the upload size: Hlas sends 16 kHz mono 16-bit WAV. */
function audioSeconds(file: File): number {
  return Math.max(1, (file.size - 44) / 32_000);
}

async function transcribe(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const who = await requireActive(request, env);
  if (who instanceof Response) return who;

  const form = await request.formData();
  const file = form.get("file");
  if (!(file instanceof File)) return apiError(400, "missing_file", "Multipart field 'file' is required");

  const seconds = audioSeconds(file);
  const used = await env.DB.prepare("SELECT audio_seconds FROM usage WHERE stripe_customer_id = ? AND day = ?")
    .bind(who.stripe_customer_id, today()).first<{ audio_seconds: number }>();
  const cap = Number(isTrial(who.stripe_customer_id) ? env.TRIAL_DAILY_AUDIO_SECONDS || 1800 : env.DAILY_AUDIO_SECONDS);
  if ((used?.audio_seconds ?? 0) + seconds > cap) {
    return apiError(429, "fair_use_limit", "Daily Hlas Cloud fair-use limit reached, resets at midnight UTC");
  }

  const upstream = new FormData();
  upstream.set("file", file, "audio.wav");
  upstream.set("model", env.TRANSCRIBE_MODEL);
  upstream.set("response_format", "json");
  upstream.set("temperature", "0");
  for (const name of ["language", "prompt"]) {
    const value = form.get(name);
    if (typeof value === "string" && value) upstream.set(name, value.slice(0, 2000));
  }
  const res = await fetch(`${env.GROQ_API_BASE || "https://api.groq.com/openai"}/v1/audio/transcriptions`, {
    method: "POST",
    headers: { Authorization: `Bearer ${env.GROQ_API_KEY}` },
    body: upstream,
  });
  if (!res.ok) {
    console.error("groq transcription", res.status, (await res.text()).slice(0, 300));
    return apiError(res.status === 429 ? 503 : 502, "upstream_error", "Transcription service unavailable");
  }
  const { text } = await res.json<{ text: string }>();
  ctx.waitUntil(env.DB.prepare(
    `INSERT INTO usage (stripe_customer_id, day, audio_seconds, requests) VALUES (?1, ?2, ?3, 1)
     ON CONFLICT(stripe_customer_id, day) DO UPDATE SET audio_seconds = audio_seconds + ?3, requests = requests + 1`,
  ).bind(who.stripe_customer_id, today(), seconds).run().then(() => usageAlert(env)));
  return json({ text });
}

async function chat(request: Request, env: Env): Promise<Response> {
  const who = await requireActive(request, env);
  if (who instanceof Response) return who;
  const body = await request.json<Record<string, unknown>>().catch(() => null);
  if (!body || !Array.isArray(body.messages)) return apiError(400, "bad_request", "messages required");

  // Only pass through what Smart text uses; model and limits are ours.
  const upstream = {
    model: env.SMART_TEXT_MODEL,
    messages: body.messages,
    temperature: 0,
    reasoning_effort: "low",
    max_completion_tokens: Math.min(16_000, Math.max(1024, Number(body.max_completion_tokens) || 4096)),
  };
  const res = await fetch(`${env.GROQ_API_BASE || "https://api.groq.com/openai"}/v1/chat/completions`, {
    method: "POST",
    headers: { Authorization: `Bearer ${env.GROQ_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify(upstream),
  });
  if (!res.ok) {
    console.error("groq chat", res.status, (await res.text()).slice(0, 300));
    return apiError(res.status === 429 ? 503 : 502, "upstream_error", "Smart text service unavailable");
  }
  return new Response(res.body, { headers: { "Content-Type": "application/json" } });
}

// ---------------------------------------------------------------- app account

async function account(request: Request, env: Env): Promise<Response> {
  const who = await licensee(request, env);
  if (!who) return apiError(401, "invalid_license", "Unknown Hlas Cloud license key");
  const trial = isTrial(who.stripe_customer_id);
  const active = !!who.entitled && !(trial && (who.period_end ?? 0) < now());
  return json({ email: who.email, active, period_end: who.period_end, ...(trial ? { trial: true } : {}) });
}

async function portalForLicense(request: Request, env: Env): Promise<Response> {
  const who = await licensee(request, env);
  if (!who) return apiError(401, "invalid_license", "Unknown Hlas Cloud license key");
  if (isTrial(who.stripe_customer_id)) return apiError(404, "no_subscription", "A trial has no subscription to manage");
  return json({ url: await portalSession(env, who.stripe_customer_id, env.PORTAL_RETURN_URL) });
}

// ---------------------------------------------------------------- e-mail sign-in

async function emailStart(request: Request, env: Env): Promise<Response> {
  if (!env.EMAIL || !env.EMAIL_FROM) return apiError(503, "email_signin_unavailable", "E-mail sign-in is not available yet");
  const { email } = await request.json<{ email?: string }>().catch(() => ({ email: undefined }));
  const address = (email ?? "").trim().toLowerCase();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(address)) return apiError(400, "bad_email", "Invalid e-mail");

  // Same answer whether or not the address has a subscription.
  const known = await env.DB.prepare(
    "SELECT 1 FROM customers c JOIN licenses l ON l.stripe_customer_id = c.stripe_customer_id WHERE c.email = ? AND l.revoked_at IS NULL LIMIT 1",
  ).bind(address).first();
  const pending = await env.DB.prepare("SELECT expires_at FROM login_codes WHERE email = ?").bind(address).first<{ expires_at: number }>();
  if (known && !(pending && pending.expires_at - now() > 9 * 60)) {
    const code = sixDigitCode();
    await env.DB.prepare(
      `INSERT INTO login_codes (email, code_hash, expires_at, attempts) VALUES (?1, ?2, ?3, 0)
       ON CONFLICT(email) DO UPDATE SET code_hash = ?2, expires_at = ?3, attempts = 0`,
    ).bind(address, await sha256Hex(`${address}:${code}`), now() + 600).run();
    await env.EMAIL.send({
      to: address,
      from: { email: env.EMAIL_FROM, name: "Hlas" },
      subject: `Kód pro přihlášení do Hlasu: ${code}`,
      text: `Tvůj kód pro přihlášení do Hlas Cloud je ${code}. Platí 10 minut.\n\nYour Hlas Cloud sign-in code is ${code}. It expires in 10 minutes.`,
      html: `<p>Tvůj kód pro přihlášení do Hlas Cloud:</p><p style="font-size:28px;font-weight:700;letter-spacing:4px">${code}</p><p>Platí 10 minut. / Expires in 10 minutes.</p>`,
    });
  }
  return json({ sent: true });
}

async function emailVerify(request: Request, env: Env): Promise<Response> {
  const body = await request.json<{ email?: string; code?: string }>().catch(() => ({} as { email?: string; code?: string }));
  const address = (body.email ?? "").trim().toLowerCase();
  const code = (body.code ?? "").replace(/\D/g, "");
  const row = await env.DB.prepare("SELECT code_hash, expires_at, attempts FROM login_codes WHERE email = ?")
    .bind(address).first<{ code_hash: string; expires_at: number; attempts: number }>();
  if (!row || row.expires_at < now() || row.attempts >= 5) return apiError(400, "code_expired", "Code expired, request a new one");
  if ((await sha256Hex(`${address}:${code}`)) !== row.code_hash) {
    await env.DB.prepare("UPDATE login_codes SET attempts = attempts + 1 WHERE email = ?").bind(address).run();
    return apiError(400, "code_invalid", "Wrong code");
  }
  await env.DB.prepare("DELETE FROM login_codes WHERE email = ?").bind(address).run();
  const customer = await env.DB.prepare("SELECT stripe_customer_id FROM customers WHERE email = ? ORDER BY entitled DESC, updated_at DESC LIMIT 1")
    .bind(address).first<{ stripe_customer_id: string }>();
  if (!customer) return apiError(400, "code_expired", "Code expired, request a new one");
  return json({ key: await licenseFor(env, customer.stripe_customer_id) });
}

// ---------------------------------------------------------------- trial

/**
 * One free trial per install. The app sends a random install id it keeps;
 * asking again from the same install returns the same key (expired or not).
 * At most 3 new trials per IP a day stops scripted farming.
 */
async function trial(request: Request, env: Env): Promise<Response> {
  const body = await request.json<{ device?: string }>().catch(() => ({} as { device?: string }));
  const device = (body.device ?? request.headers.get("X-Hlas-Device") ?? "").trim();
  if (device.length < 16 || device.length > 200) return apiError(400, "bad_device", "Install id required");
  const deviceHash = await sha256Hex(`device:${device}`);

  const existing = await env.DB.prepare("SELECT customer_id FROM trials WHERE device_hash = ?")
    .bind(deviceHash).first<{ customer_id: string }>();
  if (existing) return json(await trialAnswer(env, existing.customer_id));

  const ip = request.headers.get("CF-Connecting-IP") ?? "";
  const ipHash = ip ? await sha256Hex(`ip:${today()}:${ip}:${env.LICENSE_ENC_KEY.slice(0, 8)}`) : null;
  if (ipHash) {
    const recent = await env.DB.prepare("SELECT COUNT(*) AS n FROM trials WHERE ip_hash = ? AND created_at > ?")
      .bind(ipHash, now() - 86400).first<{ n: number }>();
    if ((recent?.n ?? 0) >= 3) return apiError(429, "trial_rate_limited", "Too many trials from this network today");
  }

  const customer = "trial_" + (await sha256Hex(crypto.randomUUID())).slice(0, 24);
  const end = now() + Number(env.TRIAL_DAYS || 7) * 86400;
  await env.DB.batch([
    env.DB.prepare("INSERT INTO customers (stripe_customer_id, email, entitled, period_end, updated_at) VALUES (?, NULL, 1, ?, ?)")
      .bind(customer, end, now()),
    env.DB.prepare("INSERT INTO trials (device_hash, customer_id, ip_hash, created_at) VALUES (?, ?, ?, ?)")
      .bind(deviceHash, customer, ipHash, now()),
  ]);
  await count(env, "trial");
  return json(await trialAnswer(env, customer));
}

async function trialAnswer(env: Env, customer: string) {
  const row = await env.DB.prepare("SELECT period_end FROM customers WHERE stripe_customer_id = ?")
    .bind(customer).first<{ period_end: number }>();
  const end = row?.period_end ?? 0;
  return { key: await licenseFor(env, customer), trial_end: end, active: end > now() };
}

// ---------------------------------------------------------------- funnel

const EVENTS = new Set([
  "download-mac", "download-win", "checkout", "trial-click", "manage",
  "app-trial-start", "app-buy-click", "app-activated",
]);

async function count(env: Env, name: string): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO events (day, name, count) VALUES (?, ?, 1)
     ON CONFLICT(day, name) DO UPDATE SET count = count + 1`,
  ).bind(today(), name).run();
}

/** Anonymous counter: name and page language only, nothing about the visitor is stored. */
async function event(request: Request, env: Env): Promise<Response> {
  const body = await request.text().then((t) => { try { return JSON.parse(t); } catch { return {}; } }) as { e?: string; l?: string };
  if (!body.e || !EVENTS.has(body.e)) return new Response(null, { status: 204 });
  const lang = /^[a-z]{2}$/.test(body.l ?? "") ? `:${body.l}` : "";
  await count(env, body.e);
  if (lang) await count(env, body.e + lang);
  return new Response(null, { status: 204 });
}

// ---------------------------------------------------------------- monitoring

async function alert(env: Env, kind: string, text: string): Promise<void> {
  const fresh = await env.DB.prepare("INSERT OR IGNORE INTO alerts_sent (day, kind) VALUES (?, ?)").bind(today(), kind).run();
  if (!fresh.meta.changes) return;
  console.warn("alert", kind, text);
  if (env.ALERT_WEBHOOK_URL) {
    await fetch(env.ALERT_WEBHOOK_URL, {
      method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ text: `Hlas Cloud: ${text}` }),
    }).catch((e) => console.error("alert webhook", e));
  }
}

/** Groq whisper-large-v3-turbo costs $0.04 per audio hour. */
const usd = (seconds: number) => (seconds / 3600) * 0.04;

async function usageAlert(env: Env): Promise<void> {
  const row = await env.DB.prepare("SELECT SUM(audio_seconds) AS s FROM usage WHERE day = ?").bind(today()).first<{ s: number | null }>();
  const total = row?.s ?? 0;
  if (total > Number(env.ALERT_DAILY_AUDIO_SECONDS || 36000)) {
    await alert(env, "usage", `today ${(total / 3600).toFixed(1)} h of audio, about $${usd(total).toFixed(2)} on Groq.`);
  }
}

async function dailyReport(env: Env): Promise<void> {
  const day = new Date(Date.now() - 86400_000).toISOString().slice(0, 10);
  const usage = await env.DB.prepare(
    "SELECT COUNT(*) AS users, SUM(audio_seconds) AS s, SUM(requests) AS r FROM usage WHERE day = ?",
  ).bind(day).first<{ users: number; s: number | null; r: number | null }>();
  const subs = await env.DB.prepare(
    "SELECT SUM(entitled) AS paid FROM customers WHERE stripe_customer_id NOT LIKE 'trial_%'",
  ).first<{ paid: number | null }>();
  const events = await env.DB.prepare("SELECT name, count FROM events WHERE day = ? AND name NOT LIKE '%:%' ORDER BY name")
    .bind(day).all<{ name: string; count: number }>();
  const funnel = events.results.map((e) => `${e.name} ${e.count}`).join(", ") || "no events";
  const seconds = usage?.s ?? 0;
  const text = `${day}: ${subs?.paid ?? 0} paying, ${usage?.users ?? 0} dictating, ${usage?.r ?? 0} requests, `
    + `${(seconds / 3600).toFixed(1)} h audio (~$${usd(seconds).toFixed(2)}). Funnel: ${funnel}.`;
  console.log("daily report", text);
  if (env.ALERT_WEBHOOK_URL) {
    await fetch(env.ALERT_WEBHOOK_URL, {
      method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ text: `Hlas Cloud ${text}` }),
    }).catch((e) => console.error("report webhook", e));
  }
  // Health check: Groq must accept our key.
  if (env.GROQ_API_KEY) {
    const res = await fetch(`${env.GROQ_API_BASE || "https://api.groq.com/openai"}/v1/models`, {
      headers: { Authorization: `Bearer ${env.GROQ_API_KEY}` },
    }).catch(() => null);
    if (!res?.ok) await alert(env, "groq", `Groq health check failed (${res?.status ?? "network"}). Dictation is down.`);
  }
}
