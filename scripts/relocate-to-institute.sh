#!/usr/bin/env bash
# One-shot: move ops repo to /opt/institute and copy Docker named volumes into bind mounts.
# Safe to re-run: skips copy when destination already has files.
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: run as root"
  exit 1
fi

OLD=""
for d in /opt/tobe /opt/shop /opt/institute; do
  if [[ -f "$d/docker-compose.prod.yml" ]]; then
    OLD="$d"
    break
  fi
done

if [[ -z "$OLD" ]]; then
  echo "ERROR: could not find docker-compose.prod.yml under /opt/tobe, /opt/shop, or /opt/institute"
  exit 1
fi

echo "== stopping stack in $OLD =="
cd "$OLD"
docker compose -p institute -f docker-compose.prod.yml stop

if [[ "$OLD" != "/opt/institute" ]]; then
  if [[ -e /opt/institute ]]; then
    echo "ERROR: /opt/institute already exists; will not overwrite."
    exit 1
  fi
  echo "== moving $OLD -> /opt/institute =="
  mv "$OLD" /opt/institute
fi

cd /opt/institute
mkdir -p data/postgres data/uploads data/letsencrypt data/certbot logs/nginx backups .deploy-state

copy_vol() {
  local vol="$1"
  local dest="$2"
  if ! docker volume inspect "$vol" >/dev/null 2>&1; then
    echo "skip missing volume $vol"
    return 0
  fi
  if [[ -n "$(ls -A "$dest" 2>/dev/null || true)" ]]; then
    echo "keep existing $dest"
    return 0
  fi
  echo "copy $vol -> $dest"
  docker run --rm \
    -v "${vol}:/from:ro" \
    -v "${dest}:/to" \
    alpine:3.20 \
    sh -c 'cp -a /from/. /to/'
}

copy_vol institute_institute-postgres-data-prod /opt/institute/data/postgres
copy_vol institute_uploads_prod /opt/institute/data/uploads
copy_vol institute_letsencrypt /opt/institute/data/letsencrypt
copy_vol institute_certbot-webroot /opt/institute/data/certbot
copy_vol institute_nginx-logs /opt/institute/logs/nginx

if [[ -f /var/log/institute-deploy.log ]] && [[ ! -f /opt/institute/logs/deploy.log ]]; then
  mv /var/log/institute-deploy.log /opt/institute/logs/deploy.log
fi

if [[ ! -f /opt/institute/data/postgres/PG_VERSION ]]; then
  echo "ERROR: postgres data missing PG_VERSION — aborting start to avoid empty DB."
  exit 1
fi

sed -i 's/\r$//' deploy.sh scripts/*.sh 2>/dev/null || true
chmod +x deploy.sh scripts/*.sh

echo "== starting stack from /opt/institute (bind mounts) =="
docker compose -p institute -f docker-compose.prod.yml up -d --force-recreate

echo "Waiting for backend health..."
for _ in $(seq 1 40); do
  if docker inspect -f '{{.State.Health.Status}}' institute-backend-prod 2>/dev/null | grep -q healthy; then
    echo "backend healthy"
    echo "RELOCATE_OK /opt/institute"
    exit 0
  fi
  sleep 3
done

echo "ERROR: backend did not become healthy after relocate"
docker compose -p institute -f docker-compose.prod.yml ps
exit 1
