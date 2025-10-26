# Production deployment notes

This document explains the minimal steps and environment variables required to run Flow7 in production.

Environment variables
- DATABASE_URL: SQLAlchemy connection string for your Postgres (example: postgresql+psycopg2://user:pass@db/flow7)
- APSCHEDULER_DB_URL: (optional) URL for APScheduler jobstore; defaults to DATABASE_URL
- FIREBASE_CREDENTIALS: Path to the Firebase service account JSON file (required)
- LOG_LEVEL: INFO (default) or DEBUG
- ALLOWED_ORIGINS: comma-separated list of allowed CORS origins. Use '*' for all (dev). Example: https://app.example.com,https://admin.example.com
- SENTRY_DSN: optional Sentry DSN for error reporting

Key production recommendations
1. Always provide `FIREBASE_CREDENTIALS`. The application fails fast on startup if it is missing to avoid running with insecure auth.
2. Run Alembic migrations before starting the app. There is an `alembic/` scaffold in the repository; use `scripts/migrate.sh` in CI/deploy pipelines.
3. Run the scheduler in a single dedicated worker (or use leader-election) when running multiple app replicas. See `docs/SCHEDULER.md` (TODO) for options.
4. Use an external secret store (K8s secrets / Docker secrets / HashiCorp Vault) to provide `FIREBASE_CREDENTIALS` rather than committing credentials to the image.

Docker
- Build and run with Docker Compose (example):

```bash
docker compose up --build -d
```

CI
- GitHub Actions workflow `./.github/workflows/ci.yml` runs lint and tests on push/PR.

Migrations
- Use Alembic to manage schema changes. Run the migration scripts on deploy:

```bash
./scripts/migrate.sh
```

Secrets
- Never commit service account JSON files into source control.

Example Docker Compose secret (production):

```yaml
secrets:
	firebase_credentials:
		external: true
```

Then mount as `/run/secrets/firebase_credentials.json` and set `FIREBASE_CREDENTIALS=/run/secrets/firebase_credentials.json` in the container env.
