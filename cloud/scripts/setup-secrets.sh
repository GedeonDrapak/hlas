#!/usr/bin/env bash
# One-time setup of Hlas Cloud secrets. Run it yourself in a terminal:
#   bash cloud/scripts/setup-secrets.sh
# Keys are read with hidden input and go straight into Cloudflare secrets.
# Nothing is printed, logged or written to disk.
set -euo pipefail
cd "$(dirname "$0")/.."

WORKER_URL="https://hlas-cloud.nepal-chance-to-choose.workers.dev"
EVENTS=(
  checkout.session.completed
  customer.subscription.created customer.subscription.updated customer.subscription.deleted
  customer.subscription.paused customer.subscription.resumed
  customer.updated
  entitlements.active_entitlement_summary.updated
)

echo "Hlas Cloud setup"
echo
echo "1) Groq API key (console.groq.com/keys), used for all transcription."
read -rsp "   Paste Groq key: " GROQ; echo
[[ "$GROQ" == gsk_* ]] || { echo "   That does not look like a Groq key (gsk_...)."; exit 1; }
printf %s "$GROQ" | npx wrangler secret put GROQ_API_KEY >/dev/null
unset GROQ
echo "   Saved GROQ_API_KEY."

echo
echo "2) Stripe restricted key for Eden Makers (live mode):"
echo "   https://dashboard.stripe.com/apikeys/create  ->  Create restricted key, name \"Hlas Cloud\""
echo "   Permissions: Checkout Sessions Read, Customers Read, Subscriptions Read,"
echo "   Entitlements Read, Customer portal Write, Webhook Endpoints Write. Everything else None."
read -rsp "   Paste key (rk_live_...): " STRIPE; echo
[[ "$STRIPE" == rk_live_* ]] || { echo "   Expected a live restricted key (rk_live_...)."; exit 1; }
printf %s "$STRIPE" | npx wrangler secret put STRIPE_SECRET_KEY >/dev/null
echo "   Saved STRIPE_SECRET_KEY."

echo
echo "3) Creating the Stripe webhook endpoint..."
ARGS=(-s -u "$STRIPE:" https://api.stripe.com/v1/webhook_endpoints
      -d "url=$WORKER_URL/stripe/webhook" -d "description=Hlas Cloud")
for e in "${EVENTS[@]}"; do ARGS+=(-d "enabled_events[]=$e"); done
RESPONSE="$(curl "${ARGS[@]}")"
unset STRIPE
SECRET="$(printf %s "$RESPONSE" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("secret",""))')"
if [[ "$SECRET" != whsec_* ]]; then
  echo "   Stripe did not create the endpoint:"
  printf %s "$RESPONSE" | python3 -c 'import sys,json; print("  ", json.load(sys.stdin).get("error",{}).get("message","unknown error"))'
  exit 1
fi
printf %s "$SECRET" | npx wrangler secret put STRIPE_WEBHOOK_SECRET >/dev/null
unset SECRET RESPONSE
echo "   Saved STRIPE_WEBHOOK_SECRET."

echo
echo "4) Optional: Slack incoming webhook for alerts and the daily report"
echo "   (api.slack.com/apps -> Incoming Webhooks). Press Enter to skip."
read -rsp "   Paste webhook URL: " HOOK; echo
if [[ "$HOOK" == https://hooks.slack.com/* ]]; then
  printf %s "$HOOK" | npx wrangler secret put ALERT_WEBHOOK_URL >/dev/null
  echo "   Saved ALERT_WEBHOOK_URL."
fi
unset HOOK

echo
npx wrangler secret list 2>/dev/null | grep -o '"name": "[A-Z_]*"' || true
echo
echo "Done. Tell Claude \"Hlas Cloud klíče jsou nastavené\" to switch the payment link to the welcome page."
