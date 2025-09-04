#!/bin/bash
# 98-remove-packages.sh
# Remove conflicting packages and cleanup package conflicts
# This script removes BIOS boot packages that conflict with UEFI packages

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
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
fi

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
    apt-get install -f -y
    
    # Clean package cache
    apt-get autoremove -y
    apt-get autoclean
    
    log "Package dependencies fixed"
}

# Clean package cache and temporary files
cleanup_package_cache() {
    log "Cleaning package cache and temporary files..."
    
    # Clean apt cache
    apt-get clean
    apt-get autoremove -y
    
    # Clean systemd journal if it's getting large
    if command -v journalctl &> /dev/null; then
        journalctl --vacuum-time=1d
    fi
    
    # Clean temporary files
    rm -rf /tmp/* 2>/dev/null || true
    rm -rf /var/tmp/* 2>/dev/null || true
    
    log "Package cache cleaned"
}

# Verify UEFI packages are available
verify_uefi_packages() {
    log "Verifying UEFI boot packages are available..."
    
    local uefi_packages=(
        "grub-efi-amd64"
        "grub-efi-amd64-bin"
        "grub-common"
        "grub2-common"
    )
    
    local missing_packages=()
    
    for package in "${uefi_packages[@]}"; do
        if ! apt-cache show "$package" &> /dev/null; then
            missing_packages+=("$package")
        fi
    done
    
    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        error "Missing UEFI packages in repository: ${missing_packages[*]}"
    fi
    
    log "All required UEFI packages are available"
}

# Main execution
main() {
    log "Starting package cleanup process..."
    
    # Update package lists first
    log "Updating package lists..."
    apt-get update
    
    # Remove conflicting packages
    remove_conflicting_packages
    
    # Fix any broken dependencies
    fix_broken_packages
    
    # Verify UEFI packages are available
    verify_uefi_packages
    
    # Clean up
    cleanup_package_cache
    
    log "Package cleanup completed successfully"
    log "You can now run the bootstrap script again"
}

# Run main function
main "$@"
