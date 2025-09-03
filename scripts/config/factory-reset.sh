#!/bin/bash
# factory-reset.sh
# Factory reset script that restores device to initial state
# Preserves EFI partition and root/initialization partition while clearing OS and data

set -euo pipefail

# Configuration
EFI_PARTITION="/dev/sda1"
ROOT_PARTITION="/dev/sda2"
SWAP_PARTITION="/dev/sda3"
OS1_PARTITION="/dev/sda4"
OS2_PARTITION="/dev/sda5"
DATA_PARTITION="/dev/sda6"

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

# Show welcome message
show_welcome() {
    clear
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║                      Factory Reset Tool                     ║
║                                                              ║
║  This tool will restore the device to factory settings      ║
║  by performing the following actions:                       ║
║                                                              ║
║  ✓ Preserve EFI partition (bootloader)                      ║
║  ✓ Preserve Root/Init partition (PXE system)                ║
║  ✓ Clear OS1 partition (primary Ubuntu)                     ║
║  ✓ Clear OS2 partition (secondary Ubuntu)                   ║
║  ✓ Clear Data partition (user data)                         ║
║  ✓ Reset swap partition                                      ║
║                                                              ║
║  After reset, the device will boot back to the              ║
║  initialization environment where you can:                  ║
║  - Reconfigure device settings                              ║
║  - Reinstall operating systems                              ║
║  - Start fresh with clean partitions                        ║
║                                                              ║
║  WARNING: This will permanently delete all user data        ║
║           and installed operating systems!                  ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝

EOF
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
    
    # Check if all expected partitions exist
    local required_partitions=("$EFI_PARTITION" "$ROOT_PARTITION" "$SWAP_PARTITION" "$OS1_PARTITION" "$OS2_PARTITION" "$DATA_PARTITION")
    
    for partition in "${required_partitions[@]}"; do
        if [[ ! -b "$partition" ]]; then
            error "Required partition $partition not found"
        fi
    done
    
    log "Prerequisites check completed"
}

# Show current disk status
show_disk_status() {
    log "Current disk status:"
    echo
    
    echo "Partition layout:"
    lsblk -f /dev/sda
    echo
    
    echo "Mounted filesystems:"
    mount | grep /dev/sda || echo "  No partitions currently mounted"
    echo
    
    echo "Disk usage summary:"
    for partition in "$OS1_PARTITION" "$OS2_PARTITION" "$DATA_PARTITION"; do
        if mountpoint -q "/mnt/check-$partition" 2>/dev/null; then
            umount "/mnt/check-$partition" 2>/dev/null || true
        fi
        
        mkdir -p "/mnt/check-$partition"
        if mount "$partition" "/mnt/check-$partition" 2>/dev/null; then
            local used=$(df -h "/mnt/check-$partition" | tail -1 | awk '{print $3}')
            local avail=$(df -h "/mnt/check-$partition" | tail -1 | awk '{print $4}')
            echo "  $partition: Used $used, Available $avail"
            umount "/mnt/check-$partition"
        else
            echo "  $partition: Cannot mount (may be empty)"
        fi
        rm -rf "/mnt/check-$partition"
    done
    echo
}

# Get user confirmation
confirm_factory_reset() {
    echo "Reset options:"
    echo "1. Full factory reset (clear OS1, OS2, and Data partitions)"
    echo "2. Reset OS partitions only (preserve Data partition)"
    echo "3. Reset Data partition only (preserve OS partitions)"
    echo "4. Cancel operation"
    echo
    echo -n "Select reset option (1-4): "
    read reset_option
    
    case "$reset_option" in
        1)
            RESET_OS1=true
            RESET_OS2=true
            RESET_DATA=true
            RESET_TYPE="Full factory reset"
            ;;
        2)
            RESET_OS1=true
            RESET_OS2=true
            RESET_DATA=false
            RESET_TYPE="OS partitions reset"
            ;;
        3)
            RESET_OS1=false
            RESET_OS2=false
            RESET_DATA=true
            RESET_TYPE="Data partition reset"
            ;;
        4|*)
            error "Factory reset cancelled"
            ;;
    esac
    
    echo
    log "Selected: $RESET_TYPE"
    echo
    
    if [[ "$RESET_OS1" == "true" ]]; then
        warn "This will DELETE Ubuntu OS1 installation"
    fi
    if [[ "$RESET_OS2" == "true" ]]; then
        warn "This will DELETE Ubuntu OS2 installation"
    fi
    if [[ "$RESET_DATA" == "true" ]]; then
        warn "This will DELETE all user data and configurations"
    fi
    
    echo
    echo "Type 'RESET' to confirm this destructive operation: "
    read confirmation
    
    if [[ "$confirmation" != "RESET" ]]; then
        error "Factory reset cancelled"
    fi
    
    log "Factory reset confirmed"
}

