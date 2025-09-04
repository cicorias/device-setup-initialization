#!/bin/bash
# 05-image-creation.sh
# Create bootable device images and filesystem artifacts
# Part of the device initialization build process

set -euo pipefail

# Script configuration
SCRIPT_NAME="05-image-creation"
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
    info "Creating bootable device images and filesystem artifacts"
}

# Check prerequisites from previous script
check_prerequisites() {
    log "Checking prerequisites from previous build stages..."
    
    # Check that GRUB configuration completed
    if [[ ! -f "$BUILD_LOG_DIR/04-grub-configuration.log" ]]; then
        error "GRUB configuration script has not completed successfully"
    fi
    
    # Check rootfs exists and is configured
    if [[ ! -d "$BUILD_DIR/rootfs" ]]; then
        error "Root filesystem directory not found"
    fi
    
    # Check required tools
    local required_tools=("dd" "mkfs.ext4" "mkfs.fat" "losetup" "parted" "sfdisk")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error "Required tool '$tool' not found"
        fi
    done
    
    log "Prerequisites check completed"
}

# Create image directory structure
create_image_directories() {
    log "Creating image directory structure..."
    
    # Create output directories
    mkdir -p "$BUILD_DIR/images"
    mkdir -p "$BUILD_DIR/images/raw"
    mkdir -p "$BUILD_DIR/images/compressed"
    mkdir -p "$BUILD_DIR/images/pxe"
    mkdir -p "$BUILD_DIR/checksums"
    
    # Create temporary working directory
    mkdir -p "$BUILD_DIR/tmp/image-creation"
    
    log "Image directories created"
}

# Calculate image size requirements
calculate_image_size() {
    log "Calculating image size requirements..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    
    # Calculate rootfs size excluding virtual filesystems
    # Use find to exclude /proc, /sys, /dev, and other virtual mounts
    local rootfs_size=$(find "$root_fs_dir" -xdev -type f -exec du -b {} + 2>/dev/null | awk '{sum+=$1} END {print sum}')
    
    # Fallback if find fails - use du with exclusions
    if [[ -z "$rootfs_size" || "$rootfs_size" -eq 0 ]]; then
        rootfs_size=$(du -sb --exclude="$root_fs_dir/proc" --exclude="$root_fs_dir/sys" --exclude="$root_fs_dir/dev" --exclude="$root_fs_dir/run" "$root_fs_dir" 2>/dev/null | cut -f1)
    fi
    
    # Convert to MB and add safety check
    local rootfs_size_mb=$((rootfs_size / 1024 / 1024))
    
    # Sanity check - rootfs should be reasonable size (100MB - 10GB)
    if [[ $rootfs_size_mb -lt 100 || $rootfs_size_mb -gt 10240 ]]; then
        warn "Calculated rootfs size seems unreasonable: ${rootfs_size_mb}MB"
        warn "Using default size of 2GB for safety"
        rootfs_size_mb=2048
    fi
    
    # Add padding for filesystem overhead and future growth (including initramfs)
    local padding_mb=1000  # Increased for initramfs-tools and initrd
    local total_rootfs_mb=$((rootfs_size_mb + padding_mb))
    
    # Calculate total image size based on partition layout
    # EFI: 512MB, Root: calculated, Swap: 4GB, OS1: 3.7GB, OS2: 3.7GB, Data: 1GB minimum
    local efi_size_mb=512
    local swap_size_mb=4096
    local os1_size_mb=3788  # 3.7GB
    local os2_size_mb=3788  # 3.7GB
    local data_min_mb=1024
    
    # Total size with some extra space for partition table and alignment
    local total_size_mb=$((efi_size_mb + total_rootfs_mb + swap_size_mb + os1_size_mb + os2_size_mb + data_min_mb + 100))
    
    # Final sanity check on total image size
    if [[ $total_size_mb -gt 51200 ]]; then
        error "Total image size too large: ${total_size_mb}MB (components: EFI=${efi_size_mb}MB, Root=${total_rootfs_mb}MB, Swap=${swap_size_mb}MB, OS1=${os1_size_mb}MB, OS2=${os2_size_mb}MB, Data=${data_min_mb}MB)"
    fi
    
    # Store calculated sizes for use in other functions
    export IMAGE_SIZE_MB="$total_size_mb"
    export ROOT_PARTITION_SIZE_MB="$total_rootfs_mb"
    export EFI_SIZE_MB="$efi_size_mb"
    export SWAP_SIZE_MB="$swap_size_mb"
    export OS1_SIZE_MB="$os1_size_mb"
    export OS2_SIZE_MB="$os2_size_mb"
    export DATA_SIZE_MB="$data_min_mb"
    
    info "Image size calculations:"
    info "  Raw rootfs size: ${rootfs_size_mb}MB"
    info "  Root partition (with padding): ${total_rootfs_mb}MB"
    info "  EFI partition: ${efi_size_mb}MB"
    info "  Swap partition: ${swap_size_mb}MB"
    info "  OS1 partition: ${os1_size_mb}MB"
    info "  OS2 partition: ${os2_size_mb}MB"
    info "  Data partition: ${data_min_mb}MB"
    info "  Total image size: ${total_size_mb}MB"
    
    log "Image size calculated: ${total_size_mb}MB"
}

