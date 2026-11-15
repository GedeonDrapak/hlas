// End-to-end test: real Worker under `wrangler dev` (local D1), fake Stripe
// and Groq on a local HTTP server. No real keys, no network.
//   npm test
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { spawn, execFileSync } from "node:child_process";
import { createServer } from "node:http";
import { createHmac } from "node:crypto";
import { writeFileSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const MOCK = 8791, WORKER = 8792;
const W = `http://127.0.0.1:${WORKER}`;
const WEBHOOK_SECRET = "whsec_test_only";
const state = { entitled: true, groqCalls: [] };

let mock, worker;

function readBody(req) {
  return new Promise((resolve) => { const c = []; req.on("data", (d) => c.push(d)); req.on("end", () => resolve(Buffer.concat(c))); });
}

before(async () => {
  mock = createServer(async (req, res) => {
    const body = await readBody(req);
    const send = (status, obj) => { res.writeHead(status, { "Content-Type": "application/json" }); res.end(JSON.stringify(obj)); };
    const url = new URL(req.url, "http://x");
    if (url.pathname.startsWith("/groq/")) {
      state.groqCalls.push({ path: url.pathname, auth: req.headers.authorization, body: body.toString("latin1") });
      if (url.pathname.endsWith("/audio/transcriptions")) return send(200, { text: "Ahoj, tohle je test." });
      return send(200, { choices: [{ message: { content: "ok" }, finish_reason: "stop" }] });
    }
    assert.equal(req.headers.authorization, "Bearer sk_test_only");
    if (url.pathname === "/v1/checkout/sessions/cs_test_ok") {
      return send(200, { id: "cs_test_ok", status: "complete", mode: "subscription", customer: "cus_1",
        customer_details: { email: "Buyer@Example.com" }, metadata: { app: "hlas" } });
    }
    if (url.pathname === "/v1/checkout/sessions/cs_test_other") {
      return send(200, { id: "cs_test_other", status: "complete", customer: "cus_9", customer_details: {}, metadata: {} });
    }
    if (url.pathname.startsWith("/v1/checkout/sessions/")) return send(404, { error: { message: "No such session" } });
    if (url.pathname === "/v1/entitlements/active_entitlements") {
      return send(200, { data: state.entitled ? [{ lookup_key: "hlas_cloud" }] : [] });
    }
    if (url.pathname === "/v1/subscriptions") {
      return send(200, { data: [{ id: "sub_1", customer: "cus_1", status: "active", items: { data: [{ current_period_end: 1826213219 }] } }] });
    }
    if (url.pathname === "/v1/customers/cus_1") return send(200, { id: "cus_1", email: "buyer@example.com" });
    if (url.pathname === "/v1/billing_portal/sessions") return send(200, { url: "https://billing.stripe.com/p/session/test" });
    send(404, { error: { message: `mock: ${url.pathname}` } });
  }).listen(MOCK);

  writeFileSync(join(root, ".dev.vars"), [
    `STRIPE_SECRET_KEY=sk_test_only`,
    `STRIPE_WEBHOOK_SECRET=${WEBHOOK_SECRET}`,
    `GROQ_API_KEY=gsk_test_only`,
    `LICENSE_ENC_KEY=${Buffer.alloc(32, 7).toString("base64")}`,
    `STRIPE_API_BASE=http://127.0.0.1:${MOCK}`,
    `GROQ_API_BASE=http://127.0.0.1:${MOCK}/groq`,
    `DAILY_AUDIO_SECONDS=30`,
    `TRIAL_DAILY_AUDIO_SECONDS=20`,
    `MAX_DEVICES=2`,
  ].join("\n"));
  rmSync(join(root, ".wrangler/state"), { recursive: true, force: true });
  execFileSync("npx", ["wrangler", "d1", "execute", "hlas-cloud", "--local", "--file=schema.sql"], { cwd: root, stdio: "ignore" });

  worker = spawn("npx", ["wrangler", "dev", "--port", String(WORKER), "--ip", "127.0.0.1"], { cwd: root, stdio: "ignore" });
  for (let i = 0; i < 120; i++) {
    try { if ((await fetch(W)).ok) return; } catch {}
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error("wrangler dev did not start");
});

after(() => {
  worker?.kill();
  mock?.close();
  rmSync(join(root, ".dev.vars"), { force: true });
});

function wav(seconds) {
  return new Blob([new Uint8Array(44 + Math.round(seconds * 32000))], { type: "audio/wav" });
}

async function transcribe(key, seconds = 3, device) {
  const form = new FormData();
  form.set("file", wav(seconds), "audio.wav");
  form.set("model", "whatever-the-client-says");
  form.set("language", "cs");
  return fetch(`${W}/v1/audio/transcriptions`, { method: "POST", body: form, headers: { ...(key ? { Authorization: `Bearer ${key}` } : {}), ...(device ? { "X-Hlas-Device": device } : {}) } });
}

function signed(event) {
  const payload = JSON.stringify(event);
  const t = Math.floor(Date.now() / 1000);
  const v1 = createHmac("sha256", WEBHOOK_SECRET).update(`${t}.${payload}`).digest("hex");
  return { payload, header: `t=${t},v1=${v1}` };
}

let key;

test("welcome rejects unknown, foreign and malformed sessions", async () => {
  assert.equal((await fetch(`${W}/welcome?session_id=cs_test_missing`)).status, 404);
  assert.equal((await fetch(`${W}/welcome?session_id=cs_test_other`)).status, 404);
  assert.equal((await fetch(`${W}/welcome?session_id=../etc`)).status, 404);
});

test("welcome shows a license key, the same one on reload", async () => {
  const first = await (await fetch(`${W}/welcome?session_id=cs_test_ok`)).text();
  key = first.match(/hlas_[0-9A-Z]{5}(-[0-9A-Z]{5}){4}/)?.[0];
  assert.ok(key, "license key on page");
  assert.match(first, /hlas:\/\/activate\?key=/);
  const second = await (await fetch(`${W}/welcome?session_id=cs_test_ok`)).text();
  assert.ok(second.includes(key), "same key on reload");
});

test("transcription works with the key and forces our model and Groq key", async () => {
  const res = await transcribe(key);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { text: "Ahoj, tohle je test." });
  const call = state.groqCalls.at(-1);
  assert.equal(call.auth, "Bearer gsk_test_only");
  assert.match(call.body, /whisper-large-v3-turbo/);
  assert.doesNotMatch(call.body, /whatever-the-client-says/);
});

test("key is accepted in lower case and with spaces", async () => {
  assert.equal((await transcribe(` ${key.toLowerCase()} `)).status, 200);
});

test("missing or unknown key is 401", async () => {
  assert.equal((await transcribe(null)).status, 401);
  assert.equal((await transcribe("hlas_00000-00000-00000-00000-00000")).status, 401);
});

test("fair-use limit returns 429", async () => {
  assert.equal((await transcribe(key, 40)).status, 429);
});

test("smart text proxies with our model", async () => {
  const res = await fetch(`${W}/v1/chat/completions`, {
    method: "POST", headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ model: "gpt-4", messages: [{ role: "user", content: "x" }] }),
  });
  assert.equal(res.status, 200);
  assert.match(state.groqCalls.at(-1).body, /openai\/gpt-oss-120b/);
});

