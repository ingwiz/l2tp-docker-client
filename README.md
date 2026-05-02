# l2tp-docker-client

Dockerized L2TP/IPSec VPN client with a SOCKS5 egress proxy.  
Designed for **Mikrotik** servers running IKEv1 + L2TP, but works with any standard L2TP/IPSec setup.

## Architecture

All three containers share **one network namespace** (owned by `ipsec`).  
Traffic from SOCKS5 clients flows: `client → :1080 → Dante → ppp0 → VPN → internet`.

```
┌───────────────────────────────────────────────────┐
│               shared network namespace            │
│                                                   │
│  ┌──────────┐   ┌──────────┐   ┌──────────────┐   │
│  │  ipsec   │   │   l2tp   │   │    socks5    │   │
│  │strongswan│   │xl2tpd    │   │    dante     │   │
│  │ IKEv1 SA │   │+ pppd    │   │  :1080       │   │
│  └──────────┘   └──────────┘   └──────────────┘   │
│       eth0 (Docker bridge)  +  ppp0 (VPN tunnel)  │
└───────────────────────────────────────────────────┘
```

| Container | Image base | Role |
|-----------|-----------|------|
| `l2tp-ipsec` | debian:bookworm-slim + strongswan | IKEv1 IPSec SA (transport mode) |
| `l2tp-daemon` | debian:bookworm-slim + xl2tpd + ppp | L2TP tunnel + PPP link (ppp0) |
| `l2tp-socks5` | debian:bookworm-slim + dante-server | SOCKS5 proxy on port 1080 |

Startup is gated by Docker healthchecks:  
`ipsec` healthy (ESP XFRM state present) → `l2tp` starts → `l2tp` healthy (ppp0 UP) → `socks5` starts.

## Requirements

- Docker 20.10+ with Compose v2
- Linux host kernel with `esp4`, `ah4`, `xfrm_user` modules available
- `/dev/ppp` on the host (created automatically if missing, requires `privileged: true`)
- `/lib/modules` mounted read-only into the `ipsec` container

## Quick start

```bash
cp .env.example .env
# Edit .env with real credentials
docker compose up --build -d
```

The SOCKS5 proxy is available at `localhost:1080`.

```bash
# Test — should show the VPN server's public IP
curl --socks5 localhost:1080 https://ifconfig.me
```

## Configuration

### `.env` variables

| Variable | Description |
|----------|-------------|
| `VPN_SERVER_IPV4` | VPN server IP address |
| `VPN_PSK` | IKEv1 pre-shared key |
| `VPN_USERNAME` | L2TP / PPP username |
| `VPN_PASSWORD` | L2TP / PPP password |
| `PROXY_USER_N` | SOCKS5 credentials, format `login:password` (optional) |

### SOCKS5 authentication

Add one variable per user. `N` must be a positive integer; gaps are allowed.

```dotenv
PROXY_USER_1=alice:s3cr3t
PROXY_USER_2=bob:hunter2
```

If **no** `PROXY_USER_*` variables are set, Dante runs without authentication (`socksmethod: none`).  
When at least one is set, `socksmethod: username` is enforced for all connections.

To add a user without rebuilding:

```bash
# 1. Add PROXY_USER_3=carol:pass to .env
# 2. Restart only the socks5 container
docker compose up -d --no-deps socks5
```

### IPSec proposals

Default proposals match Mikrotik's factory L2TP profile:

| Phase | Algorithms |
|-------|-----------|
| IKE (phase 1) | AES-256-SHA1-modp1024, AES-128-SHA1-modp1024 |
| ESP (phase 2) | AES-256-SHA1, AES-128-SHA1 |

To change them, edit `ike=` / `esp=` in [`ipsec/entrypoint.sh`](ipsec/entrypoint.sh).  
The `!` suffix restricts strongswan to exactly the listed proposals — remove it to allow negotiation.

## File structure

```
.
├── docker-compose.yml
├── .env.example
├── ipsec/
│   ├── Dockerfile        # strongswan
│   └── entrypoint.sh     # generates ipsec.conf + ipsec.secrets, runs starter
├── l2tp/
│   ├── Dockerfile        # xl2tpd + ppp
│   └── entrypoint.sh     # generates xl2tpd.conf + ppp options, runs xl2tpd
└── dante/
    ├── Dockerfile        # dante-server
    ├── danted.conf       # reference template
    └── entrypoint.sh     # creates system users, generates danted.conf, runs danted
```

## Troubleshooting

```bash
# Follow all logs
docker compose logs -f

# Check IPSec SA
docker exec l2tp-ipsec ipsec status

# Check XFRM states (kernel level)
docker exec l2tp-ipsec ip xfrm state

# Check PPP link
docker exec l2tp-daemon ip addr show ppp0

# Inspect routing table inside the namespace
docker exec l2tp-ipsec ip route
```

Common issues:

| Symptom | Likely cause |
|---------|-------------|
| `ipsec` stays unhealthy | Wrong PSK, server IP, or firewall blocking UDP 500/4500 |
| `l2tp` stays unhealthy | IPSec SA not ready, wrong credentials, or xl2tpd proposal mismatch |
| `ppp0` up but no internet | Missing host route for VPN server — check `ip route` for a `/32` entry |
| SOCKS5 auth failure | `PROXY_USER_N` var not passed to container, or malformed `login:password` |
