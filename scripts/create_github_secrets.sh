#!/usr/bin/env bash
# Usage: ./scripts/create_github_secrets.sh
# Requires: gh (GitHub CLI) authenticated to the target repo

set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI not found. Install from https://cli.github.com/" >&2
  exit 2
fi

read -p "Registry (e.g. ghcr.io/your-org): " REGISTRY
read -p "Registry username: " REG_USER
read -s -p "Registry password/token: " REG_PW
echo
read -p "Path to kubeconfig file (or press enter to skip): " KUBECONFIG_PATH
read -p "Path to firebase credentials JSON (or press enter to skip): " FIREBASE_PATH
read -p "Database URL (e.g. postgresql://...): " DATABASE_URL

# set secrets
gh secret set REGISTRY --body "$REGISTRY"
gh secret set REGISTRY_USERNAME --body "$REG_USER"
gh secret set REGISTRY_PASSWORD --body "$REG_PW"

echo "Setting DATABASE_URL"
gh secret set DATABASE_URL --body "$DATABASE_URL"

if [[ -n "$KUBECONFIG_PATH" && -f "$KUBECONFIG_PATH" ]]; then
  base64 -w0 "$KUBECONFIG_PATH" | gh secret set KUBE_CONFIG --body -
  echo "KUBE_CONFIG set"
fi

if [[ -n "$FIREBASE_PATH" && -f "$FIREBASE_PATH" ]]; then
  base64 -w0 "$FIREBASE_PATH" | gh secret set FIREBASE_CREDENTIALS --body -
  echo "FIREBASE_CREDENTIALS set (base64)"
fi

read -p "SMOKE token for in-cluster job (press enter to auto-generate): " SMOKE_TOKEN
if [[ -z "$SMOKE_TOKEN" ]]; then
  SMOKE_TOKEN=$(openssl rand -hex 32)
  echo "Generated SMOKE_TOKEN: $SMOKE_TOKEN"
fi
gh secret set SMOKE_TOKEN --body "$SMOKE_TOKEN"

read -p "CI_SMOKE_TOKEN (optional, press enter to reuse SMOKE_TOKEN): " CI_SMOKE_TOKEN
if [[ -z "$CI_SMOKE_TOKEN" ]]; then
  CI_SMOKE_TOKEN="$SMOKE_TOKEN"
fi
gh secret set CI_SMOKE_TOKEN --body "$CI_SMOKE_TOKEN"

echo "All requested GitHub secrets set."
