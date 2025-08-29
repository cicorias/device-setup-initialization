#!/bin/bash
# shellcheck disable=SC2043,SC2043
# Test script for PXE deployment artifacts verification

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACTS_DIR="$SCRIPT_DIR/../artifacts"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}✅ $1${NC}"
}

warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

echo "=== PXE Artifacts Verification Test ==="
echo

# Check if artifacts directory exists
if [ ! -d "$ARTIFACTS_DIR" ]; then
    error "Artifacts directory not found at: $ARTIFACTS_DIR"
    echo "Run create-pxe-system.sh first to generate the artifacts."
    exit 1
fi

log "Artifacts directory found"

# Check deployment script
echo "Checking deployment script..."
if [ -x "$SCRIPT_DIR/deploy-to-pxe-server.sh" ]; then
    log "deploy-to-pxe-server.sh (executable)"
else
    error "deploy-to-pxe-server.sh (missing or not executable)"
fi

# Check PXE integration files
echo "Checking PXE integration files..."
integration_files=("deployment-instructions.md" "manifest.txt" "copy-commands.sh" "grub-entries.cfg")
for file in "${integration_files[@]}"; do
    if [ -f "$ARTIFACTS_DIR/pxe-integration/$file" ]; then
        log "pxe-integration/$file"
    else
        error "pxe-integration/$file (missing)"
    fi
done

# Check IMG files (modern approach)
echo "Checking IMG files..."
img_files=("dual-os-installer.img")
optional_img_files=("ubuntu-minimal.img" "debian-minimal.img")

for file in "${img_files[@]}"; do
    if [ -f "$ARTIFACTS_DIR/images/$file" ]; then
        size=$(du -h "$ARTIFACTS_DIR/images/$file" | cut -f1)
        log "images/$file ($size)"
    else
        error "images/$file (missing)"
    fi
done

for file in "${optional_img_files[@]}"; do
    if [ -f "$ARTIFACTS_DIR/images/$file" ]; then
        size=$(du -h "$ARTIFACTS_DIR/images/$file" | cut -f1)
        log "images/$file ($size)"
    else
        warn "images/$file (optional, missing)"
    fi
done

# Check OS images for HTTP serving
echo "Checking OS images..."
os_images=("ubuntu-os.tar.gz" "debian-os.tar.gz")
for image in "${os_images[@]}"; do
    if [ -f "$ARTIFACTS_DIR/os-images/$image" ]; then
        size=$(du -h "$ARTIFACTS_DIR/os-images/$image" | cut -f1)
        log "os-images/$image ($size)"
    else
        error "os-images/$image (missing)"
    fi
done

# Check legacy PXE files (if present)
echo "Checking legacy PXE files..."
if [ -d "$ARTIFACTS_DIR/pxe-files" ]; then
    warn "Legacy PXE files detected (deprecated but functional)"
    pxe_files=("vmlinuz" "initrd" "filesystem.squashfs" "pxelinux.cfg/default")
    for file in "${pxe_files[@]}"; do
        if [ -f "$ARTIFACTS_DIR/pxe-files/$file" ]; then
            size=$(du -h "$ARTIFACTS_DIR/pxe-files/$file" | cut -f1)
            log "pxe-files/$file ($size) [LEGACY]"
        else
            warn "pxe-files/$file (missing) [LEGACY]"
        fi
    done
else
    info "No legacy PXE files (modern IMG-based approach in use)"
fi

# Check for deprecated server-deployment package
if [ -d "$ARTIFACTS_DIR/server-deployment" ]; then
    warn "Deprecated server-deployment package found"
    warn "This package is no longer maintained"
    warn "Use pxe-server-setup repository + deploy-to-pxe-server.sh instead"
fi

echo
echo "=== Artifacts Summary ==="
total_size=$(du -sh "$ARTIFACTS_DIR" | cut -f1)
echo "Total artifacts size: $total_size"
echo "Artifacts location: $ARTIFACTS_DIR"

# Show next steps
echo
echo "=== Next Steps ==="
echo "1. Set up PXE server infrastructure:"
echo "   git clone https://github.com/cicorias/pxe-server-setup"
echo "   cd pxe-server-setup && sudo ./setup-pxe-server.sh"
echo
echo "2. Deploy artifacts to PXE server:"
echo "   $SCRIPT_DIR/deploy-to-pxe-server.sh <pxe-server-ip>"
echo
echo "3. Or follow manual instructions:"
echo "   cat $ARTIFACTS_DIR/pxe-integration/deployment-instructions.md"
echo

# Validate deployment script functionality
echo "=== Deployment Script Validation ==="
if [ -x "$SCRIPT_DIR/deploy-to-pxe-server.sh" ]; then
    # Test script syntax without execution
    if bash -n "$SCRIPT_DIR/deploy-to-pxe-server.sh"; then
        log "deploy-to-pxe-server.sh syntax is valid"
    else
        error "deploy-to-pxe-server.sh has syntax errors"
    fi
    
    # Show usage
    echo
    info "Deployment script usage:"
    "$SCRIPT_DIR/deploy-to-pxe-server.sh" 2>&1 | head -15 || true
fi

echo
echo "=== Manual Verification Commands ==="
echo "# After deployment, test PXE server:"
echo "tftp <pxe-server-ip> -c get pxelinux.0"
echo
echo "# Check HTTP endpoints:"
echo "curl http://<pxe-server-ip>/images/"
echo "curl http://<pxe-server-ip>/os-images/"
echo
echo "# Check services on PXE server:"
echo "systemctl status tftpd-hpa"
echo "systemctl status nginx"
echo "systemctl status isc-dhcp-server  # if local DHCP"
echo

echo "=== Test Complete ==="
