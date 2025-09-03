#!/bin/bash
# partition-disk.sh
# Automatic disk partitioning script following PXE server instructions
# Creates 6-partition layout: EFI, Root, Swap, OS1, OS2, Data

set -euo pipefail

# Default configuration
DISK="/dev/sda"  # Default target disk
EFI_SIZE="200M"
ROOT_SIZE="2G"
SWAP_SIZE="4G"
OS1_SIZE="3.7G"
OS2_SIZE="3.7G"

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
║                    Disk Partitioning Tool                   ║
║                                                              ║
║  This tool will create the 6-partition layout required      ║
║  for edge device operation:                                  ║
║                                                              ║
║  1. EFI System Partition (200MB) - UEFI bootloader          ║
║  2. Root Partition (2GB) - initialization system            ║
║  3. Swap Partition (4GB) - virtual memory                   ║
║  4. OS1 Partition (3.7GB) - Ubuntu 24.04.3 LTS primary     ║
║  5. OS2 Partition (3.7GB) - Ubuntu 24.04.3 LTS secondary   ║
║  6. Data Partition (remaining) - persistent data            ║
║                                                              ║
║  WARNING: This will DESTROY all data on the target disk!    ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝

EOF
}

# Detect available disks
detect_disks() {
    log "Detecting available disks..."
    
    echo "Available storage devices:"
    echo
    lsblk -d -o NAME,SIZE,MODEL,TYPE | grep -E "disk|nvme" | while read -r line; do
        echo "  $line"
    done
    echo
}

# Select target disk
select_disk() {
    detect_disks
    
    echo "Current target disk: $DISK"
    echo -n "Press Enter to use $DISK or enter new disk path: "
    read user_disk
    
    if [[ -n "$user_disk" ]]; then
        DISK="$user_disk"
    fi
    
    # Validate disk exists
    if [[ ! -b "$DISK" ]]; then
        error "Disk $DISK not found or not a block device"
    fi
    
    # Check if disk is mounted
    if mount | grep -q "$DISK"; then
        warn "Disk $DISK has mounted partitions"
        echo "Mounted partitions:"
        mount | grep "$DISK" | while read -r line; do
            echo "  $line"
        done
        echo
        echo "Continue anyway? (y/N): "
        read continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            error "Operation cancelled"
        fi
    fi
    
    log "Selected disk: $DISK"
    log "Disk size: $(lsblk -d -o SIZE --noheadings "$DISK")"
}

# Show disk information
show_disk_info() {
    log "Disk information for $DISK:"
    echo
    
    # Show current partition table if exists
    if parted "$DISK" print 2>/dev/null | grep -q "Partition Table"; then
        echo "Current partition table:"
        parted "$DISK" print 2>/dev/null || echo "  Unable to read partition table"
    else
        echo "No existing partition table found"
    fi
    echo
    
    # Show disk geometry
    echo "Disk geometry:"
    fdisk -l "$DISK" 2>/dev/null | head -10 || echo "  Unable to read disk geometry"
    echo
}

# Confirm partitioning
confirm_partitioning() {
    log "Partition layout preview:"
    echo
    echo "  Partition 1: EFI System Partition - $EFI_SIZE (FAT32)"
    echo "  Partition 2: Root/Init Partition - $ROOT_SIZE (ext4)"
    echo "  Partition 3: Swap Partition - $SWAP_SIZE (swap)"
    echo "  Partition 4: OS1 Partition - $OS1_SIZE (ext4)"
    echo "  Partition 5: OS2 Partition - $OS2_SIZE (ext4)"
    echo "  Partition 6: Data Partition - remaining space (ext4)"
    echo
    
    local total_fixed=$(echo "$EFI_SIZE + $ROOT_SIZE + $SWAP_SIZE + $OS1_SIZE + $OS2_SIZE" | \
                       sed 's/G/ * 1024/g; s/M//g' | bc)
    local disk_size_mb=$(lsblk -d -o SIZE --noheadings --bytes "$DISK" | awk '{print int($1/1024/1024)}')
    local data_size_mb=$((disk_size_mb - total_fixed))
    
    echo "  Total fixed partitions: ${total_fixed}MB"
    echo "  Data partition size: ${data_size_mb}MB"
    echo "  Total disk size: ${disk_size_mb}MB"
    echo
    
    if [[ $data_size_mb -lt 1024 ]]; then
        warn "Data partition will be very small (< 1GB)"
    fi
    
    echo "WARNING: This will COMPLETELY ERASE all data on $DISK"
    echo "Type 'YES' to proceed with partitioning: "
    read confirmation
    
    if [[ "$confirmation" != "YES" ]]; then
        error "Partitioning cancelled"
    fi
}

