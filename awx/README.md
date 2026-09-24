# ENTRAP AWX — Student Attack Learning Platform

A multi-user cybersecurity lab where students launch real attacks (ransomware, DHCP exhaustion, nmap scans, SSH brute force) on an isolated virtual testbed, collect forensic logs, and download them for analysis. Instructors observe all activity from a central admin panel.

Built on **AWX** (open-source Ansible Tower) running inside **Minikube** on a single server, orchestrating attacks across a full enterprise network of 11 KVM virtual machines.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Student Laptop (Browser)                                       │
│                                                                 │
│  Tab 1: AWX (localhost:9090)     Tab 2: Logs (localhost:9091)   │
│    → Login as student1/student2    → Browse & download logs     │
│    → Select attack from dropdown   → Per-student folders        │
│    → Watch job execution live      → Suricata, syslog, DHCP    │
└──────────────────────┬──────────────────────┬───────────────────┘
                       │ SSH Tunnel           │ SSH Tunnel
                       │ :9090→:8080          │ :9091→:8888
┌──────────────────────▼──────────────────────▼───────────────────┐
│  Server (198.18.0.110)                                          │
│                                                                 │
│  Minikube Cluster (namespace: awx)                              │
│  ├── AWX Web + Task pods        (port 8080)                     │
│  ├── AWX Postgres               (persistent DB)                 │
│  ├── AWX Operator               (manages AWX lifecycle)         │
│  ├── Log Server (nginx)         (port 8888)                     │
│  └── PVCs:                                                      │
│      ├── entrap-awx-projects-claim  (git project files)         │
│      └── entrap-student-logs        (collected logs per student) │
│                                                                 │
│  KVM Virtual Machines (11 total)                                │
│  ├── gateway1      173.168.0.10   (Suricata IDS, NAT, routing) │
│  ├── coreswitch    10.10.0.2      (inter-VLAN routing)         │
│  ├── dns1          10.10.10.53    (BIND9 DNS)                  │
│  ├── dhcp1         10.10.10.2     (Kea DHCP server)            │
│  ├── web1          10.10.10.10    (Apache web server)           │
│  ├── backup1       10.10.10.20    (Samba file share)            │
│  ├── c2server      173.168.0.50   (GonnaCry C2 — Flask)        │
│  ├── client1       10.10.20.x     (victim — DHCP assigned)     │
│  └── client2       10.10.20.x     (attacker — DHCP assigned)   │
└─────────────────────────────────────────────────────────────────┘
```

---

## What Students Experience

1. **Login** to AWX at `localhost:9090` with their credentials
2. **Templates** page shows one workflow: **"Student Attack Lab"**
3. **Click the rocket icon** to launch — a survey appears:
   - **Student ID** — text field (e.g., `student1`)
   - **Student Name** — text field (e.g., `Alice Smith`)
   - **Select Attack** — dropdown:
     - `dhcp_exhaustion` — Drains DHCP pool with spoofed MACs
     - `gonnacry` — Deploys ransomware via C2 server (AES-256-GCM encryption)
     - `nmap_scan` — SYN scan of both subnets
     - `ssh_brute_force` — Hydra credential stuffing attack
4. **Watch execution** — the workflow runs 3 steps:
   - **Deploy Attack Scripts** — copies attack tools to client VMs
   - **Execute Attack** — runs the selected attack on the testbed
   - **Collect Logs** — pulls Suricata, syslog, and DHCP logs from gateway1
5. **Download logs** at `localhost:9091/logs/<student_id>/` — organized by timestamp and attack type
6. **Analyze** the logs offline using Wireshark, jq, Python, or any SIEM tool

## What Admin Sees

- **Jobs panel** — all jobs from all students with "Launched By" column
- **Workflow visualizer** — click any workflow job to see the step-by-step graph
- **Full Ansible output** — click any individual job for complete stdout
- **Activity Stream** — every user action logged with timestamps

---

## Initial Setup (One-Time)

### Prerequisites

- Ubuntu 24.04 server with KVM/libvirt
- Minikube installed (`curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64`)
- kubectl installed
- The ENTRAP testbed VMs already deployed (`ansible-playbook playbooks/site.yml`)
- Clean-state snapshots created (`ansible-playbook playbooks/snapshots.yml`)

### Step 1: Deploy AWX

```bash
cd ~/RansomwareTestbed/awx