# Create raw disk image
create_raw_image() {
    log "Creating raw disk image..."
    
    local image_path="$BUILD_DIR/images/raw/edge-device-init.img"
    
    # Validate image size is reasonable (max 50GB for safety)
    if [[ $IMAGE_SIZE_MB -gt 51200 ]]; then
        error "Image size too large: ${IMAGE_SIZE_MB}MB (max 50GB allowed)"
    fi
    
    info "Creating ${IMAGE_SIZE_MB}MB disk image..."
    
    # Create sparse file for efficiency - this is sufficient for most use cases
    dd if=/dev/zero of="$image_path" bs=1M count=0 seek="$IMAGE_SIZE_MB" 2>/dev/null || error "Failed to create raw image"
    
    # Verify the file was created with correct size
    local actual_size=$(stat -c%s "$image_path" 2>/dev/null || echo "0")
    local expected_size=$((IMAGE_SIZE_MB * 1024 * 1024))
    
    if [[ $actual_size -ne $expected_size ]]; then
        error "Image file size mismatch: expected $expected_size bytes, got $actual_size bytes"
    fi
    
    info "Raw image created: $image_path (${IMAGE_SIZE_MB}MB sparse file)"
    
    # Store image path for other functions
    export RAW_IMAGE_PATH="$image_path"
    
    log "Raw disk image created successfully"
}

# Create partition table
create_partition_table() {
    log "Creating GPT partition table..."
    
    local image_path="$RAW_IMAGE_PATH"
    
    # Setup loop device
    local loop_device=$(losetup --show -f "$image_path")
    export LOOP_DEVICE="$loop_device"
    
    # Create GPT partition table
    parted -s "$loop_device" mklabel gpt
    
    # Calculate partition boundaries (in MB)
    local efi_start=1
    local efi_end=$((efi_start + EFI_SIZE_MB))
    
    local root_start=$efi_end
    local root_end=$((root_start + ROOT_PARTITION_SIZE_MB))
    
    local swap_start=$root_end
    local swap_end=$((swap_start + SWAP_SIZE_MB))
    
    local os1_start=$swap_end
    local os1_end=$((os1_start + OS1_SIZE_MB))
    
    local os2_start=$os1_end
    local os2_end=$((os2_start + OS2_SIZE_MB))
    
    local data_start=$os2_end
    # Data partition uses remaining space
    
    # Create partitions
    parted -s "$loop_device" mkpart primary fat32 "${efi_start}MiB" "${efi_end}MiB"
    parted -s "$loop_device" set 1 esp on
    parted -s "$loop_device" set 1 boot on
    
    parted -s "$loop_device" mkpart primary ext4 "${root_start}MiB" "${root_end}MiB"
    parted -s "$loop_device" mkpart primary linux-swap "${swap_start}MiB" "${swap_end}MiB"
    parted -s "$loop_device" mkpart primary ext4 "${os1_start}MiB" "${os1_end}MiB"
    parted -s "$loop_device" mkpart primary ext4 "${os2_start}MiB" "${os2_end}MiB"
    parted -s "$loop_device" mkpart primary ext4 "${data_start}MiB" 100%
    
    # Wait for kernel to recognize partitions
    partprobe "$loop_device"
    sleep 2
    
    # Store partition devices
    export EFI_PARTITION="${loop_device}p1"
    export ROOT_PARTITION="${loop_device}p2"
    export SWAP_PARTITION="${loop_device}p3"
    export OS1_PARTITION="${loop_device}p4"
    export OS2_PARTITION="${loop_device}p5"
    export DATA_PARTITION="${loop_device}p6"
    
    log "Partition table created with 6 partitions"
}

