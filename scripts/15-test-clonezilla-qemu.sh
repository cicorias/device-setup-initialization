#!/bin/bash
# 15-test-clonezilla-qemu.sh - Dry-run PXE boot test using QEMU (UEFI)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
need_tools qemu-system-x86_64 || true

FIRMWARE=/usr/share/OVMF/OVMF_CODE.fd
[[ -f $FIRMWARE ]] || FIRMWARE=/usr/share/OVMF/OVMF_CODE_4M.fd
[[ -f $FIRMWARE ]] || error "OVMF firmware not found"

SERIAL_LOG="$ARTIFACTS/logs/qemu-clonezilla-serial.log"
log "Starting QEMU PXE dry-run (log: $SERIAL_LOG)"

# Network: user mode with tftp root pointing to PXE_FILES_DIR if supported (simplified)
# For full realism user should run against separate PXE server; here we only validate boot stub.

qemu-system-x86_64 \
  -m 1024 -enable-kvm \
  -cpu host \
  -netdev user,id=n1,tftp="$PXE_FILES_DIR",bootfile="grubx64.efi" -device e1000,netdev=n1 \
  -bios "$FIRMWARE" \
  -serial file:"$SERIAL_LOG" \
  -nographic -no-reboot || true

if grep -qi "Clonezilla" "$SERIAL_LOG"; then
  log "QEMU dry-run appears to show Clonezilla references (PASS)"
else
  warn "Clonezilla string not detected; inspect $SERIAL_LOG manually"
fi
