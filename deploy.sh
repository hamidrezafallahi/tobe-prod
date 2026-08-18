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
if [[ "$ROOT" != "/opt/institute" ]]; then
  echo "ERROR: this repo must live at /opt/institute (found $ROOT)."
  exit 1
fi

LOG_FILE="$ROOT/logs/deploy.log"
STATE_DIR="$ROOT/.deploy-state"
COMPOSE="docker compose -p institute -f docker-compose.prod.yml"

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
  echo "ERROR: /opt/institute/.env missing. cp .env.example .env and fill secrets."
  exit 1
fi

# Normalize scripts if cloned from Windows
sed -i 's/\r$//' deploy.sh 2>/dev/null || true
find scripts -name '*.sh' -exec sed -i 's/\r$//' {} \; 2>/dev/null || true
chmod +x deploy.sh scripts/*.sh 2>/dev/null || true

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git pull --ff-only origin master 2>/dev/null \
    || echo "WARN: could not fast-forward /opt/institute (local changes or remote unreachable)."
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