# Format partitions
format_partitions() {
    log "Formatting partitions..."
    
    # Format EFI partition (FAT32)
    mkfs.fat -F32 -n "EFI" "$EFI_PARTITION" || error "Failed to format EFI partition"
    info "EFI partition formatted (FAT32)"
    
    # Format Root partition (ext4)
    mkfs.ext4 -F -L "INIT-ROOT" "$ROOT_PARTITION" || error "Failed to format root partition"
    info "Root partition formatted (ext4)"
    
    # Format Swap partition
    mkswap -L "SWAP" "$SWAP_PARTITION" || error "Failed to format swap partition"
    info "Swap partition formatted"
    
    # Format OS partitions (ext4) - empty for now
    mkfs.ext4 -F -L "OS1-ROOT" "$OS1_PARTITION" || error "Failed to format OS1 partition"
    info "OS1 partition formatted (ext4)"
    
    mkfs.ext4 -F -L "OS2-ROOT" "$OS2_PARTITION" || error "Failed to format OS2 partition"
    info "OS2 partition formatted (ext4)"
    
    # Format Data partition (ext4)
    mkfs.ext4 -F -L "DATA" "$DATA_PARTITION" || error "Failed to format data partition"
    info "Data partition formatted (ext4)"
    
    log "All partitions formatted successfully"
}

# Install root filesystem
install_root_filesystem() {
    log "Installing root filesystem to image..."
    
    local mount_point="$BUILD_DIR/tmp/image-creation/root"
    mkdir -p "$mount_point"
    
    # Mount root partition
    mount "$ROOT_PARTITION" "$mount_point" || error "Failed to mount root partition"
    
    # Copy rootfs content
    info "Copying root filesystem (this may take several minutes)..."
    rsync -av --progress \
        --exclude='proc/*' \
        --exclude='sys/*' \
        --exclude='dev/*' \
        --exclude='tmp/*' \
        --exclude='run/*' \
        --exclude='mnt/*' \
        --exclude='media/*' \
        "$BUILD_DIR/rootfs/" "$mount_point/" || error "Failed to copy root filesystem"
    
    # Install GRUB to image
    install_grub_to_image "$mount_point"
    
    # Update fstab with actual UUIDs
    update_fstab_uuids "$mount_point"
    
    # Sync and unmount
    sync
    umount "$mount_point"
    
    log "Root filesystem installed successfully"
}

