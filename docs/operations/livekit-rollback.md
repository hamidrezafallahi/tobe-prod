# LiveKit SFU — rollback

The old media path (browser mesh over SignalR + coturn) is still in the application and still the default. Rolling
back is a configuration change on this server; no image rebuild, no database change.

## Rule: switch only when no class is live

Every participant of a class must use the same provider. A browser keeps the provider it got at pre-join until the
page is reloaded, so a switch during a class splits it into two groups that cannot hear each other.

```bash
curl -s -H "Authorization: Bearer <director token>" https://<domain>/api/LiveSessions/active
# data must be [] — or ask the teacher(s) to end the class, or to have everyone reload right after the switch
```

## 1. Classes back to the mesh (fast path, ~1 minute)

```bash
cd /opt/tobe-prod
sed -i 's/^MEDIA_PROVIDER=.*/MEDIA_PROVIDER=legacy/' .env
./deploy.sh backend-env
curl -s -H "Authorization: Bearer <token>" https://<domain>/api/LiveSessions/media-provider   # "legacy"
```

LiveKit keeps running (`LIVEKIT_ENABLED=true`) but no new class uses it. Pages already open in LiveKit mode keep using
it until they reload; the next pre-join uses the mesh.

## 2. Remove LiveKit from the server

```bash
sed -i 's/^LIVEKIT_ENABLED=.*/LIVEKIT_ENABLED=false/' .env
./deploy.sh livekit-down     # stops/removes the livekit containers, re-creates nginx without the wss host
./deploy.sh backend-env      # backend without LiveKit__* settings
docker exec institute-nginx-prod nginx -t
```

`data/letsencrypt/live/<LIVEKIT_DOMAIN>` can stay (unused). Close 7881/tcp, 7882–7891/udp, 5349/tcp, 3479/udp in the
host and cloud firewall; remove the DNS record if LiveKit will not come back.

## 3. Restore coturn behaviour

Nothing to restore while it was never removed: coturn (`institute-coturn-prod`, 3478, 49160–49200/udp) and
`WebRtc__Turn__*` are untouched by the LiveKit change. Check:

```bash
docker logs institute-coturn-prod --tail 20
curl -s -H "Authorization: Bearer <token>" https://<domain>/api/LiveSessions/ice-servers   # turn:<ip>:3478 present
```

If coturn was retired (below) and has to come back: revert that commit in this repo, restore the `WebRtc__Turn__*`
values in `.env`, reopen 3478/tcp+udp and 49160–49200/udp, and `docker compose -p institute -f docker-compose.prod.yml up -d coturn`
followed by `./deploy.sh backend-env`.

## 4. Roll back the Docker configuration itself

The overlay is only read when `LIVEKIT_ENABLED=true`; after step 2 the files are inert. To remove them completely,
revert the merge of `feat/livekit-sfu` in this repo (`git revert -m 1 <merge sha>` on a branch, review, merge) and
let `deploy.sh` pull it. `deploy.sh`'s default path (frontend/backend/nginx/rollback) is unchanged by that branch.

Application images: a frontend/backend SHA without the LiveKit provider can be deployed with the normal
`./deploy.sh rollback {frontend|backend|all}`; with `MEDIA_PROVIDER=legacy` the newer images behave like the old ones.

## 5. Verify active classes are unaffected

- After any switch: `GET /api/LiveSessions/active` → for each open session, ask the teacher to confirm audio, or join
  as director and check the people panel; no "AV connection lost" notice.
- Backend logs at start show the resolved provider (`Classroom media provider: …`).
- Developer quality page: loss/RTT samples keep arriving.

## Retiring coturn (later, not part of this change)

Only after LiveKit has run classes in production for a while and:

1. no rollback to the mesh is needed any more (decision by the owner);
2. TURN/TLS through LiveKit has been seen working (`diagnostics()` → `relay` with `relayProtocol: tls`) on a network
   that blocks UDP;
3. the legacy provider is removed from the application in tobe-dev.

Then: remove the `coturn` service and `WebRtc__Turn__*` from compose/.env, close 3478 and 49160–49200/udp, and move
LiveKit's `turn.udp_port` from 3479 to 3478 (config, compose port, firewall — together).
