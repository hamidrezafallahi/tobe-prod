# Deploy — VPS runbook

## Layout

| Path | Role |
|------|------|
| `/opt/institute` | This repo (compose, nginx, scripts, `.env`) |
| Docker Hub | `institute-frontend:<sha>` / `institute-backend:<sha>` from **tobe-dev** CI |
| GitHub secrets (on **tobe-dev**) | `DOCKER_USERNAME`, `DOCKERHUB_TOKEN`, `VPS_HOST`, `VPS_USER`, `VPS_PORT`, `SSH_PRIVATE_KEY` |

CI SSHs to the VPS and runs `./deploy.sh … <sha>` — it does **not** clone app source onto the VPS.

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

Rollback uses previous SHA stored under `.deploy-state/`.

## Demo tonight (honest)

- Stack is production-shaped; **Gate F public claim** stays withheld until field pilot (`PILOT_P098` in tobe-dev).
- Classroom AV needs TURN + two clients (ideally two networks — see `TURN.md`).
- Do not advertise “سایت آموزشگاهی کامل” until field sign-off.

## Troubleshooting

| Symptom | Check |
|---------|--------|
| nginx won't start | `docker logs institute-tls-bootstrap`; certs under volume `letsencrypt` |
| 502 on /api | `docker logs institute-backend-prod`; `curl 127.0.0.1:8080/health` |
| No AV across NAT | TURN IP/ports; `WebRtc__Turn__*` must match coturn user |
| Image pull denied | `docker login` + correct `DOCKER_USERNAME` |