# Install GRUB to image
install_grub_to_image() {
    local root_mount="$1"
    
    log "Installing GRUB to image..."
    
    # Mount EFI partition
    local efi_mount="$root_mount/boot/efi"
    mkdir -p "$efi_mount"
    mount "$EFI_PARTITION" "$efi_mount" || error "Failed to mount EFI partition"
    
    # Setup chroot environment
    mount --bind /dev "$root_mount/dev"
    mount --bind /dev/pts "$root_mount/dev/pts"
    mount --bind /proc "$root_mount/proc"
    mount --bind /sys "$root_mount/sys"
    
    # Install GRUB
    chroot "$root_mount" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=EdgeDevice --removable || warn "GRUB install failed"
    
    # Update GRUB configuration with actual UUIDs
    update_grub_configuration "$root_mount"
    
    # Generate GRUB configuration
    chroot "$root_mount" update-grub || warn "GRUB update failed"
    
    # Cleanup chroot environment
    umount "$root_mount/sys" 2>/dev/null || true
    umount "$root_mount/proc" 2>/dev/null || true
    umount "$root_mount/dev/pts" 2>/dev/null || true
    umount "$root_mount/dev" 2>/dev/null || true
    umount "$efi_mount" 2>/dev/null || true
    
    log "GRUB installed to image"
}

# Update GRUB configuration with UUIDs
update_grub_configuration() {
    local root_mount="$1"
    
    log "Updating GRUB configuration with partition UUIDs..."
    
    # Get partition UUIDs
    local root_uuid=$(blkid -s UUID -o value "$ROOT_PARTITION")
    local os1_uuid=$(blkid -s UUID -o value "$OS1_PARTITION")
    local os2_uuid=$(blkid -s UUID -o value "$OS2_PARTITION")
    
    # Update GRUB custom menu
    if [[ -f "$root_mount/etc/grub.d/40_custom" ]]; then
        sed -i "s/__ROOT_UUID__/$root_uuid/g" "$root_mount/etc/grub.d/40_custom"
        sed -i "s/__OS1_UUID__/$os1_uuid/g" "$root_mount/etc/grub.d/40_custom"
        sed -i "s/__OS2_UUID__/$os2_uuid/g" "$root_mount/etc/grub.d/40_custom"
        
        info "GRUB UUIDs updated:"
        info "  Root UUID: $root_uuid"
        info "  OS1 UUID: $os1_uuid"
        info "  OS2 UUID: $os2_uuid"
    fi
}

# Update fstab with actual UUIDs
update_fstab_uuids() {
    local root_mount="$1"
    
    log "Updating fstab with partition UUIDs..."
    
    # Get partition UUIDs
    local root_uuid=$(blkid -s UUID -o value "$ROOT_PARTITION")
    local efi_uuid=$(blkid -s UUID -o value "$EFI_PARTITION")
    local swap_uuid=$(blkid -s UUID -o value "$SWAP_PARTITION")
    local data_uuid=$(blkid -s UUID -o value "$DATA_PARTITION")
    
    # Create fstab from template
    if [[ -f "$root_mount/etc/fstab.template" ]]; then
        sed "s/__ROOT_UUID__/$root_uuid/g; s/__EFI_UUID__/$efi_uuid/g; s/__SWAP_UUID__/$swap_uuid/g; s/__DATA_UUID__/$data_uuid/g" \
            "$root_mount/etc/fstab.template" > "$root_mount/etc/fstab"
        
        info "fstab updated with UUIDs"
    else
        warn "fstab template not found"
    fi
}

# Setup data partition
setup_data_partition() {
    log "Setting up data partition..."
    
    local mount_point="$BUILD_DIR/tmp/image-creation/data"
    mkdir -p "$mount_point"
    
    # Mount data partition
    mount "$DATA_PARTITION" "$mount_point" || error "Failed to mount data partition"
    
    # Create directory structure
    mkdir -p "$mount_point/config"
    mkdir -p "$mount_point/logs"
    mkdir -p "$mount_point/backup"
    mkdir -p "$mount_point/docker"
    mkdir -p "$mount_point/os1-config"
    mkdir -p "$mount_point/os2-config"
    
    # Create README
    cat > "$mount_point/README.txt" << EOF
Data Partition for Edge Device
==============================

This partition contains shared data between all operating systems
installed on this device.

Directory Structure:
- config/     : Device configuration files
- logs/       : System and application logs
- backup/     : Configuration backups
- docker/     : Docker data directory
- os1-config/ : OS1 specific configurations
- os2-config/ : OS2 specific configurations

This partition is automatically mounted at /data in all operating systems.
EOF
    
    # Set permissions
    chmod 755 "$mount_point"/{config,logs,backup,docker,os1-config,os2-config}
    
    # Sync and unmount
    sync
    umount "$mount_point"
    
    log "Data partition setup completed"
}

