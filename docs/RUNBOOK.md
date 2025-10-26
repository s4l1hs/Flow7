Flow7 Runbook (basic)
======================

This runbook contains minimal operational steps for backups, migrations, and recovery.

1) Backups (Postgres)

- Logical backup (pg_dump) example:

```bash
PGPASSWORD=... pg_dump -h db -U user -Fc flow7 > flow7-$(date +%F).dump
```

- Restore:

```bash
pg_restore -h db -U user -d flow7 --clean flow7-YYYY-MM-DD.dump
```

2) Running migrations (CI or operator)

- From CI (example in `.github/workflows/deploy.yml`) the pipeline runs:

```bash
docker run --rm -e DATABASE_URL="$DATABASE_URL" my-registry/flow7:TAG \ 
  /bin/sh -c "alembic -c alembic.ini upgrade head"
```

- Locally (developer machine):

```bash
DATABASE_URL=postgresql+psycopg2://user:pass@db/flow7 ./scripts/migrate.sh
```

3) Rollback migration strategy

- If migration fails and you need to rollback:
  - Restore DB from latest dump taken prior to deployment.
  - Investigate migration failures, apply corrective migration and re-run migrations.

4) Scheduler failures

- Check `flow7-scheduler` pod logs:

```bash
kubectl logs deployment/flow7-scheduler -n your-namespace
```

- If scheduler is not running, ensure deployment has `replicas: 1` and that DB connectivity works.

5) Emergency steps (application crash)

- Check pod logs, restart deployment, and if necessary roll back image tag via:

```bash
kubectl rollout undo deployment/flow7 -n your-namespace
```

6) Contacts / On-call

- Add your on-call rotation and SRE contacts here.
