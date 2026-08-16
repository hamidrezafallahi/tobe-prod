#!/usr/bin/env bash
# P092 — pg_dump from prod Postgres container
# Usage: ./scripts/backup-db.sh [--uploads]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONTAINER="${CONTAINER:-institute-postgres-prod}"
DB="${POSTGRES_DB:-LanguageInstituteDb}"
USER="${POSTGRES_USER:-postgres}"
OUT_DIR="${OUT_DIR:-$ROOT/backups}"
KEEP="${KEEP:-14}"
INCLUDE_UPLOADS=0

if [[ "${1:-}" == "--uploads" ]]; then
  INCLUDE_UPLOADS=1
fi

if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  set -a
  # shellcheck source=/dev/null
  source .env
  set +a
  DB="${POSTGRES_DB:-$DB}"
  USER="${POSTGRES_USER:-$USER}"
fi

mkdir -p "$OUT_DIR"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
DUMP_NAME="${DB}-${STAMP}.dump"
REMOTE="/tmp/li-backup.dump"

echo "== pg_dump -Fc ${DB} from ${CONTAINER} =="
docker exec "$CONTAINER" pg_dump -U "$USER" -Fc -d "$DB" -f "$REMOTE"
docker cp "${CONTAINER}:${REMOTE}" "${OUT_DIR}/${DUMP_NAME}"
docker exec "$CONTAINER" rm -f "$REMOTE"
echo "Wrote ${OUT_DIR}/${DUMP_NAME}"

if [[ "$INCLUDE_UPLOADS" -eq 1 ]]; then
  VOL="${UPLOADS_VOLUME:-institute_uploads_prod}"
  TAR_NAME="uploads-${STAMP}.tar.gz"
  echo "== uploads volume ${VOL} =="
  docker run --rm -v "${VOL}:/data:ro" -v "${OUT_DIR}:/backup" alpine:3.20 \
    tar czf "/backup/${TAR_NAME}" -C /data .
  echo "Wrote ${OUT_DIR}/${TAR_NAME}"
fi

if [[ "$KEEP" -gt 0 ]]; then
  mapfile -t ALL < <(ls -1t "$OUT_DIR"/*.dump 2>/dev/null || true)
  if (( ${#ALL[@]} > KEEP )); then
    for old in "${ALL[@]:$KEEP}"; do
      rm -f "$old"
      echo "Pruned $(basename "$old")"
    done
  fi
fi

echo "BACKUP_OK ${DUMP_NAME}"
