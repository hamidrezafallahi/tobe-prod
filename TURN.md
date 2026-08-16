# TURN (coturn) — production

Coturn runs inside `docker-compose.prod.yml` as `institute-coturn-prod`.

## Env (required)

```bash
TURN_EXTERNAL_IP=<VPS public IPv4>   # curl -4 ifconfig.me
TURN_USERNAME=institute
TURN_CREDENTIAL=<long-random>        # never instituteTurnDev
TURN_REALM=institute.local
WebRtc__Turn__Urls=turn:<same-ip>:3478
WebRtc__Turn__Username=institute
WebRtc__Turn__Credential=<same as TURN_CREDENTIAL>
```

Firewall: **TCP+UDP 3478**, **UDP 49160–49200**.

## Verify

```bash
docker logs institute-coturn-prod --tail 50
# After login, call ice-servers (JWT):
curl -s -H "Authorization: Bearer <token>" https://$DOMAIN_NAME/api/LiveSessions/ice-servers
```

## Two-network NAT checklist (demo quality)

| # | Step | Pass |
|---|------|------|
| 1 | Public IP + ports open | ☐ |
| 2 | ice-servers returns turn:\<ip\>:3478 | ☐ |
| 3 | Client A on Wi‑Fi joins class | ☐ |
| 4 | Client B on mobile hotspot joins same session | ☐ |
| 5 | Two-way audio/video | ☐ |
| 6 | Optional: chrome://webrtc-internals shows relay when P2P fails | ☐ |

Out of scope here: `turns:` TLS, SFU.
