# tobe-prod — production ops only

Clone on VPS as **`/opt/institute`**. App source + image CI live in **tobe-dev**. This repo never builds app images.

All persistent data stays under `/opt/institute` (bind mounts). Nothing is stored in Docker named volumes.

## Quick start (VPS)

```bash
sudo mkdir -p /opt/institute && sudo chown "$USER":"$USER" /opt/institute
git clone <this-repo-url> /opt/institute
cd /opt/institute
cp .env.example .env
nano .env   # secrets, DOMAIN, TURN IP, Docker Hub user, image SHAs
./scripts/bootstrap-vps.sh
# after DNS A → VPS:
./scripts/issue-cert.sh
```

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

Images: `{DOCKER_USERNAME}/institute-frontend:<sha>` · `{DOCKER_USERNAME}/institute-backend:<sha>`

## Layout

| Path | Role |
|------|------|
| `/opt/institute` | This repo, `.env`, deploy scripts |
| `/opt/institute/data/postgres` | PostgreSQL data |
| `/opt/institute/data/uploads` | User uploads |
| `/opt/institute/data/letsencrypt` | TLS certificates |
| `/opt/institute/data/certbot` | ACME webroot |
| `/opt/institute/logs` | Deploy + nginx logs |
| `/opt/institute/backups` | `pg_dump` output |

## Firewall

| Port | Proto | Why |
|------|------|------|
| 80, 443 | TCP | HTTP / HTTPS |
| 3478 | TCP+UDP | TURN |
| 49160–49200 | UDP | TURN relay |

## Docs

| File | Topic |
|------|--------|
| [DEPLOY.md](./DEPLOY.md) | First boot, secrets, CI SSH |
| [TURN.md](./TURN.md) | Coturn + two-network NAT checklist |
| [BACKUP.md](./BACKUP.md) | pg_dump / restore |

## Health

```bash
curl -fsS http://127.0.0.1:8080/health
docker compose -p institute -f docker-compose.prod.yml ps
```
