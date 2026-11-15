// Minimal Stripe REST client: only the calls Hlas Cloud needs.

export interface StripeEnv {
  STRIPE_SECRET_KEY: string;
  STRIPE_API_BASE?: string;
  ENTITLEMENT_KEY: string;
}

export class StripeError extends Error {
  constructor(readonly status: number, message: string) { super(message); }
}

async function call<T>(env: StripeEnv, method: "GET" | "POST", path: string,
                       params: Record<string, string> = {}): Promise<T> {
  const base = env.STRIPE_API_BASE || "https://api.stripe.com";
  const query = new URLSearchParams(params).toString();
  const url = method === "GET" && query ? `${base}${path}?${query}` : `${base}${path}`;
  const res = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${env.STRIPE_SECRET_KEY}`,
      ...(method === "POST" ? { "Content-Type": "application/x-www-form-urlencoded" } : {}),
    },
    body: method === "POST" ? query : undefined,
  });
  const body = await res.json<any>();
  if (!res.ok) throw new StripeError(res.status, body?.error?.message ?? `Stripe ${res.status}`);
  return body as T;
}

export interface CheckoutSession {
  id: string;
  status: string | null;
  mode: string;
  customer: string | null;
  customer_details: { email: string | null } | null;
  metadata: Record<string, string> | null;
}

export function getCheckoutSession(env: StripeEnv, id: string) {
  return call<CheckoutSession>(env, "GET", `/v1/checkout/sessions/${encodeURIComponent(id)}`);
}

/** True when the customer currently holds the Hlas Cloud entitlement. */
export async function isEntitled(env: StripeEnv, customer: string): Promise<boolean> {
  const list = await call<{ data: { lookup_key: string }[] }>(env, "GET", "/v1/entitlements/active_entitlements",
    { customer, limit: "100" });
  return list.data.some((e) => e.lookup_key === env.ENTITLEMENT_KEY);
}

export interface Subscription {
  id: string;
  customer: string;
  status: string;
  current_period_end?: number;
  items?: { data: { current_period_end?: number }[] };
}

/** Latest period end across the customer's subscriptions, if any. */
export async function periodEnd(env: StripeEnv, customer: string): Promise<number | null> {
  const subs = await call<{ data: Subscription[] }>(env, "GET", "/v1/subscriptions",
    { customer, status: "all", limit: "10" });
  const ends = subs.data
    .filter((s) => ["active", "trialing", "past_due"].includes(s.status))
    .map((s) => s.items?.data?.[0]?.current_period_end ?? s.current_period_end ?? 0);
  return ends.length ? Math.max(...ends) : null;
}

export async function customerEmail(env: StripeEnv, customer: string): Promise<string | null> {
  const c = await call<{ email: string | null; deleted?: boolean }>(env, "GET", `/v1/customers/${encodeURIComponent(customer)}`);
  return c.deleted ? null : c.email;
}

export async function portalSession(env: StripeEnv, customer: string, returnUrl: string): Promise<string> {
  const s = await call<{ url: string }>(env, "POST", "/v1/billing_portal/sessions",
    { customer, return_url: returnUrl });
  return s.url;
}
