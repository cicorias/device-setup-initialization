#!/bin/bash
# 04-grub-configuration.sh
# Configure GRUB2 bootloader with enhanced menu system
# Part of the device initialization build process

set -euo pipefail

# Script configuration
SCRIPT_NAME="04-grub-configuration"
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
    info "Configuring GRUB2 bootloader with enhanced menu system"
}

# Check prerequisites from previous script
check_prerequisites() {
    log "Checking prerequisites from previous build stages..."
    
    # Check that package installation completed
    if [[ ! -f "$BUILD_LOG_DIR/03-package-installation.log" ]]; then
        error "Package installation script has not completed successfully"
    fi
    
    # Check rootfs exists
    if [[ ! -d "$BUILD_DIR/rootfs" ]]; then
        error "Root filesystem directory not found"
    fi
    
    # Check GRUB is installed
    if ! chroot "$BUILD_DIR/rootfs" which grub-install &>/dev/null; then
        error "GRUB not found in rootfs"
    fi
    
    log "Prerequisites check completed"
}

# Setup chroot environment
setup_chroot_environment() {
    log "Setting up chroot environment for GRUB configuration..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    
    # Mount necessary filesystems if not already mounted
    if ! mountpoint -q "$root_fs_dir/dev"; then
        mount --bind /dev "$root_fs_dir/dev"
    fi
    if ! mountpoint -q "$root_fs_dir/dev/pts"; then
        mount --bind /dev/pts "$root_fs_dir/dev/pts"
    fi
    if ! mountpoint -q "$root_fs_dir/proc"; then
        mount --bind /proc "$root_fs_dir/proc"
    fi
    if ! mountpoint -q "$root_fs_dir/sys"; then
        mount --bind /sys "$root_fs_dir/sys"
    fi
    
    log "Chroot environment ready"
}

# Configure GRUB defaults
configure_grub_defaults() {
    log "Configuring GRUB default settings..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    
    # Create GRUB default configuration
    cat > "$root_fs_dir/etc/default/grub" << EOF
# GRUB configuration for edge device initialization system
GRUB_DEFAULT=0
GRUB_TIMEOUT=30
GRUB_DISTRIBUTOR="Edge Device Initialization"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""

# Terminal configuration
GRUB_TERMINAL_OUTPUT="console"
GRUB_TERMINAL_INPUT="console"

# Menu configuration
GRUB_DISABLE_SUBMENU=y
GRUB_DISABLE_RECOVERY="true"

# Boot options
GRUB_TIMEOUT_STYLE=menu
GRUB_RECORDFAIL_TIMEOUT=30

# Graphics configuration
GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep

# Security
GRUB_DISABLE_OS_PROBER="true"
EOF
    
    log "GRUB defaults configured"
}

