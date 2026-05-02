#!/bin/bash
set -euo pipefail

# ── Parse PROXY_USER_<N>=login:password env vars ──────────────────────────
# Each var creates a Linux system user that Dante authenticates against via
# PAM/shadow (socksmethod: username). The privileged master process (root)
# reads /etc/shadow; worker processes drop to nobody.
#
# If no PROXY_USER_* vars are present, Dante runs without authentication
# (socksmethod: none) — useful for isolated / trusted network setups.

SOCKS_METHOD="none"

while IFS='=' read -r key raw_val; do
    [[ "$key" =~ ^PROXY_USER_[0-9]+$ ]] || continue

    login="${raw_val%%:*}"
    password="${raw_val#*:}"

    if [[ -z "$login" || "$login" == "$raw_val" ]]; then
        echo "[dante] WARNING: ${key} is malformed — expected login:password, skipping" >&2
        continue
    fi

    # Create user if absent, then set password via chpasswd (reads stdin).
    # -M: no home dir  -s: no interactive shell
    if id "$login" &>/dev/null; then
        echo "[dante] user '${login}' already exists, updating password"
    else
        useradd -M -s /usr/sbin/nologin "$login"
        echo "[dante] created system user '${login}'"
    fi
    echo "${login}:${password}" | chpasswd

    SOCKS_METHOD="username"
done < <(env)

if [[ "$SOCKS_METHOD" == "username" ]]; then
    echo "[dante] authentication enabled (socksmethod: username)"
else
    echo "[dante] WARNING: no PROXY_USER_* vars set — running without authentication"
fi

# ── Generate /etc/danted.conf ─────────────────────────────────────────────
cat > /etc/danted.conf <<EOF
logoutput: /proc/1/fd/2

internal: 0.0.0.0 port = 1080
external: ppp0

# clientmethod controls the TCP-handshake phase (before SOCKS negotiation).
# Always none — auth happens at the SOCKS layer below.
clientmethod: none
socksmethod: ${SOCKS_METHOD}

user.privileged: root
user.notprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    socksmethod: ${SOCKS_METHOD}
    log: error
}
EOF

# ── Wait for ppp0 (shared network namespace may not have it on restart) ───
echo "[dante] waiting for ppp0..."
until ip link show ppp0 &>/dev/null; do
    sleep 2
done
echo "[dante] ppp0 detected, starting danted"

# danted daemonizes itself; start it then monitor with pgrep.
# When the daemon stops the container exits and Docker restarts it.
danted -f /etc/danted.conf
sleep 2

if ! pgrep -x danted > /dev/null; then
    echo "[dante] danted failed to start" >&2
    exit 1
fi

echo "[dante] danted is running"
while pgrep -x danted > /dev/null; do
    sleep 5
done

echo "[dante] danted stopped, exiting for restart" >&2
exit 1
