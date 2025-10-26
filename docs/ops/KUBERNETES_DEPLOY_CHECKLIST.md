Kubernetes deploy & monitoring checklist for Flow7

This checklist helps you safely deploy Flow7 and verify scheduler + DB health.

Prerequisites
- `kubectl` configured against target cluster (kubeconfig)
- Secrets in the target namespace:
  - `flow7-secrets` with keys: `DATABASE_URL`, `APSCHEDULER_DB_URL` (optional), `ALLOWED_ORIGINS`, `SENTRY_DSN` (optional)
    - Add a `SMOKE_TOKEN` key (secret string used by in-cluster smoke Job). Optionally also add `CI_SMOKE_TOKEN` for CI-run containers.
      - Add a `SMOKE_TOKEN` key (secret string used by in-cluster smoke Job). Optionally also add `CI_SMOKE_TOKEN` for CI-run containers.
      - (Optional) `SMOKE_UID`: the uid the smoke token maps to. Defaults to `smoke-ci-user`.
      - (Optional) `ALLOW_SMOKE_TOKEN`: set to `1` to enable smoke-token acceptance by the app (default `1`).
  - `firebase-credentials` with key `firebase_credentials.json` containing the service account JSON
- Image available in registry (CI will push to `${REGISTRY}/flow7:<tag>`)

Steps
1. Apply secrets (example):

```bash
kubectl create secret generic flow7-secrets \
  --from-literal=DATABASE_URL='postgres://user:pass@host:5432/db' \
  --from-literal=APSCHEDULER_DB_URL='sqlite:////tmp/apscheduler.db' \
  --from-literal=ALLOWED_ORIGINS='https://app.example.com'

kubectl create secret generic firebase-credentials --from-file=firebase_credentials.json=./path/to/firebase_credentials.json
```

2. Apply migration Job (image substitution recommended):

```bash
export IMAGE=ghcr.io/<your-org>/flow7:<tag>
envsubst < k8s/flow7-migration-job.yaml | kubectl apply -f -
kubectl wait --for=condition=complete job/flow7-migrate --timeout=600s || kubectl logs job/flow7-migrate --all-containers
```

3. Apply main deployments and scheduler (single replica recommended):

```bash
envsubst < k8s/flow7-deployment.yaml | kubectl apply -f -
envsubst < k8s/flow7-scheduler-deployment.yaml | kubectl apply -f -
kubectl rollout status deployment/flow7 --timeout=300s
kubectl rollout status deployment/flow7-scheduler --timeout=300s
```

4. Verify health/readiness and basic endpoints

```bash
# port-forward if service isn't publicly accessible
kubectl port-forward service/flow7-web 8000:80 &
# wait a few seconds then
curl -fsS http://127.0.0.1:8000/health
curl -fsS http://127.0.0.1:8000/ready
curl -fsS http://127.0.0.1:8000/metrics
```

5. Verify scheduler pod logs and jobs

```bash
kubectl get pods -l app=flow7-scheduler
kubectl logs deployment/flow7-scheduler --tail=200
# confirm APScheduler jobs table in DB if using SQL jobstore
```

Monitoring & Alerts
- Ensure Prometheus scrapes the Flow7 metrics endpoint.
- Add rules from `docs/alerts/prometheus_rules.yml` to Prometheus config.
- Configure Alertmanager receivers (pagerduty/email/slack) for `severity=page` alerts.

Rollback
- If migration fails, do NOT immediately rollback the deployment until you've inspected the migration job logs and DB state. Consider restoring DB from backup before downgrading code.

Notes
- For high availability of scheduled jobs consider leader-election; by default the repo uses a single scheduler pod to avoid duplicate job execution.
- Always run migrations in CI before swapping traffic to a new image tag.
