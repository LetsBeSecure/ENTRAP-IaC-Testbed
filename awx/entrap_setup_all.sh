#!/bin/bash
# ============================================================
# ENTRAP AWX — Complete Setup (Single Script)
# ============================================================
# Run on server (198.18.0.110)
#
# BEFORE RUNNING:
#   On your laptop, open a SEPARATE PowerShell window and run:
#     ssh -L 9090:localhost:8080 adityak@198.18.0.110
#   Keep that window open the entire time.
#   Browser → http://localhost:9090
#
# USAGE:
#   chmod +x entrap_setup_all.sh
#   ./entrap_setup_all.sh
# ============================================================

set -o pipefail

API_BASE="http://localhost:8080/api/v2"

pause_stage() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ✅ $1 COMPLETE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    read -p "  Press ENTER to continue to next stage... " _
    echo ""
}

fail_exit() {
    echo "  ✗ FATAL: $1"
    echo "    Fix the issue and re-run this script."
    exit 1
}

# ============================================================
# STAGE 1: MINIKUBE + PODS
# ============================================================
echo "╔════════════════════════════════════════════════╗"
echo "║  STAGE 1: Minikube & AWX Pods                 ║"
echo "╚════════════════════════════════════════════════╝"

echo ""
echo "[1a] Checking Minikube..."
if minikube status 2>/dev/null | grep -q "Running"; then
    echo "  ✓ Minikube already running"
else
    echo "  Starting Minikube..."
    minikube start --cpus=4 --memory=8g --addons=ingress || fail_exit "Minikube failed to start"
    echo "  ✓ Minikube started"
fi

echo ""
echo "[1b] Checking AWX pods..."
kubectl get pods -n awx --no-headers 2>/dev/null
if ! kubectl get pods -n awx --no-headers 2>/dev/null | grep -q "entrap-awx-task"; then
    fail_exit "AWX pods not found in namespace 'awx'. Deploy AWX first."
fi
echo "  ✓ AWX pods exist (rsyslog CrashLoop is expected and harmless)"

echo ""
echo "[1c] Network routes (must re-apply after every reboot)..."
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
echo "  ✓ Routes and iptables applied"

echo ""
echo "[1d] Port-forward..."
pkill -f "kubectl port-forward.*entrap-awx" 2>/dev/null
sleep 1
nohup kubectl port-forward svc/entrap-awx-service 8080:80 -n awx --address 0.0.0.0 > /tmp/awx-pf.log 2>&1 &
PF_PID=$!
sleep 3
if kill -0 $PF_PID 2>/dev/null; then
    echo "  ✓ Port-forward running (PID: $PF_PID)"
else
    fail_exit "Port-forward died. Check /tmp/awx-pf.log"
fi

echo ""
echo "[1e] AWX API check..."
export TOWER_PASSWORD=$(kubectl get secret -n awx entrap-awx-admin-password -o jsonpath="{.data.password}" | base64 --decode)
AUTH="-u admin:$TOWER_PASSWORD"
for attempt in 1 2 3 4 5; do
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" $AUTH "$API_BASE/me/" 2>/dev/null)
    if [ "$HTTP" = "200" ]; then
        echo "  ✓ AWX API responding"
        break
    fi
    echo "  Attempt $attempt — HTTP $HTTP, retrying in 10s..."
    sleep 10
done
[ "$HTTP" != "200" ] && fail_exit "AWX API not responding after 5 attempts"

echo ""
echo "  Admin password: $TOWER_PASSWORD"

pause_stage "STAGE 1 (Infrastructure)"


# ============================================================
# STAGE 2: SSH KEY MOUNT + CREDENTIAL
# ============================================================
echo "╔════════════════════════════════════════════════╗"
echo "║  STAGE 2: SSH Key & Credentials               ║"
echo "╚════════════════════════════════════════════════╝"

