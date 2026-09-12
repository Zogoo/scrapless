#!/usr/bin/env bash
#
# Proves a deployment actually works, not merely that it started.
#
# Deliberately free: every line it sends resolves from the seeded dictionary, so
# no request reaches a model and a deploy never costs anything. That also makes
# it a real test of the volume, the migrations and the seeds — if any of those
# failed, the capture comes back with fewer items than asked for.
set -euo pipefail

BASE="${1:?usage: smoke-test.sh <base-url>}"

fail() { echo "✖ $*" >&2; exit 1; }

echo "→ health check"
curl -fsS --retry 8 --retry-delay 5 --retry-all-errors --max-time 30 "$BASE/up" >/dev/null \
  || fail "health check never came up"

# The SPA catch-all serves index.html for every non-API path, so a 200 from /up
# proves almost nothing on its own — a typo'd base URL passes it. Asking the API
# for a fridge without credentials must give a JSON 401, which only the real
# Rails API can do.
echo "→ API is mounted"
UNAUTH=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 30 "$BASE/api/v1/fridge")
[ "$UNAUTH" = "401" ] || fail "expected 401 from an unauthenticated API call, got $UNAUTH"

echo "→ SPA shell"
curl -fsS --max-time 30 "$BASE/today" | grep -q "<app-root>" \
  || fail "deep link did not serve the SPA shell"

echo "→ create a fridge"
TOKEN=$(curl -fsS --max-time 30 -X POST "$BASE/api/v1/fridge" \
  -H 'Content-Type: application/json' -d '{"name":"CI smoke test"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])') \
  || fail "could not create a fridge"

cleanup() {
  curl -fsS --max-time 30 -X DELETE "$BASE/api/v1/fridge" \
    -H "Authorization: Bearer $TOKEN" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "→ capture from the seeded dictionary"
COUNT=$(curl -fsS --max-time 60 -X POST "$BASE/api/v1/captures" \
  -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" \
  -d '{"source":"text","text":"brokkoli, h-milch, weizenbroetchen"}' \
  | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["items"]))') \
  || fail "capture request failed"

[ "$COUNT" -eq 3 ] || fail "expected 3 items from the dictionary, got $COUNT — seeds may not have run"

echo "→ deployment is serving requests correctly"
