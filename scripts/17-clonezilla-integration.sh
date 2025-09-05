#!/bin/bash
# 17-clonezilla-integration.sh - Assemble Clonezilla integration artifacts (docs + copy commands)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

OUT_DIR="$INTEGRATION_DIR/clonezilla"
ensure_dirs "$OUT_DIR"

# Copy existing docs
DOC_SRC1="$PROJECT_ROOT/docs/clonezilla-deployment.md"
DOC_SRC2="$PROJECT_ROOT/docs/clonezilla-pxe-server-quickstart.md"
[[ -f $DOC_SRC1 ]] && cp "$DOC_SRC1" "$OUT_DIR/" || warn "Missing deployment doc"
[[ -f $DOC_SRC2 ]] && cp "$DOC_SRC2" "$OUT_DIR/" || warn "Missing quickstart doc"

# Generate copy-commands.sh (manual integration helper)
cat > "$OUT_DIR/copy-commands.sh" <<'EOF'
#!/bin/bash
# Copy Clonezilla assets to PXE server directories
# Adjust DEST_* paths to match pxe-server-setup repository layout
set -euo pipefail

: "${PXE_DEST:=/srv/tftp/grub/clonezilla}"    # Kernel/initrd (TFTP/HTTP served)
: "${HTTP_DEST:=/var/www/html/images/clonezilla}" # SquashFS for HTTP
: "${GRUB_DEST:=/srv/tftp/grub}"                # Location of main grub.cfg

if [[ -z "${VERSION:-}" ]]; then
  echo "Set VERSION to clonezilla version (e.g., 2025.01.01)" >&2
  exit 1
fi

SRC_ARTifacts="${ARTIFACTS:-./artifacts}" # override when sourcing

set -x
mkdir -p "$PXE_DEST/$VERSION" "$HTTP_DEST/$VERSION"
cp "$SRC_ARTifacts/pxe-files/clonezilla/$VERSION/vmlinuz" "$PXE_DEST/$VERSION/"
cp "$SRC_ARTifacts/pxe-files/clonezilla/$VERSION/initrd.img" "$PXE_DEST/$VERSION/"
if [[ -f "$SRC_ARTifacts/images/clonezilla/$VERSION/filesystem.squashfs" ]]; then
  cp "$SRC_ARTifacts/images/clonezilla/$VERSION/filesystem.squashfs" "$HTTP_DEST/$VERSION/"
fi
cp "$SRC_ARTifacts/pxe-integration/grub-entries-clonezilla.cfg" "$GRUB_DEST/"
set +x

echo "Done. Include grub-entries-clonezilla.cfg from your main grub.cfg if not already." >&2
EOF
chmod +x "$OUT_DIR/copy-commands.sh"

# Manifest
cat > "$OUT_DIR/manifest.txt" <<EOF
Clonezilla Integration Artifacts
Version: ${clonezilla_version}
Generated: $(date -u +'%Y-%m-%dT%H:%M:%SZ')
Files:
  - $(basename "$DOC_SRC1")
  - $(basename "$DOC_SRC2")
  - copy-commands.sh
EOF

log "Clonezilla integration artifacts assembled at $OUT_DIR"
