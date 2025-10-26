#!/usr/bin/env bash
# Generate commands to create GitHub and Kubernetes secrets for Flow7.
# By default this prints the commands for manual review. Pass --apply to execute them
# (will require `gh` for GitHub secrets and `kubectl` for k8s secrets).

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./scripts/generate_secret_commands.sh [--apply] [--namespace NAMESPACE]

This script interactively asks for values (or reads env variables) and then
prints the `gh secret set` and `kubectl create secret` commands you can run.

If --apply is passed, the script will try to run the commands (requires `gh` and/or `kubectl`).
USAGE
}

APPLY=0
NS=production
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --namespace) NS=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

prompt() {
  local varname="$1" prompt_text="$2" default="$3"
  local val
  if [[ -n "${!varname:-}" ]]; then
    val="${!varname}"
  else
    read -p "$prompt_text${default:+ [$default]}: " val
    if [[ -z "$val" && -n "$default" ]]; then
      val="$default"
    fi
  fi
  export "$varname"="$val"
}

echo "Generating secret commands for namespace: $NS"

prompt REGISTRY "Registry (e.g. ghcr.io/my-org)" "${REGISTRY:-}"
prompt REGISTRY_USERNAME "Registry username" "${REGISTRY_USERNAME:-}"
prompt REGISTRY_PASSWORD "Registry password or token (will not be shown)" "${REGISTRY_PASSWORD:-}"
prompt DATABASE_URL "DATABASE_URL (postgres://...)" "${DATABASE_URL:-}"
prompt KUBECONFIG_PATH "Path to kubeconfig file (optional)" "${KUBECONFIG_PATH:-}"
prompt FIREBASE_PATH "Path to firebase JSON file (optional)" "${FIREBASE_PATH:-}"
prompt ALLOWED_ORIGINS "ALLOWED_ORIGINS (comma-separated)" "${ALLOWED_ORIGINS:-}"
prompt APSCHEDULER_DB_URL "APSCHEDULER_DB_URL (optional)" "${APSCHEDULER_DB_URL:-}"
prompt SMOKE_TOKEN "SMOKE_TOKEN (press enter to auto-generate)" "${SMOKE_TOKEN:-}"
if [[ -z "${SMOKE_TOKEN}" ]]; then
  SMOKE_TOKEN=$(openssl rand -hex 32)
  echo "Generated SMOKE_TOKEN: $SMOKE_TOKEN"
fi
prompt CI_SMOKE_TOKEN "CI_SMOKE_TOKEN (optional, press enter to reuse SMOKE_TOKEN)" "${CI_SMOKE_TOKEN:-}"
if [[ -z "${CI_SMOKE_TOKEN}" ]]; then
  CI_SMOKE_TOKEN="$SMOKE_TOKEN"
fi
prompt SENTRY_DSN "SENTRY_DSN (optional)" "${SENTRY_DSN:-}"

echo
echo "----- GitHub secrets (commands to run) -----"

echo "# Set registry and registry credentials"
printf "gh secret set REGISTRY --body '%s'\n" "$REGISTRY"
printf "gh secret set REGISTRY_USERNAME --body '%s'\n" "$REGISTRY_USERNAME"
printf "gh secret set REGISTRY_PASSWORD --body '%s'\n" "$REGISTRY_PASSWORD"

echo
printf "gh secret set DATABASE_URL --body '%s'\n" "$DATABASE_URL"

if [[ -n "$KUBECONFIG_PATH" && -f "$KUBECONFIG_PATH" ]]; then
  echo "# KUBE_CONFIG (base64 of kubeconfig)"
  printf "base64 -w0 %s | gh secret set KUBE_CONFIG --body -\n" "$KUBECONFIG_PATH"
fi

if [[ -n "$FIREBASE_PATH" && -f "$FIREBASE_PATH" ]]; then
  echo "# FIREBASE_CREDENTIALS (base64 of service account JSON)"
  printf "base64 -w0 %s | gh secret set FIREBASE_CREDENTIALS --body -\n" "$FIREBASE_PATH"
fi

printf "gh secret set SMOKE_TOKEN --body '%s'\n" "$SMOKE_TOKEN"
printf "gh secret set CI_SMOKE_TOKEN --body '%s'\n" "$CI_SMOKE_TOKEN"

if [[ -n "$SENTRY_DSN" ]]; then
  printf "gh secret set SENTRY_DSN --body '%s'\n" "$SENTRY_DSN"
fi

