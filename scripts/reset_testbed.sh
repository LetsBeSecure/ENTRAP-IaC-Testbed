#!/bin/bash
set -uo pipefail
SNAPSHOT_NAME="clean-state"
log() { echo "[$(date -u +%H:%M:%S)] $*"; }
echo "════════════════════════════════════════════════"
echo " ENTRAP Testbed Reset"
echo "════════════════════════════════════════════════"
if [[ "${1:-}" == "--all" ]]; then
    VMS=(client1 client2 dns1 dhcp1 backup1 web1 coreswitch gateway1 c2server)
else
    VMS=(client1 client2)
fi
log "Resetting ${#VMS[@]} VMs to snapshot: $SNAPSHOT_NAME"
for vm in "${VMS[@]}"; do
    log "  Reverting $vm..."
    sudo virsh snapshot-revert "$vm" "$SNAPSHOT_NAME" 2>/dev/null || {
        sudo virsh destroy "$vm" 2>/dev/null
        sudo virsh snapshot-revert "$vm" "$SNAPSHOT_NAME" 2>/dev/null
    }
    sudo virsh start "$vm" 2>/dev/null || true
done
log "Waiting 45s for VMs to boot..."
sleep 45
for vm in "${VMS[@]}"; do
    echo "  $vm: $(sudo virsh domstate "$vm" 2>/dev/null)"
done
log "Reset complete. Testbed ready for next student."
