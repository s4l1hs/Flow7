#!/usr/bin/env bash
set -euo pipefail

# Helper script to run Alembic migrations using DATABASE_URL from env.
# Usage: DATABASE_URL=... ./scripts/migrate.sh

if [ -z "${DATABASE_URL:-}" ]; then
  echo "ERROR: DATABASE_URL must be set (example: postgresql+psycopg2://user:pass@host/db)"
  exit 2
fi

echo "Running alembic migrations against $DATABASE_URL"
alembic -c alembic.ini upgrade head

echo "Migrations complete"
#!/usr/bin/env bash
set -euo pipefail

# Run alembic migrations against DATABASE_URL
if [ -z "${DATABASE_URL+x}" ]; then
  echo "Please set DATABASE_URL environment variable"
  exit 2
fi

alembic -c alembic.ini upgrade head
