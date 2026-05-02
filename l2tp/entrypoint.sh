#!/bin/bash
set -euo pipefail

: "${VPN_SERVER_IPV4:?VPN_SERVER_IPV4 is required}"
: "${VPN_USERNAME:?VPN_USERNAME is required}"
: "${VPN_PASSWORD:?VPN_PASSWORD is required}"

# ── Routing fix ───────────────────────────────────────────────────────────
# PPP's `replacedefaultroute` will swap the kernel default route to ppp0.
# We must preserve a specific host route to the VPN server so that the
# IPSec IKE daemon can still reach it after ppp0 becomes the default GW.
ORIG_GW=$(ip route | awk '/^default/{print $3; exit}')
echo "[l2tp] original gateway: ${ORIG_GW}"

# ── /dev/ppp ──────────────────────────────────────────────────────────────
if [ ! -c /dev/ppp ]; then
    mknod /dev/ppp c 108 0
fi

# Load PPP kernel modules
for mod in ppp_generic ppp_async ppp_mppe; do
    modprobe "$mod" 2>/dev/null || true
done

mkdir -p /var/run/xl2tpd /etc/xl2tpd /etc/ppp/ip-up.d

# ── /etc/xl2tpd/xl2tpd.conf ──────────────────────────────────────────────
cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
port = 1701

[lac vpn]
lns = ${VPN_SERVER_IPV4}
ppp debug = no
pppoptfile = /etc/ppp/options.l2tpd
length bit = yes
redial = yes
redial timeout = 15
EOF

# ── /etc/ppp/options.l2tpd ───────────────────────────────────────────────
cat > /etc/ppp/options.l2tpd <<EOF
ipcp-accept-local
ipcp-accept-remote
refuse-pap
refuse-eap
noccp
mtu 1280
mru 1280
noipdefault
defaultroute
replacedefaultroute
usepeerdns
noauth
name ${VPN_USERNAME}
EOF

# ── Credentials ───────────────────────────────────────────────────────────
cat > /etc/ppp/chap-secrets <<EOF
"${VPN_USERNAME}" * "${VPN_PASSWORD}" *
EOF
chmod 600 /etc/ppp/chap-secrets

# ── ip-up hook: restore host route to VPN server ─────────────────────────
# Runs after pppd replaces the default route with ppp0.
# Without this, IKE rekeying traffic would be sent into the tunnel itself,
# causing a routing loop that breaks the IPSec SA.
cat > /etc/ppp/ip-up.d/01-vpn-server-route <<EOF
#!/bin/bash
ip route replace ${VPN_SERVER_IPV4}/32 via ${ORIG_GW} 2>/dev/null || true
EOF
chmod +x /etc/ppp/ip-up.d/01-vpn-server-route

# ── Start xl2tpd ─────────────────────────────────────────────────────────
# -D  → do not daemonize (stay in foreground so Docker tracks the PID)
xl2tpd -D &
XL2TPD_PID=$!

sleep 3

# Trigger L2TP connection through the xl2tpd control socket
echo "c vpn" > /var/run/xl2tpd/l2tp-control

# ── Wait for ppp0 to appear (up to 120 s) ────────────────────────────────
echo "[l2tp] waiting for PPP link..."
for i in $(seq 1 60); do
    if ip link show ppp0 &>/dev/null; then
        echo "[l2tp] ppp0 is up"
        break
    fi
    sleep 2
done

if ! ip link show ppp0 &>/dev/null; then
    echo "[l2tp] ERROR: ppp0 never appeared" >&2
    kill "$XL2TPD_PID" 2>/dev/null
    exit 1
fi

wait "$XL2TPD_PID"