test("account and portal", async () => {
  const acc = await (await fetch(`${W}/v1/account`, { headers: { Authorization: `Bearer ${key}` } })).json();
  assert.deepEqual(acc, { email: "buyer@example.com", active: true, period_end: 1826213219 });
  const portal = await (await fetch(`${W}/v1/portal`, { method: "POST", headers: { Authorization: `Bearer ${key}` } })).json();
  assert.equal(portal.url, "https://billing.stripe.com/p/session/test");
});

test("webhook rejects a bad signature", async () => {
  const res = await fetch(`${W}/stripe/webhook`, { method: "POST", body: "{}", headers: { "Stripe-Signature": "t=1,v1=00" } });
  assert.equal(res.status, 400);
});

test("cancelled entitlement turns access off, duplicates are ignored", async () => {
  state.entitled = false;
  const ev = signed({ id: "evt_1", type: "entitlements.active_entitlement_summary.updated", data: { object: { customer: "cus_1" } } });
  const res = await fetch(`${W}/stripe/webhook`, { method: "POST", body: ev.payload, headers: { "Stripe-Signature": ev.header } });
  assert.equal(res.status, 200);
  assert.equal((await transcribe(key)).status, 402);
  const again = await fetch(`${W}/stripe/webhook`, { method: "POST", body: ev.payload, headers: { "Stripe-Signature": ev.header } });
  assert.deepEqual(await again.json(), { received: true, duplicate: true });
});

