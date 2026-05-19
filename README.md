# 🔐 Ransomware Testbed using Ansible and KVM

A fully automated enterprise ransomware cyber-range built using:

- Ansible
- KVM/QEMU
- Libvirt
- Cloud-init
- Ubuntu Server Cloud Images

The objective of this project is to create a reproducible and isolated enterprise-style environment for:

- ransomware behavior analysis
- malware execution testing
- backup and recovery validation
- DNS/DHCP infrastructure testing
- incident response experiments
- network traffic analysis

The entire infrastructure is deployed automatically using Ansible playbooks with minimal manual intervention.

---

## 📖 Overview

Modern ransomware attacks target enterprise environments containing critical infrastructure services such as DNS, DHCP, backup servers, and endpoint systems. Reproducing such environments manually is time-consuming, error-prone, and difficult to scale.

To address this challenge, we develop a fully automated ransomware testbed capable of deploying a small enterprise network using Infrastructure-as-Code (IaC) principles. The framework provisions multiple virtual machines, configures enterprise services automatically, and creates reusable snapshots for repeatable malware experimentation.

The proposed testbed allows researchers to safely evaluate:

- ransomware propagation behavior
- impact on enterprise infrastructure
- backup recovery workflows
- network-based detection approaches
- incident response mechanisms
- forensic data collection strategies

---

## 🚀 Key Features

- ⚙️ **Fully Automated Enterprise Deployment**  
  Automatically provisions and configures the complete enterprise network using Ansible playbooks.

- 🖥️ **Automated VM Provisioning**  
  Uses KVM/libvirt and cloud-init to create and configure Ubuntu virtual machines.

- 🌐 **Enterprise Network Simulation**  
  Creates an isolated NAT-based enterprise network with realistic infrastructure services.

- 📡 **Automated DHCP Deployment**  
  Automatically deploys and configures a DHCP server using Kea DHCP.

- 🔎 **Automated DNS Deployment**  
  Automatically configures internal DNS infrastructure using BIND9.

- 💾 **Backup Server Deployment**  
  Deploys a Samba-based backup server for ransomware recovery experiments.

- 📸 **Snapshot Automation**  
  Automatically creates VM snapshots for repeatable ransomware execution and rollback.

- 🔁 **Reproducible Infrastructure**  
  Enables consistent cyber-range recreation for repeated experimentation.

- 🧪 **Safe Malware Experimentation**  
  Provides isolated infrastructure for controlled ransomware analysis.

---

## 🏗️ Lab Architecture

### Infrastructure Components

| VM | Role | IP Address |
|----|------|------------|
| dhcp1 | DHCP Server | 10.10.10.10 |
| dns1 | DNS Server | 10.10.10.53 |
| backup1 | Backup/Samba Server | 10.10.10.20 |
| client1 | Enterprise Client | 10.10.10.100 |

---

## 🌐 Network Topology

- **Network Name:** `enterprise-net`
- **Subnet:** `10.10.10.0/24`
- **Gateway:** `10.10.10.1`
- **Bridge:** `virbr10`
- **Network Mode:** NAT

---

## 📂 Project Structure

```text
RansomwareTestbed/
├── captures/
├── cloud_init/
├── configs/
│   └── network/
│       └── enterprise-net.xml
├── group_vars/
│   └── all.yml
├── inventory/
│   └── hosts.ini
├── playbooks/
│   ├── site.yml
│   ├── 00_create_enterprise_network.yml
│   ├── create_vms.yml
│   ├── configure_dhcp.yml
│   ├── configure_dns.yml
│   ├── configure_backup.yml
│   ├── snapshots.yml
│   └── destroy_lab.yml
├── qcow2/
├── scripts/
└── vm_images/
```

---

## 🛠️ Prerequisites

### Host System Requirements

- Ubuntu 22.04 or later
- Hardware virtualization enabled (Intel VT-x / AMD-V)
- Minimum 16 GB RAM recommended
- KVM virtualization support enabled

---


# 🗂️ Repository Setup Guide

## 1️⃣ Clone the Repository

```bash
git clone https://github.com/<your-username>/RansomwareTestbed.git

cd RansomwareTestbed
```

---

## 2️⃣ Verify Virtualization Support

Check whether hardware virtualization is enabled:

```bash
egrep -c '(vmx|svm)' /proc/cpuinfo
```

Expected output:

```text
> 0
```

---

## 3️⃣ Verify KVM Installation

```bash
sudo kvm-ok
```

Expected output:

```text
KVM acceleration can be used
```

---

## 4️⃣ Verify Libvirt Service

```bash
sudo systemctl status libvirtd
```

---

## 5️⃣ Verify Enterprise Network

```bash
virsh net-list --all
```

---

## 6️⃣ Verify Virtual Machines

```bash
virsh list --all
```

---

# 🔄 Redeployment Workflow

If the infrastructure already exists and you want to redeploy:

## Destroy Existing Infrastructure

```bash
sudo ansible-playbook playbooks/destroy_lab.yml
```

---

## Remove Leftover Images

```bash
sudo rm -f /var/lib/libvirt/images/*.qcow2
sudo rm -f /var/lib/libvirt/images/*-seed.iso
```

---

## Redeploy Infrastructure

```bash
sudo ansible-playbook -i inventory/hosts.ini playbooks/site.yml
```

---

## 📦 Required Packages

Install the following dependencies on the host system:

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

---

## ⚡ Enable Libvirt

```bash
sudo systemctl enable libvirtd
sudo systemctl start libvirtd
```

Verify installation:

```bash
virsh list --all
```

---

