#!/bin/bash
# 13-clonezilla-generate-grub.sh - Generate GRUB menu entries for Clonezilla
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

OUTPUT="$INTEGRATION_DIR/grub-entries-clonezilla.cfg"
ensure_dirs "$INTEGRATION_DIR"

# Determine root path references (assuming later copy to PXE server keeps relative tree)
KPATH="/grub/clonezilla/${clonezilla_version}/vmlinuz"
IPATH="/grub/clonezilla/${clonezilla_version}/initrd.img"

case "$clonezilla_transport" in
  http) FETCH_ARG="fetch=${clonezilla_http_base}/clonezilla/${clonezilla_version}/filesystem.squashfs" ;;
  nfs) FETCH_ARG="boot=live netboot=nfs nfsroot=${clonezilla_server_host}:${clonezilla_nfs_export}" ;;
  tftp) FETCH_ARG="fetch=tftp://${clonezilla_server_host}/clonezilla/${clonezilla_version}/filesystem.squashfs" ;;
  *) error "Unknown transport $clonezilla_transport" ;;
endcase

COMMON_ARGS="boot=live ip=dhcp net.ifnames=0 noswap nomodeset nodmraid ${FETCH_ARG} ocs_live_run=\"ocs-live-general\""

{
  echo "# Generated Clonezilla GRUB entries ($(date -u))"
  echo "# Transport: $clonezilla_transport"
  echo "menuentry 'Clonezilla Live (Manual)' {"
  echo "    linuxefi $KPATH $COMMON_ARGS ocs_live_batch=no quiet"
  echo "    initrdefi $IPATH"
  echo "}"
} > "$OUTPUT"

if [[ "$clonezilla_confirm" == "YES" && "$clonezilla_mode" == "auto_full" ]]; then
  echo "menuentry 'Clonezilla Auto Full Restore' {" >> "$OUTPUT"
  REST_CMD="ocs-sr -e1 -e2 -r -j2 -p poweroff restore-disk ${clonezilla_image_default} ${clonezilla_target_disk}"
  [[ -n "$CLONEZILLA_DRY_RUN" ]] && REST_CMD="echo DRYRUN: $REST_CMD"
  echo "    linuxefi $KPATH $COMMON_ARGS ocs_live_batch=yes ocs_prerun=\"/clonezilla/guard/disk-check.sh\" ocs_live_extra_param=\"$REST_CMD\" quiet" >> "$OUTPUT"
  echo "    initrdefi $IPATH" >> "$OUTPUT"
  echo "}" >> "$OUTPUT"
fi

log "GRUB entries generated: $OUTPUT"