echo ""
echo "[2a] Checking SSH key K8s secret..."
if kubectl get secret entrap-ssh-key -n awx > /dev/null 2>&1; then
    echo "  ✓ Secret entrap-ssh-key already exists"
else
    echo "  Creating secret from ~/.ssh/id_ed25519..."
    kubectl create secret generic entrap-ssh-key \
        --from-file=id_ed25519=$HOME/.ssh/id_ed25519 -n awx || fail_exit "Cannot create secret"
    echo "  ✓ Secret created"
fi

echo ""
echo "[2b] Checking EE volume mount..."
MOUNT_CHECK=$(kubectl get awx entrap-awx -n awx -o jsonpath='{.spec.ee_extra_volume_mounts}' 2>/dev/null)
if echo "$MOUNT_CHECK" | grep -q "entrap-ssh-key"; then
    echo "  ✓ EE volume mount already configured"
else
    echo "  Patching AWX CR to mount SSH key into EE..."
    kubectl patch awx entrap-awx -n awx --type merge -p '{
      "spec": {
        "extra_volumes": "- name: entrap-ssh-key\n  secret:\n    secretName: entrap-ssh-key\n    defaultMode: 384\n",
        "ee_extra_volume_mounts": "- name: entrap-ssh-key\n  mountPath: /opt/entrap-ssh/id_ed25519\n  subPath: id_ed25519\n  readOnly: true\n"
      }
    }' || fail_exit "Patch failed"
    echo "  ✓ Patch applied — waiting for pod restart..."
    sleep 10
    echo "  Waiting for new task pod..."
    for i in $(seq 1 30); do
        READY=$(kubectl get pods -n awx -l app.kubernetes.io/name=entrap-awx-task --no-headers 2>/dev/null | grep "Running" | head -1)
        if [ -n "$READY" ]; then
            echo "  ✓ Task pod restarted"
            break
        fi
        sleep 10
        echo "    Waiting... ($i)"
    done
    # Restart port-forward after pod restart
    pkill -f "kubectl port-forward.*entrap-awx" 2>/dev/null
    sleep 2
    nohup kubectl port-forward svc/entrap-awx-service 8080:80 -n awx --address 0.0.0.0 > /tmp/awx-pf.log 2>&1 &
    sleep 3
    echo "  ✓ Port-forward restarted"
fi

echo ""
echo "[2c] Verifying key is mounted in EE container..."
KEY_TEST=$(kubectl exec -n awx deployment/entrap-awx-task -c entrap-awx-ee -- ls -la /opt/entrap-ssh/id_ed25519 2>/dev/null)
if [ $? -eq 0 ]; then
    echo "  ✓ Key mounted: $KEY_TEST"
else
    echo "  ⚠ Key NOT visible in EE container (pod may still be restarting)"
    echo "    Run: kubectl get pods -n awx -w   and wait, then re-run this script"
fi

echo ""
echo "[2d] Ensuring ENTRAP Infra SSH Key credential exists with valid key..."
# Check if credential 6 exists (we recreated it), or create fresh
CRED_EXISTS=$(curl -s $AUTH "$API_BASE/credentials/?name=ENTRAP+Infra+SSH+Key" 2>/dev/null | \
    python3 -c "import sys,json; print(json.load(sys.stdin)['count'])" 2>/dev/null)

if [ "$CRED_EXISTS" = "0" ]; then
    echo "  Creating ENTRAP Infra SSH Key credential..."
    python3 -c "
import json, requests
key_data = open('$HOME/.ssh/id_ed25519').read()
resp = requests.post(
    'http://localhost:8080/api/v2/credentials/',
    auth=('admin', '$TOWER_PASSWORD'),
    json={
        'name': 'ENTRAP Infra SSH Key',
        'organization': 1,
        'credential_type': 1,
        'inputs': {'username': 'admin', 'ssh_key_data': key_data}
    }
)
print(f'  Created credential ID={resp.json().get(\"id\",\"?\")}' if resp.status_code==201 else f'  Error: {resp.text[:200]}')
"
else
    echo "  ✓ ENTRAP Infra SSH Key credential exists"
