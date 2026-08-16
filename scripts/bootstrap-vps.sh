#!/usr/bin/env bash
# First boot on VPS: /opt/institute
# Usage: ./scripts/bootstrap-vps.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== bootstrap /opt/institute =="

if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Created .env from .env.example — edit secrets before pull."
else
  echo ".env already exists"
fi

# Strip Windows CRLF if present
sed -i 's/\r$//' deploy.sh scripts/*.sh 2>/dev/null || true
chmod +x deploy.sh scripts/*.sh

# shellcheck disable=SC1091
set -a
# shellcheck source=/dev/null
source .env
set +a

: "${DOCKER_USERNAME:?Set DOCKER_USERNAME in .env}"
: "${FRONTEND_IMAGE_TAG:?Set FRONTEND_IMAGE_TAG (git SHA) in .env}"
: "${BACKEND_IMAGE_TAG:?Set BACKEND_IMAGE_TAG (git SHA) in .env}"
: "${TURN_EXTERNAL_IP:?Set TURN_EXTERNAL_IP to VPS public IPv4}"
: "${JWT_KEY:?Set JWT_KEY (>=32 chars)}"
: "${POSTGRES_PASSWORD:?Set POSTGRES_PASSWORD}"
: "${DOMAIN_NAME:?Set DOMAIN_NAME}"

if [[ "${#JWT_KEY}" -lt 32 ]]; then
  echo "ERROR: JWT_KEY must be at least 32 characters"
  exit 1
fi

if [[ "$TURN_CREDENTIAL" == "replace-with-long-random-turn-secret" ]] || \
   [[ "$TURN_CREDENTIAL" == "instituteTurnDev" ]]; then
  echo "ERROR: Set a strong TURN_CREDENTIAL (not the placeholder / instituteTurnDev)"
  exit 1
fi

echo "Logging in to Docker Hub (if needed)..."
if [[ -n "${DOCKERHUB_TOKEN:-}" ]]; then
  echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKER_USERNAME" --password-stdin
else
  echo "Hint: export DOCKERHUB_TOKEN=... for non-interactive login, or docker login manually."
fi

echo "Pulling images..."
docker compose -p institute -f docker-compose.prod.yml pull

echo "Starting stack..."
docker compose -p institute -f docker-compose.prod.yml up -d

echo "Waiting for backend health..."
for _ in $(seq 1 40); do
  if docker inspect -f '{{.State.Health.Status}}' institute-backend-prod 2>/dev/null | grep -q healthy; then
    echo "backend healthy"
    break
  fi
  sleep 3
done

echo
echo "Bootstrap done."
echo "  Site: ${NEXT_PUBLIC_SITE_URL}"
echo "  Health: curl -fsS http://127.0.0.1:${BACKEND_PORT:-8080}/health"
echo "  TLS: self-signed until ./scripts/issue-cert.sh (after DNS A → this VPS)"
echo "  Firewall: open 80/tcp 443/tcp 3478/tcp 3478/udp 49160-49200/udp"
echo "  Seed password: rotate after first login (/account/password)"
