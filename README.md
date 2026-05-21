# 🔐 Ransomware Testbed using Ansible and KVM

A fully automated enterprise ransomware cyber-range built using **Ansible**, **KVM/QEMU**, **Libvirt**, **Cloud-init**, and **Ubuntu Server Cloud Images**.

The testbed provides a reproducible, isolated, enterprise-style environment for ransomware behavior analysis, malware execution testing, backup and recovery validation, DNS/DHCP infrastructure testing, incident response experiments, and network traffic analysis.

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

### Infrastructure Components

| VM       | Role           | Technology  | IP Address     |
|----------|----------------|-------------|----------------|
| dhcp1    | DHCP Server    | Kea DHCP    | 10.10.10.10    |
| dns1     | DNS Server     | BIND9       | 10.10.10.53    |
| backup1  | Backup Server  | Samba       | 10.10.10.20    |
| client1  | Enterprise Client | Ubuntu   | 10.10.10.100   |

### Underlying Stack

| Layer            | Technology       |
|------------------|------------------|
| Virtualization   | KVM/QEMU         |
| VM Management    | Libvirt          |
| Automation       | Ansible          |
| VM Bootstrap     | Cloud-init       |
| Base Image       | Ubuntu 22.04 Cloud Image |

### Network Topology

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
git clone https://github.com/<your-username>/RansomwareTestbed.git
cd RansomwareTestbed
```

### 2. Download the Ubuntu Cloud Image

```bash
sudo mkdir -p /opt/vm_images
cd /opt/vm_images
sudo wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
```

### 3. Configure Inventory

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

## 🚀 Deployment

### Deploy the Complete Lab

Run the following command to deploy the entire enterprise testbed:

```bash
sudo ansible-playbook -i inventory/hosts.ini playbooks/site.yml
```

This automatically performs the following steps in order:

1. Creates the enterprise network
2. Provisions virtual machines
3. Configures static networking
4. Deploys the DHCP server
5. Deploys the DNS server
6. Deploys the backup server
7. Creates clean-state snapshots

> **Note:** During first boot, cloud-init initialization may take 1–3 minutes depending on system resources. Wait until cloud-init finishes before attempting SSH.

### Individual Playbooks

Each step can also be executed independently for granular control or debugging:

```bash
# Create the enterprise network
sudo ansible-playbook playbooks/00_create_enterprise_network.yml

# Create virtual machines
sudo ansible-playbook playbooks/create_vms.yml

# Configure DHCP server
sudo ansible-playbook -i inventory/hosts.ini playbooks/configure_dhcp.yml

# Configure DNS server
sudo ansible-playbook -i inventory/hosts.ini playbooks/configure_dns.yml

# Configure backup server
sudo ansible-playbook -i inventory/hosts.ini playbooks/configure_backup.yml

# Create snapshots
sudo ansible-playbook playbooks/snapshots.yml
```

### Verify Deployment

```bash
# List enterprise network
virsh net-list --all

# List virtual machines
virsh list --all
```

Expected virtual machines:

- `dhcp1`
- `dns1`
- `backup1`
- `client1`

---

## 🔧 Usage

### SSH Access

Default credentials:

- **Username:** `student`
- **Password:** `student`

Example:

```bash
ssh student@10.10.10.10
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

Snapshots are automatically created with the name `clean-state`, which is useful for ransomware rollback, malware experimentation, forensic recovery, and repeatable testing.

Restore a VM to its clean state:

```bash
sudo virsh snapshot-revert client1 clean-state
```

### Ransomware Experimentation Workflow

A typical evaluation workflow consists of the following steps:

1. Deploy the enterprise infrastructure.
2. Confirm that clean-state VM snapshots exist.
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

## 🔄 Redeployment & Teardown

### Destroy the Lab

Tear down all VMs and the enterprise network:

```bash
sudo ansible-playbook playbooks/destroy_lab.yml
```

### Remove Leftover Disk Images

```bash
sudo rm -f /var/lib/libvirt/images/*.qcow2
sudo rm -f /var/lib/libvirt/images/*-seed.iso
```

### Redeploy

```bash
sudo ansible-playbook -i inventory/hosts.ini playbooks/site.yml
```

---

---

# 🌐 Internal Enterprise DNS Validation

After deployment, the enterprise infrastructure can be configured to use the internally deployed DNS server:

```text
10.10.10.53
```

instead of public DNS resolvers.

Example `netplan` configuration on `client1`:

```yaml
network:
  version: 2
  ethernets:
    enp1s0:
      dhcp4: false
      addresses:
        - 10.10.10.100/24
      routes:
        - to: default
          via: 10.10.10.1
      nameservers:
        addresses:
          - 10.10.10.53
```

Apply configuration:

```bash
sudo netplan apply
```

---

## 🔍 Verify DNS Resolver

```bash
resolvectl status
```

Expected output:

```text
Link 2 (enp1s0)
Current Scopes: DNS
DNS Servers: 10.10.10.53
```

---

## 🧪 Validate Internal DNS Resolution

Example:

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

This is normal behavior.

The local resolver forwards DNS requests internally to the configured enterprise DNS server:

```text
10.10.10.53
```

---

## ⚠️ Open vSwitch Warning

During `netplan apply`, Ubuntu may display:

```text
WARNING:root:Cannot call Open vSwitch: ovsdb-server.service is not running.
```

This warning is harmless in this project because the ransomware testbed uses:

- libvirt NAT networking
- standard Linux bridges

and does NOT depend on Open vSwitch.

---

## 🧯 Troubleshooting

### VM Already Exists

If a VM definition blocks redeployment, remove it manually:

```bash
sudo virsh undefine <vm-name> --remove-all-storage
```

Example:

```bash
sudo virsh undefine dhcp1 --remove-all-storage
```

If multiple VMs are stale, use the teardown workflow described in the [Redeployment & Teardown](#-redeployment--teardown) section.

### Common Issues

| Issue                  | Possible Cause                  | Solution                                  |
|------------------------|---------------------------------|-------------------------------------------|
| SSH timeout            | cloud-init still running        | Wait 1–3 minutes after boot               |
| VM creation fails      | Existing VM definitions         | Undefine old VMs                          |
| Disk already in use    | Stale libvirt definitions       | Remove old VM disk images                 |
| Network unreachable    | `enterprise-net` not active     | Restart libvirt network                   |
| Ansible SSH failure    | `sshpass` missing               | Install `sshpass`                         |
| No VM IP address       | netplan configuration issue     | Verify the `enp1s0` interface             |

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
