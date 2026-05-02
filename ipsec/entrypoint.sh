#!/bin/bash
set -euo pipefail

: "${VPN_SERVER_IPV4:?VPN_SERVER_IPV4 is required}"
: "${VPN_PSK:?VPN_PSK is required}"

# strongswan's charon talks to the kernel via XFRM netlink — no af_key needed.
# esp4 / ah4 handle the actual packet encapsulation in the kernel.
for mod in esp4 ah4 xfrm_user xfrm4_tunnel ipcomp; do
    modprobe "$mod" 2>/dev/null || true
done

# ── /etc/ipsec.conf (strongswan stroke/starter format) ────────────────────
# IKEv1 main mode, PSK, transport (not tunnel) — standard Mikrotik L2TP profile.
#
# Proposal syntax in strongswan uses dashes: aes256-sha1-modp1024
# (libreswan used semicolons: aes256-sha1;modp1024 — not valid here).
#
# The trailing ! restricts charon to exactly the listed proposals;
# without it strongswan may append its own defaults, causing mismatches.
cat > /etc/ipsec.conf <<EOF
config setup
    charondebug="ike 0, knl 0, cfg 0, net 0, esp 0, dmn 0"
    uniqueids=no

conn L2TP-PSK
    keyexchange=ikev1
    authby=secret
    type=transport
    left=%defaultroute
    leftprotoport=17/1701
    right=${VPN_SERVER_IPV4}
    rightprotoport=17/1701
    ike=aes256-sha1-modp1024,aes128-sha1-modp1024!
    esp=aes256-sha1,aes128-sha1!
    ikelifetime=8h
    lifetime=1h
    keyingtries=%forever
    dpdaction=restart
    dpddelay=30s
    auto=start
EOF

# ── /etc/ipsec.secrets ────────────────────────────────────────────────────
# Format is identical between strongswan and libreswan.
cat > /etc/ipsec.secrets <<EOF
%any ${VPN_SERVER_IPV4} : PSK "${VPN_PSK}"
EOF
chmod 600 /etc/ipsec.secrets

# starter reads ipsec.conf, launches charon, and initiates connections.
# --nofork keeps starter (and charon) in the foreground so Docker tracks the PID.
exec ipsec start --nofork
