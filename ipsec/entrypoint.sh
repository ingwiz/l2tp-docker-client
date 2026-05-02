#!/bin/bash
set -euo pipefail

: "${VPN_SERVER_IPV4:?VPN_SERVER_IPV4 is required}"
: "${VPN_PSK:?VPN_PSK is required}"

# Load kernel modules required for IPSec (ignore errors if already loaded)
for mod in af_key ah4 esp4 ipcomp xfrm_user xfrm4_tunnel; do
    modprobe "$mod" 2>/dev/null || true
done

mkdir -p /run/pluto /var/log/pluto

# ── /etc/ipsec.conf ───────────────────────────────────────────────────────
# Transport mode (not tunnel): IPSec protects only the L2TP UDP stream.
# IKEv1 main mode with PSK — matches Mikrotik default profile.
# Offer several cipher suites so Mikrotik can pick what it supports.
cat > /etc/ipsec.conf <<EOF
config setup
    protostack=netkey
    plutodebug=none
    dumpdir=/run/pluto

conn L2TP-PSK
    authby=secret
    pfs=no
    rekey=yes
    auto=start
    keyingtries=%forever
    ikelifetime=8h
    keylife=1h
    type=transport
    left=%defaultroute
    leftprotoport=17/1701
    right=${VPN_SERVER_IPV4}
    rightprotoport=17/1701
    ike=aes256-sha1;modp1024,aes128-sha1;modp1024
    phase2alg=aes256-sha1,aes128-sha1
    ikev2=never
EOF

# ── /etc/ipsec.secrets ────────────────────────────────────────────────────
cat > /etc/ipsec.secrets <<EOF
%any ${VPN_SERVER_IPV4} : PSK "${VPN_PSK}"
EOF
chmod 600 /etc/ipsec.secrets

exec /usr/sbin/ipsec start --nofork