# Install the AWX operator
kubectl apply -k kustomization_operator.yaml
kubectl wait --for=condition=Available deployment/awx-operator-controller-manager \
  -n awx --timeout=300s

# Deploy AWX instance
kubectl apply -k kustomization.yaml

# Wait for pods (takes 5-10 minutes; rsyslog CrashLoop is expected and harmless)
kubectl get pods -n awx -w
```

### Step 2: Run the setup script

```bash
cd ~/RansomwareTestbed/awx
chmod +x entrap_setup_all.sh
./entrap_setup_all.sh
```

This script handles (idempotent — safe to re-run):
- Minikube status check
- Network routes (Minikube → testbed VMs)
- iptables rules (NAT/forwarding)
- Port-forward to AWX
- SSH key secret + volume mount into AWX EE
- AWX credential creation (properly JSON-encoded SSH key)
- Job template configuration with ProxyCommand SSH args
- Student user creation (student1, student2, instructor)
- Workflow creation with survey
- RBAC permissions

### Step 3: Configure the workflow and log server

```bash
# Run configure_awx_workflow.sh (creates templates, workflow, survey, RBAC)
# Or run the commands from the "AWX Configuration" section below

# Deploy the log server
kubectl apply -f log-server.yaml -n awx  # or use the kubectl commands below
```

---

## Daily Startup Procedure

### Terminal 1 — Server (main working terminal)

SSH into the server and start services:

```bash
ssh adityak@198.18.0.110
cd ~/RansomwareTestbed

# 1. Start Minikube (if not running)
minikube status || minikube start

# 2. Check AWX pods
kubectl get pods -n awx

# 3. Add network routes (lost on every reboot)
minikube ssh "sudo ip route add 173.168.0.0/24 via 192.168.49.1 2>/dev/null; true"
minikube ssh "sudo ip route add 10.10.0.0/24 via 192.168.49.1 2>/dev/null; true"
minikube ssh "sudo ip route add 10.10.10.0/24 via 192.168.49.1 2>/dev/null; true"
minikube ssh "sudo ip route add 10.10.20.0/24 via 192.168.49.1 2>/dev/null; true"
sudo iptables -C FORWARD -s 192.168.49.0/24 -d 173.168.0.0/24 -j ACCEPT 2>/dev/null || \
    sudo iptables -I FORWARD -s 192.168.49.0/24 -d 173.168.0.0/24 -j ACCEPT
sudo iptables -C FORWARD -s 192.168.49.0/24 -d 10.10.0.0/16 -j ACCEPT 2>/dev/null || \
    sudo iptables -I FORWARD -s 192.168.49.0/24 -d 10.10.0.0/16 -j ACCEPT
sudo iptables -C FORWARD -d 192.168.49.0/24 -s 173.168.0.0/24 -j ACCEPT 2>/dev/null || \
    sudo iptables -I FORWARD -d 192.168.49.0/24 -s 173.168.0.0/24 -j ACCEPT
sudo iptables -C FORWARD -d 192.168.49.0/24 -s 10.10.0.0/16 -j ACCEPT 2>/dev/null || \
    sudo iptables -I FORWARD -d 192.168.49.0/24 -s 10.10.0.0/16 -j ACCEPT
sudo iptables -t nat -C POSTROUTING -s 192.168.49.0/24 -d 173.168.0.0/24 -j MASQUERADE 2>/dev/null || \
    sudo iptables -t nat -I POSTROUTING -s 192.168.49.0/24 -d 173.168.0.0/24 -j MASQUERADE
sudo iptables -t nat -C POSTROUTING -s 192.168.49.0/24 -d 10.10.0.0/16 -j MASQUERADE 2>/dev/null || \
    sudo iptables -t nat -I POSTROUTING -s 192.168.49.0/24 -d 10.10.0.0/16 -j MASQUERADE

# 4. Check VMs
virsh list --all