fi

# Get the credential ID
INFRA_CRED_ID=$(curl -s $AUTH "$API_BASE/credentials/?name=ENTRAP+Infra+SSH+Key" 2>/dev/null | \
    python3 -c "import sys,json; r=json.load(sys.stdin)['results']; print(r[0]['id'] if r else '')" 2>/dev/null)
echo "  Infra SSH Key credential ID: $INFRA_CRED_ID"

pause_stage "STAGE 2 (SSH Key & Credentials)"


# ============================================================
# STAGE 3: FIX JOB TEMPLATES (the networking fix)
# ============================================================
echo "╔════════════════════════════════════════════════╗"
echo "║  STAGE 3: Fix Job Templates                   ║"
echo "╚════════════════════════════════════════════════╝"

echo ""
echo "[3a] Discovering live client IPs from gateway1..."
echo "     (Playbook hardcodes 10.10.20.151 which is dead)"
LIVE_CLIENTS=$(ssh -i $HOME/.ssh/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    admin@173.168.0.10 "for ip in 10.10.20.150 10.10.20.151 10.10.20.152 10.10.20.153 10.10.20.154; do \
    ping -c1 -W1 \$ip >/dev/null 2>&1 && echo \$ip; done" 2>/dev/null)
echo "  Live client IPs:"
echo "$LIVE_CLIENTS" | while read ip; do echo "    ✓ $ip"; done

# Build target_ips YAML list
TARGET_IPS_YAML=$(echo "$LIVE_CLIENTS" | awk '{printf "    - %s\\n", $1}')
if [ -z "$TARGET_IPS_YAML" ]; then
    echo "  ⚠ No live clients found! Using defaults .152 .153"
    TARGET_IPS_YAML="    - 10.10.20.152\n    - 10.10.20.153"
fi