test("renewed subscription turns access back on", async () => {
  state.entitled = true;
  const ev = signed({ id: "evt_2", type: "customer.subscription.updated", data: { object: { customer: "cus_1" } } });
  await fetch(`${W}/stripe/webhook`, { method: "POST", body: ev.payload, headers: { "Stripe-Signature": ev.header } });
  assert.equal((await transcribe(key)).status, 200);
});

test("e-mail sign-in reports unavailable until a sender domain exists", async () => {
  const res = await fetch(`${W}/v1/auth/email/start`, { method: "POST", body: JSON.stringify({ email: "buyer@example.com" }) });
  assert.equal(res.status, 503);
});

test("device limit: two installs fine, a third new one is refused", async () => {
  assert.equal((await transcribe(key, 1, "install-aaaaaaaaaaaaaaaa")).status, 200);
  assert.equal((await transcribe(key, 1, "install-bbbbbbbbbbbbbbbb")).status, 200);
  assert.equal((await transcribe(key, 1, "install-cccccccccccccccc")).status, 403);
  assert.equal((await transcribe(key, 1, "install-aaaaaaaaaaaaaaaa")).status, 200);
});

let trialKey;
test("trial: key for an install, same key again, works, has its own cap", async () => {
  const post = (body) => fetch(`${W}/v1/trial`, { method: "POST", body: JSON.stringify(body) });
  assert.equal((await post({ device: "short" })).status, 400);
  const first = await (await post({ device: "trial-install-0123456789" })).json();
  assert.match(first.key, /^hlas_/);
  assert.equal(first.active, true);
  assert.ok(first.trial_end > Date.now() / 1000 + 6 * 86400);
  trialKey = first.key;
  const again = await (await post({ device: "trial-install-0123456789" })).json();
  assert.equal(again.key, trialKey);
  assert.equal((await transcribe(trialKey, 3)).status, 200);
  assert.equal((await transcribe(trialKey, 25)).status, 429);
  const acc = await (await fetch(`${W}/v1/account`, { headers: { Authorization: `Bearer ${trialKey}` } })).json();
  assert.equal(acc.trial, true);
  assert.equal(acc.active, true);
  const portal = await fetch(`${W}/v1/portal`, { method: "POST", headers: { Authorization: `Bearer ${trialKey}` } });
  assert.equal(portal.status, 404);
});

test("funnel events count known names only", async () => {
  const send = (b) => fetch(`${W}/v1/event`, { method: "POST", body: JSON.stringify(b) });
  assert.equal((await send({ e: "download-mac", l: "pl" })).status, 204);
  assert.equal((await send({ e: "<script>" })).status, 204);
  const pre = await fetch(`${W}/v1/event`, { method: "OPTIONS" });
  assert.equal(pre.headers.get("access-control-allow-origin"), "*");
});

test("recover page renders", async () => {
  const res = await fetch(`${W}/recover`);
  assert.equal(res.status, 200);
  assert.match(await res.text(), /licenční klíč/);
});
