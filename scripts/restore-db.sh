#!/usr/bin/env bash
# P092 — destructive restore into prod Postgres
# Usage: ./scripts/restore-db.sh backups/LanguageInstituteDb-YYYYMMDD-HHMMSS.dump
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DUMP="${1:-}"
FORCE="${2:-}"
if [[ -z "$DUMP" ]]; then
  echo "Usage: $0 <path-to.dump> --force"
  exit 1
fi
if [[ "$FORCE" != "--force" ]]; then
  echo "Refusing restore without --force (destructive)."
  exit 1
fi

CONTAINER="${CONTAINER:-institute-postgres-prod}"
DB="${POSTGRES_DB:-LanguageInstituteDb}"
USER="${POSTGRES_USER:-postgres}"

if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  set -a
  # shellcheck source=/dev/null
  source .env
  set +a
  DB="${POSTGRES_DB:-$DB}"
  USER="${POSTGRES_USER:-$USER}"
fi

if [[ ! -f "$DUMP" ]]; then
  echo "Dump not found: $DUMP"
  exit 1
fi

echo "Stopping backend..."
docker stop institute-backend-prod || true

echo "Restoring $DUMP → $DB"
docker cp "$DUMP" "${CONTAINER}:/tmp/li-restore.dump"
docker exec -u postgres "$CONTAINER" psql -U "$USER" -d postgres -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB' AND pid <> pg_backend_pid();"
docker exec "$CONTAINER" dropdb -U "$USER" --if-exists "$DB"
docker exec "$CONTAINER" createdb -U "$USER" "$DB"
docker exec "$CONTAINER" pg_restore -U "$USER" --no-owner --dbname="$DB" /tmp/li-restore.dump
docker exec "$CONTAINER" rm -f /tmp/li-restore.dump

echo "Starting backend..."
docker start institute-backend-prod

echo "RESTORE_OK $DUMP"
