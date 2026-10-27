#!/bin/bash
# =============================================================================
# Deploy / rollback using immutable image tags (git SHA).
#
# Usage:
#   ./deploy.sh frontend <sha>
#   ./deploy.sh backend <sha>
#   ./deploy.sh all <sha>
#   ./deploy.sh nginx
#   ./deploy.sh rollback frontend
#   ./deploy.sh rollback backend
#   ./deploy.sh rollback all
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
if [[ "$ROOT" != "/opt/tobe-prod" ]]; then
  echo "ERROR: this repo must live at /opt/tobe-prod (found $ROOT)."
  exit 1
fi

LOG_FILE="$ROOT/logs/deploy.log"
STATE_DIR="$ROOT/.deploy-state"
COMPOSE="docker compose -p institute -f docker-compose.prod.yml"
ALPINE_IMAGE="alpine:3.24.3@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a"

ensure_dirs() {
  mkdir -p \
    "$ROOT/data/postgres" \
    "$ROOT/data/uploads" \
    "$ROOT/data/letsencrypt" \
    "$ROOT/data/certbot" \
    "$ROOT/logs/nginx" \
    "$ROOT/backups" \
    "$STATE_DIR"
}

ensure_dirs

# هم در GitHub Actions نمایش داده می‌شود و هم در فایل لاگ ذخیره می‌شود.
exec > >(tee -a "$LOG_FILE") 2>&1

cd "$ROOT"

echo "=================================================="
echo "Deploy started at: $(date)"
echo "Args: $*"
echo "=================================================="

if [[ ! -f .env ]]; then
  echo "ERROR: /opt/tobe-prod/.env missing. cp .env.example .env and fill secrets."
  exit 1
fi

# Normalize line endings if cloned from Windows
sed -i 's/\r$//' deploy.sh 2>/dev/null || true
chmod +x deploy.sh 2>/dev/null || true

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git pull --ff-only origin master 2>/dev/null \
    || echo "WARN: could not fast-forward /opt/tobe-prod (local changes or remote unreachable)."
fi

read_sha() {
  local service="$1"
  local file="$STATE_DIR/${service}.sha"
  if [[ -f "$file" ]]; then
    cat "$file"
  fi
}

write_sha() {
  local service="$1"
  local sha="$2"
  local file="$STATE_DIR/${service}.sha"
  local prev="$STATE_DIR/${service}.sha.prev"

  if [[ -f "$file" ]]; then
    cp "$file" "$prev"
  fi
  echo -n "$sha" > "$file"
}

update_env_tag() {
  local var_name="$1"
  local sha="$2"

  if grep -q "^${var_name}=" .env 2>/dev/null; then
    sed -i "s|^${var_name}=.*|${var_name}=${sha}|" .env
  else
    echo "${var_name}=${sha}" >> .env
  fi
}

wait_healthy() {
  local service="$1"
  local container="institute-${service}-prod"
  echo "Waiting for $container to become healthy..."
  for _ in $(seq 1 40); do
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container" 2>/dev/null || true)"
    if [[ "$status" == "healthy" ]]; then
      echo "$container is $status"
      return 0
    fi
    sleep 3
  done
  echo "ERROR: $container did not become healthy in time (last=${status:-unknown})"
  return 1
}

recreate_nginx() {
  echo "Recreating nginx..."
  $COMPOSE up -d --force-recreate --no-deps nginx
}

# The backend runs as uid/gid 1654 ("app"). The uploads bind mount lives on
# the host, so Dockerfile ownership alone cannot make it writable. Ensure the
# host directory is owned by the backend user before deployment.
ensure_uploads_dir() {
  local dir="$ROOT/data/uploads"
  mkdir -p "$dir"

  if [[ "$(stat -c '%u:%g' "$dir")" != "1654:1654" ]]; then
    echo "Giving $dir to uid/gid 1654 (backend app user)..."
    docker run --rm -v "$dir:/uploads" "$ALPINE_IMAGE" \
      chown -R 1654:1654 /uploads \
      || {
        echo "ERROR: could not give $dir to uid/gid 1654; backend uploads may fail."
        return 1
      }
  fi
}

