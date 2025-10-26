#!/usr/bin/env bash
set -euo pipefail

# Run alembic migrations against DATABASE_URL
if [ -z "${DATABASE_URL+x}" ]; then
  echo "Please set DATABASE_URL environment variable"
  exit 2
fi

alembic -c alembic.ini upgrade head
