# Scheduler deployment guidance

APScheduler is currently used in-process with a SQLAlchemyJobStore for persistence. For production use you should avoid running the scheduler in every web replica. Options:

1. Dedicated Scheduler Service
   - Create a small worker image that imports the same app code but starts only the scheduler (no HTTP server).
   - Run a single replica of this worker (replicated by orchestration for high availability + leader-election).

2. Leader election
   - Keep APScheduler in the app but implement leader-election (e.g., via DB lock or Redis) to ensure only one instance runs scheduled jobs.

3. Move to an external job system
   - Use Celery/RQ with Redis/Postgres for distributed task processing. This is the most scalable option for many workers and retries.

Recommend: Start with a single dedicated scheduler container that runs the same code but invokes scheduler start and a minimal health endpoint. Add leader-election later if you need multiple scheduler replicas.
