#!/bin/bash
# 10-clonezilla-fetch.sh - Download & extract Clonezilla Live ISO assets
# Idempotent: reuses existing verified artifacts

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
need_tools curl sha256sum mount umount grep awk stat jq || true

log "Clonezilla fetch start (version=${clonezilla_version})"
ensure_dirs "$CLONEZILLA_ISO_DIR" "$CLONEZILLA_EXTRACT_DIR" "$CLONEZILLA_MANIFESTS_DIR"

ISO_PATH="$CLONEZILLA_ISO_DIR/clonezilla-live-${clonezilla_version}-amd64.iso"
MANIFEST_JSON="$CLONEZILLA_EXTRACT_DIR/manifest.json"

# Step 1: Download ISO if missing
if [[ -f "$ISO_PATH" ]]; then
  info "ISO already present: $(basename "$ISO_PATH")"
else
  log "Downloading ISO: $clonezilla_iso_url"
  curl_fetch "$clonezilla_iso_url" "$ISO_PATH"
fi

# Step 2: Verify checksum (if expected provided) or compute
ISO_SHA_COMPUTED=$(checksum_sha256 "$ISO_PATH")
if [[ -n "$clonezilla_iso_sha256" ]]; then
  if verify_sha256 "$ISO_PATH" "$clonezilla_iso_sha256"; then
    info "ISO checksum verified"
  else
    error "ISO checksum mismatch. expected=$clonezilla_iso_sha256 got=$ISO_SHA_COMPUTED"
  fi
else
  log "No expected checksum provided; recording computed value"
  clonezilla_iso_sha256="$ISO_SHA_COMPUTED"
fi

# Step 3: Extract required files (vmlinuz, initrd.img, filesystem.squashfs)
EXTRACTED_KERNEL="$CLONEZILLA_EXTRACT_DIR/vmlinuz"
EXTRACTED_INITRD="$CLONEZILLA_EXTRACT_DIR/initrd.img"
EXTRACTED_SQUASHFS="$CLONEZILLA_EXTRACT_DIR/filesystem.squashfs"

if [[ -f "$EXTRACTED_KERNEL" && -f "$EXTRACTED_INITRD" && -f "$EXTRACTED_SQUASHFS" ]]; then
  info "Clonezilla assets already extracted"
else
  TMP_MNT=$(mktemp -d)
  trap 'cleanup_mount "$TMP_MNT"; rmdir "$TMP_MNT" 2>/dev/null || true' EXIT
  log "Mounting ISO for extraction"
  tmp_mount_iso "$ISO_PATH" "$TMP_MNT"
  cp "$TMP_MNT/live/vmlinuz" "$EXTRACTED_KERNEL"
  cp "$TMP_MNT/live/initrd.img" "$EXTRACTED_INITRD"
  cp "$TMP_MNT/live/filesystem.squashfs" "$EXTRACTED_SQUASHFS"
  sync
  cleanup_mount "$TMP_MNT"
  rmdir "$TMP_MNT" || true
  trap - EXIT
  log "Extraction complete"
fi

# Step 4: Generate sha256sums.txt
SHA_FILE="$CLONEZILLA_EXTRACT_DIR/sha256sums.txt"
if [[ ! -f "$SHA_FILE" ]]; then
  (cd "$CLONEZILLA_EXTRACT_DIR" && sha256sum vmlinuz initrd.img filesystem.squashfs > sha256sums.txt)
  info "sha256sums.txt generated"
fi

# Step 5: Manifest JSON
if [[ ! -f "$MANIFEST_JSON" ]]; then
  SIZE_KERNEL=$(stat -c%s "$EXTRACTED_KERNEL")
  SIZE_INITRD=$(stat -c%s "$EXTRACTED_INITRD")
  SIZE_SQUASH=$(stat -c%s "$EXTRACTED_SQUASHFS")
  NOW=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  cat > "$MANIFEST_JSON" <<EOF
{
  "version": "${clonezilla_version}",
  "timestamp": "$NOW",
  "iso": {
    "path": "${ISO_PATH}",
    "sha256": "${clonezilla_iso_sha256}",
    "size_bytes": $(stat -c%s "$ISO_PATH")
  },
  "files": [
    {"name":"vmlinuz","size":$SIZE_KERNEL,"sha256":"$(checksum_sha256 "$EXTRACTED_KERNEL")"},
    {"name":"initrd.img","size":$SIZE_INITRD,"sha256":"$(checksum_sha256 "$EXTRACTED_INITRD")"},
    {"name":"filesystem.squashfs","size":$SIZE_SQUASH,"sha256":"$(checksum_sha256 "$EXTRACTED_SQUASHFS")"}
  ]
}
EOF
  info "Manifest created: $MANIFEST_JSON"
fi

# Step 6: Copy aggregate manifest reference
cp "$MANIFEST_JSON" "$CLONEZILLA_MANIFESTS_DIR/manifest-${clonezilla_version}.json"

log "Clonezilla fetch completed successfully"
