#!/usr/bin/env bash
# Issue / replace Let's Encrypt cert (webroot). DNS A must already point here.
# Usage: ./scripts/issue-cert.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck disable=SC1091
set -a
# shellcheck source=/dev/null
source .env
set +a

: "${DOMAIN_NAME:?}"
: "${CERTBOT_EMAIL:?}"

echo "Requesting Let's Encrypt for ${DOMAIN_NAME} + www.${DOMAIN_NAME}"

docker compose -p institute -f docker-compose.prod.yml run --rm --entrypoint certbot certbot_renew \
  certonly --webroot -w /var/www/certbot \
  --email "${CERTBOT_EMAIL}" \
  --agree-tos --no-eff-email \
  -d "${DOMAIN_NAME}" -d "www.${DOMAIN_NAME}" \
  --force-renewal

echo "Reloading nginx..."
docker compose -p institute -f docker-compose.prod.yml exec -T nginx nginx -s reload \
  || docker compose -p institute -f docker-compose.prod.yml up -d --force-recreate --no-deps nginx

echo "CERT_OK ${DOMAIN_NAME}"