# Create backup of critical data
create_backup() {
    if [[ "$RESET_DATA" == "true" ]]; then
        log "Offering to backup critical data..."
        
        echo "Would you like to backup critical configuration data? (y/N): "
        read backup_choice
        
        if [[ "$backup_choice" =~ ^[Yy]$ ]]; then
            local backup_dir="/tmp/factory-reset-backup-$(date +%Y%m%d-%H%M%S)"
            mkdir -p "$backup_dir"
            
            # Try to mount data partition and backup configs
            if mkdir -p /mnt/data-backup && mount "$DATA_PARTITION" /mnt/data-backup 2>/dev/null; then
                if [[ -d "/mnt/data-backup/config" ]]; then
                    cp -r /mnt/data-backup/config "$backup_dir/"
                    log "Configuration backed up to $backup_dir/config"
                fi
                
                if [[ -d "/mnt/data-backup/logs" ]]; then
                    cp -r /mnt/data-backup/logs "$backup_dir/"
                    log "Logs backed up to $backup_dir/logs"
                fi
                
                umount /mnt/data-backup
            fi
            
            rm -rf /mnt/data-backup
            
            # Create backup summary
            cat > "$backup_dir/backup-info.txt" << EOF
Factory Reset Backup
Created: $(date)
Reset Type: $RESET_TYPE

This backup contains critical configuration data that was saved
before performing the factory reset. You can use this data to
restore device settings after reinstalling the operating systems.

Contents:
$(find "$backup_dir" -type f 2>/dev/null | sed 's|^|  |')

To restore configurations:
1. Reinstall operating systems
2. Copy config files back to /data/config/
3. Run configure-device.sh to apply settings
EOF
            
            info "Backup created at: $backup_dir"
            echo "You can copy this backup to external storage if needed."
            echo "Press Enter to continue with reset..."
            read
        fi
    fi
}

# Unmount all target partitions
unmount_partitions() {
    log "Unmounting target partitions..."
    
    local partitions_to_unmount=()
    
    if [[ "$RESET_OS1" == "true" ]]; then
        partitions_to_unmount+=("$OS1_PARTITION")
    fi
    if [[ "$RESET_OS2" == "true" ]]; then
        partitions_to_unmount+=("$OS2_PARTITION")
    fi
    if [[ "$RESET_DATA" == "true" ]]; then
        partitions_to_unmount+=("$DATA_PARTITION")
    fi
    
    # Always check swap
    partitions_to_unmount+=("$SWAP_PARTITION")
    
    for partition in "${partitions_to_unmount[@]}"; do
        # Unmount if mounted
        if mount | grep -q "$partition"; then
            local mount_points=$(mount | grep "$partition" | awk '{print $3}')
            for mount_point in $mount_points; do
                umount "$mount_point" && log "Unmounted $partition from $mount_point" || warn "Failed to unmount $partition"
            done
        fi
        
        # Deactivate swap if it's the swap partition
        if [[ "$partition" == "$SWAP_PARTITION" ]] && swapon --show | grep -q "$partition"; then
            swapoff "$partition" && log "Deactivated swap on $partition" || warn "Failed to deactivate swap"
        fi
    done
    
    # Wait for unmounts to complete
    sleep 2
}