# Create enhanced GRUB menu
create_enhanced_grub_menu() {
    log "Creating enhanced GRUB menu with device management options..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    
    # Create custom GRUB menu entries
    cat > "$root_fs_dir/etc/grub.d/40_custom" << 'EOF'
#!/bin/sh
exec tail -n +3 $0
# Custom GRUB menu entries for edge device management

# Device Configuration Menu Entry
menuentry 'Configure Device' --class ubuntu --class gnu-linux --class gnu --class os {
    echo 'Loading device configuration utility...'
    set root='hd0,gpt2'
    linux /boot/vmlinuz root=UUID=__ROOT_UUID__ ro quiet splash init=/usr/local/bin/configure-device.sh
    initrd /boot/initrd.img
}

# Disk Partitioning Menu Entry
menuentry 'Partition Disk' --class ubuntu --class gnu-linux --class gnu --class os {
    echo 'Loading disk partitioning utility...'
    set root='hd0,gpt2'
    linux /boot/vmlinuz root=UUID=__ROOT_UUID__ ro quiet splash init=/usr/local/bin/partition-disk.sh
    initrd /boot/initrd.img
}

# OS1 Installation Menu Entry
menuentry 'Install OS1 (Primary Ubuntu)' --class ubuntu --class gnu-linux --class gnu --class os {
    echo 'Loading OS1 installation utility...'
    set root='hd0,gpt2'
    linux /boot/vmlinuz root=UUID=__ROOT_UUID__ ro quiet splash init=/usr/local/bin/install-os1.sh
    initrd /boot/initrd.img
}

# OS2 Installation Menu Entry
menuentry 'Install OS2 (Secondary Ubuntu)' --class ubuntu --class gnu-linux --class gnu --class os {
    echo 'Loading OS2 installation utility...'
    set root='hd0,gpt2'
    linux /boot/vmlinuz root=UUID=__ROOT_UUID__ ro quiet splash init=/usr/local/bin/install-os2.sh
    initrd /boot/initrd.img
}

# Boot OS1 Menu Entry (will be populated after OS1 installation)
menuentry 'Boot OS1 (Primary Ubuntu)' --class ubuntu --class gnu-linux --class gnu --class os {
    echo 'Booting Ubuntu OS1...'
    set root='hd0,gpt4'
    linux /boot/vmlinuz root=UUID=__OS1_UUID__ ro quiet splash
    initrd /boot/initrd.img
}

# Boot OS2 Menu Entry (will be populated after OS2 installation)
menuentry 'Boot OS2 (Secondary Ubuntu)' --class ubuntu --class gnu-linux --class gnu --class os {
    echo 'Booting Ubuntu OS2...'
    set root='hd0,gpt5'
    linux /boot/vmlinuz root=UUID=__OS2_UUID__ ro quiet splash
    initrd /boot/initrd.img
}

# Factory Reset Menu Entry
menuentry 'Factory Reset' --class ubuntu --class gnu-linux --class gnu --class os {
    echo 'Loading factory reset utility...'
    set root='hd0,gpt2'
    linux /boot/vmlinuz root=UUID=__ROOT_UUID__ ro quiet splash init=/usr/local/bin/factory-reset.sh
    initrd /boot/initrd.img
}

# Advanced Options Submenu
submenu 'Advanced Options' {
    
    # Boot to Shell
    menuentry 'Boot to Emergency Shell' --class ubuntu --class gnu-linux --class gnu --class os {
        echo 'Booting to emergency shell...'
        set root='hd0,gpt2'
        linux /boot/vmlinuz root=UUID=__ROOT_UUID__ ro quiet splash init=/bin/bash
        initrd /boot/initrd.img
    }
    
    # Boot with Network Debugging
    menuentry 'Boot with Network Debugging' --class ubuntu --class gnu-linux --class gnu --class os {
        echo 'Booting with network debugging...'
        set root='hd0,gpt2'
        linux /boot/vmlinuz root=UUID=__ROOT_UUID__ ro debug systemd.log_level=debug systemd.log_target=console
        initrd /boot/initrd.img
    }
    
    # Memory Test
    menuentry 'Memory Test (memtest86+)' {
        linux16 /boot/memtest86+.bin
    }
    
    # Hardware Detection
    menuentry 'Hardware Detection Mode' --class ubuntu --class gnu-linux --class gnu --class os {
        echo 'Booting in hardware detection mode...'
        set root='hd0,gpt2'
        linux /boot/vmlinuz root=UUID=__ROOT_UUID__ ro quiet splash systemd.unit=multi-user.target
        initrd /boot/initrd.img
    }
}

# System Information Menu Entry
menuentry 'System Information' --class ubuntu --class gnu-linux --class gnu --class os {
    echo 'Loading system information...'
    set root='hd0,gpt2'
    linux /boot/vmlinuz root=UUID=__ROOT_UUID__ ro quiet splash init=/usr/local/bin/show-system-info.sh
    initrd /boot/initrd.img
}
EOF
    
    chmod +x "$root_fs_dir/etc/grub.d/40_custom"
    
    log "Enhanced GRUB menu created"
}

# Create system information script
create_system_info_script() {
    log "Creating system information display script..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    
    cat > "$root_fs_dir/usr/local/bin/show-system-info.sh" << 'EOF'
#!/bin/bash
# System information display script

clear
cat << 'INFO_EOF'
╔══════════════════════════════════════════════════════════════╗
║                    Edge Device System Information           ║
╚══════════════════════════════════════════════════════════════╝

Hardware Information:
INFO_EOF

echo "CPU: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
echo "Memory: $(free -h | grep '^Mem:' | awk '{print $2}')"
echo "Storage: $(lsblk -d -o NAME,SIZE | grep -E '^sd|^nvme' | head -1 | awk '{print $2}')"

echo
echo "Network Interfaces:"
ip link show | grep -E '^[0-9]+:' | awk -F: '{print "  " $2}' | grep -v lo

echo
echo "Partition Layout:"
lsblk -f 2>/dev/null || echo "  Unable to read partition information"

echo
echo "Boot Information:"
echo "  Boot Mode: $([ -d /sys/firmware/efi ] && echo "UEFI" || echo "Legacy")"
echo "  Kernel: $(uname -r)"
echo "  Uptime: $(uptime -p)"

echo
echo "Device Status:"
echo "  Build Date: $(stat -c %y /usr/local/bin/configure-device.sh 2>/dev/null | cut -d' ' -f1 || echo "Unknown")"
echo "  Initialization: $([ -f /data/config/device.conf ] && echo "Configured" || echo "Not configured")"

echo
echo "Available Actions:"
echo "  1. Configure Device Settings"
echo "  2. Partition Disk"
echo "  3. Install Operating Systems"
echo "  4. Boot into OS1 or OS2"
echo "  5. Factory Reset"

echo
echo "Press any key to return to GRUB menu..."
read -n 1 -s
exec /sbin/reboot
EOF
    
    chmod +x "$root_fs_dir/usr/local/bin/show-system-info.sh"
    
    log "System information script created"
}