# Panel backups are written by the backend's non-root "app" user (uid 1654).
ensure_backups_dir() {
  local dir="$ROOT/data/backups"
  mkdir -p "$dir"
  if [[ "$(stat -c '%u' "$dir")" != "1654" ]]; then
    echo "Giving $dir to uid 1654 (backend app user)..."
    docker run --rm -v "$dir:/backups" "$ALPINE_IMAGE" \
      chown 1654:1654 /backups \
      || echo "WARN: could not give $dir to uid 1654; panel backups fail until the backend can write there."
  fi
}

deploy_service() {
  local service="$1"
  local sha="$2"
  local var_name

  if [[ -z "$sha" ]]; then
    echo "ERROR: SHA is required for $service deploy (do not use :latest)."
    echo "Usage: ./deploy.sh $service <git-sha>"
    exit 1
  fi

  if [[ "$service" == "frontend" ]]; then
    var_name="FRONTEND_IMAGE_TAG"
  elif [[ "$service" == "backend" ]]; then
    var_name="BACKEND_IMAGE_TAG"
  else
    echo "ERROR: Unknown service '$service'"
    exit 1
  fi

  echo "Deploying $service @ $sha"
  update_env_tag "$var_name" "$sha"
  export "$var_name=$sha"

  $COMPOSE pull "$service"
  $COMPOSE up -d --force-recreate --no-deps "$service"
  wait_healthy "$service"
  write_sha "$service" "$sha"
}

rollback_service() {
  local service="$1"
  local prev_file="$STATE_DIR/${service}.sha.prev"
  if [[ ! -f "$prev_file" ]]; then
    echo "ERROR: No previous SHA for $service (cannot rollback)."
    exit 1
  fi
  local prev
  prev="$(cat "$prev_file")"
  if [[ -z "$prev" ]]; then
    echo "ERROR: Previous SHA for $service is empty."
    exit 1
  fi
  echo "Rolling back $service to $prev"
  deploy_service "$service" "$prev"
}

# Ensure writable host bind mounts before any deployment action.
ensure_uploads_dir
ensure_backups_dir

ACTION="${1:-}"
ARG2="${2:-}"

case "$ACTION" in
  frontend|backend)
    deploy_service "$ACTION" "$ARG2"
    recreate_nginx
    ;;

  all)
    deploy_service frontend "$ARG2"
    deploy_service backend "$ARG2"
    recreate_nginx
    ;;

  nginx)
    recreate_nginx
    ;;

  rollback)
    TARGET="${ARG2:-}"
    case "$TARGET" in
      frontend|backend)
        rollback_service "$TARGET"
        recreate_nginx
        ;;
      all)
        rollback_service frontend
        rollback_service backend
        recreate_nginx
        ;;
      *)
        echo "Usage: ./deploy.sh rollback {frontend|backend|all}"
        exit 1
        ;;
    esac
    ;;

  *)
    echo "Usage:"
    echo "  ./deploy.sh {frontend|backend|all} <sha>"
    echo "  ./deploy.sh nginx"
    echo "  ./deploy.sh rollback {frontend|backend|all}"
    echo "Current frontend SHA: $(read_sha frontend || true)"
    echo "Current backend SHA:  $(read_sha backend || true)"
    exit 1
    ;;
esac

echo
echo "Pruning unused images..."
docker image prune -f

echo "=================================================="
echo "Deploy finished successfully at: $(date)"
echo "Frontend SHA: $(read_sha frontend || true)"
echo "Backend SHA:  $(read_sha backend || true)"
echo "Frontend image: $(docker inspect institute-frontend-prod --format '{{.Config.Image}}' 2>/dev/null || true)"
echo "Backend image:  $(docker inspect institute-backend-prod --format '{{.Config.Image}}' 2>/dev/null || true)"
echo "=================================================="
