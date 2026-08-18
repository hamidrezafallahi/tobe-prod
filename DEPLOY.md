# Deploy — VPS runbook

## Layout

| Path | Role |
|------|------|
| `/opt/institute` | This repo (compose, nginx, scripts, `.env`) |
| `/opt/institute/data` | Postgres, uploads, Let's Encrypt, certbot webroot |
| `/opt/institute/logs` | `deploy.log` + nginx logs |
| Docker Hub | `institute-frontend:<sha>` / `institute-backend:<sha>` from **tobe-dev** CI |
| GitHub secrets (on **tobe-dev**) | `DOCKER_USERNAME`, `DOCKERHUB_TOKEN`, `VPS_HOST`, `VPS_USER`, `VPS_PORT`, `SSH_PRIVATE_KEY` |

CI SSHs to the VPS and runs `./deploy.sh … <sha>` — it does **not** clone app source onto the VPS.

Compose project name is `institute` (container names `institute-*-prod`). Ops home is `/opt/institute`.

## First boot checklist

1. DNS **A** record → VPS public IPv4 (`DOMAIN_NAME` + optional `www`).
2. Open firewall: `80/tcp`, `443/tcp`, `3478/tcp`, `3478/udp`, `49160-49200/udp`.
3. `git clone` this repo to `/opt/institute`.
4. `cp .env.example .env` and set at least:
   - `POSTGRES_PASSWORD`, `JWT_KEY` (≥32)
   - `DOCKER_USERNAME`, `FRONTEND_IMAGE_TAG`, `BACKEND_IMAGE_TAG` (real SHAs already pushed)
   - `DOMAIN_NAME`, `SERVER_IP`, `CERTBOT_EMAIL`, `NEXT_PUBLIC_SITE_URL`
   - `TURN_EXTERNAL_IP` (= public IP), strong `TURN_CREDENTIAL`
   - Matching `WebRtc__Turn__Urls` / Username / Credential
5. `docker login` (or `DOCKERHUB_TOKEN` for bootstrap).
6. `./scripts/bootstrap-vps.sh`
7. Browser: accept self-signed once, or run `./scripts/issue-cert.sh` for Let's Encrypt.
8. Login as director → change seed password.
9. Optional: enable SMTP in `.env`, recreate backend.

## Day-2 deploy

```bash
cd /opt/institute
./deploy.sh all <new-sha>
```

GitHub Actions on **tobe-dev** (push to `master`):

1. Detect whether `FrontEnd/**` and/or `BackEnd/**` changed.
2. Build and push only those images, tagged with the git SHA.
3. SSH in and run `./deploy.sh {frontend|backend|all} <sha>`.
4. Recreate the changed service(s) and refresh nginx.

Rollback uses previous SHA stored under `.deploy-state/`.

## Relocate from `/opt/tobe` or `/opt/shop`

If the stack already runs from an older path with Docker named volumes:

```bash
./scripts/relocate-to-institute.sh
```

That stops the stack, moves the repo to `/opt/institute`, copies volumes into `/opt/institute/data` and `/opt/institute/logs`, then starts again on bind mounts. Old named volumes are left in place until you confirm health, then:

```bash
docker volume rm institute_institute-postgres-data-prod institute_uploads_prod institute_letsencrypt institute_certbot-webroot institute_nginx-logs
```

## Demo tonight (honest)

- Stack is production-shaped; **Gate F public claim** stays withheld until field pilot (`PILOT_P098` in tobe-dev).
- Classroom AV needs TURN + two clients (ideally two networks — see `TURN.md`).
- Do not advertise “سایت آموزشگاهی کامل” until field sign-off.

## Troubleshooting

| Symptom | Check |
|---------|--------|
| nginx won't start | `docker logs institute-tls-bootstrap`; certs under `/opt/institute/data/letsencrypt` |
| 502 on /api | `docker logs institute-backend-prod`; `curl 127.0.0.1:8080/health` |
| No AV across NAT | TURN IP/ports; `WebRtc__Turn__*` must match coturn user |
| Image pull denied | `docker login` + correct `DOCKER_USERNAME` |
