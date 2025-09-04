#!/bin/bash
# 07-generate-integration.sh
# Generate integration artifacts for PXE server deployment
# Part of the device initialization build process

set -euo pipefail

# Script configuration
SCRIPT_NAME="07-generate-integration"
SCRIPT_VERSION="1.0.0"

# Import configuration
if [[ -f "$(dirname "$0")/../config.sh" ]]; then
    source "$(dirname "$0")/../config.sh"
else
    echo "ERROR: config.sh not found"
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] [$SCRIPT_NAME] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] [$SCRIPT_NAME] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] [$SCRIPT_NAME] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] [$SCRIPT_NAME] INFO: $1${NC}"
}

# Script header
show_header() {
    log "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
    info "Generating integration artifacts for PXE server deployment"
}

# Check prerequisites from previous script
check_prerequisites() {
    log "Checking prerequisites from previous build stages..."
    
    # Check that testing completed
    if [[ ! -f "$BUILD_LOG_DIR/06-testing-validation.log" ]]; then
        error "Testing and validation script has not completed successfully"
    fi
    
    # Check images exist
    if [[ ! -f "$BUILD_DIR/images/raw/edge-device-init.img" ]]; then
        error "Raw image not found"
    fi
    
    # Check PXE files exist
    if [[ ! -d "$BUILD_DIR/images/pxe" ]]; then
        error "PXE files not found"
    fi
    
    log "Prerequisites check completed"
}

# Create integration directory structure
create_integration_directories() {
    log "Creating integration directory structure..."
    
    # Create integration output directories
    mkdir -p "$BUILD_DIR/integration"
    mkdir -p "$BUILD_DIR/integration/pxe-server"
    mkdir -p "$BUILD_DIR/integration/deployment"
    mkdir -p "$BUILD_DIR/integration/documentation"
    mkdir -p "$BUILD_DIR/integration/scripts"
    mkdir -p "$BUILD_DIR/integration/config"
    
    log "Integration directories created"
}