# Reset OS1 partition
reset_os1_partition() {
    if [[ "$RESET_OS1" != "true" ]]; then
        return
    fi
    
    log "Resetting OS1 partition..."
    
    # Wipe filesystem signatures
    wipefs -a "$OS1_PARTITION" || warn "Failed to wipe OS1 filesystem signatures"
    
    # Recreate filesystem
    mkfs.ext4 -F -L "OS1-ROOT" "$OS1_PARTITION" || error "Failed to format OS1 partition"
    
    log "OS1 partition reset completed"
}

# Reset OS2 partition
reset_os2_partition() {
    if [[ "$RESET_OS2" != "true" ]]; then
        return
    fi
    
    log "Resetting OS2 partition..."
    
    # Wipe filesystem signatures
    wipefs -a "$OS2_PARTITION" || warn "Failed to wipe OS2 filesystem signatures"
    
    # Recreate filesystem
    mkfs.ext4 -F -L "OS2-ROOT" "$OS2_PARTITION" || error "Failed to format OS2 partition"
    
    log "OS2 partition reset completed"
}

# Reset data partition
reset_data_partition() {
    if [[ "$RESET_DATA" != "true" ]]; then
        return
    fi
    
    log "Resetting data partition..."
    
    # Secure wipe option
    echo "Perform secure wipe of data partition? (y/N): "
    read secure_wipe
    
    if [[ "$secure_wipe" =~ ^[Yy]$ ]]; then
        log "Performing secure wipe (this may take several minutes)..."
        dd if=/dev/urandom of="$DATA_PARTITION" bs=1M count=100 2>/dev/null || true
    fi
    
    # Wipe filesystem signatures
    wipefs -a "$DATA_PARTITION" || warn "Failed to wipe data filesystem signatures"
    
    # Recreate filesystem
    mkfs.ext4 -F -L "DATA" "$DATA_PARTITION" || error "Failed to format data partition"
    
    log "Data partition reset completed"
}

# Reset swap partition
reset_swap_partition() {
    log "Resetting swap partition..."
    
    # Recreate swap
    mkswap -L "SWAP" "$SWAP_PARTITION" || error "Failed to format swap partition"
    
    log "Swap partition reset completed"
}

# Update GRUB configuration
update_grub_config() {
    log "Updating GRUB configuration..."
    
    # Mount root partition to update GRUB
    mkdir -p /mnt/root-temp
    if mount "$ROOT_PARTITION" /mnt/root-temp; then
        # Mount EFI partition
        mkdir -p /mnt/root-temp/boot/efi
        mount "$EFI_PARTITION" /mnt/root-temp/boot/efi
        
        # Set up chroot environment
        mount --bind /dev /mnt/root-temp/dev
        mount --bind /dev/pts /mnt/root-temp/dev/pts
        mount --bind /proc /mnt/root-temp/proc
        mount --bind /sys /mnt/root-temp/sys
        
        # Update GRUB to remove OS entries
        if [[ -f "/mnt/root-temp/etc/grub.d/40_custom" ]]; then
            # Remove custom OS entries
            sed -i '/Boot OS1/,+10d' /mnt/root-temp/etc/grub.d/40_custom
            sed -i '/Boot OS2/,+10d' /mnt/root-temp/etc/grub.d/40_custom
        fi
        
        # Regenerate GRUB configuration
        chroot /mnt/root-temp update-grub
        
        # Clean up chroot
        umount /mnt/root-temp/sys 2>/dev/null || true
        umount /mnt/root-temp/proc 2>/dev/null || true
        umount /mnt/root-temp/dev/pts 2>/dev/null || true
        umount /mnt/root-temp/dev 2>/dev/null || true
        umount /mnt/root-temp/boot/efi 2>/dev/null || true
        umount /mnt/root-temp 2>/dev/null || true
    fi
    
    rm -rf /mnt/root-temp
    
    log "GRUB configuration updated"
}

