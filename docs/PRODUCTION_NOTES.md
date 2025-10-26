Production deployment notes

This document explains the minimal steps and environment variables required to run Flow7 in production.

Environment variables
- DATABASE_URL: SQLAlchemy connection string for your Postgres (example: postgresql+psycopg2://user:pass@db/flow7)
- APSCHEDULER_DB_URL: (optional) URL for APScheduler jobstore; defaults to DATABASE_URL
- FIREBASE_CREDENTIALS: Path to the Firebase service account JSON file inside the container (required). We recommend mounting it at /run/secrets/firebase_credentials.json.
- LOG_LEVEL: INFO (default) or DEBUG
- LOG_JSON: set to `1` to enable structured JSON logs in production
- ALLOWED_ORIGINS: comma-separated list of allowed CORS origins. Example: https://app.example.com,https://admin.example.com
- SENTRY_DSN: optional Sentry DSN for error reporting

Key production recommendations
1. Always provide `FIREBASE_CREDENTIALS`. The application fails fast on startup if it is missing to avoid running with insecure auth.
2. Run Alembic migrations before starting the app. There is an `alembic/` scaffold in the repository; use `scripts/migrate.sh` in CI/deploy pipelines.
3. Run the scheduler in a single dedicated worker (or use leader-election) when running multiple app replicas. The repo includes `scheduler_worker.py` and `docker-compose.yml` has an example `scheduler` service.
4. Use an external secret store (K8s secrets / Docker secrets / HashiCorp Vault) to provide `FIREBASE_CREDENTIALS` rather than committing credentials to the image.

Docker (example: production with Docker Swarm / Compose)
- Create the Docker secret locally (on the host where you will run the stack):

```bash
docker secret create firebase_credentials /path/to/service-account.json
```

- The `docker-compose.yml` in this repo expects the external secret named `firebase_credentials` and mounts it at `/run/secrets/firebase_credentials.json` for both `app` and `scheduler` services. The container env should set:

```
FIREBASE_CREDENTIALS=/run/secrets/firebase_credentials.json
```

Kubernetes
- Create a Kubernetes secret for the service account JSON and mount it into the pod:

```bash
kubectl create secret generic firebase-credentials --from-file=firebase_credentials.json=/path/to/service-account.json -n your-namespace
```

# Example deployment snippet (volume + mount):
```
volumes:
  - name: firebase-credentials
    secret:
      secretName: firebase-credentials

volumeMounts:
  - name: firebase-credentials
    mountPath: /run/secrets/firebase_credentials.json
    subPath: firebase_credentials.json
```

Vault / Secret Manager
- For larger infra, store the service account JSON in Vault or cloud secret manager and project it into the container at `/run/secrets/firebase_credentials.json`, using an init container or sidecar pattern to write the file before the app starts.

Scheduler deployment
--------------------
To avoid duplicate scheduled job execution, run a single instance of the scheduler worker. This repository includes `scheduler_worker.py` and `docker-compose.yml` provides a `scheduler` service that runs it. In Kubernetes, run a single-replica Deployment or use a leader-election mechanism.

Leader-election alternatives:
- Use Postgres advisory locks for leader election before starting scheduler loops.
- Use Redis-based distributed locks (e.g., Redlock) if you already have Redis in the infra.

CI / Deploy notes
-----------------
We recommend a deploy pipeline that follows these steps:

1. Build and push a tagged container image to your registry (ECR/GCR/ACR/DockerHub).
2. Run Alembic migrations against the target `DATABASE_URL` (use a migration role with appropriate privileges).
3. Deploy the new image to your orchestrator (Kubernetes/Swarm) and roll traffic.

Observability & logs
--------------------
Set `LOG_JSON=1` in production for structured JSON logs. Configure `SENTRY_DSN` to enable Sentry error capture. The application exposes Prometheus metrics at `/metrics`.

Prometheus example scrape config (docs/prometheus.yml):

```yaml
scrape_configs:
  - job_name: 'flow7'
    static_configs:
      - targets: ['flow7.example.com:8000']
    metrics_path: /metrics
    scheme: http
```

Monitoring & alert ideas
- Alert on elevated 5xx rate and request error rate.
- Alert if scheduler job failures increase or if scheduler misses heartbeats.
- Track FCM success/failure rates.

Security & ops reminders
------------------------
- Terminate TLS at the edge (load balancer / ingress controller).
- Set `ALLOWED_ORIGINS` to your frontend origin(s) (do not use `*` in production).
- Use least-privilege DB credentials and rotate them regularly.
- Rotate service account JSON and audit access to secrets in your secret manager.

Quick "try it" (docker-compose local production-like run)
-----------------------------------------------------
# create the secret locally first:
docker secret create firebase_credentials /path/to/service-account.json
docker compose up -d --build

Replace the Docker secret creation with the equivalent in your orchestration platform when deploying to production.
