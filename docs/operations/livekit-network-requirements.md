# LiveKit SFU — network, DNS, TLS, host and region

## Traffic paths

| Path | Transport | Through nginx? |
|------|-----------|----------------|
| Browser → `wss://LIVEKIT_DOMAIN` (signaling, token in URL) | TCP 443, TLS by nginx → `livekit:7880` | yes |
| Browser ↔ SFU media (preferred) | UDP `LIVEKIT_NODE_IP:7882–7891` (ICE, DTLS-SRTP) | **no** |
| Browser ↔ SFU media, UDP blocked | TCP `7881` (ICE/TCP) | no |
| Browser ↔ SFU media, only TLS allowed | TURN/TLS `LIVEKIT_DOMAIN:5349` | no |
| Browser ↔ SFU media via TURN/UDP | UDP `3479` | no |
| Backend → SFU room API (Twirp) | HTTP `livekit:7880` on the Docker network | no (closed on the public host) |

nginx only ever carries the WebSocket. Media is encrypted end to end between browser and SFU (DTLS-SRTP) and goes
straight to the container ports.

## Ports — one list for config, compose, host firewall and cloud firewall

| Port | Proto | Config key (`livekit.prod.yaml`) | Compose (`docker-compose.livekit.yml`) | Open to |
|------|-------|----------------------------------|----------------------------------------|---------|
| 443 | TCP | — (nginx) | nginx, already published | internet (already) |
| 80 | TCP | — (nginx, ACME) | already published | internet (already) |
| 7880 | TCP | `port` | **not published** | Docker network only |
| 7881 | TCP | `rtc.tcp_port` | `7881:7881/tcp` | internet |
| 7882–7891 | UDP | `rtc.udp_port: 7882-7891` | `7882-7891:7882-7891/udp` | internet |
| 5349 | TCP | `turn.tls_port` | `5349:5349/tcp` | internet |
| 3479 | UDP | `turn.udp_port` | `3479:3479/udp` | internet |

Unchanged while the legacy mesh is kept: coturn 3478/tcp+udp and 49160–49200/udp.
Example host firewall (ufw): `ufw allow 7881/tcp; ufw allow 7882:7891/udp; ufw allow 5349/tcp; ufw allow 3479/udp`.
Docker-published ports bypass ufw's INPUT chain, so the **cloud/provider firewall** must also allow exactly these
(and nothing in 7880). Do not open 50000–60000: this setup does not use that range.

Not done here: DSCP/QoS marking (no evidence the host or the networks in between honour it).

## Host networking vs published ports

| | Bridge + published ports (chosen) | `network_mode: host` |
|---|---|---|
| Fits current stack | yes: same network, nginx reaches `livekit:7880` by name | nginx (bridge) would need `host-gateway` and 7880 bound on the host |
| UDP | 10-port mux, cheap to publish | any range, no NAT |
| Overhead | Docker DNAT/conntrack per packet (small at this scale) | none |
| TURN relay to the SFU | hairpins through the host's public IP — verify in the TURN test | direct |
| Recommended for | the co-located single VPS, small number of concurrent classes | a dedicated media host |

On a dedicated media server use host networking with the same `livekit.prod.yaml` (keep `rtc.udp_port`), run a small
TLS proxy (nginx/Caddy) for `wss://` on that host, and point `LiveKit__ApiUrl` at it over a private network or HTTPS.

## DNS and TLS

- Record to add (operator, not done by this repo): `livekit.<domain>  A  <public IPv4 of the LiveKit host>`.
  The name must resolve directly to that host (no HTTP proxy/CDN): TURN/TLS and media go to the same IP.
- Current domains seen (2026-11-02, read-only DNS): `2blanguage.com → 185.213.167.252` (the site tobe-dev CI builds for),
  `hamidrezafallahi.ir → 188.240.196.165` (the `.env.example` defaults). `livekit.2blanguage.com` has no record yet.
  Confirm which host is production before choosing `LIVEKIT_DOMAIN` / `LIVEKIT_NODE_IP`.
- Certificate: Let's Encrypt for `LIVEKIT_DOMAIN` (deployment doc step 3), used by nginx (wss) and by LiveKit
  TURN/TLS (mounted read-only). The self-signed placeholder only keeps nginx starting; browsers reject it.
  No self-signed certificate in production use.

## TURN strategy

- LiveKit's embedded TURN replaces coturn **for the LiveKit path**: credentials are generated per join and expire;
  TURN/TLS on 5349 gets through networks that only allow TLS; TURN/UDP on 3479.
- Most clients will not need TURN: an SFU with a public IP is reachable by direct UDP from almost any NAT, and
  ICE/TCP 7881 is tried next. LiveKit falls back automatically (`allow_tcp_fallback` default true).
- coturn is not touched: it still serves the legacy mesh (rollback path) and nothing else uses it.
- Port 443 for TURN/TLS (best for strict firewalls) is taken by nginx on this host. Options later: a second IP, a
  dedicated media host, or nginx `stream` with SNI routing. Not done now.

## Host resources — measure before enabling

The production host could not be inspected from the development machine. Measure on the VPS:

```bash
nproc; free -h; df -h /opt/tobe-prod
ip -s link                         # NIC, errors
cat /sys/class/net/eth0/speed      # port speed (may be absent on VMs)
vnstat -m || true                  # monthly traffic, if installed; check the provider's quota
docker stats --no-stream           # current use by postgres/backend/frontend/nginx
```

Estimates (not measured; VP8 simulcast, Opus 32 kbps, adaptive stream, all cameras on):

| Class size | Uplink per publisher | Downlink per student | SFU egress | SFU ingress |
|-----------:|---------------------:|---------------------:|-----------:|------------:|
| 2 | ≤1.4 Mbps | ≤1.5 Mbps | ~3 Mbps | ~3 Mbps |
| 5 | ≤1.4 Mbps | 1–3 Mbps | ~10–15 Mbps | ~7 Mbps |
| 10 | ≤1.4 Mbps | 1.5–4 Mbps | ~20–40 Mbps | ~14 Mbps |

CPU: an SFU forwards, it does not transcode; expect a fraction of a core per 10-person class. Memory: 1 GB limit set.
Traffic per 90-minute class of 10: roughly 15–25 GB egress — check the hosting traffic quota.

Recommendation: co-locate only if the VPS has ≥4 vCPU, ≥2 GB RAM free after the current stack, a ≥100 Mbps port and
enough monthly traffic for the number of concurrent classes. Otherwise (or above ~3 concurrent full classes) use a
**dedicated media VPS**, so heavy media traffic cannot slow down the backend, database and website.

## Region and latency

- Both production IPs are registered to Iranian hosting providers (RIPE RDAP: 185.213.167.0/24 Greenweb IR;
  188.240.196.0/24 Abrha IR). Students inside Iran get a short domestic path; students abroad cross Iran's
  international links, which are often slow, filtered or UDP-throttled. VPNs on the student side add more latency.
- First deployment: **one** media server in the same region as the majority of students. No fake multi-region setup.
- Multi-region later, only if diaspora classes suffer: LiveKit OSS places each room on one node; a second region helps
  only if whole classes are routed to it (e.g. classes made of students abroad). That needs Redis shared by the nodes,
  region-aware node selection, a per-class choice of node/URL in the backend token response, and real latency data from
  `diagnostics()` per student location first.