# Unmount existing partitions
unmount_partitions() {
    log "Unmounting any existing partitions on $DISK..."
    
    # Find and unmount all partitions on the disk
    for partition in $(lsblk -ln -o NAME "$DISK" | tail -n +2); do
        local dev="/dev/$partition"
        if mountpoint -q "/mnt/$partition" 2>/dev/null; then
            umount "/mnt/$partition" && log "Unmounted $dev" || warn "Failed to unmount $dev"
        fi
        if mount | grep -q "$dev"; then
            umount "$dev" && log "Unmounted $dev" || warn "Failed to unmount $dev"
        fi
    done
    
    # Deactivate any swap on the disk
    for partition in $(lsblk -ln -o NAME "$DISK" | tail -n +2); do
        local dev="/dev/$partition"
        if swapon --show | grep -q "$dev"; then
            swapoff "$dev" && log "Deactivated swap on $dev" || warn "Failed to deactivate swap on $dev"
        fi
    done
}

# Create partition table
create_partitions() {
    log "Creating GPT partition table on $DISK..."
    
    # Clear existing partition signatures
    wipefs -a "$DISK" || warn "Failed to wipe filesystem signatures"
    
    # Create new GPT partition table
    parted -s "$DISK" mklabel gpt
    
    # Create partitions with calculated offsets
    log "Creating partitions..."
    
    # Partition 1: EFI System Partition (1MB to 201MB)
    parted -s "$DISK" mkpart primary fat32 1MiB 201MiB
    parted -s "$DISK" set 1 esp on
    parted -s "$DISK" set 1 boot on
    
    # Partition 2: Root/Init Partition (201MB to 2249MB)
    parted -s "$DISK" mkpart primary ext4 201MiB 2249MiB
    
    # Partition 3: Swap Partition (2249MB to 6345MB)
    parted -s "$DISK" mkpart primary linux-swap 2249MiB 6345MiB
    
    # Partition 4: OS1 Partition (6345MB to 10137MB)
    parted -s "$DISK" mkpart primary ext4 6345MiB 10137MiB
    
    # Partition 5: OS2 Partition (10137MB to 13929MB)
    parted -s "$DISK" mkpart primary ext4 10137MiB 13929MiB
    
    # Partition 6: Data Partition (13929MB to end)
    parted -s "$DISK" mkpart primary ext4 13929MiB 100%
    
    # Wait for kernel to recognize partitions
    partprobe "$DISK"
    sleep 2
    
    log "Partition table created successfully"
}

# Format partitions
format_partitions() {
    log "Formatting partitions..."
    
    # Format EFI partition (FAT32)
    mkfs.fat -F32 -n "EFI" "${DISK}1" || error "Failed to format EFI partition"
    info "Formatted EFI partition: ${DISK}1"
    
    # Format Root partition (ext4)
    mkfs.ext4 -F -L "INIT-ROOT" "${DISK}2" || error "Failed to format root partition"
    info "Formatted root partition: ${DISK}2"
    
    # Format Swap partition
    mkswap -L "SWAP" "${DISK}3" || error "Failed to format swap partition"
    info "Formatted swap partition: ${DISK}3"
    
    # Format OS1 partition (ext4)
    mkfs.ext4 -F -L "OS1-ROOT" "${DISK}4" || error "Failed to format OS1 partition"
    info "Formatted OS1 partition: ${DISK}4"
    
    # Format OS2 partition (ext4)
    mkfs.ext4 -F -L "OS2-ROOT" "${DISK}5" || error "Failed to format OS2 partition"
    info "Formatted OS2 partition: ${DISK}5"
    
    # Format Data partition (ext4)
    mkfs.ext4 -F -L "DATA" "${DISK}6" || error "Failed to format data partition"
    info "Formatted data partition: ${DISK}6"
}

