-- Hlas Cloud D1 schema. Apply with:
--   wrangler d1 execute hlas-cloud --remote --file=schema.sql
-- Every statement is idempotent so the file can be re-run safely.

-- One row per Stripe customer. `entitled` mirrors the active `hlas_cloud`
-- Stripe Entitlement and is the only thing that gates transcription.
CREATE TABLE IF NOT EXISTS customers (
  stripe_customer_id TEXT PRIMARY KEY,
  email TEXT,
  entitled INTEGER NOT NULL DEFAULT 0,
  period_end INTEGER,
  updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS customers_email ON customers(email);

-- License keys. The key itself is the bearer credential the app sends.
-- key_hash is the lookup; key_enc (AES-GCM) lets the welcome page and
-- e-mail sign-in show the same key again.
CREATE TABLE IF NOT EXISTS licenses (
  key_hash TEXT PRIMARY KEY,
  stripe_customer_id TEXT NOT NULL,
  key_enc TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  revoked_at INTEGER
);
CREATE INDEX IF NOT EXISTS licenses_customer ON licenses(stripe_customer_id);

-- Fair-use accounting, one row per customer per UTC day.
CREATE TABLE IF NOT EXISTS usage (
  stripe_customer_id TEXT NOT NULL,
  day TEXT NOT NULL,
  audio_seconds REAL NOT NULL DEFAULT 0,
  requests INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (stripe_customer_id, day)
);

-- One pending e-mail sign-in code per address.
CREATE TABLE IF NOT EXISTS login_codes (
  email TEXT PRIMARY KEY,
  code_hash TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0
);

-- Stripe retries webhooks; remember what was already processed.
CREATE TABLE IF NOT EXISTS webhook_events (
  id TEXT PRIMARY KEY,
  received_at INTEGER NOT NULL
);

-- Free trial without a card: one per install (device_hash), a few per IP a day.
-- The trial gets a synthetic customer id "trial_..." in `customers`, entitled
-- until period_end, so the normal license path serves it.
CREATE TABLE IF NOT EXISTS trials (
  device_hash TEXT PRIMARY KEY,
  customer_id TEXT NOT NULL,
  ip_hash TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS trials_ip ON trials(ip_hash, created_at);

-- Installs seen per license key (X-Hlas-Device), for the device limit.
CREATE TABLE IF NOT EXISTS license_devices (
  key_hash TEXT NOT NULL,
  device_hash TEXT NOT NULL,
  last_seen INTEGER NOT NULL,
  PRIMARY KEY (key_hash, device_hash)
);

-- Anonymous funnel counters (no IP, no cookie, no user id).
CREATE TABLE IF NOT EXISTS events (
  day TEXT NOT NULL,
  name TEXT NOT NULL,
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, name)
);

-- Alerts already sent, so each fires at most once a day.
CREATE TABLE IF NOT EXISTS alerts_sent (
  day TEXT NOT NULL,
  kind TEXT NOT NULL,
  PRIMARY KEY (day, kind)
);