echo ""
echo "[3b] Listing job templates..."
curl -s $AUTH "$API_BASE/job_templates/" 2>/dev/null | python3 -c "
import sys, json
for t in json.load(sys.stdin).get('results', []):
    creds = [c['name'] for c in t.get('summary_fields',{}).get('credentials',[])]
    print(f\"  ID={t['id']:3d}  {t['name']:40s}  Creds={creds}\")"

echo ""
echo "[3c] Applying fixes to 'Deploy Attack Scripts' template (ID=15)..."

# The playbook expects these variables:
#   target_ips, client_user, client_password,
#   infra_ssh_private_key_path, infra_admin_user, vms, project_root
#
# We supply them all via extra_vars so the playbook's own
# add_host ProxyCommand works correctly.

EXTRA_VARS=$(cat <<'VARSEOF'
---
target_ips:
TARGET_IPS_PLACEHOLDER
client_user: "student"
client_password: "student"
infra_ssh_private_key_path: "/opt/entrap-ssh/id_ed25519"
infra_admin_user: "admin"
vms:
  - name: "gateway1"
    wan_ip: "173.168.0.10"
VARSEOF
)

# Replace placeholder with actual IPs
EXTRA_VARS=$(echo "$EXTRA_VARS" | sed "s|TARGET_IPS_PLACEHOLDER|$TARGET_IPS_YAML|")

echo "  Extra vars to apply:"
echo "$EXTRA_VARS" | sed 's/^/    /'

# Apply via API using python3 for proper JSON encoding
python3 -c "
import json, requests
extra_vars = '''$EXTRA_VARS'''
resp = requests.patch(
    'http://localhost:8080/api/v2/job_templates/15/',
    auth=('admin', '$TOWER_PASSWORD'),
    json={'extra_vars': extra_vars}
)
print(f'  Template 15 update: HTTP {resp.status_code}')
"

# Assign credential to template 15
echo ""
echo "  Assigning credential ID=$INFRA_CRED_ID to template 15..."
curl -s -X POST $AUTH -H "Content-Type: application/json" \
    "$API_BASE/job_templates/15/credentials/" \
    -d "{\"id\": $INFRA_CRED_ID}" > /dev/null 2>&1
echo "  ✓ Credential assigned"

echo ""
echo "[3d] Applying ProxyCommand + credential to OTHER templates..."
# For templates that use AWX inventory (not hardcoded), we set
# ansible_ssh_common_args as extra_vars
for TMPL_ID in 10 12 13 14; do
    TMPL_NAME=$(curl -s $AUTH "$API_BASE/job_templates/$TMPL_ID/" 2>/dev/null | \
        python3 -c "import sys,json; print(json.load(sys.stdin).get('name','?'))" 2>/dev/null)
    
    echo "  Fixing template $TMPL_ID ($TMPL_NAME)..."
    
    # Assign credential
    curl -s -X POST $AUTH -H "Content-Type: application/json" \
        "$API_BASE/job_templates/$TMPL_ID/credentials/" \
        -d "{\"id\": $INFRA_CRED_ID}" > /dev/null 2>&1
    
    # Set ProxyCommand via extra_vars (uses ssh-agent, key auto-loaded by AWX)
    python3 -c "
import requests
resp = requests.patch(
    'http://localhost:8080/api/v2/job_templates/$TMPL_ID/',
    auth=('admin', '$TOWER_PASSWORD'),
    json={'extra_vars': '---\nansible_ssh_common_args: \"-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand=\\\\\"ssh -A -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p admin@173.168.0.10\\\\\"\"'}
)
print(f'    HTTP {resp.status_code}')
" 2>/dev/null
done

# Snapshots and Destroy run locally — just assign credential
for TMPL_ID in 16 17; do
    curl -s -X POST $AUTH -H "Content-Type: application/json" \
        "$API_BASE/job_templates/$TMPL_ID/credentials/" \
        -d "{\"id\": $INFRA_CRED_ID}" > /dev/null 2>&1
    echo "  Template $TMPL_ID: credential assigned (runs locally, no proxy needed)"
done

echo ""
echo "[3e] Setting up persistent student logs volume..."
# Create a PVC for student logs (separate from projects PVC)
if kubectl get pvc entrap-student-logs -n awx > /dev/null 2>&1; then
    echo "  ✓ PVC entrap-student-logs already exists"
else
    cat <<PVCEOF | kubectl apply -f - -n awx
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: entrap-student-logs
  namespace: awx
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 5Gi
PVCEOF
    echo "  ✓ PVC created"
fi

echo ""
echo "[3f] Updating Container Group pod spec (SSH key + logs PVC mount)..."
# Job pods are spawned by the Container Group (ID=2 "default").
# Mount both the SSH key and logs PVC, with fsGroup so uid 1000 can write.
CG_UPDATE=$(curl -s -X PATCH -H "Content-Type: application/json" \
  -u "admin:$TOWER_PASSWORD" \
  "$API_BASE/instance_groups/2/" \
  -d '{
    "pod_spec_override": "apiVersion: v1\nkind: Pod\nmetadata:\n  namespace: awx\nspec:\n  securityContext:\n    fsGroup: 0\n    runAsUser: 1000\n  containers:\n    - name: worker\n      image: quay.io/ansible/awx-ee:latest\n      volumeMounts:\n        - name: entrap-ssh-key\n          mountPath: /opt/entrap-ssh/id_ed25519\n          subPath: id_ed25519\n          readOnly: true\n        - name: entrap-logs\n          mountPath: /mnt/entrap-logs\n  volumes:\n    - name: entrap-ssh-key\n      secret:\n        secretName: entrap-ssh-key\n        defaultMode: 384\n    - name: entrap-logs\n      persistentVolumeClaim:\n        claimName: entrap-student-logs\n"
  }' 2>/dev/null)
echo "  ✓ Container Group pod spec updated (SSH key + logs PVC + fsGroup)"

echo ""
echo "[3g] Ensuring AWX project tracks 'awx-ansible' branch..."
CURRENT_BRANCH=$(curl -s $AUTH "$API_BASE/projects/8/" 2>/dev/null | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('scm_branch',''))" 2>/dev/null)
if [ "$CURRENT_BRANCH" != "awx-ansible" ]; then
    curl -s -X PATCH -H "Content-Type: application/json" $AUTH \
        "$API_BASE/projects/8/" \
        -d '{"scm_branch": "awx-ansible"}' > /dev/null 2>&1
    echo "  ✓ Project branch switched to awx-ansible"
    curl -s -X POST $AUTH "$API_BASE/projects/8/update/" -d '' > /dev/null 2>&1
    sleep 15
    echo "  ✓ Project synced"
else
    echo "  ✓ Project already on awx-ansible branch"
fi

pause_stage "STAGE 3 (Job Templates + Log Persistence Fixed)"


# ============================================================
# STAGE 4: TEST JOB LAUNCH
# ============================================================
echo "╔════════════════════════════════════════════════╗"
echo "║  STAGE 4: Test Job Launch                     ║"
echo "╚════════════════════════════════════════════════╝"

echo ""
echo "[4a] Launching 'Deploy Attack Scripts' as admin..."
JOB_ID=$(curl -s -X POST $AUTH -H "Content-Type: application/json" \
    "$API_BASE/job_templates/15/launch/" -d '{}' 2>/dev/null | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)

if [ -z "$JOB_ID" ]; then
    echo "  ✗ Failed to launch job"
else
    echo "  ✓ Job $JOB_ID launched — monitoring..."
    for i in $(seq 1 20); do
        sleep 5
        STATUS=$(curl -s $AUTH "$API_BASE/jobs/$JOB_ID/" 2>/dev/null | \
            python3 -c "import sys,json; print(json.load(sys.stdin).get('status','?'))" 2>/dev/null)
        echo "    [$i] $STATUS"
        case "$STATUS" in
            successful) echo "  ✓ JOB SUCCEEDED!"; break ;;
            failed|error|canceled)
                echo "  ✗ JOB FAILED — output:"
                curl -s $AUTH "$API_BASE/jobs/$JOB_ID/stdout/?format=txt" 2>/dev/null | tail -25
                break ;;
        esac
    done