# Create GRUB theme
create_grub_theme() {
    log "Creating GRUB theme for edge device..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    local theme_dir="$root_fs_dir/boot/grub/themes/edge-device"
    
    mkdir -p "$theme_dir"
    
    # Create theme configuration
    cat > "$theme_dir/theme.txt" << EOF
# Edge Device GRUB Theme
title-text: "Edge Device Initialization System"
title-font: "DejaVu Sans Bold 16"
title-color: "#ffffff"

desktop-image: "background.png"
desktop-color: "#000000"

terminal-box: "terminal_box_*.png"
terminal-font: "DejaVu Sans Mono 12"

+ boot_menu {
    left = 20%
    top = 30%
    width = 60%
    height = 50%
    
    item_font = "DejaVu Sans 14"
    item_color = "#cccccc"
    selected_item_color = "#ffffff"
    selected_item_pixmap_style = "select_*.png"
    
    item_height = 30
    item_padding = 10
    item_spacing = 5
    
    scrollbar = true
    scrollbar_width = 20
    scrollbar_thumb = "scrollbar_thumb_*.png"
}

+ progress_bar {
    id = "__timeout__"
    left = 20%
    top = 85%
    width = 60%
    height = 20
    
    fg_color = "#ffffff"
    bg_color = "#666666"
    border_color = "#ffffff"
    
    font = "DejaVu Sans 12"
    text_color = "#ffffff"
    text = "Timeout: %d seconds remaining"
}
EOF
    
    # Create simple background (placeholder)
    # In a real implementation, you would copy actual image files
    touch "$theme_dir/background.png"
    touch "$theme_dir/select_c.png"
    touch "$theme_dir/select_e.png"
    touch "$theme_dir/select_w.png"
    touch "$theme_dir/terminal_box_c.png"
    touch "$theme_dir/terminal_box_e.png"
    touch "$theme_dir/terminal_box_w.png"
    touch "$theme_dir/scrollbar_thumb_c.png"
    touch "$theme_dir/scrollbar_thumb_n.png"
    touch "$theme_dir/scrollbar_thumb_s.png"
    
    # Update GRUB configuration to use theme
    cat >> "$root_fs_dir/etc/default/grub" << EOF

# Theme configuration
GRUB_THEME="/boot/grub/themes/edge-device/theme.txt"
EOF
    
    log "GRUB theme created"
}

# Create UUID placeholder replacement script
create_uuid_replacement_script() {
    log "Creating UUID placeholder replacement script..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    
    cat > "$root_fs_dir/usr/local/bin/update-grub-uuids.sh" << 'EOF'
#!/bin/bash
# Update GRUB configuration with actual partition UUIDs

set -euo pipefail

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

update_grub_uuids() {
    log "Updating GRUB configuration with partition UUIDs..."
    
    # Get partition UUIDs
    local root_uuid=$(blkid -s UUID -o value /dev/sda2 2>/dev/null || echo "")
    local os1_uuid=$(blkid -s UUID -o value /dev/sda4 2>/dev/null || echo "")
    local os2_uuid=$(blkid -s UUID -o value /dev/sda5 2>/dev/null || echo "")
    
    # Update GRUB custom menu
    if [[ -f /etc/grub.d/40_custom ]]; then
        sed -i "s/__ROOT_UUID__/$root_uuid/g" /etc/grub.d/40_custom
        sed -i "s/__OS1_UUID__/$os1_uuid/g" /etc/grub.d/40_custom
        sed -i "s/__OS2_UUID__/$os2_uuid/g" /etc/grub.d/40_custom
        
        log "GRUB UUIDs updated:"
        log "  Root UUID: $root_uuid"
        log "  OS1 UUID: $os1_uuid"
        log "  OS2 UUID: $os2_uuid"
        
        # Regenerate GRUB configuration
        update-grub
        
        log "GRUB configuration regenerated"
    else
        log "ERROR: GRUB custom configuration not found"
        exit 1
    fi
}

# Main execution
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

update_grub_uuids
EOF
    
    chmod +x "$root_fs_dir/usr/local/bin/update-grub-uuids.sh"
    
    log "UUID replacement script created"
}

