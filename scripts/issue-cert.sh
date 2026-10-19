#!/usr/bin/env bash
# Issue / replace Let's Encrypt cert (webroot). DNS A must already point here.
# Uses `docker run` (not compose run) so tls_bootstrap cannot recreate a self-signed cert.
# Usage: ./scripts/issue-cert.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Read only the keys we need: sourcing .env breaks on unquoted values with spaces
# (e.g. NEXT_PUBLIC_SITE_NAME=کالج زبان tobe), which docker compose accepts.
env_get() {
  grep -E "^$1=" .env | tail -n1 | cut -d= -f2- | sed -e 's/^["'\'']//' -e 's/["'\'']$//' -e 's/\r$//'
}
DOMAIN_NAME="${DOMAIN_NAME:-$(env_get DOMAIN_NAME)}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-$(env_get CERTBOT_EMAIL)}"

: "${DOMAIN_NAME:?}"
: "${CERTBOT_EMAIL:?}"

echo "Requesting Let's Encrypt for ${DOMAIN_NAME} + www.${DOMAIN_NAME}"

LIVE_CERT="${ROOT}/data/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem"
if [[ -f "$LIVE_CERT" ]]; then
  issuer="$(openssl x509 -in "$LIVE_CERT" -noout -issuer 2>/dev/null || true)"
  if [[ "$issuer" != *"Let's Encrypt"* ]]; then
    # Certbot refuses a live/ dir it did not create; move the placeholder aside
    # and put it back if issuance fails, so nginx can still (re)start.
    echo "Moving self-signed placeholder aside so Certbot can issue a real cert..."
    PLACEHOLDER_BAK="$(mktemp -d)"
    mv "${ROOT}/data/letsencrypt/live/${DOMAIN_NAME}" "$PLACEHOLDER_BAK/"
    rm -rf \
      "${ROOT}/data/letsencrypt/archive/${DOMAIN_NAME}" \
      "${ROOT}/data/letsencrypt/renewal/${DOMAIN_NAME}.conf"
  fi
fi

restore_placeholder() {
  if [[ -n "${PLACEHOLDER_BAK:-}" && ! -e "${ROOT}/data/letsencrypt/live/${DOMAIN_NAME}" ]]; then
    echo "Certbot failed; restoring self-signed placeholder."
    mv "$PLACEHOLDER_BAK/${DOMAIN_NAME}" "${ROOT}/data/letsencrypt/live/${DOMAIN_NAME}"
  fi
}
trap restore_placeholder ERR

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
