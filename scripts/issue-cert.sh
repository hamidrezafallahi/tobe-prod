#!/usr/bin/env bash
# Issue / replace Let's Encrypt cert (webroot). DNS A must already point here.
# Uses `docker run` (not compose run) so tls_bootstrap cannot recreate a self-signed cert.
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

LIVE_CERT="${ROOT}/data/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem"
if [[ -f "$LIVE_CERT" ]]; then
  issuer="$(openssl x509 -in "$LIVE_CERT" -noout -issuer 2>/dev/null || true)"
  if [[ "$issuer" != *"Let's Encrypt"* ]]; then
    echo "Removing self-signed placeholder so Certbot can issue a real cert..."
    rm -rf \
      "${ROOT}/data/letsencrypt/live/${DOMAIN_NAME}" \
      "${ROOT}/data/letsencrypt/archive/${DOMAIN_NAME}" \
      "${ROOT}/data/letsencrypt/renewal/${DOMAIN_NAME}.conf"
  fi
fi

docker run --rm \
  -v "${ROOT}/data/letsencrypt:/etc/letsencrypt" \
  -v "${ROOT}/data/certbot:/var/www/certbot" \
  certbot/certbot \
  certonly --webroot -w /var/www/certbot \
  --email "${CERTBOT_EMAIL}" \
  --agree-tos --no-eff-email --non-interactive \
  -d "${DOMAIN_NAME}" -d "www.${DOMAIN_NAME}"

echo "Reloading nginx..."
docker compose -p institute -f docker-compose.prod.yml exec -T nginx nginx -s reload

echo "CERT_OK ${DOMAIN_NAME}"