# Create compressed images
create_compressed_images() {
    log "Creating compressed images..."
    
    local raw_image="$RAW_IMAGE_PATH"
    local compressed_dir="$BUILD_DIR/images/compressed"
    
    # Create gzipped image (optimal for PXE - fast decompression, good compression)
    info "Creating gzipped image..."
    gzip -c "$raw_image" > "$compressed_dir/edge-device-init.img.gz" || error "Failed to create gzipped image"
    
    log "Compressed images created"
}

# Create PXE boot files
create_pxe_files() {
    log "Creating PXE boot files..."
    
    local pxe_dir="$BUILD_DIR/images/pxe"
    local root_mount="$BUILD_DIR/tmp/image-creation/root-extract"
    
    mkdir -p "$root_mount"
    mount "$ROOT_PARTITION" "$root_mount" || error "Failed to mount root partition for PXE extraction"
    
    # Copy kernel and initrd
    cp "$root_mount/boot/vmlinuz-"* "$pxe_dir/vmlinuz" 2>/dev/null || warn "Kernel not found"
    cp "$root_mount/boot/initrd.img-"* "$pxe_dir/initrd.img" 2>/dev/null || warn "Initrd not found"
    
    # Create PXE configuration
    cat > "$pxe_dir/pxelinux.cfg" << EOF
DEFAULT edge-device-init
TIMEOUT 30

LABEL edge-device-init
    MENU LABEL Edge Device Initialization
    KERNEL vmlinuz
    APPEND initrd=initrd.img root=UUID=$(blkid -s UUID -o value "$ROOT_PARTITION") ro quiet splash
    
LABEL edge-device-rescue
    MENU LABEL Edge Device Rescue Mode
    KERNEL vmlinuz
    APPEND initrd=initrd.img root=UUID=$(blkid -s UUID -o value "$ROOT_PARTITION") ro single
EOF
    
    umount "$root_mount"
    rm -rf "$root_mount"
    
    log "PXE boot files created"
}

# Generate checksums
generate_checksums() {
    log "Generating checksums for all images..."
    
    local checksum_dir="$BUILD_DIR/checksums"
    
    # Generate checksums for all image files
    find "$BUILD_DIR/images" -type f -name "*.img" -o -name "*.gz" | while read -r file; do
        local filename=$(basename "$file")
        local dirname=$(dirname "$file" | sed "s|$BUILD_DIR/images/||")
        
        # Create subdirectory in checksums if needed
        mkdir -p "$checksum_dir/$dirname"
        
        # Generate multiple hash types
        md5sum "$file" > "$checksum_dir/$dirname/$filename.md5"
        sha256sum "$file" > "$checksum_dir/$dirname/$filename.sha256"
        sha512sum "$file" > "$checksum_dir/$dirname/$filename.sha512"
        
        info "Checksums generated for $filename"
    done
    
    log "All checksums generated"
}

