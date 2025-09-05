#!/bin/bash
# 12-clonezilla-sync-artifacts.sh - Prepare transport-specific Clonezilla assets
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
need_tools sha256sum rsync || true

log "Syncing Clonezilla artifacts for transport=$clonezilla_transport"
ensure_dirs "$PXE_FILES_DIR/clonezilla/${clonezilla_version}" "$IMAGES_DIR/clonezilla/${clonezilla_version}" "$IMAGES_DIR/clonezilla/images"

KERNEL_SRC="$CLONEZILLA_EXTRACT_DIR/vmlinuz"
INITRD_SRC="$CLONEZILLA_EXTRACT_DIR/initrd.img"
SQUASH_SRC="$CLONEZILLA_EXTRACT_DIR/filesystem.squashfs"
[[ -f $KERNEL_SRC && -f $INITRD_SRC && -f $SQUASH_SRC ]] || error "Missing extracted Clonezilla files. Run 10-clonezilla-fetch.sh first"

# Always copy kernel/initrd to PXE files (served via TFTP or HTTP depending on deployment)
DEST_PXE="$PXE_FILES_DIR/clonezilla/${clonezilla_version}"
cp "$KERNEL_SRC" "$DEST_PXE/vmlinuz"; cp "$INITRD_SRC" "$DEST_PXE/initrd.img"

case "$clonezilla_transport" in
  http)
    HTTP_DEST="$IMAGES_DIR/clonezilla/${clonezilla_version}"
    cp "$SQUASH_SRC" "$HTTP_DEST/filesystem.squashfs"
    ;;
  nfs)
    # Keep images locally; operator must export $IMAGES_DIR via NFS mapping to clonezilla_nfs_export
    info "NFS mode: ensure server exports $IMAGES_DIR/clonezilla as $clonezilla_nfs_export"
    rsync -a "$CLONEZILLA_IMAGES_DIR/" "$IMAGES_DIR/clonezilla/images/" 2>/dev/null || true
    ;;
  tftp)
    warn "TFTP transport selected: performance will be poor for large squashfs"
    cp "$SQUASH_SRC" "$DEST_PXE/filesystem.squashfs"
    ;;
  *) error "Unknown transport: $clonezilla_transport" ;;
esac

# Aggregate manifest
MAN_OUT="$CLONEZILLA_MANIFESTS_DIR/transport-${clonezilla_version}.json"
cat > "$MAN_OUT" <<EOF
{
  "version":"${clonezilla_version}",
  "transport":"${clonezilla_transport}",
  "timestamp":"$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "files":{
    "kernel":"$DEST_PXE/vmlinuz",
    "initrd":"$DEST_PXE/initrd.img"
  }
}
EOF

aggregate_sha256 "$CLONEZILLA_MANIFESTS_DIR/hashes-${clonezilla_version}.sha256" \
  "$DEST_PXE/vmlinuz" "$DEST_PXE/initrd.img" "$SQUASH_SRC" || true

log "Clonezilla artifact sync complete"