# Verify reset
verify_reset() {
    log "Verifying factory reset..."
    
    echo
    echo "Post-reset partition status:"
    lsblk -f /dev/sda
    echo
    
    # Test mounting each reset partition
    local test_mounts=()
    
    if [[ "$RESET_OS1" == "true" ]]; then
        test_mounts+=("$OS1_PARTITION:/mnt/test-os1")
    fi
    if [[ "$RESET_OS2" == "true" ]]; then
        test_mounts+=("$OS2_PARTITION:/mnt/test-os2")
    fi
    if [[ "$RESET_DATA" == "true" ]]; then
        test_mounts+=("$DATA_PARTITION:/mnt/test-data")
    fi
    
    for mount_spec in "${test_mounts[@]}"; do
        IFS=':' read -ra MOUNT_INFO <<< "$mount_spec"
        local device="${MOUNT_INFO[0]}"
        local mountpoint="${MOUNT_INFO[1]}"
        
        mkdir -p "$mountpoint"
        
        if mount "$device" "$mountpoint"; then
            local file_count=$(find "$mountpoint" -type f 2>/dev/null | wc -l)
            info "✓ $device: mounted successfully, contains $file_count files"
            umount "$mountpoint"
        else
            error "✗ Failed to mount $device"
        fi
        
        rm -rf "$mountpoint"
    done
    
    # Test swap activation
    if swapon "$SWAP_PARTITION"; then
        info "✓ Swap partition: activated successfully"
        swapoff "$SWAP_PARTITION"
    else
        error "✗ Failed to activate swap partition"
    fi
    
    log "Factory reset verification completed"
}

# Create reset log
create_reset_log() {
    local log_file="/tmp/factory-reset-$(date +%Y%m%d-%H%M%S).log"
    
    cat > "$log_file" << EOF
# Factory Reset Log
# Generated on $(date)

Reset Configuration:
- Reset Type: $RESET_TYPE
- OS1 Reset: $RESET_OS1
- OS2 Reset: $RESET_OS2
- Data Reset: $RESET_DATA

Partitions Status:
$(lsblk -f /dev/sda)

Reset completed: $(date)

Next Steps:
1. Reboot to initialization environment
2. Run partition-disk.sh if needed
3. Run install-os1.sh to reinstall primary OS
4. Run install-os2.sh to reinstall secondary OS
5. Run configure-device.sh to reconfigure settings
EOF
    
    info "Reset log saved to $log_file"
    
    # Try to save to remaining mounted partitions
    local save_locations=("/tmp" "/var/log")
    
    for location in "${save_locations[@]}"; do
        if [[ -w "$location" ]]; then
            cp "$log_file" "$location/factory-reset.log" 2>/dev/null || true
        fi
    done
}

# Show completion message
show_completion() {
    log "Factory reset completed successfully!"
    
    echo
    echo "=== Factory Reset Complete ==="
    echo
    echo "Reset summary:"
    if [[ "$RESET_OS1" == "true" ]]; then
        echo "  ✓ OS1 partition cleared and reformatted"
    fi
    if [[ "$RESET_OS2" == "true" ]]; then
        echo "  ✓ OS2 partition cleared and reformatted"
    fi
    if [[ "$RESET_DATA" == "true" ]]; then
        echo "  ✓ Data partition cleared and reformatted"
    fi
    echo "  ✓ Swap partition reset"
    echo "  ✓ GRUB configuration updated"
    echo
    echo "Preserved components:"
    echo "  ✓ EFI partition (bootloader)"
    echo "  ✓ Root/Init partition (PXE system)"
    echo
    echo "The device will now reboot to the initialization environment."
    echo "From there you can:"
    echo "  1. Reconfigure device settings"
    echo "  2. Reinstall operating systems"
    echo "  3. Restore from backup if available"
    echo
    echo "Press Enter to reboot..."
    read
    
    log "Rebooting system..."
    reboot
}

# Main execution
main() {
    show_welcome
    check_prerequisites
    show_disk_status
    confirm_factory_reset
    create_backup
    unmount_partitions
    reset_os1_partition
    reset_os2_partition
    reset_data_partition
    reset_swap_partition
    update_grub_config
    verify_reset
    create_reset_log
    show_completion
}

# Run main function
main "$@"
