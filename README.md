# tobe-prod — production ops only

Clone on VPS as **`/opt/tobe-prod`**. App source + image CI live in **tobe-dev**. This repo never builds app images.

All persistent data stays under `/opt/tobe-prod` (bind mounts). Nothing is stored in Docker named volumes.

## Quick start (VPS)

```bash
sudo mkdir -p /opt/tobe-prod && sudo chown "$USER":"$USER" /opt/tobe-prod
git clone <this-repo-url> /opt/tobe-prod
cd /opt/tobe-prod
cp .env.example .env
nano .env   # secrets, DOMAIN, TURN IP, Docker Hub user, image SHAs
./deploy.sh all <git-sha>
```

Until a real certificate exists, `tls_bootstrap` puts a 7-day self-signed one in place so nginx can start.
After DNS A → VPS, issue Let's Encrypt (move the self-signed placeholder aside first; Certbot refuses a `live/` dir it did not create):

```bash
DOMAIN=example.com EMAIL=you@example.com
mv data/letsencrypt/live/$DOMAIN /tmp/placeholder-$DOMAIN
rm -rf data/letsencrypt/archive/$DOMAIN data/letsencrypt/renewal/$DOMAIN.conf
docker run --rm -v "$PWD/data/letsencrypt:/etc/letsencrypt" -v "$PWD/data/certbot:/var/www/certbot" \
  certbot/certbot certonly --webroot -w /var/www/certbot --email "$EMAIL" \
  --agree-tos --no-eff-email --non-interactive -d "$DOMAIN" -d "www.$DOMAIN"
docker compose -p institute -f docker-compose.prod.yml exec -T nginx nginx -s reload
```

If Certbot fails, move `/tmp/placeholder-$DOMAIN` back. `certbot_renew` renews from then on.

Seed logins (password from `SEED_ADMIN_PASSWORD`, default `ChangeMe!123`):  
`director@institute.local` · `teacher@institute.local` · `student@institute.local` · `staff@institute.local` · `developer@institute.local`  
**Rotate after first login** → `/account/password`. Production seed with this default password requires `Seed__AllowDefaultPasswordInProduction=true`.

## Deploy new SHA (CI or manual)

```bash
./deploy.sh all <git-sha>
./deploy.sh frontend <git-sha>
./deploy.sh backend <git-sha>
./deploy.sh rollback all
```

## Administration tools

Start pgAdmin and Portainer after the production stack is running:

```bash
docker compose -p institute -f docker-compose.tools.yml up -d
```

Set `PGADMIN_DEFAULT_EMAIL` and `PGADMIN_DEFAULT_PASSWORD` in `.env` first. The
interfaces bind to the server localhost by default. From your workstation, use
an SSH tunnel:

```bash
ssh -N -L 5050:127.0.0.1:5050 -L 9443:127.0.0.1:9443 user@server
```

## Swagger (API testing and data entry)

Swagger is on in production (`Swagger__Enabled`, default `true`), but nginx only
serves `/swagger` to the server itself. From your workstation, tunnel straight to
the backend:

```bash
ssh -N -L 8080:127.0.0.1:8080 user@server
```

Then open <http://localhost:8080/swagger>, log in through `/api/Identity/...` and
paste the token into **Authorize**. Set `Swagger__Enabled=false` in `.env` and
`./deploy.sh backend <sha>` to turn it off.

Open `http://localhost:5050` for pgAdmin and `https://localhost:9443` for
Portainer. In pgAdmin, register a server with host `postgres`, port `5432`, and
the `POSTGRES_DB`, `POSTGRES_USER`, and `POSTGRES_PASSWORD` values from `.env`.

Images: `{DOCKER_USERNAME}/institute-frontend:<sha>` · `{DOCKER_USERNAME}/institute-backend:<sha>`

## Layout

| Path | Role |
|------|------|
| `/opt/tobe-prod` | This repo, `.env`, deploy scripts |
| `/opt/tobe-prod/data/postgres` | PostgreSQL data |
| `/opt/tobe-prod/data/uploads` | User uploads |
| `/opt/tobe-prod/data/backups` | Backups made from the panel |
| `/opt/tobe-prod/data/letsencrypt` | TLS certificates |
| `/opt/tobe-prod/data/certbot` | ACME webroot |
| `/opt/tobe-prod/logs` | Deploy + nginx logs |

## Firewall

| Port | Proto | Why |
|------|------|------|
| 80, 443 | TCP | HTTP / HTTPS |
| 3478 | TCP+UDP | TURN |
| 49160–49200 | UDP | TURN relay |

## Docs

| File | Topic |
|------|--------|
| [TURN.md](./TURN.md) | Coturn + two-network NAT checklist |

## Health

```bash
curl -fsS http://127.0.0.1:8080/health
docker compose -p institute -f docker-compose.prod.yml ps
```
