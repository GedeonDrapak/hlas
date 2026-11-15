// Small WebCrypto helpers: hashing, license keys, AES-GCM, Stripe signatures.

const enc = new TextEncoder();

export async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", enc.encode(text));
  return hex(new Uint8Array(digest));
}

function hex(bytes: Uint8Array): string {
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function b64(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
}

function unb64(text: string): Uint8Array {
  return Uint8Array.from(atob(text), (c) => c.charCodeAt(0));
}

// Crockford base32 without I, L, O, U: easy to read aloud and retype.
const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

/** hlas_XXXXX-XXXXX-XXXXX-XXXXX-XXXXX, 125 bits of randomness. */
export function newLicenseKey(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(25));
  const chars = [...bytes].map((b) => ALPHABET[b & 31]).join("");
  return "hlas_" + chars.match(/.{5}/g)!.join("-");
}

/** Accepts keys pasted with stray spaces or lower case. */
export function normalizeLicenseKey(raw: string): string {
  const body = raw.trim().replace(/^hlas_/i, "").replace(/[^0-9a-z]/gi, "").toUpperCase();
  if (body.length !== 25) return "";
  return "hlas_" + body.match(/.{5}/g)!.join("-");
}

export function sixDigitCode(): string {
  const n = crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000;
  return n.toString().padStart(6, "0");
}

async function aesKey(secretB64: string): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", unb64(secretB64), "AES-GCM", false, ["encrypt", "decrypt"]);
}

export async function seal(plain: string, secretB64: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const data = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, await aesKey(secretB64), enc.encode(plain));
  return b64(iv) + "." + b64(new Uint8Array(data));
}

export async function open(sealed: string, secretB64: string): Promise<string> {
  const [iv, data] = sealed.split(".");
  const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv: unb64(iv) }, await aesKey(secretB64), unb64(data));
  return new TextDecoder().decode(plain);
}

/** Stripe-Signature check: HMAC-SHA256 over "t.payload", 5 minute tolerance. */
export async function verifyStripeSignature(payload: string, header: string | null, secret: string,
                                            nowSeconds = Math.floor(Date.now() / 1000)): Promise<boolean> {
  if (!header || !secret) return false;
  const parts = header.split(",").map((p) => p.split("="));
  const t = parts.find(([k]) => k === "t")?.[1];
  const signatures = parts.filter(([k]) => k === "v1").map(([, v]) => v);
  if (!t || signatures.length === 0) return false;
  if (Math.abs(nowSeconds - Number(t)) > 300) return false;
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const expected = hex(new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(`${t}.${payload}`))));
  return signatures.some((s) => timingSafeEqual(s, expected));
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