# Create image manifest
create_image_manifest() {
    log "Creating image manifest..."
    
    local manifest_file="$BUILD_DIR/images/manifest.json"
    
    # Get image information
    local raw_image="$RAW_IMAGE_PATH"
    local raw_size=$(stat -c%s "$raw_image")
    local build_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local ubuntu_release="${UBUNTU_RELEASE:-noble}"
    
    # Create JSON manifest
    cat > "$manifest_file" << EOF
{
    "build_info": {
        "build_date": "$build_date",
        "build_version": "$SCRIPT_VERSION",
        "ubuntu_release": "$ubuntu_release",
        "image_size_mb": $IMAGE_SIZE_MB,
        "partition_layout": {
            "efi": {"size_mb": $EFI_SIZE_MB, "type": "fat32", "label": "EFI"},
            "root": {"size_mb": $ROOT_PARTITION_SIZE_MB, "type": "ext4", "label": "INIT-ROOT"},
            "swap": {"size_mb": $SWAP_SIZE_MB, "type": "swap", "label": "SWAP"},
            "os1": {"size_mb": $OS1_SIZE_MB, "type": "ext4", "label": "OS1-ROOT"},
            "os2": {"size_mb": $OS2_SIZE_MB, "type": "ext4", "label": "OS2-ROOT"},
            "data": {"size_mb": $DATA_SIZE_MB, "type": "ext4", "label": "DATA"}
        }
    },
    "images": {
        "raw": {
            "filename": "raw/edge-device-init.img",
            "size_bytes": $raw_size,
            "description": "Raw disk image ready for writing to storage device"
        },
        "compressed": {
            "gzip": {
                "filename": "compressed/edge-device-init.img.gz",
                "description": "Gzip compressed disk image (optimal for PXE)"
            }
        },
        "pxe": {
            "kernel": "pxe/vmlinuz",
            "initrd": "pxe/initrd.img",
            "config": "pxe/pxelinux.cfg",
            "description": "PXE boot files for network installation"
        }
    },
    "usage": {
        "raw_image": "Write to USB/SD card with dd or imaging tool",
        "compressed": "Extract and write to storage device",
        "pxe": "Deploy to PXE server for network boot installation"
    }
}
EOF
    
    log "Image manifest created: $manifest_file"
}

# Cleanup loop devices
cleanup_loop_devices() {
    log "Cleaning up loop devices..."
    
    if [[ -n "${LOOP_DEVICE:-}" ]]; then
        losetup -d "$LOOP_DEVICE" 2>/dev/null || warn "Failed to detach loop device $LOOP_DEVICE"
    fi
    
    log "Loop devices cleaned up"
}

# Save image creation log
save_image_log() {
    local log_file="$BUILD_LOG_DIR/$SCRIPT_NAME.log"
    
    cat > "$log_file" << EOF
# Image Creation Log
# Generated by $SCRIPT_NAME v$SCRIPT_VERSION on $(date)

Build Configuration:
- Build Directory: $BUILD_DIR
- Ubuntu Release: ${UBUNTU_RELEASE:-noble}
- Image Size: ${IMAGE_SIZE_MB}MB

Images Created:
- Raw image: $RAW_IMAGE_PATH
- Compressed images: gzip format (optimal for PXE)
- PXE boot files: kernel, initrd, configuration
- Checksums: md5, sha256, sha512 for all images

Partition Layout:
- EFI System Partition: ${EFI_SIZE_MB}MB (FAT32)
- Root/Init Partition: ${ROOT_PARTITION_SIZE_MB}MB (ext4)
- Swap Partition: ${SWAP_SIZE_MB}MB (swap)
- OS1 Partition: ${OS1_SIZE_MB}MB (ext4, empty)
- OS2 Partition: ${OS2_SIZE_MB}MB (ext4, empty)
- Data Partition: ${DATA_SIZE_MB}MB+ (ext4)

Files Generated:
$(find "$BUILD_DIR/images" -type f | sed 's|^|  |')

Image creation completed: $(date)
Next step: Run 06-testing-validation.sh
EOF
    
    info "Image creation log saved to $log_file"
}

# Main execution function
main() {
    show_header
    check_prerequisites
    create_image_directories
    calculate_image_size
    create_raw_image
    create_partition_table
    format_partitions
    install_root_filesystem
    setup_data_partition
    create_compressed_images
    create_pxe_files
    generate_checksums
    create_image_manifest
    cleanup_loop_devices
    save_image_log
    
    log "$SCRIPT_NAME completed successfully"
    info "Bootable device images created and ready for deployment"
    info "Next: Run 06-testing-validation.sh"
}

# Trap to cleanup on exit
cleanup_on_exit() {
    cleanup_loop_devices
}
trap cleanup_on_exit EXIT

# Run main function
main "$@"
