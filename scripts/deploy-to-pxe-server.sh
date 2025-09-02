#!/bin/bash
# shellcheck disable=SC2029,SC2029,SC2029,SC2029,SC2029,SC2029,SC2029,SC2029,SC2029
set -euo pipefail

# Deploy artifacts to existing PXE server
# This script assumes pxe-server-setup repo is already configured on target server

# Configuration
PXE_SERVER_IP="${1:-}"
PXE_SERVER_USER="${2:-root}"
PXE_SERVER_PATH="${3:-/home/cicorias/g/pxe-server-setup}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

usage() {
    echo "Usage: $0 <pxe-server-ip> [ssh-user] [pxe-server-path]"
    echo
    echo "Deploy built artifacts to an existing PXE server"
    echo
    echo "Arguments:"
    echo "  pxe-server-ip     IP address of the PXE server"
    echo "  ssh-user          SSH username (default: root)"
    echo "  pxe-server-path   Path to pxe-server-setup on remote server"
    echo "                    (default: /home/cicorias/g/pxe-server-setup)"
    echo
    echo "Examples:"
    echo "  $0 10.1.1.1"
    echo "  $0 192.168.1.10 ubuntu /opt/pxe-server-setup"
    echo
    echo "Prerequisites:"
    echo "  1. PXE server must be set up using cicorias/pxe-server-setup"
    echo "  2. SSH access to PXE server must be configured"
    echo "  3. Artifacts must be built using ./create-pxe-system.sh"
}

# add a warning message that this was not tested well and wait 5 seconds for user to config Y/n
warn "WARNING: This script has not been extensively tested."
read -t 5 -p "Please configure your settings (Y/n): " response || response="Y"
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    error "User aborted deployment."
fi

# Validate arguments
if [[ -z "$PXE_SERVER_IP" ]]; then
    echo -e "${RED}Error: PXE server IP address required${NC}"
    echo
    usage
    exit 1
fi

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ARTIFACTS_DIR="$PROJECT_ROOT/artifacts"

# Check if artifacts exist
if [[ ! -d "$ARTIFACTS_DIR" ]]; then
    error "Artifacts directory not found. Run ./scripts/create-pxe-system.sh first."
fi

log "Starting deployment to PXE server $PXE_SERVER_IP"
info "User: $PXE_SERVER_USER"
info "Remote path: $PXE_SERVER_PATH"
info "Local artifacts: $ARTIFACTS_DIR"

# Test SSH connectivity
log "Testing SSH connectivity..."
if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$PXE_SERVER_USER@$PXE_SERVER_IP" exit 2>/dev/null; then
    error "Cannot connect to $PXE_SERVER_USER@$PXE_SERVER_IP via SSH. Please check connectivity and SSH keys."
fi

# Verify PXE server setup exists
log "Verifying PXE server setup..."
if ! ssh "$PXE_SERVER_USER@$PXE_SERVER_IP" "test -d '$PXE_SERVER_PATH'"; then
    error "PXE server setup not found at $PXE_SERVER_PATH. Please ensure pxe-server-setup is installed."
fi

if ! ssh "$PXE_SERVER_USER@$PXE_SERVER_IP" "test -f '$PXE_SERVER_PATH/scripts/08-iso-manager.sh'"; then
    error "ISO manager script not found. PXE server setup appears incomplete."
fi

# Create deployment timestamp
DEPLOYMENT_ID="device-setup-$(date +%Y%m%d_%H%M%S)"

# Deploy IMG files if they exist
if [[ -d "$ARTIFACTS_DIR/images" ]] && [[ -n "$(ls -A "$ARTIFACTS_DIR/images"/*.img 2>/dev/null)" ]]; then
    log "Deploying IMG files..."
    
    # Create temporary directory on remote server
    ssh "$PXE_SERVER_USER@$PXE_SERVER_IP" "mkdir -p /tmp/$DEPLOYMENT_ID/images"
    
    # Copy IMG files
    scp "$ARTIFACTS_DIR/images"/*.img "$PXE_SERVER_USER@$PXE_SERVER_IP:/tmp/$DEPLOYMENT_ID/images/"
    
    # Add IMG files to PXE server
    for img_file in "$ARTIFACTS_DIR/images"/*.img; do
        if [[ -f "$img_file" ]]; then
            img_name=$(basename "$img_file")
            log "Adding $img_name to PXE server..."
            ssh "$PXE_SERVER_USER@$PXE_SERVER_IP" \
                "cd '$PXE_SERVER_PATH' && sudo ./scripts/08-iso-manager.sh add /tmp/$DEPLOYMENT_ID/images/$img_name"
        fi
    done
else
    warn "No IMG files found in $ARTIFACTS_DIR/images"
fi

# Deploy legacy PXE files if they exist
if [[ -d "$ARTIFACTS_DIR/pxe-files" ]]; then
    log "Deploying legacy PXE files..."
    
    # Create temporary directory for PXE files
    ssh "$PXE_SERVER_USER@$PXE_SERVER_IP" "mkdir -p /tmp/$DEPLOYMENT_ID/pxe-files"
    
    # Copy PXE files
    scp -r "$ARTIFACTS_DIR/pxe-files"/* "$PXE_SERVER_USER@$PXE_SERVER_IP:/tmp/$DEPLOYMENT_ID/pxe-files/"
    
    # Manual integration required for legacy files
    warn "Legacy PXE files copied to /tmp/$DEPLOYMENT_ID/pxe-files"
    warn "Manual integration may be required for filesystem.squashfs"
fi

# Deploy integration files if they exist
if [[ -d "$ARTIFACTS_DIR/pxe-integration" ]]; then
    log "Deploying integration configuration..."
    
    ssh "$PXE_SERVER_USER@$PXE_SERVER_IP" "mkdir -p /tmp/$DEPLOYMENT_ID/integration"
    scp -r "$ARTIFACTS_DIR/pxe-integration"/* "$PXE_SERVER_USER@$PXE_SERVER_IP:/tmp/$DEPLOYMENT_ID/integration/"
    
    info "Integration files available at /tmp/$DEPLOYMENT_ID/integration"
    
    # Apply GRUB configuration if available
    if [[ -f "$ARTIFACTS_DIR/pxe-integration/grub-entries.cfg" ]]; then
        log "Applying custom GRUB configuration..."
        ssh "$PXE_SERVER_USER@$PXE_SERVER_IP" \
            "cd '$PXE_SERVER_PATH' && sudo ./scripts/09-uefi-pxe-setup.sh"
    fi
fi

# Run deployment validation
log "Validating deployment..."
ssh "$PXE_SERVER_USER@$PXE_SERVER_IP" \
    "cd '$PXE_SERVER_PATH' && sudo ./scripts/08-iso-manager.sh validate"

# Clean up temporary files
log "Cleaning up temporary files..."
ssh "$PXE_SERVER_USER@$PXE_SERVER_IP" "rm -rf /tmp/$DEPLOYMENT_ID"

log "Deployment completed successfully!"
info "PXE server status: ssh $PXE_SERVER_USER@$PXE_SERVER_IP 'cd $PXE_SERVER_PATH && sudo ./scripts/08-iso-manager.sh status'"
info "Test PXE boot from a client machine on the same network"

echo
echo -e "${GREEN}=== Deployment Summary ===${NC}"
echo "Server: $PXE_SERVER_IP"
echo "Deployment ID: $DEPLOYMENT_ID"
echo "Status: Success"
echo
echo "Next steps:"
echo "1. Test PXE boot from client machine"
echo "2. Verify GRUB menu contains new entries"
echo "3. Check server logs if issues occur"