# 5. Set AWX credentials for API commands
export TOWER_PASSWORD=$(kubectl get secret -n awx entrap-awx-admin-password \
  -o jsonpath="{.data.password}" | base64 --decode)
echo "Admin password: $TOWER_PASSWORD"
```

### Terminal 2 — Server (port-forwards — keep open)

```bash
ssh adityak@198.18.0.110

pkill -f "kubectl port-forward" 2>/dev/null
sleep 2
kubectl port-forward svc/entrap-awx-service 8080:80 -n awx --address 0.0.0.0 &
kubectl port-forward svc/log-server 8888:8888 -n awx --address 0.0.0.0 &

# These must stay running. If they die, re-run the two lines above.
```

### Terminal 3 — Laptop (SSH tunnel — keep open)

```powershell
# Windows PowerShell (or Mac/Linux terminal)
ssh -L 9090:localhost:8080 -L 9091:localhost:8888 adityak@198.18.0.110

# This tunnels:
#   localhost:9090 → AWX web UI
#   localhost:9091 → Log download server
# Keep this window open the entire session.
```

### Browser — Laptop

| Tab | URL | User | Password |
|-----|-----|------|----------|
| Admin | `http://localhost:9090` | `admin` | *(from Terminal 1 output)* |
| Student 1 | `http://localhost:9090` (incognito) | `student1` | `Student@123` |
| Student 2 | `http://localhost:9090` (Edge/Firefox) | `student2` | `Student@123` |
| Logs | `http://localhost:9091` | *(no login)* | — |

---

## Admin Operations

### Get Admin Password

```bash
kubectl get secret -n awx entrap-awx-admin-password \
  -o jsonpath="{.data.password}" | base64 --decode; echo
```

### Check AWX Pod Status

```bash
kubectl get pods -n awx
# Expected: task and web pods at 3/4 and 2/3 (rsyslog CrashLoop is harmless)
# If pods show 0/4 or Pending, wait or check: kubectl describe pod <name> -n awx
```

### Check VM Status

```bash
virsh list --all
# All 11 VMs should show "running"

# Start a stopped VM
sudo virsh start <vm-name>
```

### Check Client VM Connectivity

```bash
# Ping through gateway
ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no admin@173.168.0.10 \
  "ping -c1 10.10.20.152; ping -c1 10.10.20.153"
```

### Check Active DHCP Leases (find client IPs)

```bash
ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no \
  -o ProxyJump=admin@173.168.0.10 admin@10.10.10.2 \
  "awk -F',' 'NR>1 && \$10==\"0\" {print \$1}' /var/lib/kea/kea-leases4.csv"
```

### Check C2 Server (needed for GonnaCry attacks)

```bash
ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no admin@173.168.0.50 \
  "curl -s http://localhost/ > /dev/null && echo 'C2 UP' || echo 'C2 DOWN'"
```

### View All Student Jobs (API)

```bash
export TOWER_PASSWORD=$(kubectl get secret -n awx entrap-awx-admin-password \
  -o jsonpath="{.data.password}" | base64 --decode)

curl -s -u "admin:$TOWER_PASSWORD" \
  "http://localhost:8080/api/v2/unified_jobs/?order_by=-created&page_size=20" | \
  python3 -c "
import sys,json
for j in json.load(sys.stdin)['results']:
    user = j.get('summary_fields',{}).get('created_by',{}).get('username','?')
    print(f'  {j[\"id\"]:3d}  {j[\"status\"]:12s}  {user:12s}  {j[\"name\"]}')"
```

### View Job Output

```bash
# Replace JOB_ID with the job number
curl -s -u "admin:$TOWER_PASSWORD" \
  "http://localhost:8080/api/v2/jobs/JOB_ID/stdout/?format=txt"
```

### Live Job Monitor (refreshes every 5s)

```bash
watch -n5 'curl -s -u "admin:'$TOWER_PASSWORD'" \
  "http://localhost:8080/api/v2/unified_jobs/?order_by=-created&page_size=10" | \
  python3 -c "
import sys,json
for j in json.load(sys.stdin)[\"results\"]:
    user=j.get(\"summary_fields\",{}).get(\"created_by\",{}).get(\"username\",\"?\")
    print(f\"  {j[\\\"id\\\"]:3d}  {j[\\\"status\\\"]:12s}  {user:12s}  {j[\\\"name\\\"]}\")"'
```

