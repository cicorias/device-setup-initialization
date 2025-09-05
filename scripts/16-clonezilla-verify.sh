#!/bin/bash
# 16-clonezilla-verify.sh - Integrity and transport verification
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
need_tools sha256sum grep awk || true

PASS=()
FAIL=()
add_pass(){ PASS+=("$1"); }
add_fail(){ FAIL+=("$1"); warn "FAIL: $1"; }

# 1. Check extracted files
for f in vmlinuz initrd.img filesystem.squashfs; do
  if [[ -f "$CLONEZILLA_EXTRACT_DIR/$f" ]]; then add_pass "extract:$f"; else add_fail "extract:$f missing"; fi
done

# 2. Hash consistency
if [[ -f "$CLONEZILLA_EXTRACT_DIR/sha256sums.txt" ]]; then
  pushd "$CLONEZILLA_EXTRACT_DIR" >/dev/null
  if sha256sum -c sha256sums.txt >/dev/null 2>&1; then add_pass hashes; else add_fail hashes; fi
  popd >/dev/null
else add_fail hashes-missing; fi

# 3. GRUB entry contains transport token
GRUB_FILE="$INTEGRATION_DIR/grub-entries-clonezilla.cfg"
if [[ -f "$GRUB_FILE" ]]; then
  case "$clonezilla_transport" in
    http) grep -q "fetch=${clonezilla_http_base}" "$GRUB_FILE" && add_pass grub-transport || add_fail grub-transport ;;
    nfs) grep -q "nfsroot=${clonezilla_server_host}:${clonezilla_nfs_export}" "$GRUB_FILE" && add_pass grub-transport || add_fail grub-transport ;;
    tftp) grep -q "tftp://${clonezilla_server_host}" "$GRUB_FILE" && add_pass grub-transport || add_fail grub-transport ;;
  esac
else add_fail grub-file-missing; fi

# 4. Image presence if auto/full mode
if [[ "$clonezilla_mode" == "auto_full" ]]; then
  [[ -d "$CLONEZILLA_IMAGES_DIR/$clonezilla_image_default" ]] && add_pass image-present || add_fail image-present
fi

# 5. Summary
log "Verification Summary"
echo "PASS: ${PASS[*]}"
echo "FAIL: ${FAIL[*]:-none}"
[[ ${#FAIL[@]} -eq 0 ]] || exit 1
