#!/bin/bash
# common.sh - Shared functions for build & Clonezilla integration
# Sourced by scripts. Do NOT execute directly.

set -o pipefail

# Colors (only if terminal)
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi

_ts() { date +'%Y-%m-%d %H:%M:%S'; }
_log_core() { local lvl="$1" msg="$2"; echo -e "${GREEN}[$(_ts)][$(basename "$0")]${NC} ${lvl}: $msg" >&2; }
log() { _log_core INFO "$1"; }
info() { _log_core INFO "$1"; }
warn() { echo -e "${YELLOW}[$(_ts)][$(basename "$0")] WARNING: $1${NC}" >&2; }
error() { echo -e "${RED}[$(_ts)][$(basename "$0")] ERROR: $1${NC}" >&2; exit 1; }
debug() { [[ "${DEBUG:-false}" == "true" ]] && echo -e "${BLUE}[$(_ts)] DEBUG: $1${NC}" >&2; }

require_root() { [[ $EUID -ne 0 ]] && error "Must run as root"; }
ensure_dirs() { for d in "$@"; do mkdir -p "$d" || error "Failed mkdir $d"; done; }

checksum_sha256() { sha256sum "$1" | awk '{print $1}'; }
verify_sha256() { local file="$1" expect="$2"; local got=$(checksum_sha256 "$file"); [[ "$got" == "$expect" ]]; }

curl_fetch() { local url="$1" out="$2"; curl -L --fail --retry 3 --continue-at - -o "$out" "$url" || error "Download failed: $url"; }

json_manifest() { # usage: json_manifest file key value (appends)
  local file="$1"; shift
  printf '%s\n' "$*" >> "$file";
}

tmp_mount_iso() { local iso="$1" mnt="$2"; ensure_dirs "$mnt"; sudo mount -o loop,ro "$iso" "$mnt" || error "Mount ISO failed"; }
cleanup_mount() { local m="$1"; mountpoint -q "$m" && sudo umount "$m" || true; }

write_json() { local path="$1"; shift; printf '%s\n' "$*" > "$path"; }

# Safe sed inline (GNU) - backup suppressed
sedi() { sed -i "$@"; }

# Guard: confirm destructive
require_confirm() { [[ "${clonezilla_confirm}" != "YES" ]] && error "clonezilla_confirm not YES - aborting destructive op"; }

# Disk size (bytes)
disk_size_bytes() { blockdev --getsize64 "$1" 2>/dev/null || echo 0; }

# Logging wrappers for commands
run() { debug "RUN: $*"; "$@"; }
run_quiet() { debug "RUNQ: $*"; "$@" >/dev/null 2>&1; }

# Simple table formatter (name size checksum)
file_entry() { local f="$1"; [[ -f $f ]] || return 0; local s=$(stat -c%s "$f"); local h=$(checksum_sha256 "$f"); echo "{\"file\":\"$f\",\"size\":$s,\"sha256\":\"$h\"}"; }

# Aggregate sha256 for list of files
aggregate_sha256() { local out="$1"; shift; : > "$out"; for f in "$@"; do [[ -f $f ]] && sha256sum "$f" >> "$out"; done; }

# Detect tool availability
need_tools() { local miss=(); for t in "$@"; do command -v "$t" >/dev/null 2>&1 || miss+=("$t"); done; [[ ${#miss[@]} -gt 0 ]] && error "Missing tools: ${miss[*]}"; }

# Load project config if not already
if [[ -z "${PROJECT_ROOT:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || true
  PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
fi

CONFIG_SH="${PROJECT_ROOT}/config.sh"
[[ -f "$CONFIG_SH" ]] && source "$CONFIG_SH" || warn "config.sh not found at $CONFIG_SH"

export -f log info warn error debug require_root ensure_dirs checksum_sha256 verify_sha256 curl_fetch tmp_mount_iso cleanup_mount write_json run run_quiet file_entry aggregate_sha256 need_tools require_confirm disk_size_bytes