echo
echo "----- Kubernetes secrets (commands to run in cluster: $NS) -----"
echo "# flow7-secrets: contains DATABASE_URL, ALLOWED_ORIGINS, SMOKE_TOKEN and optional APSCHEDULER_DB_URL & SENTRY_DSN"

printf "kubectl create secret generic flow7-secrets -n %s \\" "$NS"
printf "\n  --from-literal=DATABASE_URL='%s' \\\n+  \n  --from-literal=ALLOWED_ORIGINS='%s' \\\n+  \n  --from-literal=SMOKE_TOKEN='%s' \\\n+  \n  --from-literal=CI_SMOKE_TOKEN='%s' \\n+  \n  --dry-run=client -o yaml | kubectl apply -f -\n" "$DATABASE_URL" "$ALLOWED_ORIGINS" "$SMOKE_TOKEN" "$CI_SMOKE_TOKEN"

if [[ -n "$APSCHEDULER_DB_URL" ]]; then
  printf "# (Optional) add APSCHEDULER_DB_URL to flow7-secrets\n"
  printf "kubectl patch secret flow7-secrets -n %s --type=json -p '[{"op":"add","path":"/data/APSCHEDULER_DB_URL","value":"%s"}]' || true\n" "$NS" "$(echo -n "$APSCHEDULER_DB_URL" | base64 -w0)"
fi

if [[ -n "$FIREBASE_PATH" && -f "$FIREBASE_PATH" ]]; then
  printf "kubectl create secret generic firebase-credentials -n %s --from-file=firebase_credentials.json=%s --dry-run=client -o yaml | kubectl apply -f -\n" "$NS" "$FIREBASE_PATH"
else
  echo "# firebase-credentials not created (no file provided). Create later with kubectl create secret generic firebase-credentials --from-file=firebase_credentials.json=./path/to/firebase.json"
fi

echo
echo "----- Notes -----"
echo "Review the above commands before running. The gh commands will set repo-level secrets using your authenticated 'gh' session." 
echo "The kubectl commands apply secrets in namespace: $NS. Ensure your kubeconfig/context points to the correct cluster/namespace."

if [[ "$APPLY" -eq 1 ]]; then
  echo "--apply provided: attempting to run commands (requires gh and kubectl)"
  if ! command -v gh >/dev/null 2>&1; then
    echo "gh CLI not found; cannot apply GitHub secrets" >&2
  else
    echo "Applying GitHub secrets..."
    gh secret set REGISTRY --body "$REGISTRY"
    gh secret set REGISTRY_USERNAME --body "$REGISTRY_USERNAME"
    gh secret set REGISTRY_PASSWORD --body "$REGISTRY_PASSWORD"
    gh secret set DATABASE_URL --body "$DATABASE_URL"
    if [[ -n "$KUBECONFIG_PATH" && -f "$KUBECONFIG_PATH" ]]; then
      base64 -w0 "$KUBECONFIG_PATH" | gh secret set KUBE_CONFIG --body -
    fi
    if [[ -n "$FIREBASE_PATH" && -f "$FIREBASE_PATH" ]]; then
      base64 -w0 "$FIREBASE_PATH" | gh secret set FIREBASE_CREDENTIALS --body -
    fi
    gh secret set SMOKE_TOKEN --body "$SMOKE_TOKEN"
    gh secret set CI_SMOKE_TOKEN --body "$CI_SMOKE_TOKEN"
    if [[ -n "$SENTRY_DSN" ]]; then
      gh secret set SENTRY_DSN --body "$SENTRY_DSN"
    fi
    echo "GitHub secrets applied."
  fi

  if ! command -v kubectl >/dev/null 2>&1; then
    echo "kubectl not found; cannot apply k8s secrets" >&2
  else
    echo "Applying Kubernetes secrets to namespace $NS..."
    kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
    kubectl create secret generic flow7-secrets -n "$NS" \
      --from-literal=DATABASE_URL="$DATABASE_URL" \
      --from-literal=ALLOWED_ORIGINS="$ALLOWED_ORIGINS" \
      --from-literal=SMOKE_TOKEN="$SMOKE_TOKEN" \
      --from-literal=CI_SMOKE_TOKEN="$CI_SMOKE_TOKEN" \
      --dry-run=client -o yaml | kubectl apply -f -
    if [[ -n "$FIREBASE_PATH" && -f "$FIREBASE_PATH" ]]; then
      kubectl create secret generic firebase-credentials -n "$NS" --from-file=firebase_credentials.json="$FIREBASE_PATH" --dry-run=client -o yaml | kubectl apply -f -
      echo "firebase-credentials secret applied"
    fi
    echo "Kubernetes secrets applied."
  fi
fi

echo "Done."