### View Collected Logs (from server)

```bash
kubectl run log-view --rm -it --image=busybox -n awx --restart=Never \
  --overrides='{"spec":{"volumes":[{"name":"logs","persistentVolumeClaim":{"claimName":"entrap-student-logs"}}],"containers":[{"name":"c","image":"busybox","command":["find","/mnt","-type","f"],"volumeMounts":[{"name":"logs","mountPath":"/mnt"}]}]}}'
```

### Log Storage Path

Logs are stored in PVC `entrap-student-logs` mounted inside job pods at `/mnt/entrap-logs/`:

```
/mnt/entrap-logs/
├── student1/
│   ├── 20260924T094346_dhcp_exhaustion/
│   │   └── gateway1/
│   │       ├── eve-alert.json
│   │       ├── eve-dns.json
│   │       ├── eve-http.json
│   │       ├── eve-tls.json
│   │       ├── eve-flow.json
│   │       ├── eve-smb.json
│   │       ├── eve-anomaly.json
│   │       ├── fast.log
│   │       └── suricata.log
│   └── 20260924T100512_gonnacry/
│       └── gateway1/
│           └── ...
└── student2/
    └── ...
```

On the Minikube node, the physical path is:
```
/tmp/hostpath-provisioner/awx/entrap-student-logs/
```

Students download logs via the nginx log server at `http://localhost:9091/logs/<student_id>/`.

---

## Reset Testbed Between Students

```bash
# Reset client VMs only (preserves infra)
sudo virsh snapshot-revert client1 clean-state
sudo virsh snapshot-revert client2 clean-state
sudo virsh start client1 2>/dev/null; sudo virsh start client2 2>/dev/null

echo "Waiting 45s for VMs to boot..."
sleep 45

# Verify
ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no admin@173.168.0.10 \
  "ping -c1 -W2 10.10.20.152; ping -c1 -W2 10.10.20.153" 2>/dev/null | grep "bytes from"
```

**Important:** After snapshot revert, `python3-scapy` must be reinstalled for DHCP attacks:

```bash
# Copy the .deb from server to client (fast)
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o ProxyJump=admin@173.168.0.10 \
  ~/python3-scapy*.deb student@10.10.20.153:/tmp/

sshpass -p student ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o ProxyJump=admin@173.168.0.10 student@10.10.20.153 \
  "sudo dpkg -i /tmp/python3-scapy*.deb"
```

**Tip:** To avoid reinstalling scapy after every reset, take a new snapshot after installing it:

```bash
sudo virsh snapshot-delete client2 clean-state
sudo virsh snapshot-create-as client2 clean-state --live
# Repeat for client1
```

---

## Troubleshooting

### Port-forward died

```bash
# Terminal 2 on server
pkill -f "kubectl port-forward" 2>/dev/null
sleep 2
kubectl port-forward svc/entrap-awx-service 8080:80 -n awx --address 0.0.0.0 &
kubectl port-forward svc/log-server 8888:8888 -n awx --address 0.0.0.0 &
```

### Browser shows "Connection Refused"

1. Check port-forward is running on Terminal 2
2. Check SSH tunnel is running on Terminal 3
3. Re-establish: `ssh -L 9090:localhost:8080 -L 9091:localhost:8888 adityak@198.18.0.110`

### Student can't see the workflow

```bash
# Re-run RBAC assignment
export TOWER_PASSWORD=$(kubectl get secret -n awx entrap-awx-admin-password \
  -o jsonpath="{.data.password}" | base64 --decode)

# Check what student sees
curl -s -u "student1:Student@123" \
  "http://localhost:8080/api/v2/workflow_job_templates/" | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['count'])"
# Should print 1
```

### Job fails with SSH timeout

```bash
# Check routes exist inside Minikube
minikube ssh "ip route" | grep -E "173.168|10.10"

# If missing, re-add (see Daily Startup Procedure)
```

