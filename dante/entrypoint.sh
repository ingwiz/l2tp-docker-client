#!/bin/bash
set -euo pipefail

# The l2tp healthcheck guarantees ppp0 is up before this container starts,
# but on restart ppp0 may not be available yet, so we poll.
echo "[dante] waiting for ppp0..."
until ip link show ppp0 &>/dev/null; do
    sleep 2
done
echo "[dante] ppp0 detected, starting danted"

# danted daemonizes itself; start it, then monitor with pgrep.
# When the daemon stops, the container exits and Docker restarts it.
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