# Verify partitions
verify_partitions() {
    log "Verifying partition layout..."
    
    echo
    echo "Final partition table:"
    parted "$DISK" print
    echo
    
    echo "Filesystem labels:"
    lsblk -f "$DISK"
    echo
    
    echo "Partition sizes:"
    lsblk -o NAME,SIZE,FSTYPE,LABEL "$DISK"
    echo
}

# Create mount points and test mounting
test_mounting() {
    log "Testing partition mounting..."
    
    local test_mounts=(
        "${DISK}1:/mnt/test-efi:vfat"
        "${DISK}2:/mnt/test-root:ext4"
        "${DISK}4:/mnt/test-os1:ext4"
        "${DISK}5:/mnt/test-os2:ext4"
        "${DISK}6:/mnt/test-data:ext4"
    )
    
    # Create mount points
    for mount_spec in "${test_mounts[@]}"; do
        IFS=':' read -ra MOUNT_INFO <<< "$mount_spec"
        local device="${MOUNT_INFO[0]}"
        local mountpoint="${MOUNT_INFO[1]}"
        local fstype="${MOUNT_INFO[2]}"
        
        mkdir -p "$mountpoint"
        
        if mount -t "$fstype" "$device" "$mountpoint"; then
            info "Successfully mounted $device at $mountpoint"
            umount "$mountpoint"
        else
            error "Failed to mount $device"
        fi
    done
    
    # Test swap activation
    if swapon "${DISK}3"; then
        info "Successfully activated swap partition"
        swapoff "${DISK}3"
    else
        error "Failed to activate swap partition"
    fi
    
    # Clean up test mount points
    rm -rf /mnt/test-*
}

# Save partitioning information
save_partition_info() {
    log "Saving partition information..."
    
    local info_file="/tmp/partition-info.txt"
    
    cat > "$info_file" << EOF
# Disk Partitioning Information
# Generated on $(date)
# Target disk: $DISK

# Partition Layout:
$(parted "$DISK" print)

# Filesystem Information:
$(lsblk -f "$DISK")

# Partition UUIDs:
$(blkid | grep "$DISK")

# Partitioning completed: $(date)
EOF
    
    info "Partition information saved to $info_file"
    
    # Try to save to data partition if it exists and is mounted
    if mkdir -p /mnt/data-temp && mount "${DISK}6" /mnt/data-temp 2>/dev/null; then
        mkdir -p /mnt/data-temp/logs
        cp "$info_file" /mnt/data-temp/logs/
        umount /mnt/data-temp
        info "Partition information also saved to data partition"
    fi
    
    rm -rf /mnt/data-temp
}

# Show completion message
show_completion() {
    log "Disk partitioning completed successfully!"
    
    echo
    echo "=== Partitioning Complete ==="
    echo
    echo "Your disk has been partitioned with the following layout:"
    echo "  ${DISK}1: EFI System Partition (200MB, FAT32)"
    echo "  ${DISK}2: Root/Init Partition (2GB, ext4)"
    echo "  ${DISK}3: Swap Partition (4GB, swap)"
    echo "  ${DISK}4: OS1 Partition (3.7GB, ext4)"
    echo "  ${DISK}5: OS2 Partition (3.7GB, ext4)"
    echo "  ${DISK}6: Data Partition (remaining, ext4)"
    echo
    echo "Next steps:"
    echo "1. Run 'install-os1' to install primary Ubuntu system"
    echo "2. Run 'install-os2' to install secondary Ubuntu system"
    echo "3. Configure device settings if needed"
    echo
    echo "The system is ready for OS installation."
    echo
    echo "Press Enter to continue..."
    read
}

# Main execution
main() {
    show_welcome
    select_disk
    show_disk_info
    confirm_partitioning
    unmount_partitions
    create_partitions
    format_partitions
    verify_partitions
    test_mounting
    save_partition_info
    show_completion
}

# Run main function
main "$@"
