#!/usr/bin/env bash
# tests/test_firewall.sh
#
# Verify gateway.nft enterprise firewall rules.
# Run from the hypervisor host (173.168.0.1).
#
# Requires: nc, ssh, sshpass, curl, nmap (apt install nmap netcat sshpass)
# CLIENT_IP: set to an active client DHCP lease from /var/lib/kea/kea-leases4.csv on dhcp1

set -uo pipefail

GATEWAY_WAN="173.168.0.10"
GW_USER="student"
GW_PASS="student"
DNS1="10.10.10.53"
DHCP1="10.10.10.2"
CLIENT_IP="${1:-}"          # pass as first arg or set here

PASS=0
FAIL=0

# ── helpers ────────────────────────────────────────────────────────────────

ok()  { echo "  PASS [$1]"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL [$1] — $2"; FAIL=$((FAIL + 1)); }

# expect_open: command should succeed (exit 0 = port reachable)
expect_open() {
    local label=$1; shift
    if "$@" &>/dev/null 2>&1; then ok "$label"
    else bad "$label" "expected OPEN/CONNECTED, got BLOCKED/TIMEOUT"; fi
}

# expect_blocked: command should fail (exit non-zero = dropped/refused/timeout)
expect_blocked() {
    local label=$1; shift
    if "$@" &>/dev/null 2>&1; then bad "$label" "expected BLOCKED, got OPEN"
    else ok "$label"; fi
}

gw_ssh() {
    # Run a command on gateway1 via SSH (password auth)
    sshpass -p "$GW_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        "${GW_USER}@${GATEWAY_WAN}" "$@"
}

client_ssh() {
    # Run a command on a client VM via ProxyJump through gateway1
    [[ -z "$CLIENT_IP" ]] && { echo "  SKIP (CLIENT_IP not set — pass as arg: $0 <client-ip>)"; return; }
    sshpass -p "$GW_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        -o ProxyCommand="sshpass -p $GW_PASS ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p ${GW_USER}@${GATEWAY_WAN}" \
        "${GW_USER}@${CLIENT_IP}" "$@"
}

ensure_route() {
    # Hypervisor needs a route to internal subnets through gateway1 for WAN→LAN tests
    for net in 10.10.10.0/24 10.10.20.0/24 10.10.0.0/24; do
        ip route show | grep -q "$net" || {
            echo "  [route] adding $net via $GATEWAY_WAN"
            sudo ip route add "$net" via "$GATEWAY_WAN" 2>/dev/null || true
        }
    done
}

# ── Section A: INPUT chain — gateway1 self-protection ──────────────────────

echo ""
echo "=== A: INPUT — gateway1 self-protection ==="
echo "    SSH from MGMT_NET allowed. All other ports/WAN blocked."

# A1: SSH to gateway1 from hypervisor MGMT_NET — must succeed (Ansible depends on this)
expect_open    "A1: SSH gateway1 from MGMT_NET (173.168.0.x)" \
    nc -zv -w 5 "$GATEWAY_WAN" 22

# A2: HTTP port on gateway1 from WAN — no service + policy drop
expect_blocked "A2: HTTP port 80 on gateway1 from WAN" \
    nc -zv -w 3 "$GATEWAY_WAN" 80

# A3: HTTPS port on gateway1 from WAN — policy drop
expect_blocked "A3: HTTPS port 443 on gateway1 from WAN" \
    nc -zv -w 3 "$GATEWAY_WAN" 443

# A4: Arbitrary high port on gateway1 from WAN — policy drop
expect_blocked "A4: Port 8080 on gateway1 from WAN" \
    nc -zv -w 3 "$GATEWAY_WAN" 8080

# ── Section B: FORWARD WAN→LAN new sessions — must be blocked ─────────────

echo ""
echo "=== B: FORWARD WAN→LAN — unsolicited inbound must be BLOCKED ==="
echo "    Direct connections to internal IPs from hypervisor (simulated WAN)."

ensure_route

# B1: SSH directly to dns1 — no ProxyJump, raw WAN→LAN, must drop
expect_blocked "B1: SSH to dns1 (10.10.10.53) direct from WAN" \
    nc -zv -w 3 "$DNS1" 22

# B2: SSH directly to dhcp1 — must drop
expect_blocked "B2: SSH to dhcp1 (10.10.10.2) direct from WAN" \
    nc -zv -w 3 "$DHCP1" 22

# B3: DNS query to dns1 directly — must be blocked (UDP 53).
# nc -u is unreliable for UDP block testing: no 3-way handshake, exits 0 even when dropped.
# dig actually waits for a response; exits non-zero on timeout = firewall dropped it.
expect_blocked "B3: DNS query to dns1 (UDP 53) direct from WAN" \
    dig @"$DNS1" google.com +time=3 +tries=1 +short

if [[ -n "$CLIENT_IP" ]]; then
    # B4: SSH to client directly — must drop
    expect_blocked "B4: SSH to client ($CLIENT_IP) direct from WAN" \
        nc -zv -w 3 "$CLIENT_IP" 22
else
    echo "  SKIP B4 (CLIENT_IP not set)"
fi

# ── Section C: FORWARD LAN→WAN — outbound must work ───────────────────────

echo ""
echo "=== C: FORWARD LAN→WAN — client outbound must reach internet ==="
echo "    Tests via ProxyJump: hypervisor → gateway1 → client."

if [[ -n "$CLIENT_IP" ]]; then
    # C1: Client can ping internet
    expect_open "C1: Client ping 8.8.8.8 outbound" \
        client_ssh "ping -c 2 -W 3 8.8.8.8"

    # C2: Client can curl HTTP
    expect_open "C2: Client curl http://example.com outbound" \
        client_ssh "curl -sfm 8 http://example.com"

    # C3: Client can resolve DNS (proves gateway routes to external DNS)
    expect_open "C3: Client DNS resolution (nslookup google.com)" \
        client_ssh "nslookup google.com"
else
    echo "  SKIP C1-C3 (CLIENT_IP not set — pass as arg: $0 <client-ip>)"
fi

# ── Section D: nftables live rule dump on gateway1 ────────────────────────

echo ""
echo "=== D: nft ruleset dump on gateway1 (manual inspection) ==="
gw_ssh "sudo nft list ruleset" 2>/dev/null || echo "  [SKIP] SSH to gateway1 failed"

# ── Section E: nft packet counters (requires counter keyword in rules) ─────
# To enable per-rule counters without editing gateway.nft, insert temporary
# counter rules via:
#   sudo nft add rule inet fw forward counter comment \"fwd-counter\"
# Then check: sudo nft list ruleset | grep counter
# Reset with: sudo nft flush ruleset && sudo nft -f /etc/nftables.conf

echo ""
echo "=== E: nft per-chain packet counts ==="
echo "  Run on gateway1 after traffic tests:"
echo "    sudo nft list ruleset        # shows chains with counter if added"
echo "    sudo conntrack -L            # active connections through gateway"
echo "    sudo nft list counters       # named counters only"

# ── Summary ────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════"
echo "  Results: PASS=$PASS  FAIL=$FAIL"
echo "══════════════════════════════════"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
