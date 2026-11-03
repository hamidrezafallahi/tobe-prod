# LiveKit SFU — deployment

Architecture and application side: tobe-dev `docs/architecture/livekit-architecture.md`.
Network, DNS, ports, sizing: [livekit-network-requirements.md](./livekit-network-requirements.md).
Going back: [livekit-rollback.md](./livekit-rollback.md).

Nothing here is active until an operator turns it on. With `LIVEKIT_ENABLED=false` (default) `deploy.sh`
and CI behave exactly as before; LiveKit files are never loaded.

## What is in this repo

| File | Role |
|------|------|
| `docker-compose.livekit.yml` | Overlay: `livekit` (pinned `livekit/livekit-server:v1.13.10@sha256:89ca9ce0…`), `livekit_tls_bootstrap`, extra nginx template + env, backend `Media__Provider` / `LiveKit__*` env |
| `docker/livekit/livekit.prod.yaml` | LiveKit config (no secrets, no domain, no IP) |
| `docker/nginx/conf.d/livekit.conf` | `wss://${LIVEKIT_DOMAIN}` → `livekit:7880`; access log without query strings (the join token is in the URL); `/twirp/` closed |
| `deploy.sh` | Loads the overlay only when `LIVEKIT_ENABLED=true`; adds `livekit`, `backend-env`, `livekit-down` |
| `.env.example` | `LIVEKIT_*`, `MEDIA_PROVIDER` names with placeholders only |

Images: frontend and backend stay `${DOCKER_USERNAME}/institute-{frontend,backend}:<git sha>` from tobe-dev CI.
LiveKit is a public upstream image, pinned by version and digest; it is never built here and never `:latest`.
To upgrade: pick a new tag in tobe-dev and here together (client SDK and server must stay compatible), update the
digest from Docker Hub, test in development first.

## Two switches

| `.env` | Effect |
|--------|--------|
| `LIVEKIT_ENABLED=true` | LiveKit container, its TLS placeholder and the nginx wss host run; backend gets `LiveKit__*` |
| `MEDIA_PROVIDER=livekit` | Backend tells pre-join to use LiveKit (read only when `LIVEKIT_ENABLED=true`) |

`LIVEKIT_ENABLED=true` + `MEDIA_PROVIDER=legacy` is the safe "dark" state: the SFU runs and can be tested,
classes still use the mesh.

## Prerequisites (outside the repo, by the operator)

1. Decide the media host (same VPS or dedicated, see network requirements). Measure it first.
2. DNS: `A  livekit.<domain>  →  <public IPv4 of that host>` (e.g. `livekit.2blanguage.com`). No proxying/CDN on this name.
3. Firewall (host and cloud): open 7881/tcp, 7882–7891/udp, 5349/tcp, 3479/udp. 80/443 are already open.
4. Generate a production key pair on the server (never the development pair):
   `openssl rand -hex 8` (key), `openssl rand -base64 36` (secret).
5. A tobe-dev build that contains the LiveKit provider must be deployed (frontend + backend SHA).
   Until `MEDIA_PROVIDER=livekit` that build behaves like the old one (it asks the backend, gets `legacy`).

## Deployment sequence

Run on the VPS in `/opt/tobe-prod`, outside class hours.

```bash
# 0. Validate before changing anything (both must print a config without errors)
docker compose -p institute -f docker-compose.prod.yml config -q
docker compose -p institute -f docker-compose.prod.yml -f docker-compose.livekit.yml config -q   # after step 1

# 1. .env: LIVEKIT_ENABLED=true, MEDIA_PROVIDER=legacy, LIVEKIT_DOMAIN, LIVEKIT_NODE_IP, LIVEKIT_API_KEY, LIVEKIT_API_SECRET
nano .env

# 2. Start the SFU (+ self-signed placeholder) and nginx with the wss host
./deploy.sh livekit
docker exec institute-nginx-prod nginx -t

# 3. Real certificate for the LiveKit name (same flow as the main domain in README)
D=livekit.example.com EMAIL=you@example.com
mv data/letsencrypt/live/$D /tmp/placeholder-$D
rm -rf data/letsencrypt/archive/$D data/letsencrypt/renewal/$D.conf
docker run --rm -v "$PWD/data/letsencrypt:/etc/letsencrypt" -v "$PWD/data/certbot:/var/www/certbot" \
  certbot/certbot certonly --webroot -w /var/www/certbot --email "$EMAIL" \
  --agree-tos --no-eff-email --non-interactive -d "$D"
docker compose -p institute -f docker-compose.prod.yml -f docker-compose.livekit.yml exec -T nginx nginx -s reload
docker restart institute-livekit-prod      # TURN/TLS reads the certificate at start

# 4. Backend gets the LiveKit settings (still MEDIA_PROVIDER=legacy)
./deploy.sh backend-env

# 5. Verify the SFU (section below), then — with no class live — activate:
curl -s -H "Authorization: Bearer <director token>" https://<domain>/api/LiveSessions/active   # must be empty
sed -i 's/^MEDIA_PROVIDER=.*/MEDIA_PROVIDER=livekit/' .env
./deploy.sh backend-env
```

