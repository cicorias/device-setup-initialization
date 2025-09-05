#!/bin/bash
# 99-cleanup.sh
# Comprehensive cleanup script for device setup initialization
# Handles package removal, mount cleanup, loop device cleanup, and artifact cleanup

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ARTIFACTS_DIR="$PROJECT_DIR/artifacts"

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Clean up mounted filesystems
cleanup_mounts() {
    log "Cleaning up mounted filesystems..."
    
    # Find all mounts in artifacts directory
    local artifacts_mounts
    artifacts_mounts=$(mount | grep "$ARTIFACTS_DIR" | awk '{print $3}' | sort -r || true)
    
    if [[ -n "$artifacts_mounts" ]]; then
        warn "Found mounted filesystems in artifacts directory"
        while IFS= read -r mount_point; do
            if [[ -n "$mount_point" ]]; then
                info "Unmounting: $mount_point"
                if umount -l "$mount_point" 2>/dev/null; then
                    log "Successfully unmounted: $mount_point"
                else
                    warn "Failed to unmount: $mount_point, trying lazy unmount"
                    umount -l "$mount_point" 2>/dev/null || warn "Lazy unmount also failed for: $mount_point"
                fi
            fi
        done <<< "$artifacts_mounts"
    else
        log "No mounted filesystems found in artifacts directory"
    fi
    
    # Cleanup specific mount points that might be stuck
    local special_mounts=(
        "$ARTIFACTS_DIR/build-env/rootfs/dev/pts"
        "$ARTIFACTS_DIR/build-env/rootfs/dev/shm"
        "$ARTIFACTS_DIR/build-env/rootfs/dev/mqueue"
        "$ARTIFACTS_DIR/build-env/rootfs/dev/hugepages"
        "$ARTIFACTS_DIR/build-env/rootfs/proc"
        "$ARTIFACTS_DIR/build-env/rootfs/sys"
        "$ARTIFACTS_DIR/build-env/rootfs/dev"
    )
    
    for mount_point in "${special_mounts[@]}"; do
        if mountpoint -q "$mount_point" 2>/dev/null; then
            info "Unmounting special filesystem: $mount_point"
            umount -l "$mount_point" 2>/dev/null || warn "Failed to unmount: $mount_point"
        fi
    done
}

# Clean up loop devices
cleanup_loop_devices() {
    log "Cleaning up loop devices..."
    
    # Find loop devices associated with artifacts directory
    local loop_devices
    loop_devices=$(losetup -l | grep "$ARTIFACTS_DIR" | awk '{print $1}' || true)
    
    if [[ -n "$loop_devices" ]]; then
        warn "Found loop devices associated with artifacts directory"
        while IFS= read -r loop_device; do
            if [[ -n "$loop_device" ]]; then
                info "Detaching loop device: $loop_device"
                if losetup -d "$loop_device" 2>/dev/null; then
                    log "Successfully detached: $loop_device"
                else
                    warn "Failed to detach: $loop_device"
                fi
            fi
        done <<< "$loop_devices"
    else
        log "No loop devices found associated with artifacts directory"
    fi
    
    # Clean up any orphaned loop devices
    local orphaned_loops
    orphaned_loops=$(losetup -l | grep -E '^\s*/dev/loop[0-9]+\s+\s' | awk '{print $1}' || true)
    
    if [[ -n "$orphaned_loops" ]]; then
        warn "Found orphaned loop devices"
        while IFS= read -r loop_device; do
            if [[ -n "$loop_device" ]]; then
                info "Detaching orphaned loop device: $loop_device"
                losetup -d "$loop_device" 2>/dev/null || warn "Failed to detach orphaned loop: $loop_device"
            fi
        done <<< "$orphaned_loops"
    fi
}

# Force cleanup of busy directories
force_cleanup_directories() {
    log "Force cleaning up busy directories..."
    
    # Kill any processes using files in artifacts directory
    local artifacts_pids
    artifacts_pids=$(lsof +D "$ARTIFACTS_DIR" 2>/dev/null | awk 'NR>1 {print $2}' | sort -u || true)
    
    if [[ -n "$artifacts_pids" ]]; then
        warn "Found processes using files in artifacts directory"
        while IFS= read -r pid; do
            if [[ -n "$pid" ]] && [[ "$pid" =~ ^[0-9]+$ ]]; then
                info "Killing process: $pid"
                kill -TERM "$pid" 2>/dev/null || true
                sleep 1
                kill -KILL "$pid" 2>/dev/null || true
            fi
        done <<< "$artifacts_pids"
        
        # Wait a bit for processes to die
        sleep 2
    fi
    
    # Try to remove the directory tree
    if [[ -d "$ARTIFACTS_DIR" ]]; then
        info "Attempting to remove artifacts directory"
        if rm -rf "$ARTIFACTS_DIR" 2>/dev/null; then
            log "Successfully removed artifacts directory"
        else
            warn "Failed to remove artifacts directory, trying alternative methods"
            
            # Try to unmount and remove each subdirectory
            find "$ARTIFACTS_DIR" -type d -exec umount {} \; 2>/dev/null || true
            
            # Remove files first, then directories
            find "$ARTIFACTS_DIR" -type f -delete 2>/dev/null || true
            find "$ARTIFACTS_DIR" -type d -empty -delete 2>/dev/null || true
            
            # If still exists, try one more time
            if [[ -d "$ARTIFACTS_DIR" ]]; then
                rm -rf "$ARTIFACTS_DIR" 2>/dev/null || warn "Some files in artifacts directory could not be removed"
            fi
        fi
    else
        log "Artifacts directory does not exist"
    fi
}