### Job fails with "Permission denied" on SSH

```bash
# Verify the SSH key mount in job pods
kubectl exec -n awx deployment/entrap-awx-task -c entrap-awx-ee -- \
  ls -la /opt/entrap-ssh/id_ed25519
# Should show the key file

# Verify key works
kubectl exec -n awx deployment/entrap-awx-task -c entrap-awx-ee -- \
  ssh -i /opt/entrap-ssh/id_ed25519 -o StrictHostKeyChecking=no \
  admin@173.168.0.10 hostname
# Should print "gateway1"
```

### Job fails with "checksum mismatch" during log collection

This happens when Suricata is actively writing to a log file while Ansible fetches it. The `ignore_errors: true` on the fetch task handles this — most logs still collect. Re-run the collect step if needed.

### Job hangs indefinitely

```bash
# Find and cancel
curl -s -u "admin:$TOWER_PASSWORD" \
  "http://localhost:8080/api/v2/jobs/?status=running" | \
  python3 -c "import sys,json; [print(j['id']) for j in json.load(sys.stdin)['results']]"

# Cancel job
curl -s -X POST -u "admin:$TOWER_PASSWORD" \
  -H "Content-Type: application/json" \
  "http://localhost:8080/api/v2/jobs/JOB_ID/cancel/"

# Kill stuck job pod
kubectl get pods -n awx | grep automation-job
kubectl delete pod <pod-name> -n awx --force
```

### Network routes lost after reboot

Routes inside Minikube and iptables rules on the host are not persistent. Re-run the route commands from the Daily Startup Procedure section, or run `./awx/entrap_setup_all.sh` which handles this automatically.

### AWX pods won't start after Minikube restart

```bash
minikube start
# Wait 2-3 minutes for pods to schedule
kubectl get pods -n awx -w
# The operator will reconcile and restart AWX pods
```

---

## Available Attacks

| Attack | Variable | What it does | Duration |
|--------|----------|-------------|----------|
| DHCP Exhaustion | `dhcp_exhaustion` | Spoofs random MACs to drain the DHCP pool using Scapy | ~2 min |
| GonnaCry Ransomware | `gonnacry` | Downloads binary from C2, encrypts victim files with AES-256-GCM | ~4 min |
| Nmap Reconnaissance | `nmap_scan` | SYN scan of both subnets on common ports | ~2 min |
| SSH Brute Force | `ssh_brute_force` | Hydra credential stuffing against victim VM | ~2 min |

### Logs Collected

| Source | Log files | What they capture |
|--------|-----------|-------------------|
| gateway1 (Suricata) | `eve-alert.json` | IDS alert events |
| gateway1 (Suricata) | `eve-dns.json` | DNS query/response logs |
| gateway1 (Suricata) | `eve-http.json` | HTTP transaction logs |
| gateway1 (Suricata) | `eve-tls.json` | TLS handshake logs |
| gateway1 (Suricata) | `eve-flow.json` | Network flow records |
| gateway1 (Suricata) | `eve-smb.json` | SMB protocol events |
| gateway1 (Suricata) | `eve-anomaly.json` | Protocol anomalies |
| gateway1 (Suricata) | `fast.log` | One-line alert summary |
| gateway1 (Suricata) | `suricata.log` | Engine operational log |

---

## AWX Configuration Reference

### Users

| Username | Password | Role |
|----------|----------|------|
| admin | *(auto-generated, see kubectl command)* | Superuser — full access |
| instructor | `Instructor@123` | Can view all jobs and templates |
| student1 | `Student@123` | Can launch workflow, view own jobs |
| student2 | `Student@123` | Can launch workflow, view own jobs |

### Job Templates

| ID | Name | Playbook | Purpose |
|----|------|----------|---------|
| 15 | ENTRAP: Deploy Attack Scripts | `deploy_attack_scripts.yml` | Copy attack tools to client VMs |
| 19 | ENTRAP: Execute Attack | `execute_attack.yml` | Run the selected attack |
| 12 | ENTRAP: Collect Logs | `collect_logs.yml` | Fetch logs from gateway1 |
| 13 | ENTRAP: Configure Logging | `configure_logging.yml` | Set up Suricata on gateway1 |
| 10 | ENTRAP: Build Testbed | `site.yml` | Full testbed deployment |
| 18 | ENTRAP: Check Testbed | `check_testbed.yml` | Verify testbed readiness |

