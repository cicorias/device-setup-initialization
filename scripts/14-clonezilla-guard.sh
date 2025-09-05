#!/bin/bash
# 14-clonezilla-guard.sh - Prepare runtime guard scripts used by Clonezilla prerun
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

GUARD_DIR="$IMAGES_DIR/clonezilla/guard"
ensure_dirs "$GUARD_DIR"

# disk-check.sh ensures target disk large enough (simple size compare placeholder)
cat > "$GUARD_DIR/disk-check.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
TARGET_DISK="${clonezilla_target_disk:-/dev/sda}"  # substituted later if environment exports
# Placeholder: always pass for now; future parse image metadata
if [[ ! -b "$TARGET_DISK" ]]; then
  echo "Guard: target disk not block device: $TARGET_DISK" >&2
  exit 1
fi
echo "Guard: disk-check passed for $TARGET_DISK" >&2
exit 0
EOF
chmod +x "$GUARD_DIR/disk-check.sh"

# echo wrapper if dry-run desired
if [[ -n "$CLONEZILLA_DRY_RUN" ]]; then
  cat > "$GUARD_DIR/echo-ocs-sr" <<'EOF'
#!/bin/bash
echo "[DRYRUN] ocs-sr $*" >&2
EOF
  chmod +x "$GUARD_DIR/echo-ocs-sr"
fi

log "Guard scripts prepared in $GUARD_DIR"