Certificate renewal: `certbot_renew` already renews every name under `data/letsencrypt`, and nginx reloads every 12 h.
LiveKit's TURN/TLS only reads the certificate at start: `docker restart institute-livekit-prod` outside class hours
at least once a month (Let's Encrypt renews 30 days before expiry).

## Verification

Before activation (`MEDIA_PROVIDER=legacy`):

```bash
docker compose -p institute -f docker-compose.prod.yml -f docker-compose.livekit.yml ps livekit   # healthy
docker logs institute-livekit-prod --tail 50          # no "invalid config", node IP = LIVEKIT_NODE_IP
curl -fsS https://$LIVEKIT_DOMAIN/                     # "OK" through nginx/TLS
curl -s -o /dev/null -w "%{http_code}\n" https://$LIVEKIT_DOMAIN/twirp/livekit.RoomService/ListRooms   # 404
curl -s -H "Authorization: Bearer <token>" https://<domain>/api/LiveSessions/media-provider   # {"provider":"legacy"}
```

Connectivity from outside (UDP, TCP fallback, TURN/TLS): generate a test token inside the container and use LiveKit's
connection test page or the `lk` CLI from a client machine:

```bash
docker exec institute-livekit-prod /livekit-server --config /etc/livekit.yaml \
  create-join-token --room conn-test --identity ops-test
```

After activation: open a test class (teacher + one student account) and check, in this order — two-person audio,
mute/unmute, camera on/off, screen share, student permission grant/revoke, kick, refresh, phone on mobile data,
then a five-person class. In the browser console `__classroomMedia.diagnostics()` shows codec (`opus`, `vp8`),
candidate type (`host`/`srflx` = direct UDP, `relay` = TURN), protocol, RTT, jitter, loss, simulcast layers and
health. The tobe-dev architecture doc lists the full functional/quality checklist.

## Monitoring and logs

- `docker logs institute-livekit-prod` (json-file, 5×20 MB): joins, disconnect reasons, TURN, errors.
- `logs/nginx/livekit.access.log`: signaling requests without query strings.
- Backend logs: `Classroom media provider: livekit (...)` at start; `LiveKit <Method> for room ... failed` when a
  permission sync could not reach the SFU (the class action itself still succeeded).
- Developer quality page (`/api/LiveSessions/quality-samples`) keeps receiving per-peer loss/RTT samples.
- No new monitoring platform is added. LiveKit's Prometheus endpoint exists (`prometheus.port`) if one is wanted later.

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Pre-join still says legacy | `LIVEKIT_ENABLED=true` and `MEDIA_PROVIDER=livekit` in `.env`, then `./deploy.sh backend-env`; backend log shows the resolved provider. A half-configured LiveKit (bad URL, short secret) falls back to legacy and logs why. |
| Token 403 | User not admitted yet (waiting room), kicked, or not a member — same rules as joining the class. |
| Token 409 | Provider not livekit on the backend, or session closed. |
| "AV connection lost" notice in class | Browser cannot reach `wss://LIVEKIT_DOMAIN` (DNS, certificate, nginx) — `curl https://LIVEKIT_DOMAIN/`. |
| Joins, but no audio/video | UDP 7882–7891 / TCP 7881 / TLS 5349 blocked, or `LIVEKIT_NODE_IP` wrong. `diagnostics()` → `transport` null or `relay`. |
| Everyone on `relay` | UDP to the SFU blocked by the hosting provider or cloud firewall. |
| "Class opened in another tab" message | Same user joined from a second tab/device; the newest one keeps the media (by design). |
