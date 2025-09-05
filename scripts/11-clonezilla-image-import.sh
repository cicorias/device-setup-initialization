#!/bin/bash
# 11-clonezilla-image-import.sh - Manage Clonezilla image sets (add/list/verify)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
need_tools rsync sha256sum awk grep || true

usage() {
  cat <<EOF
Usage: $0 <command> [args]
Commands:
  add <path-to-clonezilla-image-dir>   Import image directory
  list                                 List available images
  verify <image-name>                  Recompute hashes & compare
EOF
}

is_clonezilla_dir() { [[ -f "$1/info" ]] && [[ -d "$1/parts" ]]; }

cmd_add() {
  local src="$1"; [[ -d $src ]] || error "Source directory not found: $src"
  is_clonezilla_dir "$src" || error "Not a Clonezilla image dir (missing info/parts)"
  ensure_dirs "$CLONEZILLA_IMAGES_DIR"
  local name
  name=$(basename "$src")
  local dest="$CLONEZILLA_IMAGES_DIR/$name"
  if [[ -d "$dest" ]]; then
    warn "Image already exists: $name (skipping copy)"
  else
    log "Copying image $name"
    rsync -a "$src/" "$dest/"
  fi
  # Generate SHA256SUMS
  ( cd "$dest" && find . -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS )
  info "Imported image: $name"
}

cmd_list() {
  [[ -d "$CLONEZILLA_IMAGES_DIR" ]] || { warn "No images directory"; return 0; }
  find "$CLONEZILLA_IMAGES_DIR" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort
}

cmd_verify() {
  local name="$1"; local dir="$CLONEZILLA_IMAGES_DIR/$name"
  [[ -d "$dir" ]] || error "Image not found: $name"
  [[ -f "$dir/SHA256SUMS" ]] || error "SHA256SUMS missing for $name"
  pushd "$dir" >/dev/null
  local tmp=$(mktemp)
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > "$tmp"
  if diff -q "$tmp" SHA256SUMS >/dev/null; then
    info "Image $name verification PASSED"
  else
    error "Image $name verification FAILED"
  fi
  rm -f "$tmp"
  popd >/dev/null
}

main() {
  local cmd="${1:-}"; [[ -z "$cmd" ]] && { usage; exit 1; }
  case "$cmd" in
    add) shift; [[ $# -eq 1 ]] || { usage; exit 1; }; cmd_add "$1" ;;
    list) cmd_list ;;
    verify) shift; [[ $# -eq 1 ]] || { usage; exit 1; }; cmd_verify "$1" ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
