#!/usr/bin/env bash
# Usage: ./scripts/create_k8s_secrets.sh <namespace>
# Creates `flow7-secrets` and `firebase-credentials` from provided env or files.

set -euo pipefail
NS=${1:-default}

read -p "DATABASE_URL: " DATABASE_URL
read -p "APSCHEDULER_DB_URL (optional): " APSCHEDULER_DB_URL
read -p "ALLOWED_ORIGINS (comma-separated): " ALLOWED_ORIGINS
read -p "Path to firebase credentials JSON file (or press enter to skip): " FIREBASE_PATH
read -p "SMOKE_TOKEN (press enter to auto-generate): " SMOKE_TOKEN
if [[ -z "$SMOKE_TOKEN" ]]; then
  SMOKE_TOKEN=$(openssl rand -hex 32)
  echo "Generated SMOKE_TOKEN: $SMOKE_TOKEN"
fi

# create secret yaml to avoid shell escaping issues
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic flow7-secrets -n "$NS" \
  --from-literal=DATABASE_URL="${DATABASE_URL}" \
  --from-literal=ALLOWED_ORIGINS="${ALLOWED_ORIGINS}" \
  --from-literal=SMOKE_TOKEN="${SMOKE_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

if [[ -n "$APSCHEDULER_DB_URL" ]]; then
  kubectl patch secret flow7-secrets -n "$NS" --patch "{\"data\":{}}" || true
  kubectl create secret generic flow7-secrets -n "$NS" --from-literal=APSCHEDULER_DB_URL="${APSCHEDULER_DB_URL}" --dry-run=client -o yaml | kubectl apply -f -
fi

if [[ -n "$FIREBASE_PATH" && -f "$FIREBASE_PATH" ]]; then
  kubectl create secret generic firebase-credentials -n "$NS" --from-file=firebase_credentials.json="$FIREBASE_PATH" --dry-run=client -o yaml | kubectl apply -f -
  echo "Created firebase-credentials secret"
else
  echo "No firebase credentials provided; create firebase-credentials secret later if needed"
fi

echo "Kubernetes secrets created/updated in namespace $NS"
