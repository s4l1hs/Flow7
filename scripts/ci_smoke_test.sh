#!/usr/bin/env bash
set -euo pipefail

BASE=http://127.0.0.1:8000
# Prefer CI-provided tokens; fall back to SMOKE_TOKEN or a default for CI convenience
TOKEN=${CI_SMOKE_TOKEN:-${SMOKE_TOKEN:-ci-smoke-user}}
HDR="Authorization: Bearer ${TOKEN}"

# basic health checks
curl -fsS ${BASE}/health || (echo 'health failed' >&2; exit 2)
curl -fsS ${BASE}/metrics || (echo 'metrics failed' >&2; exit 3)

# wait a short moment for readiness endpoint
for i in {1..20}; do
  if curl -fsS ${BASE}/ready >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

# Authenticated smoke calls using DEV_ALLOW_MISSING_FIREBASE (raw uid token)
curl -fsS -H "${HDR}" ${BASE}/user/profile/ || (echo 'profile failed' >&2; exit 4)

# update theme
curl -fsS -X PUT -H "${HDR}" -H "Content-Type: application/json" -d '{"theme":"DARK"}' ${BASE}/user/theme/ || (echo 'theme update failed' >&2; exit 5)
# update language
curl -fsS -X PUT -H "${HDR}" -H "Content-Type: application/json" -d '{"language_code":"en"}' ${BASE}/user/language/ || (echo 'language update failed' >&2; exit 6)
# update notifications
curl -fsS -X PUT -H "${HDR}" -H "Content-Type: application/json" -d '{"enabled":true}' ${BASE}/user/notifications/ || (echo 'notifications update failed' >&2; exit 7)

# create a plan
TODAY=$(date +%F)
CREATE_RESP=$(curl -fsS -X POST -H "${HDR}" -H "Content-Type: application/json" -d "{\"date\":\"${TODAY}\",\"start_time\":\"12:00\",\"end_time\":\"12:30\",\"title\":\"CI smoke\",\"description\":\"smoke test\"}" ${BASE}/api/plans)
echo "$CREATE_RESP"

# list plans
curl -fsS -H "${HDR}" ${BASE}/api/plans || (echo 'list plans failed' >&2; exit 8)

echo 'CI smoke tests passed'