fi

pause_stage "STAGE 4 (Test Launch)"


# ============================================================
# STAGE 5: USERS & RBAC
# ============================================================
echo "╔════════════════════════════════════════════════╗"
echo "║  STAGE 5: Users & RBAC                        ║"
echo "╚════════════════════════════════════════════════╝"

echo ""
echo "[5a] Creating users..."
for INFO in "student1:Student:One:student1@entrap.lab:Student@123" \
            "student2:Student:Two:student2@entrap.lab:Student@123" \
            "instructor:Lab:Instructor:instructor@entrap.lab:Instructor@123"; do
    IFS=':' read -r uname fname lname email pass <<< "$INFO"
    EXISTS=$(curl -s $AUTH "$API_BASE/users/?username=$uname" 2>/dev/null | \
        python3 -c "import sys,json; print(json.load(sys.stdin)['count'])" 2>/dev/null)
    if [ "$EXISTS" = "0" ]; then
        curl -s -X POST $AUTH -H "Content-Type: application/json" "$API_BASE/users/" \
            -d "{\"username\":\"$uname\",\"password\":\"$pass\",\"email\":\"$email\",\"first_name\":\"$fname\",\"last_name\":\"$lname\"}" > /dev/null 2>&1
        echo "  ✓ Created $uname"
    else
        echo "  ✓ $uname exists"
    fi
done

