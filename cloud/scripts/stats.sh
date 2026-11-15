#!/usr/bin/env bash
# Hlas Cloud numbers from the live D1 database: funnel, customers, usage.
#   bash cloud/scripts/stats.sh [days]   (default 14)
set -euo pipefail
cd "$(dirname "$0")/.."
DAYS="${1:-14}"
q() { npx wrangler d1 execute hlas-cloud --remote --command "$1" 2>/dev/null | python3 -c '
import sys, json
raw = sys.stdin.read(); rows = json.loads(raw[raw.index("["):])[0]["results"]
if not rows: print("  (nothing yet)"); sys.exit()
cols = list(rows[0]); w = [max(len(str(c)), *(len(str(r[c])) for r in rows)) for c in cols]
print("  " + "  ".join(str(c).ljust(x) for c, x in zip(cols, w)))
for r in rows: print("  " + "  ".join(str(r[c]).ljust(x) for c, x in zip(cols, w)))'; }

echo "Funnel, last $DAYS days"
q "SELECT name, SUM(count) AS total FROM events WHERE day >= date('now','-$DAYS days') AND name NOT LIKE '%:%' GROUP BY name ORDER BY total DESC"
echo; echo "Downloads and checkouts by page language"
q "SELECT name, SUM(count) AS total FROM events WHERE day >= date('now','-$DAYS days') AND name LIKE '%:%' GROUP BY name ORDER BY total DESC LIMIT 20"
echo; echo "Customers"
q "SELECT SUM(stripe_customer_id NOT LIKE 'trial_%' AND entitled=1) AS paying, SUM(stripe_customer_id NOT LIKE 'trial_%' AND entitled=0) AS lapsed, SUM(stripe_customer_id LIKE 'trial_%' AND period_end > unixepoch()) AS trials_running, SUM(stripe_customer_id LIKE 'trial_%') AS trials_total FROM customers"
echo; echo "Usage per day (Groq whisper-large-v3-turbo at \$0.04/h)"
q "SELECT day, COUNT(*) AS users, SUM(requests) AS requests, ROUND(SUM(audio_seconds)/3600.0,2) AS hours, ROUND(SUM(audio_seconds)/3600.0*0.04,2) AS usd FROM usage WHERE day >= date('now','-$DAYS days') GROUP BY day ORDER BY day DESC"
