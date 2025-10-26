# CI & Kubernetes Secrets for Flow7

This document lists the exact GitHub and Kubernetes secrets required by the CI pipeline and k8s manifests, includes expected formats, and gives the commands to create them using the helper scripts already in `./scripts`.

## GitHub repository secrets (used by `.github/workflows/deploy.yml`)

- `REGISTRY` — container registry host + org (example: `ghcr.io/my-org`).
- `REGISTRY_USERNAME` — username used to push images (e.g. your GitHub username or org actor).
- `REGISTRY_PASSWORD` — registry token / password (e.g. personal access token with packages:write).
- `DATABASE_URL` — full DB connection string used by the app and CI migration step (e.g. `postgresql://user:pass@host:5432/flow7`).
- `KUBE_CONFIG` — base64-encoded kubeconfig for the target cluster. The deploy workflow decodes this into a `kubeconfig` file to run kubectl.
- `FIREBASE_CREDENTIALS` — (optional but recommended for production) base64 of the Firebase service account JSON. The `create_github_secrets.sh` script encodes the file.
- `SMOKE_TOKEN` — secret string used by the in-cluster smoke Job and CI-run container to authenticate smoke tests.
- `CI_SMOKE_TOKEN` — optional separate smoke token for runner-local smoke tests (if omitted the `SMOKE_TOKEN` is reused).
- `SENTRY_DSN` — optional Sentry DSN for error reporting (if you use Sentry in production).

Notes:
- The included script `./scripts/create_github_secrets.sh` will prompt for these values and set the GitHub secrets via the `gh` CLI. It base64-encodes kubeconfig and firebase JSON before creating secrets.

## Kubernetes secrets (used by `k8s/*.yaml` manifests)

- `flow7-secrets` (generic secret) - keys expected by Flow7 runtime:
  - `DATABASE_URL` (string)
  - `APSCHEDULER_DB_URL` (optional override for APScheduler jobstore)
  - `ALLOWED_ORIGINS` (comma-separated origins for CORS)
  - `SMOKE_TOKEN` (string used by in-cluster smoke Job)
  - `CI_SMOKE_TOKEN` (optional)
  - `SENTRY_DSN` (optional)

- `firebase-credentials` - contains a file entry named `firebase_credentials.json` with the Firebase service account JSON. Example consumed by k8s manifests via volume mount.

Example commands (manual):

```bash
# Create flow7-secrets (replace values)
kubectl create secret generic flow7-secrets \
  --from-literal=DATABASE_URL='postgres://user:pass@host:5432/db' \
  --from-literal=ALLOWED_ORIGINS='https://app.example.com' \
  --from-literal=SMOKE_TOKEN='$(openssl rand -hex 32)'

# Create firebase credentials secret (file)
kubectl create secret generic firebase-credentials --from-file=firebase_credentials.json=./path/to/firebase_credentials.json
```

## Using the helper scripts (recommended)

- Create GitHub secrets (requires `gh` CLI authenticated to the repository):

There are two helper scripts in `./scripts`:

- `create_github_secrets.sh` — interactive script that will set GitHub secrets using the `gh` CLI.
- `generate_secret_commands.sh` — interactive script that prints the exact `gh secret set` and `kubectl create secret` commands for manual review. It can also run the commands for you if you pass `--apply` (requires `gh` and `kubectl`).

Examples:

```bash
# Interactive: sets GitHub secrets via gh
./scripts/create_github_secrets.sh

# Print commands (review then run manually)
./scripts/generate_secret_commands.sh --namespace production

# Print and apply (will run gh and kubectl if available)
./scripts/generate_secret_commands.sh --namespace production --apply
```

- Create Kubernetes secrets (requires `kubectl` configured for the target cluster):

```bash
# Usage: ./scripts/create_k8s_secrets.sh <namespace>
./scripts/create_k8s_secrets.sh production

# The script prompts for DATABASE_URL, APSCHEDULER_DB_URL, ALLOWED_ORIGINS, path to firebase JSON and will create/update
# `flow7-secrets` and `firebase-credentials` in the target namespace.
```

## What you (operator) must do next

1. Run `./scripts/create_github_secrets.sh` from a machine with `gh` logged in and supply values when prompted — this will set the GitHub secrets.
2. Run `./scripts/create_k8s_secrets.sh <namespace>` with `kubectl` access to the cluster to create `flow7-secrets` and optionally `firebase-credentials`.
3. Verify in GitHub repository Settings -> Secrets that `REGISTRY`, `DATABASE_URL`, `KUBE_CONFIG`, `SMOKE_TOKEN`, etc. exist.
4. Trigger CI by pushing a tag (the `deploy.yml` triggers on tag pushes) and monitor the `build-and-push` and `migrate-and-deploy` jobs.

## Troubleshooting

- If CI cannot access the registry, confirm `REGISTRY_USERNAME` and `REGISTRY_PASSWORD` are correct and have permissions to push.
- If `kubectl` in the CI step fails, ensure `KUBE_CONFIG` contains a base64-encoded kubeconfig with correct cluster credentials and that cluster allows API access from GitHub Actions runner.
- If Firebase notifications fail in production, confirm `firebase-credentials` exists in the cluster and contains a valid service account JSON.

If you'd like I can (a) run the scripts locally if you provide values here (not recommended for secrets), or (b) walk you step-by-step through setting each secret via your local terminal. Which would you prefer?
