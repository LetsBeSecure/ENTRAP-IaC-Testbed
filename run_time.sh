#!/usr/bin/env bash
# run_timed.sh
set -uo pipefail  # removed -e so one failure doesn't kill whole run

ASK_PASS=""
[[ "${1:-}" == "-K" ]] && ASK_PASS="--ask-become-pass"

INV="inventory/hosts.ini"
PB="playbooks"
LOG="timing_results.txt"
DETAIL_LOG="timing_detail.txt"

> "$LOG"
> "$DETAIL_LOG"

run_pb() {
    local pb="$1"
    local start end elapsed
    start=$(date +%s.%N)
    ansible-playbook "$PB/$pb" -i "$INV" $ASK_PASS
    local rc=$?
    end=$(date +%s.%N)
    elapsed=$(echo "$end - $start" | bc)
    printf "%-50s %8.1f s  (rc=%d)\n" "$pb" "$elapsed" "$rc" | tee -a "$DETAIL_LOG"
    echo "$elapsed"
}

# Follow site.yml order exactly
net_t=$(run_pb 00_create_networks.yml)

gw_t=$(run_pb create_gateway_vm.yml)
gw_cfg_t=$(run_pb configure_gateway.yml)

cs_t=$(run_pb create_coreswitch_vm.yml)
cs_cfg_t=$(run_pb configure_coreswitch.yml)

infra_t=$(run_pb create_infra_vms.yml)
dns_t=$(run_pb configure_dns.yml)
dhcp_t=$(run_pb configure_dhcp.yml)
bkp_t=$(run_pb configure_backup.yml)
web_t=$(run_pb configure_web.yml)

cli_t=$(run_pb create_client_vms.yml)
cli_cfg_t=$(run_pb configure_clients.yml)

c2_t=$(run_pb create_c2_vm.yml)
c2_cfg_t=$(run_pb configure_c2.yml)

log_t=$(run_pb configure_logging.yml)

# Sum into paper phases
vm_phase=$(echo "$gw_t + $cs_t + $infra_t + $cli_t + $c2_t" | bc)
svc_phase=$(echo "$gw_cfg_t + $cs_cfg_t + $dns_t + $dhcp_t + $bkp_t + $web_t + $cli_cfg_t + $c2_cfg_t + $log_t" | bc)
net_phase=$net_t

echo ""
echo "====== PAPER TABLE VALUES ======"
printf "%-55s %8.1f s\n" "VM image provisioning (Cloud-init, 7 entities)" "$vm_phase" | tee -a "$LOG"
printf "%-55s %8.1f s\n" "Service configuration (Ansible playbooks)" "$svc_phase" | tee -a "$LOG"
printf "%-55s %8.1f s\n" "Network configuration (libvirt, nftables, iptables)" "$net_phase" | tee -a "$LOG"
total=$(echo "$vm_phase + $svc_phase + $net_phase" | bc)
printf "%-55s %8.1f s\n" "TOTAL" "$total" | tee -a "$LOG"