# Remove conflicting BIOS boot packages
remove_conflicting_packages() {
    log "Removing conflicting BIOS boot packages..."
    
    local packages_to_remove=(
        # BIOS GRUB packages that conflict with UEFI
        "grub-pc"
        "grub-pc-bin"
        
        # Legacy boot components
        "lilo"
        "extlinux"
        
        # Old initramfs tools that might conflict
        "initramfs-tools-core"
    )
    
    local installed_packages=()
    
    # Check which packages are actually installed
    for package in "${packages_to_remove[@]}"; do
        if dpkg -l | grep -q "^ii.*$package "; then
            installed_packages+=("$package")
            info "Found installed package: $package"
        fi
    done
    
    if [[ ${#installed_packages[@]} -eq 0 ]]; then
        log "No conflicting packages found to remove"
        return 0
    fi
    
    # Remove packages
    warn "Removing ${#installed_packages[@]} conflicting packages: ${installed_packages[*]}"
    
    # Use --purge to completely remove configuration files
    if apt-get remove --purge -y "${installed_packages[@]}"; then
        log "Conflicting packages removed successfully"
    else
        error "Failed to remove conflicting packages"
    fi
}

# Fix broken packages
fix_broken_packages() {
    log "Fixing broken package dependencies..."
    
    # Fix broken dependencies
    apt-get install -f -y || warn "Some package dependencies could not be fixed"
    
    # Clean package cache
    apt-get autoremove -y || warn "Autoremove failed"
    apt-get autoclean || warn "Autoclean failed"
    
    log "Package dependencies cleanup completed"
}

# Clean package cache and temporary files
cleanup_package_cache() {
    log "Cleaning package cache and temporary files..."
    
    # Clean apt cache
    apt-get clean || warn "Failed to clean apt cache"
    apt-get autoremove -y || warn "Failed to autoremove packages"
    
    # Clean systemd journal if it's getting large
    if command -v journalctl &> /dev/null; then
        journalctl --vacuum-time=1d || warn "Failed to vacuum journal"
    fi
    
    # Clean temporary files in chroot areas
    rm -rf /tmp/chroot-* 2>/dev/null || true
    rm -rf /var/tmp/chroot-* 2>/dev/null || true
    
    log "Package cache cleanup completed"
}

# Clean up build environment
cleanup_build_environment() {
    log "Cleaning up build environment..."
    
    # Remove any remaining build directories
    local build_dirs=(
        "/tmp/device-init-build"
        "/tmp/rootfs-*"
        "/var/tmp/device-init-*"
    )
    
    for dir in "${build_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            info "Removing build directory: $dir"
            rm -rf "$dir" 2>/dev/null || warn "Failed to remove: $dir"
        fi
    done
    
    # Clean up any remaining mount points from failed builds
    local temp_mounts
    temp_mounts=$(mount | grep -E "(chroot|rootfs|device-init)" | awk '{print $3}' || true)
    
    if [[ -n "$temp_mounts" ]]; then
        while IFS= read -r mount_point; do
            if [[ -n "$mount_point" ]]; then
                info "Unmounting temporary mount: $mount_point"
                umount -l "$mount_point" 2>/dev/null || warn "Failed to unmount: $mount_point"
            fi
        done <<< "$temp_mounts"
    fi
}

# Main cleanup function
main() {
    log "Starting comprehensive cleanup process..."
    
    # Cleanup in order of dependencies
    cleanup_mounts
    cleanup_loop_devices
    force_cleanup_directories
    cleanup_build_environment
    
    # Package cleanup
    if command -v apt-get &> /dev/null; then
        log "Updating package lists..."
        apt-get update || warn "Failed to update package lists"
        
        remove_conflicting_packages
        fix_broken_packages
        cleanup_package_cache
    else
        info "Skipping package cleanup (apt-get not available)"
    fi
    
    log "Comprehensive cleanup completed successfully"
    log "System is ready for a fresh build"
}

# Handle command line arguments
case "${1:-}" in
    --mounts-only)
        check_root
        cleanup_mounts
        ;;
    --loops-only)
        check_root
        cleanup_loop_devices
        ;;
    --packages-only)
        check_root
        remove_conflicting_packages
        fix_broken_packages
        cleanup_package_cache
        ;;
    --force-artifacts)
        check_root
        force_cleanup_directories
        ;;
    --help|-h)
        echo "Usage: $0 [--mounts-only|--loops-only|--packages-only|--force-artifacts|--help]"
        echo "  --mounts-only      Clean up mounted filesystems only"
        echo "  --loops-only       Clean up loop devices only"
        echo "  --packages-only    Clean up packages only"
        echo "  --force-artifacts  Force cleanup of artifacts directory only"
        echo "  --help            Show this help message"
        echo "  (no args)         Run full cleanup"
        exit 0
        ;;
    "")
        check_root
        main
        ;;
    *)
        error "Unknown argument: $1. Use --help for usage information."
        ;;
esac
