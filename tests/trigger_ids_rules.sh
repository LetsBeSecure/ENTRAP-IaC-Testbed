#!/usr/bin/env bash
# Trigger IDS rules on gateway1 Suricata and verify alerts fire.
#
# Usage:
#   ./trigger_ids_rules.sh <gateway1_wan_ip>              # Section A only
#   ./trigger_ids_rules.sh <gateway1_wan_ip> <client_ip>  # A + B
#
# Section A — run FROM this host → tests rules visible on enp2s0 (inbound to gateway).
# Section B — run via SSH jump through gateway1 into a client VM → tests rules
#             visible on enp1s0 (outbound from VMs, pre-NAT with real internal IPs).
#
# Watch alerts live on gateway1 (separate terminal):
#   ssh student@<gateway1_wan_ip> \
#     'tail -f /var/log/suricata/eve-alert.json | jq -c "{sig:.alert.signature,src:.src_ip,dst:.dest_ip,port:.dest_port}"'
#
# Requirements on host: sshpass, nmap (optional), hping3 (optional)
#   apt install sshpass nmap hping3

set -uo pipefail

GATEWAY_WAN="${1:?Usage: $0 <gateway1_wan_ip> [client_ip]}"
CLIENT_IP="${2:-}"

PASS="student"

log()  { echo "[$(date +%T)] $*"; }
pass() { echo "[$(date +%T)] PASS  $*"; }
note() { echo "[$(date +%T)] NOTE  $*"; }

# Run a command on a client VM via ProxyJump through gateway1
run_on_client() {
    sshpass -p "$PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        -o ProxyCommand="sshpass -p $PASS ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p student@$GATEWAY_WAN" \
        "student@$CLIENT_IP" "$@" 2>/dev/null
}

echo "======================================================="
echo " Suricata IDS Rule Trigger Tests — RansomwareTestbed"
echo " Gateway WAN : $GATEWAY_WAN"
echo " Client IP   : ${CLIENT_IP:-not provided (Section B skipped)}"
echo "======================================================="
echo ""

# =============================================================
# SECTION A — FROM HOST → GATEWAY1 WAN (enp2s0 inbound rules)
# =============================================================
# These packets arrive on enp2s0 from outside before NAT.
# Rules with any dst or $HOME_NET including gateway1 WAN IP fire here.

echo "--- SECTION A: from host → gateway1 WAN ($GATEWAY_WAN) ---"
echo ""

# A1: SSH brute force (rule 1000021)
# Sends 8 rapid SSH connection attempts to gateway1:22.
# Rule threshold: 5 SYN packets in 60s from same src → alert fires.
# Expected alert: "ATTACK: SSH Brute Force Attempt Detected"
log "A1: SSH brute force → gateway1:22 (rule 1000021)"
for i in $(seq 1 8); do
    ssh -o ConnectTimeout=1 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -p 22 "baduser@$GATEWAY_WAN" exit 2>/dev/null &
done
wait
pass "A1: sent 8 SSH SYNs — expect 'SSH Brute Force' alert"
sleep 3

# A2: TCP SYN flood (rule 1000020)
# Sends >100 SYN packets per second to gateway1:80 using hping3.
# Rule: flags:S + 100 SYN/sec from same src → alert.
# NOTE: rule targets $HOME_NET dst — fires only if gateway1 WAN IP is in HOME_NET.
#       If not, add gateway1 WAN to HOME_NET in suricata.yaml.j2 for this test.
# Expected alert: "ATTACK: TCP SYN Flood Detected"
log "A2: TCP SYN flood → gateway1:80 (rule 1000020)"
if command -v hping3 &>/dev/null; then
    timeout 3 hping3 -S -p 80 --flood --rand-source "$GATEWAY_WAN" 2>/dev/null || true
    pass "A2: SYN flood sent — expect 'TCP SYN Flood' alert (if HOME_NET includes gateway1 WAN)"
else
    note "A2: hping3 not found — install with: sudo apt install hping3"
fi
sleep 2

# A3: ICMP ping flood (rule 1000044)
# Sends 300+ ICMP echo requests per second to gateway1.
# Same HOME_NET caveat as A2.
# Expected alert: "ATTACK: ICMP Ping Flood Detected"
log "A3: ICMP ping flood → gateway1 (rule 1000044)"
if command -v hping3 &>/dev/null; then
    timeout 2 hping3 --icmp --flood "$GATEWAY_WAN" 2>/dev/null || true
    pass "A3: ICMP flood sent — expect 'ICMP Ping Flood' alert (if HOME_NET includes gateway1 WAN)"
else
    note "A3: hping3 not found — skipping"
fi
sleep 2

# A4: Nmap SYN scan (rule 1000060)
# 15+ SYNs to different ports in 3s from same src → alert.
# Same HOME_NET caveat as A2/A3.
# Expected alert: "RECON: Nmap SYN Scan Detected"
log "A4: Nmap SYN scan → gateway1 (rule 1000060)"
if command -v nmap &>/dev/null; then
    nmap -sS -T4 -p 1-100 --open "$GATEWAY_WAN" -oN /dev/null 2>/dev/null || true
    pass "A4: nmap scan sent — expect 'Nmap SYN Scan' alert (if HOME_NET includes gateway1 WAN)"
else
    note "A4: nmap not found — install with: sudo apt install nmap"
fi

echo ""

# =============================================================
# SECTION B — VIA SSH INTO CLIENT VM (enp1s0 outbound rules)
# =============================================================
# Traffic from inside the client VM exits through gateway1 enp1s0 → enp2s0.
# Suricata on enp1s0 sees pre-NAT src IPs (real client subnet IPs).
# HOME_NET-based outbound rules ($HOME_NET → $EXTERNAL_NET) fire correctly here.