# Install GRUB configuration
install_grub_configuration() {
    log "Installing GRUB configuration..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    
    # Generate initial GRUB configuration
    chroot "$root_fs_dir" update-grub || warn "Failed to generate GRUB configuration"
    
    # Create GRUB installation script for later use
    cat > "$root_fs_dir/usr/local/bin/install-grub-efi.sh" << 'EOF'
#!/bin/bash
# Install GRUB to EFI partition

set -euo pipefail

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

install_grub_efi() {
    log "Installing GRUB to EFI partition..."
    
    # Check if EFI partition is mounted
    if ! mountpoint -q /boot/efi; then
        log "Mounting EFI partition..."
        mount /dev/sda1 /boot/efi || {
            log "ERROR: Failed to mount EFI partition"
            exit 1
        }
    fi
    
    # Install GRUB
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=EdgeDevice --recheck || {
        log "ERROR: GRUB installation failed"
        exit 1
    }
    
    # Update GRUB configuration
    update-grub || {
        log "ERROR: GRUB configuration update failed"
        exit 1
    }
    
    log "GRUB installation completed successfully"
}

# Main execution
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

install_grub_efi
EOF
    
    chmod +x "$root_fs_dir/usr/local/bin/install-grub-efi.sh"
    
    log "GRUB configuration installed"
}

# Create GRUB recovery tools
create_grub_recovery_tools() {
    log "Creating GRUB recovery tools..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    
    # Create GRUB rescue script
    cat > "$root_fs_dir/usr/local/bin/grub-rescue.sh" << 'EOF'
#!/bin/bash
# GRUB rescue and repair utility

set -euo pipefail

show_menu() {
    clear
    cat << 'MENU_EOF'
╔══════════════════════════════════════════════════════════════╗
║                     GRUB Rescue Utility                     ║
╚══════════════════════════════════════════════════════════════╝

1. Reinstall GRUB to EFI partition
2. Regenerate GRUB configuration
3. Update partition UUIDs
4. Boot repair (fix boot issues)
5. Reset GRUB to defaults
6. Exit

Select an option (1-6): 
MENU_EOF
}

reinstall_grub() {
    echo "Reinstalling GRUB..."
    /usr/local/bin/install-grub-efi.sh
}

regenerate_config() {
    echo "Regenerating GRUB configuration..."
    update-grub
}

update_uuids() {
    echo "Updating partition UUIDs..."
    /usr/local/bin/update-grub-uuids.sh
}

boot_repair() {
    echo "Performing boot repair..."
    # Comprehensive boot repair
    mount /dev/sda1 /boot/efi 2>/dev/null || true
    reinstall_grub
    regenerate_config
    update_uuids
}

reset_grub() {
    echo "Resetting GRUB to defaults..."
    cp /etc/default/grub.backup /etc/default/grub 2>/dev/null || true
    cp /etc/grub.d/40_custom.backup /etc/grub.d/40_custom 2>/dev/null || true
    regenerate_config
}

# Main menu loop
while true; do
    show_menu
    read -r choice
    
    case $choice in
        1) reinstall_grub ;;
        2) regenerate_config ;;
        3) update_uuids ;;
        4) boot_repair ;;
        5) reset_grub ;;
        6) exit 0 ;;
        *) echo "Invalid option. Please try again." ;;
    esac
    
    echo
    echo "Press Enter to continue..."
    read
done
EOF
    
    chmod +x "$root_fs_dir/usr/local/bin/grub-rescue.sh"
    
    log "GRUB recovery tools created"
}

# Save configuration log
save_configuration_log() {
    local log_file="$BUILD_LOG_DIR/$SCRIPT_NAME.log"
    
    cat > "$log_file" << EOF
# GRUB Configuration Log
# Generated by $SCRIPT_NAME v$SCRIPT_VERSION on $(date)

Build Configuration:
- Build Directory: $BUILD_DIR
- Root Filesystem: $BUILD_DIR/rootfs

GRUB Configuration:
- Default timeout: 30 seconds
- Theme: Edge Device custom theme
- Menu entries: Device management options
- Recovery tools: Available
- UUID placeholders: Will be replaced during installation

Menu Entries Created:
- Configure Device
- Partition Disk
- Install OS1 (Primary Ubuntu)
- Install OS2 (Secondary Ubuntu)
- Boot OS1 (Primary Ubuntu)
- Boot OS2 (Secondary Ubuntu)
- Factory Reset
- Advanced Options (submenu)
- System Information

Utilities Created:
- update-grub-uuids.sh
- install-grub-efi.sh
- grub-rescue.sh
- show-system-info.sh

Configuration completed: $(date)
Next step: Run 05-image-creation.sh
EOF
    
    info "Configuration log saved to $log_file"
}

# Main execution function
main() {
    show_header
    check_prerequisites
    setup_chroot_environment
    configure_grub_defaults
    create_enhanced_grub_menu
    create_system_info_script
    create_grub_theme
    create_uuid_replacement_script
    install_grub_configuration
    create_grub_recovery_tools
    save_configuration_log
    
    log "$SCRIPT_NAME completed successfully"
    info "GRUB bootloader configured with enhanced menu system"
    info "Next: Run 05-image-creation.sh"
}

# Run main function
main "$@"