## ☁️ Download Ubuntu Cloud Image

```bash
sudo mkdir -p /opt/vm_images

cd /opt/vm_images

sudo wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
```

---

## 📝 Inventory Configuration

File: `inventory/hosts.ini`

```ini
[dhcp]
10.10.10.10

[dns]
10.10.10.53

[backup]
10.10.10.20

[clients]
10.10.10.100

[all:vars]
ansible_user=student
ansible_password=student
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

---

# 🚀 Deployment

## Deploy Complete Enterprise Lab

Run the following command to automatically deploy the complete enterprise ransomware testbed:

```bash
sudo ansible-playbook -i inventory/hosts.ini playbooks/site.yml
```

This automatically:

- creates the enterprise network
- provisions virtual machines
- configures static networking
- deploys DHCP server
- deploys DNS server
- deploys backup server
- creates snapshots

---

## 🔍 Verify VM Status

```bash
virsh list --all
```

Expected virtual machines:

- `dhcp1`
- `dns1`
- `backup1`
- `client1`

---

## 🔐 SSH Access

### Username

```text
student
```

### Password

```text
student
```

Example:

```bash
ssh student@10.10.10.10
```

---

# 📜 Individual Playbooks

## Create Enterprise Network

```bash
sudo ansible-playbook playbooks/00_create_enterprise_network.yml
```

---

## Create Virtual Machines

```bash
sudo ansible-playbook playbooks/create_vms.yml
```

---

## Configure DHCP Server

```bash
sudo ansible-playbook -i inventory/hosts.ini playbooks/configure_dhcp.yml
```

---

## Configure DNS Server

```bash
sudo ansible-playbook -i inventory/hosts.ini playbooks/configure_dns.yml
```

---

## Configure Backup Server

```bash
sudo ansible-playbook -i inventory/hosts.ini playbooks/configure_backup.yml
```

---

## Create Snapshots

```bash
sudo ansible-playbook playbooks/snapshots.yml
```

---

## 🛑 Destroy Lab

```bash
sudo ansible-playbook playbooks/destroy_lab.yml
```

---

# 🧨 Ransomware Experimentation Workflow

A typical ransomware evaluation workflow can be performed as follows:

1. Deploy the enterprise infrastructure.
2. Create clean-state VM snapshots.
3. Transfer ransomware samples into `client1`.
4. Execute ransomware samples in the isolated environment.
5. Monitor:
   - network traffic
   - file system activity
   - backup server interactions
   - DNS/DHCP behavior
6. Restore VMs using snapshots.
7. Repeat experiments safely.

---

# 📸 Snapshot Management

Snapshots are automatically created using the name:

```text
clean-state
```

Useful for:

- ransomware rollback
- malware experimentation
- forensic recovery
- repeatable testing

Restore example:

```bash
sudo virsh snapshot-revert client1 clean-state
```

# 🧯 Troubleshooting

## VM Already Exists

If virtual machines already exist and prevent redeployment:

```bash
sudo virsh undefine <vm-name> --remove-all-storage
```

Example:

```bash
sudo virsh undefine dhcp1 --remove-all-storage
```

---

## Destroy Existing Lab

Destroy all deployed virtual machines and enterprise networks:

```bash
sudo ansible-playbook playbooks/destroy_lab.yml
```

---

## Remove Leftover Disk Images

If old QCOW2 or cloud-init ISO files remain:

```bash
sudo rm -f /var/lib/libvirt/images/*.qcow2
sudo rm -f /var/lib/libvirt/images/*-seed.iso
```

---

## Verify Enterprise Network

```bash
virsh net-list --all
```

Expected network:

```text
enterprise-net
```

---

## Verify Virtual Machines

```bash
virsh list --all
```

---

## Access VM Console

```bash
virsh console dhcp1
```

Inside VM:

```bash
ip a
```

Exit console:

```text
CTRL + ]
```

---

## Verify SSH Connectivity

```bash
ssh student@10.10.10.10
```

---

## Cloud-init Delays

During first boot, Ubuntu cloud-init initialization may take approximately:

- 1–3 minutes
- depending on system resources

Wait until cloud-init finishes before testing SSH connectivity.

---

## Common Issues

| Issue | Possible Cause | Solution |
|---|---|---|
| SSH timeout | cloud-init still running | wait longer |
| VM creation fails | existing VM definitions | undefine old VMs |
| Disk already in use | stale libvirt definitions | remove old VMs |
| Network unreachable | enterprise-net not active | restart libvirt network |
| Ansible SSH failure | sshpass missing | install sshpass |
| No VM IP address | netplan configuration issue | verify `enp1s0` interface |

---

# 📚 References

## Official Documentation

- [Ansible Documentation](https://docs.ansible.com/)
- [Libvirt Documentation](https://libvirt.org/docs.html)
- [KVM Documentation](https://www.linux-kvm.org/)
- [Cloud-init Documentation](https://cloudinit.readthedocs.io/)
- [Ubuntu Cloud Images](https://cloud-images.ubuntu.com/)
- [BIND9 Documentation](https://bind9.readthedocs.io/)
- [Kea DHCP Documentation](https://kea.readthedocs.io/)
- [Samba Documentation](https://www.samba.org/samba/docs/)

---

---

# 📦 Infrastructure Services

The deployed enterprise infrastructure currently includes:

| Service | Technology |
|---|---|
| DHCP Server | Kea DHCP |
| DNS Server | BIND9 |
| Backup Server | Samba |
| Virtualization | KVM/QEMU |
| VM Management | Libvirt |
| Automation | Ansible |
| VM Bootstrap | Cloud-init |

---