if [[ -z "$CLIENT_IP" ]]; then
    echo "--- SECTION B: skipped (no client IP provided) ---"
    echo "   Re-run: $0 $GATEWAY_WAN <client_ip>"
    echo ""
    echo "Find client IP: check Kea leases on gateway1:"
    echo "  ssh student@$GATEWAY_WAN 'ssh student@<dhcp1_ip> awk -F, NR>1&&\$10==\"0\"{print \$1} /var/lib/kea/kea-leases4.csv'"
    exit 0
fi

echo "--- SECTION B: from client ($CLIENT_IP) via ProxyJump → outbound rules ---"
echo ""

# B1: Oversized ICMP — covert channel detection (rule 1000040)
# Standard ping payload = 56 bytes. Tool-generated tunnels use >1000 bytes.
# ping -s 1200 sends 1200-byte payload ICMP echo to 100.100.100.100.
# Suricata on enp1s0: src=client_ip ($HOME_NET), dst=100.100.100.100 ($EXTERNAL_NET), dsize>1000 → alert.
# Expected alert: "EXFIL: Oversized ICMP Payload - Possible Covert Channel"
log "B1: Oversized ICMP ping -s 1200 → 100.100.100.100 (rule 1000040)"
run_on_client "ping -c 5 -s 1200 100.100.100.100" || true
pass "B1: done — expect 'Oversized ICMP Payload' alert"
sleep 2

# B2: PowerShell User-Agent HTTP request (rule 1000042)
# Spoofs the default Windows PowerShell HTTP user-agent string.
# This is what unmodified Meterpreter/Empire/ransomware droppers send.
# Suricata on enp1s0: http.user_agent matches "PowerShell" → alert.
# Expected alert: "ATTACK: PowerShell HTTP User-Agent - Possible C2 Downloader"
log "B2: PowerShell UA curl → example.com (rule 1000042)"
run_on_client "curl -s -A 'Mozilla/5.0 (Windows NT; Windows NT 10.0; en-US) WindowsPowerShell/5.1.19041.1320' http://example.com/ -o /dev/null" || true
pass "B2: done — expect 'PowerShell HTTP User-Agent' alert"
sleep 2

# B3: DNS query for .onion domain (rule 1000070)
# Queries a fake .onion address against Google DNS (100.100.100.100).
# Real resolver returns NXDOMAIN; Suricata sees the DNS query packet on enp1s0.
# dns.query content matches ".onion" → alert fires on the query itself, not the response.
# Expected alert: "MALWARE: DNS Query for .onion Domain - Possible TOR C2"
log "B3: DNS query for fake .onion (rule 1000070)"
run_on_client "nslookup fakeransomware-c2-test.onion 100.100.100.100" || true
pass "B3: done — expect '.onion Domain' alert"
sleep 2

# B4: Crypto miner pool port connection (rule 1000072)
# Opens TCP connection to Stratum mining pool port 3333.
# nc -zv attempts connection (no actual mining — just the TCP SYN/handshake).
# Suricata on enp1s0: src=client ($HOME_NET), dst=$EXTERNAL_NET port 3333 → alert.
# Expected alert: "MALWARE: Crypto Miner Stratum Pool Connection"
log "B4: Stratum miner port probe → port 3333 (rule 1000072)"
run_on_client "nc -zv -w 3 pool.minexmr.com 3333" || true
pass "B4: done — expect 'Crypto Miner Stratum Pool Connection' alert"
sleep 2

# B5: Large outbound data transfer >50MB (rule 1000032)
# Generates 60MB of zero bytes and streams it via HTTP POST to httpbin.org.
# stream_size:client,>,50000000 triggers once the stream exceeds 50MB.
# Expected alert: "EXFIL: Large Outbound Data Transfer Detected (>50MB)"
# NOTE: this test takes ~30-60s depending on client upload speed.
log "B5: 60MB upload → httpbin.org (rule 1000032) — may take ~30s"
run_on_client "dd if=/dev/zero bs=1M count=60 2>/dev/null | curl -s -X POST --data-binary @- http://httpbin.org/post -o /dev/null" || true
pass "B5: done — expect 'Large Outbound Data Transfer' alert"
sleep 2

# B6: DGA simulation — rapid NXDOMAINs via multiple fake domain lookups (rule 1000076)
# DGA malware queries ~hundreds of random domains per minute; most return NXDOMAIN.
# 25 queries in quick succession triggers the NXDomain burst threshold (20 in 10s).
# Expected alert: "MALWARE: Possible DGA Beaconing - NXDomain Burst"
log "B6: DGA simulation — 25 NXDomain queries in burst (rule 1000076)"
run_on_client "
for i in \$(seq 1 25); do
    nslookup dga\${i}xzqfakeransomware\$(date +%s%N | md5sum | head -c8).evil 100.100.100.100
done 2>/dev/null" || true
pass "B6: done — expect 'DGA Beaconing NXDomain Burst' alert"

echo ""
echo "======================================================="
echo " Tests complete. Check gateway1 alerts:"
echo ""
echo "   ssh student@$GATEWAY_WAN \\"
echo "     'tail -50 /var/log/suricata/eve-alert.json | \\"
echo "      jq -c \"{sig:.alert.signature,src:.src_ip,dst:.dest_ip}\"'"
echo ""
echo " Count by rule:"
echo "   ssh student@$GATEWAY_WAN \\"
echo "     'jq .alert.signature /var/log/suricata/eve-alert.json | sort | uniq -c | sort -rn'"
echo "======================================================="