echo ""
echo "[5b] Finding/creating workflow..."
WF_ID=$(curl -s $AUTH "$API_BASE/workflow_job_templates/" 2>/dev/null | \
    python3 -c "import sys,json; r=json.load(sys.stdin)['results']; print(r[0]['id'] if r else '')" 2>/dev/null)

if [ -z "$WF_ID" ]; then
    echo "  Creating workflow..."
    WF_ID=$(curl -s -X POST $AUTH -H "Content-Type: application/json" \
        "$API_BASE/workflow_job_templates/" \
        -d '{"name":"Experiment: Ransomware Campaign","organization":1,"description":"Deploy attack scripts to target clients, then collect forensic logs (Suricata, syslog, DHCP).","ask_variables_on_launch":true,"survey_enabled":true}' 2>/dev/null | \
        python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
    echo "  ✓ Created workflow ID=$WF_ID"
    
    # Add workflow nodes: Deploy(15) → Collect(12)
    # NOTE: Snapshot removed — virsh not available inside AWX container
    NODE1=$(curl -s -X POST $AUTH -H "Content-Type: application/json" \
        "$API_BASE/workflow_job_templates/$WF_ID/workflow_nodes/" \
        -d '{"unified_job_template":15}' 2>/dev/null | \
        python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
    echo "  ✓ Node 1 (Deploy): $NODE1"
    
    if [ -n "$NODE1" ]; then
        NODE2=$(curl -s -X POST $AUTH -H "Content-Type: application/json" \
            "$API_BASE/workflow_job_template_nodes/$NODE1/success_nodes/" \
            -d '{"unified_job_template":12}' 2>/dev/null | \
            python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
        echo "  ✓ Node 2 (Collect): $NODE2"
    fi
else
    echo "  ✓ Workflow exists (ID=$WF_ID)"
    
    # Remove Snapshot node if it still exists
    echo "  Checking for stale Snapshot node..."
    curl -s $AUTH "$API_BASE/workflow_job_templates/$WF_ID/workflow_nodes/" 2>/dev/null | python3 -c "
import sys, json, requests
for n in json.load(sys.stdin)['results']:
    name = n.get('summary_fields',{}).get('unified_job_template',{}).get('name','')
    if 'Snapshot' in name or 'snapshot' in name:
        resp = requests.delete(
            f'http://localhost:8080/api/v2/workflow_job_template_nodes/{n[\"id\"]}/',
            auth=('admin', '$TOWER_PASSWORD'))
        print(f'  ✓ Removed Snapshot node (ID={n[\"id\"]})')
" 2>/dev/null
fi

echo ""
echo "[5c] Adding survey..."
curl -s -X POST $AUTH -H "Content-Type: application/json" \
    "$API_BASE/workflow_job_templates/$WF_ID/survey_spec/" \
    -d '{
        "name":"Experiment Parameters",
        "description":"Configure your experiment",
        "spec":[
            {"question_name":"Student ID","required":true,"type":"text","variable":"student_id","min":1,"max":50,"default":""},
            {"question_name":"Student Name","required":true,"type":"text","variable":"student_name","min":1,"max":100,"default":""},
            {"question_name":"Attack Target","required":true,"type":"multiplechoice","variable":"attack_target","choices":["clients","infrastructure","all"],"default":"clients"}
        ]
    }' > /dev/null 2>&1
curl -s -X PATCH $AUTH -H "Content-Type: application/json" \
    "$API_BASE/workflow_job_templates/$WF_ID/" \
    -d '{"survey_enabled":true}' > /dev/null 2>&1
echo "  ✓ Survey configured"

echo ""
echo "[5d] Assigning RBAC permissions..."
# Get role IDs
EXEC_ROLE=$(curl -s $AUTH "$API_BASE/workflow_job_templates/$WF_ID/object_roles/" 2>/dev/null | \
    python3 -c "import sys,json; [print(r['id']) for r in json.load(sys.stdin)['results'] if 'execute' in r['name'].lower()]" 2>/dev/null | head -1)

INV_ID=$(curl -s $AUTH "$API_BASE/inventories/?name=ENTRAP+Network" 2>/dev/null | \
    python3 -c "import sys,json; r=json.load(sys.stdin)['results']; print(r[0]['id'] if r else '')" 2>/dev/null)
INV_READ_ROLE=""
if [ -n "$INV_ID" ]; then
    INV_READ_ROLE=$(curl -s $AUTH "$API_BASE/inventories/$INV_ID/object_roles/" 2>/dev/null | \
        python3 -c "import sys,json; [print(r['id']) for r in json.load(sys.stdin)['results'] if 'read' in r['name'].lower()]" 2>/dev/null | head -1)
fi

for UNAME in student1 student2; do
    UID_VAL=$(curl -s $AUTH "$API_BASE/users/?username=$UNAME" 2>/dev/null | \
        python3 -c "import sys,json; r=json.load(sys.stdin)['results']; print(r[0]['id'] if r else '')" 2>/dev/null)
    if [ -n "$UID_VAL" ] && [ -n "$EXEC_ROLE" ]; then
        curl -s -X POST $AUTH -H "Content-Type: application/json" \
            "$API_BASE/roles/$EXEC_ROLE/users/" -d "{\"id\":$UID_VAL}" > /dev/null 2>&1
        echo "  ✓ $UNAME → workflow execute role"
    fi
    if [ -n "$UID_VAL" ] && [ -n "$INV_READ_ROLE" ]; then
        curl -s -X POST $AUTH -H "Content-Type: application/json" \
            "$API_BASE/roles/$INV_READ_ROLE/users/" -d "{\"id\":$UID_VAL}" > /dev/null 2>&1
        echo "  ✓ $UNAME → inventory read role"
    fi
done

echo ""
echo "[5e] Testing student login..."
for UNAME in student1 student2; do
    COUNT=$(curl -s -u "$UNAME:Student@123" "$API_BASE/workflow_job_templates/" 2>/dev/null | \
        python3 -c "import sys,json; print(json.load(sys.stdin)['count'])" 2>/dev/null)
    echo "  $UNAME sees $COUNT workflow(s)"
done

pause_stage "STAGE 5 (Users & RBAC)"


# ============================================================
# FINAL SUMMARY
# ============================================================
echo ""
echo "╔════════════════════════════════════════════════╗"
echo "║  ✅  SETUP COMPLETE                            ║"
echo "╠════════════════════════════════════════════════╣"
echo "║                                                ║"
echo "║  On your LAPTOP browser:                       ║"
echo "║                                                ║"
echo "║  Tab 1 (Chrome):                               ║"
echo "║    http://localhost:9090                        ║"
echo "║    admin / $TOWER_PASSWORD"
echo "║                                                ║"
echo "║  Tab 2 (Incognito or Firefox):                 ║"
echo "║    http://localhost:9090                        ║"
echo "║    student1 / Student@123                      ║"
echo "║                                                ║"
echo "║  Tab 3 (Edge or another browser):              ║"
echo "║    http://localhost:9090                        ║"
echo "║    student2 / Student@123                      ║"
echo "║                                                ║"
echo "║  As student:                                   ║"
echo "║    Templates → Experiment: Ransomware Campaign ║"
echo "║    Click 🚀 → Fill survey → Watch it run       ║"
echo "║                                                ║"
echo "║  As admin:                                     ║"
echo "║    Jobs → See ALL student jobs                 ║"
echo "║    Click any job → Full Ansible output         ║"
echo "║    'Launched By' shows which student            ║"
echo "║                                                ║"
echo "╚════════════════════════════════════════════════╝"
echo ""
echo "  To run the live admin monitor in another terminal:"
echo "    watch -n5 'curl -s -u admin:$TOWER_PASSWORD http://localhost:8080/api/v2/unified_jobs/?order_by=-created\&page_size=10 | python3 -m json.tool | grep -E \"name|status|username\"'"
echo ""