# Generate PXE server integration files
generate_pxe_integration() {
    log "Generating PXE server integration files..."
    
    local pxe_integration_dir="$BUILD_DIR/integration/pxe-server"
    
    # Copy PXE boot files
    cp -r "$BUILD_DIR/images/pxe"/* "$pxe_integration_dir/"
    
    # Create PXE menu configuration for integration
    cat > "$pxe_integration_dir/edge-device.menu" << EOF
# Edge Device PXE Menu Configuration
# Add this to your PXE server menu system

LABEL edge-device-init
    MENU LABEL Edge Device Initialization
    KERNEL edge-device/vmlinuz
    APPEND initrd=edge-device/initrd.img root=LABEL=INIT-ROOT ro quiet splash
    TEXT HELP
        Boot the Edge Device Initialization System
        Use this to configure, partition, and install operating systems
        on edge devices.
    ENDTEXT

LABEL edge-device-rescue
    MENU LABEL Edge Device Rescue Mode
    KERNEL edge-device/vmlinuz
    APPEND initrd=edge-device/initrd.img root=LABEL=INIT-ROOT ro single
    TEXT HELP
        Boot Edge Device in rescue mode for troubleshooting
        and recovery operations.
    ENDTEXT
EOF
    
    # Create GRUB PXE configuration
    cat > "$pxe_integration_dir/grub-edge-device.cfg" << EOF
# GRUB PXE Configuration for Edge Device
# Add this to your GRUB PXE server configuration

menuentry 'Edge Device Initialization' {
    echo 'Loading Edge Device Initialization System...'
    linux edge-device/vmlinuz root=LABEL=INIT-ROOT ro quiet splash
    initrd edge-device/initrd.img
}

menuentry 'Edge Device Rescue Mode' {
    echo 'Loading Edge Device Rescue Mode...'
    linux edge-device/vmlinuz root=LABEL=INIT-ROOT ro single
    initrd edge-device/initrd.img
}
EOF
    
    # Create standard PXE configuration for SYSLINUX/PXELINUX
    cat > "$pxe_integration_dir/pxelinux.cfg" << EOF
# PXE Configuration for Edge Device Initialization
# Uses standard PXE implementation (no iPXE)

DEFAULT edge-device-init
TIMEOUT 300
PROMPT 1

LABEL edge-device-init
    MENU LABEL Edge Device Initialization
    KERNEL edge-device/vmlinuz
    APPEND initrd=edge-device/initrd.img root=LABEL=INIT-ROOT ro quiet splash
    
LABEL edge-device-rescue
    MENU LABEL Edge Device Rescue Mode  
    KERNEL edge-device/vmlinuz
    APPEND initrd=edge-device/initrd.img root=LABEL=INIT-ROOT ro single
EOF
    
    log "PXE server integration files generated"
}

# Generate deployment scripts
generate_deployment_scripts() {
    log "Generating deployment scripts..."
    
    local deployment_dir="$BUILD_DIR/integration/deployment"
    
    # Create deployment script for PXE server
    cat > "$deployment_dir/deploy-to-pxe-server.sh" << 'EOF'
#!/bin/bash
# Deploy Edge Device Initialization to PXE Server
# This script deploys the edge device initialization system to a PXE server

set -euo pipefail

# Configuration variables
PXE_SERVER_HOST="${PXE_SERVER_HOST:-}"
PXE_SERVER_USER="${PXE_SERVER_USER:-root}"
PXE_TFTP_ROOT="${PXE_TFTP_ROOT:-/var/lib/tftpboot}"
PXE_HTTP_ROOT="${PXE_HTTP_ROOT:-/var/www/html}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-edge-device}"

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

# Show usage
show_usage() {
    cat << USAGE_EOF
Usage: $0 [OPTIONS]

Options:
    -h, --host HOST         PXE server hostname or IP address
    -u, --user USER         SSH user for PXE server (default: root)
    -t, --tftp-root PATH    TFTP root directory (default: /var/lib/tftpboot)
    -w, --http-root PATH    HTTP root directory (default: /var/www/html)
    -n, --name NAME         Deployment name (default: edge-device)
    --help                  Show this help message

Environment Variables:
    PXE_SERVER_HOST         PXE server hostname or IP
    PXE_SERVER_USER         SSH user for PXE server
    PXE_TFTP_ROOT          TFTP root directory
    PXE_HTTP_ROOT          HTTP root directory
    DEPLOYMENT_NAME        Deployment name

Examples:
    # Deploy to local PXE server
    $0 --host 192.168.1.100

    # Deploy with custom paths
    $0 --host pxe.example.com --tftp-root /srv/tftp --http-root /srv/www

    # Deploy with environment variables
    export PXE_SERVER_HOST=192.168.1.100
    $0
USAGE_EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--host)
                PXE_SERVER_HOST="$2"
                shift 2
                ;;
            -u|--user)
                PXE_SERVER_USER="$2"
                shift 2
                ;;
            -t|--tftp-root)
                PXE_TFTP_ROOT="$2"
                shift 2
                ;;
            -w|--http-root)
                PXE_HTTP_ROOT="$2"
                shift 2
                ;;
            -n|--name)
                DEPLOYMENT_NAME="$2"
                shift 2
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "$PXE_SERVER_HOST" ]]; then
        error "PXE server host is required. Use --host or set PXE_SERVER_HOST environment variable."
    fi
}

# Test SSH connectivity
test_ssh_connectivity() {
    log "Testing SSH connectivity to PXE server..."
    
    if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$PXE_SERVER_USER@$PXE_SERVER_HOST" exit &>/dev/null; then
        error "Cannot connect to PXE server via SSH. Please check connectivity and SSH keys."
    fi
    
    log "SSH connectivity confirmed"
}

# Deploy files to PXE server
deploy_files() {
    log "Deploying files to PXE server..."
    
    local script_dir="$(dirname "$0")"
    local pxe_files_dir="$script_dir/../pxe-server"
    
    if [[ ! -d "$pxe_files_dir" ]]; then
        error "PXE files directory not found: $pxe_files_dir"
    fi
    
    # Create remote directories
    ssh "$PXE_SERVER_USER@$PXE_SERVER_HOST" "mkdir -p $PXE_TFTP_ROOT/$DEPLOYMENT_NAME"
    ssh "$PXE_SERVER_USER@$PXE_SERVER_HOST" "mkdir -p $PXE_HTTP_ROOT/$DEPLOYMENT_NAME"
    
    # Copy PXE boot files
    info "Copying PXE boot files..."
    scp "$pxe_files_dir/vmlinuz" "$PXE_SERVER_USER@$PXE_SERVER_HOST:$PXE_TFTP_ROOT/$DEPLOYMENT_NAME/"
    scp "$pxe_files_dir/initrd.img" "$PXE_SERVER_USER@$PXE_SERVER_HOST:$PXE_TFTP_ROOT/$DEPLOYMENT_NAME/"
    
    # Copy configuration files
    info "Copying configuration files..."
    scp "$pxe_files_dir"/*.menu "$PXE_SERVER_USER@$PXE_SERVER_HOST:$PXE_TFTP_ROOT/$DEPLOYMENT_NAME/" 2>/dev/null || true
    scp "$pxe_files_dir"/*.cfg "$PXE_SERVER_USER@$PXE_SERVER_HOST:$PXE_TFTP_ROOT/$DEPLOYMENT_NAME/" 2>/dev/null || true
    
    # Copy images to HTTP server if available
    local images_dir="$script_dir/../../images"
    if [[ -d "$images_dir" ]]; then
        info "Copying images to HTTP server..."
        scp -r "$images_dir" "$PXE_SERVER_USER@$PXE_SERVER_HOST:$PXE_HTTP_ROOT/$DEPLOYMENT_NAME/"
    fi
    
    log "File deployment completed"
}

# Configure PXE server
configure_pxe_server() {
    log "Configuring PXE server..."
    
    # Create configuration script to run on PXE server
    local config_script="/tmp/configure-edge-device-pxe.sh"
    
    cat > "$config_script" << 'REMOTE_SCRIPT_EOF'
#!/bin/bash
# Configuration script for Edge Device PXE integration

DEPLOYMENT_NAME="__DEPLOYMENT_NAME__"
PXE_TFTP_ROOT="__PXE_TFTP_ROOT__"

# Add to PXE menu if using pxelinux
if [[ -f "$PXE_TFTP_ROOT/pxelinux.cfg/default" ]]; then
    if ! grep -q "edge-device-init" "$PXE_TFTP_ROOT/pxelinux.cfg/default"; then
        echo "Adding Edge Device entries to PXE menu..."
        cat "$PXE_TFTP_ROOT/$DEPLOYMENT_NAME/edge-device.menu" >> "$PXE_TFTP_ROOT/pxelinux.cfg/default"
    fi
fi

# Restart services if needed
if systemctl is-active --quiet tftpd-hpa; then
    systemctl restart tftpd-hpa
fi

if systemctl is-active --quiet isc-dhcp-server; then
    systemctl restart isc-dhcp-server
fi

echo "PXE server configuration completed"
REMOTE_SCRIPT_EOF
    
    # Customize the script
    sed -i "s/__DEPLOYMENT_NAME__/$DEPLOYMENT_NAME/g" "$config_script"
    sed -i "s|__PXE_TFTP_ROOT__|$PXE_TFTP_ROOT|g" "$config_script"
    
    # Copy and execute the script on PXE server
    scp "$config_script" "$PXE_SERVER_USER@$PXE_SERVER_HOST:/tmp/"
    ssh "$PXE_SERVER_USER@$PXE_SERVER_HOST" "chmod +x /tmp/configure-edge-device-pxe.sh && /tmp/configure-edge-device-pxe.sh"
    
    # Clean up
    rm "$config_script"
    ssh "$PXE_SERVER_USER@$PXE_SERVER_HOST" "rm /tmp/configure-edge-device-pxe.sh"
    
    log "PXE server configuration completed"
}

# Show deployment summary
show_deployment_summary() {
    log "Deployment completed successfully!"
    
    echo
    echo "=== Deployment Summary ==="
    echo "PXE Server: $PXE_SERVER_HOST"
    echo "Deployment Name: $DEPLOYMENT_NAME"
    echo "TFTP Root: $PXE_TFTP_ROOT"
    echo "HTTP Root: $PXE_HTTP_ROOT"
    echo
    echo "Files deployed:"
    echo "  - $PXE_TFTP_ROOT/$DEPLOYMENT_NAME/vmlinuz"
    echo "  - $PXE_TFTP_ROOT/$DEPLOYMENT_NAME/initrd.img"
    echo "  - $PXE_TFTP_ROOT/$DEPLOYMENT_NAME/*.menu"
    echo "  - $PXE_TFTP_ROOT/$DEPLOYMENT_NAME/*.cfg"
    echo "  - $PXE_HTTP_ROOT/$DEPLOYMENT_NAME/images/"
    echo
    echo "The Edge Device Initialization system is now available for PXE boot."
    echo "Clients can boot using the 'Edge Device Initialization' menu option."
    echo
}

# Main execution
main() {
    parse_arguments "$@"
    test_ssh_connectivity
    deploy_files
    configure_pxe_server
    show_deployment_summary
}

# Run main function
main "$@"
EOF
    
    chmod +x "$deployment_dir/deploy-to-pxe-server.sh"
    
    # Create image deployment script
    cat > "$deployment_dir/write-to-device.sh" << 'EOF'
#!/bin/bash
# Write Edge Device image to storage device (USB/SD card)

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

# Show usage
show_usage() {
    cat << USAGE_EOF
Usage: $0 [OPTIONS] TARGET_DEVICE

Write Edge Device initialization image to storage device.

Arguments:
    TARGET_DEVICE          Target device (e.g., /dev/sdb, /dev/mmcblk0)

Options:
    -i, --image PATH       Image file path (auto-detected if not specified)
    -f, --force            Skip confirmation prompts
    -v, --verify           Verify write after completion
    --help                 Show this help message

Examples:
    # Write to USB device
    $0 /dev/sdb

    # Write specific image with verification
    $0 --image edge-device-init.img --verify /dev/sdb

    # Force write without confirmation
    $0 --force /dev/sdb
USAGE_EOF
}

# Detect available images
detect_images() {
    local script_dir="$(dirname "$0")"
    local images_dir="$script_dir/../../images"
    
    echo "Available images:"
    find "$images_dir" -name "*.img" -o -name "*.img.gz" 2>/dev/null | while read -r img; do
        local size=$(du -h "$img" | cut -f1)
        echo "  $(basename "$img") ($size)"
    done
}

# Parse arguments
parse_arguments() {
    local image_path=""
    local target_device=""
    local force=false
    local verify=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--image)
                image_path="$2"
                shift 2
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -v|--verify)
                verify=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            -*)
                error "Unknown option: $1"
                ;;
            *)
                if [[ -z "$target_device" ]]; then
                    target_device="$1"
                else
                    error "Too many arguments"
                fi
                shift
                ;;
        esac
    done
    
    # Validate target device
    if [[ -z "$target_device" ]]; then
        error "Target device is required"
    fi
    
    if [[ ! -b "$target_device" ]]; then
        error "Target device does not exist or is not a block device: $target_device"
    fi
    
    # Auto-detect image if not specified
    if [[ -z "$image_path" ]]; then
        local script_dir="$(dirname "$0")"
        local raw_image="$script_dir/../../images/raw/edge-device-init.img"
        local gz_image="$script_dir/../../images/compressed/edge-device-init.img.gz"
        
        if [[ -f "$raw_image" ]]; then
            image_path="$raw_image"
        elif [[ -f "$gz_image" ]]; then
            image_path="$gz_image"
        else
            echo "No image found automatically. Available images:"
            detect_images
            error "Please specify image path with --image option"
        fi
    fi
    
    if [[ ! -f "$image_path" ]]; then
        error "Image file not found: $image_path"
    fi
    
    # Export variables for other functions
    export IMAGE_PATH="$image_path"
    export TARGET_DEVICE="$target_device"
    export FORCE_WRITE="$force"
    export VERIFY_WRITE="$verify"
}

# Show device information
show_device_info() {
    log "Target device information:"
    
    echo "Device: $TARGET_DEVICE"
    echo "Size: $(lsblk -d -o SIZE --noheadings "$TARGET_DEVICE")"
    echo "Model: $(lsblk -d -o MODEL --noheadings "$TARGET_DEVICE" 2>/dev/null || echo "Unknown")"
    
    # Show current partitions
    echo "Current partitions:"
    lsblk "$TARGET_DEVICE" || echo "  No partitions found"
    
    # Check if mounted
    if mount | grep -q "$TARGET_DEVICE"; then
        warn "Device has mounted partitions:"
        mount | grep "$TARGET_DEVICE"
    fi
    
    echo
    echo "Image: $IMAGE_PATH"
    echo "Image size: $(du -h "$IMAGE_PATH" | cut -f1)"
}

# Confirm write operation
confirm_write() {
    if [[ "$FORCE_WRITE" == "true" ]]; then
        return 0
    fi
    
    echo
    warn "This will COMPLETELY ERASE all data on $TARGET_DEVICE"
    echo "Type 'YES' to proceed: "
    read confirmation
    
    if [[ "$confirmation" != "YES" ]]; then
        error "Write operation cancelled"
    fi
}

# Unmount device
unmount_device() {
    log "Unmounting any mounted partitions..."
    
    # Find and unmount all partitions
    mount | grep "$TARGET_DEVICE" | while read -r line; do
        local partition=$(echo "$line" | awk '{print $1}')
        local mountpoint=$(echo "$line" | awk '{print $3}')
        umount "$mountpoint" && log "Unmounted $partition" || warn "Failed to unmount $partition"
    done
}

# Write image to device
write_image() {
    log "Writing image to device..."
    
    local image_path="$IMAGE_PATH"
    
    # Handle compressed images
    if [[ "$image_path" =~ \.gz$ ]]; then
        info "Decompressing and writing gzip image..."
        gunzip -c "$image_path" | dd of="$TARGET_DEVICE" bs=4M status=progress oflag=sync
    else
        info "Writing raw image..."
        dd if="$image_path" of="$TARGET_DEVICE" bs=4M status=progress oflag=sync
    fi
    
    # Sync to ensure all data is written
    sync
    
    log "Image write completed"
}

# Verify write
verify_write() {
    if [[ "$VERIFY_WRITE" != "true" ]]; then
        return 0
    fi
    
    log "Verifying written image..."
    
    # Re-read partition table
    partprobe "$TARGET_DEVICE"
    sleep 2
    
    # Check partition table
    local partition_count=$(fdisk -l "$TARGET_DEVICE" | grep "^${TARGET_DEVICE}" | wc -l)
    if [[ $partition_count -eq 6 ]]; then
        info "Partition table verified: 6 partitions found ✓"
    else
        warn "Partition verification failed: expected 6 partitions, found $partition_count"
    fi
    
    # Check partition labels
    for i in {1..6}; do
        local partition="${TARGET_DEVICE}$i"
        if [[ ! -b "$partition" ]]; then
            partition="${TARGET_DEVICE}p$i"  # For nvme devices
        fi
        
        if [[ -b "$partition" ]]; then
            local label=$(blkid -s LABEL -o value "$partition" 2>/dev/null || echo "")
            if [[ -n "$label" ]]; then
                info "Partition $i label: $label ✓"
            fi
        fi
    done
    
    log "Verification completed"
}

# Show completion message
show_completion() {
    log "Image write completed successfully!"
    
    echo
    echo "=== Write Summary ==="
    echo "Image: $IMAGE_PATH"
    echo "Target: $TARGET_DEVICE"
    echo "Status: Success"
    echo
    echo "The device is now ready for use as an edge device."
    echo "You can:"
    echo "1. Boot the device from this storage"
    echo "2. Use the GRUB menu to configure and install operating systems"
    echo "3. Set up the device for your specific edge computing needs"
    echo
    echo "First boot will show the Edge Device Initialization menu."
    echo
}

# Main execution
main() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
    
    parse_arguments "$@"
    show_device_info
    confirm_write
    unmount_device
    write_image
    verify_write
    show_completion
}

# Run main function
main "$@"
EOF
    
    chmod +x "$deployment_dir/write-to-device.sh"
    
    log "Deployment scripts generated"
}

# Generate configuration templates
generate_configuration_templates() {
    log "Generating configuration templates..."
    
    local config_dir="$BUILD_DIR/integration/config"
    
    # Create PXE server configuration template
    cat > "$config_dir/pxe-server-config.template" << 'EOF'
# PXE Server Configuration Template for Edge Device Integration
# Copy and customize this configuration for your PXE server setup

# DHCP Configuration (dhcpd.conf)
# Add these options to your DHCP server configuration:

option domain-name "edge.local";
option domain-name-servers 8.8.8.8, 8.8.4.4;

# PXE Boot configuration
option tftp-server-name "192.168.1.100";  # Replace with your PXE server IP
filename "pxelinux.0";

# Edge device subnet configuration
subnet 192.168.1.0 netmask 255.255.255.0 {
    range 192.168.1.150 192.168.1.200;
    option routers 192.168.1.1;
    option broadcast-address 192.168.1.255;
    
    # Edge device specific configuration
    class "edge-devices" {
        match if option vendor-class-identifier = "EdgeDevice";
        filename "edge-device/pxelinux.0";
    }
}

# TFTP Configuration (tftpd-hpa)
# /etc/default/tftpd-hpa
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/var/lib/tftpboot"
TFTP_ADDRESS=":69"
TFTP_OPTIONS="--secure"

# Apache HTTP Configuration
# /etc/apache2/sites-available/pxe-server.conf
<VirtualHost *:80>
    DocumentRoot /var/www/html
    
    <Directory "/var/www/html/edge-device">
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
</VirtualHost>
EOF
    
    # Create edge device configuration template
    cat > "$config_dir/edge-device-config.template" << 'EOF'
# Edge Device Configuration Template
# Use this template to pre-configure edge devices

# Network Configuration
NETWORK_TYPE="dhcp"              # dhcp or static
STATIC_IP=""                     # IP address for static configuration
STATIC_NETMASK=""               # Netmask for static configuration
STATIC_GATEWAY=""               # Gateway for static configuration
STATIC_DNS="8.8.8.8,8.8.4.4"   # DNS servers for static configuration

# Device Configuration
DEVICE_HOSTNAME="edge-device"    # Device hostname
TIMEZONE="UTC"                   # System timezone
DEFAULT_OS="os1"                 # Default OS to boot (os1 or os2)

# Security Configuration
ROOT_PASSWORD_HASH=""            # Pre-hashed root password
EDGE_USER_PASSWORD_HASH=""       # Pre-hashed edge user password
SSH_PUBLIC_KEYS=""               # SSH public keys (comma-separated)
DISABLE_PASSWORD_AUTH="false"    # Disable SSH password authentication

# Services Configuration
ENABLE_DOCKER="true"             # Enable Docker service
ENABLE_SSH="true"                # Enable SSH service
ENABLE_FIREWALL="true"           # Enable UFW firewall

# Custom Configuration Scripts
PRE_INSTALL_SCRIPT=""            # Script to run before OS installation
POST_INSTALL_SCRIPT=""           # Script to run after OS installation
CUSTOM_PACKAGES=""               # Additional packages to install
EOF
    
    # Create deployment checklist
    cat > "$config_dir/deployment-checklist.md" << 'EOF'
# Edge Device Deployment Checklist

## Pre-Deployment

- [ ] PXE server is configured and running
- [ ] DHCP server is configured for PXE boot
- [ ] TFTP server is accessible
- [ ] HTTP server is accessible (for image downloads)
- [ ] Network connectivity is established
- [ ] Edge device configuration template is customized

## Deployment Steps

### 1. Deploy to PXE Server
- [ ] Run `deploy-to-pxe-server.sh` script
- [ ] Verify files are copied to PXE server
- [ ] Test PXE boot menu includes edge device options

### 2. Test PXE Boot
- [ ] Boot test device from network
- [ ] Verify edge device initialization menu appears
- [ ] Test menu options (configure, partition, install)

### 3. Device Configuration
- [ ] Configure network settings
- [ ] Set device hostname and timezone
- [ ] Configure security settings (passwords, SSH keys)
- [ ] Configure services (Docker, SSH, firewall)

### 4. OS Installation
- [ ] Partition disk with 6-partition layout
- [ ] Install OS1 (primary Ubuntu system)
- [ ] Install OS2 (secondary Ubuntu system)
- [ ] Verify both OS installations boot correctly

### 5. Final Verification
- [ ] Test switching between OS1 and OS2
- [ ] Verify shared data partition access
- [ ] Test device configuration persistence
- [ ] Verify network connectivity
- [ ] Test SSH access
- [ ] Verify Docker functionality (if enabled)

## Post-Deployment

- [ ] Document device configuration
- [ ] Create backup of device configuration
- [ ] Set up monitoring (if applicable)
- [ ] Configure automatic updates
- [ ] Test factory reset functionality

## Troubleshooting

### Common Issues
- Network boot fails: Check DHCP and TFTP configuration
- Menu doesn't appear: Verify PXE files are accessible
- OS installation fails: Check debootstrap mirror accessibility
- Boot issues: Verify GRUB configuration and partition UUIDs
- Network issues: Check NetworkManager configuration

### Recovery Options
- Boot to rescue mode from PXE menu
- Use factory reset option to restore device
- Re-deploy from PXE server if needed
- Use emergency shell for manual recovery
EOF
    
    log "Configuration templates generated"
}

# Generate documentation
generate_documentation() {
    log "Generating integration documentation..."
    
    local docs_dir="$BUILD_DIR/integration/documentation"
    
    # Create deployment guide
    cat > "$docs_dir/deployment-guide.md" << 'EOF'
# Edge Device Initialization - Deployment Guide

## Overview

This guide covers the deployment of the Edge Device Initialization system to a PXE server infrastructure, enabling automated provisioning and configuration of edge computing devices.

## Architecture

The Edge Device Initialization system consists of:

1. **Initialization Environment**: Minimal Ubuntu system with configuration tools
2. **6-Partition Layout**: EFI, Root, Swap, OS1, OS2, and Data partitions
3. **GRUB Menu System**: Interactive menu for device management
4. **Configuration Scripts**: Bash-based device configuration tools
5. **PXE Integration**: Network boot capabilities for mass deployment

## Prerequisites

### PXE Server Requirements

- Ubuntu/Debian server with network access
- DHCP server (ISC DHCP or similar)
- TFTP server (tftpd-hpa)
- HTTP server (Apache/Nginx)
- Sufficient storage for images and boot files

### Network Requirements

- Isolated network segment for edge devices
- DHCP range for device provisioning
- Internet access for package downloads
- DNS resolution for external repositories

## Deployment Process

### 1. Prepare PXE Server

```bash
# Install required packages
sudo apt-get update
sudo apt-get install -y dhcp-server tftpd-hpa apache2

# Configure DHCP server
sudo cp /path/to/pxe-server-config.template /etc/dhcp/dhcpd.conf
sudo systemctl restart dhcp-server

# Configure TFTP server
sudo systemctl enable tftpd-hpa
sudo systemctl start tftpd-hpa
```

### 2. Deploy Edge Device Files

```bash
# Use the deployment script
./deploy-to-pxe-server.sh --host your-pxe-server --user root

# Or manually copy files
scp -r pxe-server/* root@pxe-server:/var/lib/tftpboot/edge-device/
scp -r ../images/* root@pxe-server:/var/www/html/edge-device/
```

### 3. Configure Device Options

Edit the device configuration template:

```bash
cp config/edge-device-config.template my-device-config
# Customize network, security, and service settings
```

### 4. Test Deployment

1. Boot test device from network
2. Verify edge device menu appears
3. Test configuration options
4. Verify OS installation process

## Device Provisioning Workflow

### Initial Boot

1. Device boots from network (PXE)
2. Edge Device Initialization menu appears
3. Administrator selects configuration option

### Configuration Phase

1. **Configure Device**: Set network, hostname, security
2. **Partition Disk**: Create 6-partition layout
3. **Install OS1**: Install primary Ubuntu system
4. **Install OS2**: Install secondary Ubuntu system

### Operational Phase

1. Device boots to selected OS (OS1 or OS2)
2. Shared data partition provides configuration persistence
3. Factory reset option available for re-provisioning

## Configuration Options

### Network Configuration

- **DHCP**: Automatic IP assignment (default)
- **Static IP**: Manual IP configuration
- **DNS**: Custom DNS servers
- **Hostname**: Device identification

### Security Configuration

- **User Accounts**: edge user with sudo access
- **SSH Keys**: Public key authentication
- **Firewall**: UFW with SSH access
- **Passwords**: Secure password policies

### Service Configuration

- **Docker**: Container runtime
- **SSH**: Remote access
- **Automatic Updates**: Security patches
- **Monitoring**: System health

## Troubleshooting

### Boot Issues

**Symptom**: Device doesn't boot from network
**Solution**: 
- Check DHCP configuration
- Verify TFTP server accessibility
- Ensure PXE files are present

**Symptom**: Menu doesn't appear
**Solution**:
- Check GRUB configuration
- Verify kernel and initrd files
- Test network connectivity

### Installation Issues

**Symptom**: OS installation fails
**Solution**:
- Check internet connectivity
- Verify Ubuntu mirror accessibility
- Ensure sufficient disk space

**Symptom**: Partition creation fails
**Solution**:
- Check disk size requirements
- Verify no existing partitions conflict
- Ensure proper permissions

### Configuration Issues

**Symptom**: Network configuration doesn't persist
**Solution**:
- Check data partition mount
- Verify configuration file permissions
- Ensure proper systemd service configuration

## Best Practices

### Security

1. Use SSH key authentication
2. Disable root SSH access
3. Configure firewall rules
4. Regular security updates

### Management

1. Document device configurations
2. Create configuration backups
3. Use consistent naming conventions
4. Monitor device health

### Scalability

1. Automate deployment scripts
2. Use configuration management
3. Implement monitoring systems
4. Plan for device lifecycle management

## Support

For additional support and troubleshooting:

1. Check system logs: `/var/log/syslog`
2. Review build logs: `build/logs/`
3. Test individual components
4. Use rescue mode for recovery
EOF
    
    # Create API reference
    cat > "$docs_dir/script-api-reference.md" << 'EOF'
# Edge Device Scripts - API Reference

## Configuration Scripts

### configure-device.sh

**Purpose**: Interactive device configuration utility

**Usage**: 
```bash
/usr/local/bin/configure-device.sh [OPTIONS]
```

**Options**:
- `--first-boot`: Run first-boot configuration
- `--network-only`: Configure network settings only
- `--security-only`: Configure security settings only
- `--non-interactive`: Run with pre-configured settings

**Functions**:
- `configure_network()`: Network configuration (DHCP/static)
- `configure_security()`: User accounts and SSH keys
- `configure_system()`: Hostname, timezone, services
- `save_configuration()`: Persist settings to data partition

**Configuration File**: `/data/config/device.conf`

### partition-disk.sh

**Purpose**: Automated disk partitioning utility

**Usage**:
```bash
/usr/local/bin/partition-disk.sh [DISK]
```

**Parameters**:
- `DISK`: Target disk device (default: /dev/sda)

**Partition Layout**:
1. EFI System Partition (200MB, FAT32)
2. Root/Init Partition (2GB, ext4)
3. Swap Partition (4GB, swap)
4. OS1 Partition (3.7GB, ext4)
5. OS2 Partition (3.7GB, ext4)
6. Data Partition (remaining, ext4)

**Functions**:
- `create_partitions()`: Create GPT partition table
- `format_partitions()`: Format all partitions
- `verify_partitions()`: Validate partition layout

### install-os1.sh / install-os2.sh

**Purpose**: Ubuntu OS installation utilities

**Usage**:
```bash
/usr/local/bin/install-os1.sh
/usr/local/bin/install-os2.sh
```

**Installation Process**:
1. Install base Ubuntu system with debootstrap
2. Configure essential packages
3. Set up network and SSH
4. Configure GRUB bootloader
5. Create first-boot scripts

**Functions**:
- `install_base_system()`: Debootstrap installation
- `configure_packages()`: Package installation and configuration
- `configure_grub()`: Bootloader setup
- `create_users()`: User account creation

### factory-reset.sh

**Purpose**: Factory reset utility

**Usage**:
```bash
/usr/local/bin/factory-reset.sh
```

**Reset Options**:
1. Full factory reset (clear all data)
2. Reset OS partitions only
3. Reset data partition only

**Functions**:
- `reset_partitions()`: Clear and reformat partitions
- `preserve_config()`: Backup critical configurations
- `update_grub()`: Remove OS boot entries

## Build Scripts

### 01-bootstrap-environment.sh

**Purpose**: Bootstrap build environment

**Functions**:
- Install build dependencies
- Create build directory structure
- Validate configuration

### 02-system-configuration.sh

**Purpose**: Configure base system

**Functions**:
- Install Ubuntu base system
- Configure APT sources
- Set up chroot environment
- Configure network and locales

### 03-package-installation.sh

**Purpose**: Install essential packages

**Package Categories**:
- Essential system packages
- Kernel and boot packages
- Network packages
- Security packages
- Development packages
- Edge computing packages

### 04-grub-configuration.sh

**Purpose**: Configure GRUB bootloader

**Functions**:
- Create enhanced GRUB menu
- Configure boot entries
- Install GRUB theme
- Create recovery tools

### 05-image-creation.sh

**Purpose**: Create bootable images

**Artifacts**:
- Raw disk image
- Compressed images (gzip)
- PXE boot files
- Checksums

### 06-testing-validation.sh

**Purpose**: Test and validate images

**Test Categories**:
- Image integrity
- Partition table validation
- Filesystem checks
- Configuration validation
- Boot testing

### 07-generate-integration.sh

**Purpose**: Generate deployment artifacts

**Artifacts**:
- PXE server integration files
- Deployment scripts
- Configuration templates
- Documentation

## Utility Functions

### Common Functions

Available in all scripts:

```bash
log()    # Log success messages
warn()   # Log warning messages  
error()  # Log error messages and exit
info()   # Log information messages
```

### Configuration Management

```bash
load_config()     # Load configuration file
save_config()     # Save configuration file
merge_config()    # Merge configuration files
validate_config() # Validate configuration
```

### System Detection

```bash
detect_hardware()  # Detect hardware information
detect_network()   # Detect network interfaces
detect_storage()   # Detect storage devices
```

## Environment Variables

### Build Configuration

- `BUILD_DIR`: Build directory path
- `UBUNTU_RELEASE`: Ubuntu release codename
- `UBUNTU_MIRROR`: Ubuntu package mirror
- `KERNEL_PACKAGE`: Kernel package name

### Device Configuration

- `DEVICE_HOSTNAME`: Device hostname
- `NETWORK_TYPE`: Network configuration type
- `DEFAULT_TIMEZONE`: Default timezone
- `ENABLE_SSH`: Enable SSH service

### Deployment Configuration

- `PXE_SERVER_HOST`: PXE server hostname
- `PXE_TFTP_ROOT`: TFTP root directory
- `PXE_HTTP_ROOT`: HTTP root directory

## Exit Codes

- `0`: Success
- `1`: General error
- `2`: Configuration error
- `3`: Network error
- `4`: Permission error
- `5`: Resource error

## Logging

All scripts log to:
- Console output (real-time)
- Build logs: `build/logs/`
- System logs: `/var/log/syslog`
- Device logs: `/data/logs/`

## Error Handling

All scripts implement:
- Parameter validation
- Error checking with immediate exit
- Cleanup on exit
- Informative error messages
- Recovery suggestions
EOF
    
    log "Integration documentation generated"
}

# Generate deployment package
generate_deployment_package() {
    log "Generating deployment package..."
    
    local package_dir="$BUILD_DIR/integration"
    local package_file="$BUILD_DIR/edge-device-initialization-$(date +%Y%m%d-%H%M%S).tar.gz"
    
    # Create package manifest
    cat > "$package_dir/manifest.txt" << EOF
Edge Device Initialization - Deployment Package
Generated: $(date)

Contents:
- pxe-server/          PXE server integration files
- deployment/          Deployment scripts
- config/              Configuration templates  
- documentation/       Deployment documentation
- scripts/             Utility scripts

Usage:
1. Extract package on deployment system
2. Customize configuration templates
3. Run deploy-to-pxe-server.sh to deploy to PXE server
4. Use write-to-device.sh to create bootable devices
5. Follow deployment-guide.md for complete setup

For support and troubleshooting, see documentation/
EOF
    
    # Create package README
    cat > "$package_dir/README.md" << 'EOF'
# Edge Device Initialization - Deployment Package

This package contains all the necessary files and documentation for deploying the Edge Device Initialization system to your infrastructure.

## Quick Start

1. **Deploy to PXE Server**:
   ```bash
   cd deployment/
   ./deploy-to-pxe-server.sh --host your-pxe-server
   ```

2. **Create Bootable Device**:
   ```bash
   cd deployment/
   ./write-to-device.sh /dev/sdX
   ```

3. **Configure Device**:
   - Boot device from network or storage
   - Use GRUB menu to configure and install OS

## Package Contents

- `pxe-server/`: Files for PXE server integration
- `deployment/`: Deployment and imaging scripts
- `config/`: Configuration templates and examples
- `documentation/`: Complete deployment documentation
- `scripts/`: Additional utility scripts

## Documentation

See `documentation/deployment-guide.md` for complete setup instructions.

## Support

For troubleshooting and support:
1. Check deployment-guide.md
2. Review script-api-reference.md
3. Use deployment-checklist.md for systematic verification
EOF
    
    # Create the package
    (cd "$BUILD_DIR" && tar -czf "$package_file" -C integration .)
    
    info "Deployment package created: $package_file"
    
    # Generate checksum
    local checksum_file="$package_file.sha256"
    sha256sum "$package_file" > "$checksum_file"
    
    info "Package checksum: $checksum_file"
    
    log "Deployment package generation completed"
}

# Save integration log
save_integration_log() {
    local log_file="$BUILD_LOG_DIR/$SCRIPT_NAME.log"
    
    cat > "$log_file" << EOF
# Integration Generation Log
# Generated by $SCRIPT_NAME v$SCRIPT_VERSION on $(date)

Build Configuration:
- Build Directory: $BUILD_DIR
- Integration Directory: $BUILD_DIR/integration

Artifacts Generated:
- PXE server integration files
- Deployment scripts (deploy-to-pxe-server.sh, write-to-device.sh)
- Configuration templates
- Documentation (deployment guide, API reference)
- Deployment package

Integration Files:
$(find "$BUILD_DIR/integration" -type f | sed 's|^|  |')

Deployment Package:
$(ls -la "$BUILD_DIR"/*.tar.gz 2>/dev/null | sed 's|^|  |' || echo "  No package created")

Integration completed: $(date)
Build process completed successfully!
EOF
    
    info "Integration log saved to $log_file"
}

# Main execution function
main() {
    show_header
    check_prerequisites
    create_integration_directories
    generate_pxe_integration
    generate_deployment_scripts
    generate_configuration_templates
    generate_documentation
    generate_deployment_package
    save_integration_log
    
    log "$SCRIPT_NAME completed successfully"
    info "All integration artifacts generated and packaged"
    
    echo
    log "BUILD PROCESS COMPLETED SUCCESSFULLY!"
    echo
    info "Generated artifacts:"
    info "  - Raw image: $BUILD_DIR/images/raw/edge-device-init.img"
    info "  - Compressed images: $BUILD_DIR/images/compressed/"
    info "  - PXE files: $BUILD_DIR/images/pxe/"
    info "  - Integration package: $BUILD_DIR/*.tar.gz"
    echo
    info "Next steps:"
    info "  1. Extract deployment package"
    info "  2. Customize configuration templates"
    info "  3. Deploy to PXE server or write to storage devices"
    info "  4. Follow deployment guide for complete setup"
    echo
    log "Edge Device Initialization system is ready for deployment!"
}

# Run main function
main "$@"