### Workflow: Student Attack Lab

```
Deploy Attack Scripts → Execute Attack → Collect Logs
```

Survey variables passed to all steps:
- `student_id` — identifies the student (used for log folder names)
- `student_name` — student's full name (for records)
- `attack_type` — which attack to run (dropdown selection)

### Key AWX API Endpoints

```bash
# Base URL (from server)
http://localhost:8080/api/v2/

# Useful endpoints
/api/v2/me/                        # Current user info
/api/v2/unified_jobs/              # All jobs (filter: ?status=running)
/api/v2/workflow_jobs/             # Workflow jobs only
/api/v2/jobs/{id}/stdout/          # Job output (?format=txt)
/api/v2/job_templates/             # All templates
/api/v2/workflow_job_templates/    # All workflows
/api/v2/users/                     # User management
/api/v2/activity_stream/           # Audit trail
```

---

## Git Branch

All AWX-related changes are on the `awx-ansible` branch:

```bash
git checkout awx-ansible
```

The AWX project is configured to track this branch. After pushing changes:

```bash
git push origin awx-ansible

# Sync in AWX
curl -s -X POST -u "admin:$TOWER_PASSWORD" \
  "http://localhost:8080/api/v2/projects/8/update/" -d ''
```

---

## File Structure

```
RansomwareTestbed/
├── awx/
│   ├── awx-instance.yaml            # AWX CR definition
│   ├── kustomization.yaml           # AWX kustomize config
│   ├── kustomization_operator.yaml  # Operator kustomize config
│   └── entrap_setup_all.sh          # Master setup script
├── playbooks/
│   ├── check_testbed.yml            # Verify testbed is clean and ready
│   ├── deploy_attack_scripts.yml    # Copy attack tools to clients
│   ├── execute_attack.yml           # Run selected attack
│   ├── collect_logs.yml             # Fetch logs to persistent storage
│   ├── configure_logging.yml        # Set up Suricata on gateway1
│   ├── configure_c2.yml             # Deploy GonnaCry C2 server
│   ├── snapshots.yml                # Create clean-state VM snapshots
│   ├── site.yml                     # Full testbed deployment
│   └── group_vars/all.yml           # All shared variables
├── attacks/
│   ├── dhcp_exhaustion.py           # Scapy DHCP pool drain
│   ├── dhcp_attack_combined.sh      # DHCP stealth/MitM attack
│   ├── rogue_dhcp_server.sh         # Rogue DHCP server
│   ├── mitm_intercept.sh            # MitM traffic capture
│   └── GonnaCry/                    # Ransomware module
│       ├── src/GonnaCry/            # Encryptor Python source
│       ├── src/Server/              # C2 Flask server
│       └── build_binaries.sh        # PyInstaller build script
├── scripts/
│   ├── reset_testbed.sh             # Admin: restore VMs to clean state
│   ├── collect_logs.sh              # Manual attack orchestrator (pre-AWX)
│   └── export_dataset.py            # Export logs to ML dataset format
├── dataset/
│   ├── logs/                        # Historical log collections
│   └── labels.jsonl                 # Attack labels for ML training
└── inventory/
    └── hosts.ini                    # Ansible inventory (manual runs)
```

---

## Future Enhancements

- **Auto-reset:** Trigger `virsh snapshot-revert` from AWX via SSH to the hypervisor host
- **More attacks:** DHCP stealth, DHCP MitM (currently need multiple terminals)
- **Client VM logs:** Collect syslog and auth logs from victim/attacker VMs
- **Log packaging:** Tar and compress logs per student for bulk download
- **ML pipeline:** Feed collected logs into the anomaly detection model
- **Notifications:** Email students when their workflow completes
- **Bulk student creation:** Script to create 20+ student accounts
- **Persistent scapy:** Bake python3-scapy into client VM base image and re-snapshot
