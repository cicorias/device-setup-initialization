#!/bin/bash

set -eo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
ARTIFACTS="${ARTIFACTS:-$(pwd -P)/artifacts}"
CHROOT_DIR="${ARTIFACTS}/pxe-rootfs"
PXE_DIR="${ARTIFACTS}/pxe-files"
OS_IMAGES_DIR="${ARTIFACTS}/os-images"
IMAGES_DIR="${ARTIFACTS}/images"
INTEGRATION_DIR="${ARTIFACTS}/pxe-integration"

# Output format options
OUTPUT_SQUASHFS="${OUTPUT_SQUASHFS:-true}"
OUTPUT_IMG="${OUTPUT_IMG:-true}"
IMG_SIZE="${IMG_SIZE:-4G}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Clean up function
cleanup() {
    log "Cleaning up mounts..."
    for mount in dev proc sys run; do
        if mountpoint -q "${CHROOT_DIR}/$mount" 2>/dev/null; then
            sudo umount "${CHROOT_DIR}/$mount" || warn "Failed to unmount $mount"
        fi
    done
}

# Set trap for cleanup
trap cleanup EXIT

# Create directory structure
setup_directories() {
    log "Setting up directory structure..."
    mkdir -p "${ARTIFACTS}" "${PXE_DIR}" "${OS_IMAGES_DIR}" "${IMAGES_DIR}" "${INTEGRATION_DIR}"
    cd "${ARTIFACTS}"
}

# Build PXE boot environment (based on script 1)
build_pxe_environment() {
    log "Building PXE boot environment..."
    
    # Install required packages
    sudo apt-get update
    sudo apt-get install -y debootstrap squashfs-tools live-boot live-boot-initramfs-tools \
                             parted gdisk dosfstools e2fsprogs qemu-utils
    
    # Bootstrap minimal Debian system for PXE
    log "Creating Debian bootstrap for PXE environment..."
    sudo debootstrap --variant=minbase --arch=amd64 trixie "${CHROOT_DIR}" http://deb.debian.org/debian/
    
    # Mount required filesystems
    sudo mount --bind /dev "${CHROOT_DIR}/dev"
    sudo mount --bind /proc "${CHROOT_DIR}/proc"
    sudo mount --bind /sys "${CHROOT_DIR}/sys"
    sudo mount --bind /run "${CHROOT_DIR}/run"
    
    # Configure PXE environment
    sudo chroot "${CHROOT_DIR}" /bin/bash -c '
        export DEBIAN_FRONTEND=noninteractive
        export LANG=C
        export LC_ALL=C
        
        echo "pxe-installer" > /etc/hostname
        
        cat <<EOF > /etc/apt/sources.list
deb http://deb.debian.org/debian trixie main
deb http://security.debian.org/debian-security trixie-security main
EOF
        
        # Update package lists first
        apt-get update
        
        # Install core system packages first
        apt-get install -y --no-install-recommends \
            systemd-sysv \
            ifupdown \
            net-tools \
            iputils-ping \
            curl \
            wget \
            dialog \
            whiptail
            
        # Install partitioning and filesystem tools
        apt-get install -y --no-install-recommends \
            parted \
            gdisk \
            dosfstools \
            e2fsprogs \
            rsync \
            pv
            
        # Install bootloader tools
        apt-get install -y --no-install-recommends \
            grub-pc \
            grub-efi-amd64 \
            grub-common
            
        # Install live-boot system
        apt-get install -y --no-install-recommends \
            live-boot
            
        # Install kernel last to ensure all dependencies are ready
        echo "Installing Linux kernel..."
        apt-get install -y --no-install-recommends linux-image-amd64
        
        # Verify kernel installation
        if ls /boot/vmlinuz-* >/dev/null 2>&1; then
            echo "Kernel installation successful:"
            ls -la /boot/vmlinuz-* /boot/initrd.img-*
        else
            echo "WARNING: Kernel files not found after installation!"
            ls -la /boot/
        fi
        
        # Create installation script that will run in PXE environment
        cat > /usr/local/bin/disk-installer << "INSTALLER_EOF"
#!/bin/bash

# Disk installer script for PXE environment
DISK="/dev/sda"  # Adjust as needed

# Function to detect disk
detect_disk() {
    echo "Detecting target disk..."
    
    # List available disks
    echo "Available disks:"
    lsblk -d -o NAME,SIZE,MODEL | grep -E "sd[a-z]|nvme|vd[a-z]"
    
    if [ -t 0 ]; then  # Interactive mode
        echo "Current target: $DISK"
        read -p "Press Enter to use $DISK or type new disk path: " user_disk
        if [ -n "$user_disk" ]; then
            DISK="$user_disk"
        fi
    fi
    
    if [ ! -b "$DISK" ]; then
        echo "Error: Disk $DISK not found!"
        exit 1
    fi
    
    echo "Using disk: $DISK"
}

# Function to create partitions according to your specification
create_partitions() {
    echo "Creating partition layout on $DISK..."
    echo "Layout: GRUB | Boot OS1 | Boot OS2 | Data"
    
    # Clear existing partition table
    sudo wipefs -a "$DISK"
    sudo parted "$DISK" mklabel gpt
    
    # Create partitions according to your specification:
    # 1. GRUB partition (512MB) - contains bootloader and boot files
    # 2. OS1 Boot partition (3.5GB) - Ubuntu root filesystem  
    # 3. OS2 Boot partition (3.5GB) - Debian root filesystem
    # 4. Data partition (remaining) - shared data
    
    sudo parted "$DISK" mkpart primary fat32 1MiB 513MiB      # GRUB (512MB)
    sudo parted "$DISK" mkpart primary ext4 513MiB 4097MiB    # OS1 (3.5GB)
    sudo parted "$DISK" mkpart primary ext4 4097MiB 7681MiB   # OS2 (3.5GB) 
    sudo parted "$DISK" mkpart primary ext4 7681MiB 100%      # DATA (remaining)
    
    # Set partition flags
    sudo parted "$DISK" set 1 esp on    # Mark GRUB partition as EFI System Partition
    sudo parted "$DISK" set 1 boot on   # Also set boot flag for BIOS compatibility
    
    # Format partitions with labels
    echo "Formatting partitions..."
    sudo mkfs.fat -F32 -n "GRUB" "${DISK}1"
    sudo mkfs.ext4 -L "OS1-ROOT" "${DISK}2"
    sudo mkfs.ext4 -L "OS2-ROOT" "${DISK}3"
    sudo mkfs.ext4 -L "DATA" "${DISK}4"
    
    # Print partition table
    echo "Partition table created:"
    sudo parted "$DISK" print
}

# Function to install GRUB bootloader
install_grub() {
    echo "Installing GRUB bootloader..."
    
    GRUB_MNT="/mnt/grub"
    mkdir -p "$GRUB_MNT"
    mount "${DISK}1" "$GRUB_MNT"
    
    # Install GRUB for both UEFI and BIOS compatibility
    echo "Installing GRUB (UEFI)..."
    grub-install --target=x86_64-efi --efi-directory="$GRUB_MNT" --boot-directory="$GRUB_MNT/boot" --no-floppy --removable
    
    echo "Installing GRUB (BIOS)..."
    grub-install --target=i386-pc --boot-directory="$GRUB_MNT/boot" "$DISK"
    
    # Create GRUB configuration for dual-boot
    mkdir -p "$GRUB_MNT/boot/grub"
    cat > "$GRUB_MNT/boot/grub/grub.cfg" << "GRUB_EOF"
set timeout=10
set default=0

# Load video drivers
insmod all_video

menuentry "Ubuntu OS" {
    search --set=root --label OS1-ROOT
    linux /boot/vmlinuz root=LABEL=OS1-ROOT ro quiet splash
    initrd /boot/initrd.img
}

menuentry "Debian OS" {
    search --set=root --label OS2-ROOT  
    linux /boot/vmlinuz root=LABEL=OS2-ROOT ro quiet
    initrd /boot/initrd.img
}

menuentry "Ubuntu OS (Recovery Mode)" {
    search --set=root --label OS1-ROOT
    linux /boot/vmlinuz root=LABEL=OS1-ROOT ro recovery nomodeset
    initrd /boot/initrd.img
}

menuentry "Debian OS (Recovery Mode)" {
    search --set=root --label OS2-ROOT
    linux /boot/vmlinuz root=LABEL=OS2-ROOT ro recovery nomodeset  
    initrd /boot/initrd.img
}

menuentry "System Information" {
    search --set=root --label GRUB
    linux /boot/memtest86+.bin
}

menuentry "Reboot System" {
    reboot
}

menuentry "Shutdown System" {
    halt
}
GRUB_EOF
    
    umount "$GRUB_MNT"
    echo "GRUB installation complete."
}

# Function to download and install OS images
install_os_images() {
    echo "Downloading and installing OS images..."
    
    OS1_MNT="/mnt/os1"
    OS2_MNT="/mnt/os2"
    mkdir -p "$OS1_MNT" "$OS2_MNT"
    
    # Mount OS partitions
    mount "${DISK}2" "$OS1_MNT"
    mount "${DISK}3" "$OS2_MNT"
    
    # Download and extract Ubuntu
    echo "Installing Ubuntu OS..."
    if curl -f -o /tmp/ubuntu.tar.gz "http://pxe-server/images/ubuntu-os.tar.gz"; then
        tar -xzf /tmp/ubuntu.tar.gz -C "$OS1_MNT"
        
        # Update fstab for Ubuntu
        cat > "$OS1_MNT/etc/fstab" << "FSTAB_EOF"
LABEL=OS1-ROOT / ext4 defaults 0 1
LABEL=DATA /data ext4 defaults 0 2
LABEL=GRUB /boot/efi vfat defaults 0 2
FSTAB_EOF
        
        # Create data mount point
        mkdir -p "$OS1_MNT/data"
        
        echo "Ubuntu installation complete."
    else
        echo "Warning: Ubuntu image download failed."
    fi
    
    # Download and extract Debian
    echo "Installing Debian OS..."
    if curl -f -o /tmp/debian.tar.gz "http://pxe-server/images/debian-os.tar.gz"; then
        tar -xzf /tmp/debian.tar.gz -C "$OS2_MNT"
        
        # Update fstab for Debian  
        cat > "$OS2_MNT/etc/fstab" << "FSTAB_EOF"
LABEL=OS2-ROOT / ext4 defaults 0 1
LABEL=DATA /data ext4 defaults 0 2
LABEL=GRUB /boot/efi vfat defaults 0 2
FSTAB_EOF
        
        # Create data mount point
        mkdir -p "$OS2_MNT/data"
        
        echo "Debian installation complete."
    else
        echo "Warning: Debian image download failed."
    fi
    
    umount "$OS1_MNT" "$OS2_MNT"
}

# Function to setup shared data partition
setup_data_partition() {
    echo "Setting up shared data partition..."
    
    DATA_MNT="/mnt/data"
    mkdir -p "$DATA_MNT"
    mount "${DISK}4" "$DATA_MNT"
    
    # Create standard directories
    mkdir -p "$DATA_MNT"/{shared,ubuntu-home,debian-home,logs,backups}
    
    # Create README
    cat > "$DATA_MNT/README.txt" << "README_EOF"
Shared Data Partition

This partition is accessible from both Ubuntu and Debian OS installations.
It is mounted at /data in both operating systems.

Directory Structure:
- shared/     - Files accessible to both OS
- ubuntu-home/ - Ubuntu user home directories
- debian-home/ - Debian user home directories  
- logs/       - System logs from both OS
- backups/    - System backups

Mount point: /data
Label: DATA
Filesystem: ext4
README_EOF
    
    umount "$DATA_MNT"
    echo "Data partition setup complete."
}

# Main installation function
main() {
    echo "=== PXE Disk Installation System ==="
    echo "This will create a dual-boot system with:"
    echo "1. GRUB partition (bootloader)"
    echo "2. Ubuntu OS partition"  
    echo "3. Debian OS partition"
    echo "4. Shared data partition"
    echo
    
    detect_disk
    
    echo "WARNING: This will DESTROY all data on $DISK"
    echo "Disk size: $(lsblk -d -o SIZE "$DISK" | tail -1)"
    
    if [ -t 0 ]; then  # Interactive mode
        read -p "Type 'YES' to continue: " confirm
        if [ "$confirm" != "YES" ]; then
            echo "Installation cancelled."
            exit 0
        fi
    fi
    
    echo "Starting installation..."
    create_partitions
    install_grub
    install_os_images  
    setup_data_partition
    
    echo
    echo "=== Installation Complete ==="
    echo "System is ready to boot!"
    echo
    echo "Partition layout:"
    sudo parted "$DISK" print
    echo
    echo "The system will reboot in 10 seconds..."
    echo "Remove PXE boot media and boot from hard disk."
    
    if [ -t 0 ]; then
        read -t 10 -p "Press Enter to reboot now or wait 10 seconds: "
    else
        sleep 10
    fi
    
    reboot
}

# Check if running interactively
if [ -t 0 ]; then
    main
else
    # Auto-install mode (uncomment next line to enable)
    # main
    echo "Auto-install disabled. Run 'disk-installer' manually to begin installation."
fi
INSTALLER_EOF
        
        chmod +x /usr/local/bin/disk-installer
        
        # Create auto-start service for installer
        cat > /etc/systemd/system/auto-installer.service << "SERVICE_EOF"
[Unit]
Description=Automatic Disk Installer
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/disk-installer
StandardInput=null
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE_EOF
        
        # Enable auto-installer (commented out for manual testing)
        # systemctl enable auto-installer
        
        # Set root password
        echo "root:pxeinstaller" | chpasswd
        
        apt-get clean
        rm -rf /var/lib/apt/lists/*
    '
    
    # Unmount filesystems
    sudo umount "${CHROOT_DIR}/dev" "${CHROOT_DIR}/proc" "${CHROOT_DIR}/sys" "${CHROOT_DIR}/run"
    
    # Create SquashFS and extract boot files
    if [[ "$OUTPUT_SQUASHFS" == "true" ]]; then
        log "Creating SquashFS filesystem..."
        sudo mksquashfs "${CHROOT_DIR}" "${PXE_DIR}/filesystem.squashfs" -e boot
    fi
    
    log "Extracting kernel and initrd..."
    # Check if kernel files exist in boot directory
    if ls "${CHROOT_DIR}"/boot/vmlinuz-* 1> /dev/null 2>&1; then
        sudo cp "${CHROOT_DIR}"/boot/vmlinuz-* "${PXE_DIR}/vmlinuz"
        sudo cp "${CHROOT_DIR}"/boot/initrd.img-* "${PXE_DIR}/initrd"
        log "Kernel and initrd extracted successfully"
    else
        warn "Kernel files not found in boot directory, checking alternative locations..."
        
        # Check if kernel was installed but not linked
        if ls "${CHROOT_DIR}"/boot/vmlinuz-*-amd64 1> /dev/null 2>&1; then
            sudo cp "${CHROOT_DIR}"/boot/vmlinuz-*-amd64 "${PXE_DIR}/vmlinuz"
            sudo cp "${CHROOT_DIR}"/boot/initrd.img-*-amd64 "${PXE_DIR}/initrd"
            log "Found and extracted versioned kernel files"
        else
            error "No kernel files found. The linux-image-amd64 package may not have installed correctly."
        fi
    fi
    
    # Create PXE configuration
    create_pxe_config
}

# Create OS images for HTTP download
build_os_images() {
    log "Building OS images for HTTP distribution..."
    
    # Ubuntu image
    log "Creating Ubuntu OS image..."
    UBUNTU_DIR="${OS_IMAGES_DIR}/ubuntu-build"
    sudo debootstrap --arch=amd64 jammy "$UBUNTU_DIR" http://archive.ubuntu.com/ubuntu/
    
    # Configure Ubuntu
    sudo chroot "$UBUNTU_DIR" /bin/bash -c '
        echo "ubuntu-os" > /etc/hostname
        echo "root:ubuntu123" | chpasswd
        apt update
        DEBIAN_FRONTEND=noninteractive apt install -y linux-image-generic openssh-server
        systemctl enable ssh
        apt clean
    '
    
    # Create Ubuntu tarball
    sudo tar -czf "${OS_IMAGES_DIR}/ubuntu-os.tar.gz" -C "$UBUNTU_DIR" .
    sudo rm -rf "$UBUNTU_DIR"
    
    # Debian image  
    log "Creating Debian OS image..."
    DEBIAN_DIR="${OS_IMAGES_DIR}/debian-build"
    sudo debootstrap --arch=amd64 bookworm "$DEBIAN_DIR" http://deb.debian.org/debian/
    
    # Configure Debian
    sudo chroot "$DEBIAN_DIR" /bin/bash -c '
        echo "debian-os" > /etc/hostname
        echo "root:debian123" | chpasswd
        apt update
        DEBIAN_FRONTEND=noninteractive apt install -y linux-image-amd64 openssh-server
        systemctl enable ssh
        apt clean
    '
    
    # Create Debian tarball
    sudo tar -czf "${OS_IMAGES_DIR}/debian-os.tar.gz" -C "$DEBIAN_DIR" .
    sudo rm -rf "$DEBIAN_DIR"
}

# Create IMG files for HTTP serving
create_img_files() {
    if [[ "$OUTPUT_IMG" != "true" ]]; then
        log "IMG output disabled, skipping IMG creation"
        return 0
    fi
    
    log "Creating IMG files for HTTP serving..."
    
    # Create dual-OS installer IMG
    log "Creating dual-OS installer IMG file..."
    local installer_img="${IMAGES_DIR}/dual-os-installer.img"
    
    # Create empty IMG file
    sudo dd if=/dev/zero of="$installer_img" bs=1M count=0 seek=$(echo "$IMG_SIZE" | sed 's/G/*1024/g' | bc) status=progress
    
    # Format as ext4
    sudo mkfs.ext4 -F -L "DualOSInstaller" "$installer_img"
    
    # Mount and populate IMG
    local img_mount="/tmp/img_mount_$$"
    sudo mkdir -p "$img_mount"
    sudo mount -o loop "$installer_img" "$img_mount"
    
    # Copy installer system to IMG
    sudo rsync -av --exclude='/dev/*' --exclude='/proc/*' --exclude='/sys/*' --exclude='/run/*' \
        --exclude='/tmp/*' --exclude='/boot/*' "${CHROOT_DIR}/" "$img_mount/"
    
    # Create installation metadata
    sudo tee "$img_mount/etc/installer-info" > /dev/null << EOF
# Dual-OS Installer Image Information
INSTALLER_VERSION=1.0
BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
UBUNTU_VERSION=24.04
DEBIAN_VERSION=bookworm
SUPPORT_UEFI=true
SUPPORT_BIOS=true
PARTITION_LAYOUT=grub:512M,ubuntu:3.5G,debian:3.5G,data:remaining
EOF
    
    sudo umount "$img_mount"
    sudo rmdir "$img_mount"
    
    # Create Ubuntu minimal IMG if OS images were built
    if [[ -f "${OS_IMAGES_DIR}/ubuntu-os.tar.gz" ]]; then
        log "Creating Ubuntu minimal IMG file..."
        local ubuntu_img="${IMAGES_DIR}/ubuntu-minimal.img"
        
        sudo dd if=/dev/zero of="$ubuntu_img" bs=1M count=0 seek=3584 status=progress  # 3.5G
        sudo mkfs.ext4 -F -L "UbuntuMinimal" "$ubuntu_img"
        
        local ubuntu_mount="/tmp/ubuntu_mount_$$"
        sudo mkdir -p "$ubuntu_mount"
        sudo mount -o loop "$ubuntu_img" "$ubuntu_mount"
        
        # Extract Ubuntu OS
        sudo tar -xzf "${OS_IMAGES_DIR}/ubuntu-os.tar.gz" -C "$ubuntu_mount"
        
        sudo umount "$ubuntu_mount"
        sudo rmdir "$ubuntu_mount"
    fi
    
    # Create Debian minimal IMG if OS images were built
    if [[ -f "${OS_IMAGES_DIR}/debian-os.tar.gz" ]]; then
        log "Creating Debian minimal IMG file..."
        local debian_img="${IMAGES_DIR}/debian-minimal.img"
        
        sudo dd if=/dev/zero of="$debian_img" bs=1M count=0 seek=3584 status=progress  # 3.5G
        sudo mkfs.ext4 -F -L "DebianMinimal" "$debian_img"
        
        local debian_mount="/tmp/debian_mount_$$"
        sudo mkdir -p "$debian_mount"
        sudo mount -o loop "$debian_img" "$debian_mount"
        
        # Extract Debian OS
        sudo tar -xzf "${OS_IMAGES_DIR}/debian-os.tar.gz" -C "$debian_mount"
        
        sudo umount "$debian_mount"
        sudo rmdir "$debian_mount"
    fi
    
    # Set proper permissions
    sudo chown -R $(whoami):$(whoami) "${IMAGES_DIR}"
    
    log "IMG files created successfully"
}

# Create PXE configuration files
create_pxe_config() {
    log "Creating PXE configuration files..."
    
    mkdir -p "${PXE_DIR}/pxelinux.cfg"
    
    # Create PXE menu using PXELINUX (default Debian/Ubuntu PXE implementation)
    cat > "${PXE_DIR}/pxelinux.cfg/default" << 'EOF'
DEFAULT menu.c32
PROMPT 0
TIMEOUT 100
ONTIMEOUT installer

MENU TITLE PXE Boot Menu - Dual-OS Installation
MENU BACKGROUND pxelinux.cfg/background.png

LABEL installer
    MENU LABEL Auto Install Dual-OS System
    KERNEL vmlinuz
    APPEND initrd=initrd boot=live fetch=http://pxe-server/pxe-files/filesystem.squashfs
    
LABEL manual
    MENU LABEL Manual Installation Mode
    KERNEL vmlinuz
    APPEND initrd=initrd boot=live fetch=http://pxe-server/pxe-files/filesystem.squashfs systemd.unit=multi-user.target

LABEL localboot
    MENU LABEL Boot from Local Hard Drive
    LOCALBOOT 0
EOF
}

# Generate server deployment package (DEPRECATED)
create_deployment_package() {
    warn "create_deployment_package() is DEPRECATED"
    warn "Use cicorias/pxe-server-setup for PXE server infrastructure"
    warn "Use ./scripts/deploy-to-pxe-server.sh for deploying built images"
    warn ""
    warn "Skipping legacy deployment package creation"
    warn "Set CREATE_LEGACY_PACKAGE=true to force creation"
}

# Main execution
main() {
    log "Starting PXE system creation..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --no-squashfs)
                OUTPUT_SQUASHFS="false"
                shift
                ;;
            --no-img)
                OUTPUT_IMG="false"
                shift
                ;;
            --img-size)
                IMG_SIZE="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [options]"
                echo "Options:"
                echo "  --no-squashfs     Skip SquashFS creation (legacy compatibility)"
                echo "  --no-img          Skip IMG file creation"
                echo "  --img-size SIZE   Set IMG file size (default: 4G)"
                echo "  --help, -h        Show this help"
                exit 0
                ;;
            *)
                warn "Unknown option: $1"
                shift
                ;;
        esac
    done
    
    log "Configuration:"
    log "- SquashFS output: $OUTPUT_SQUASHFS"
    log "- IMG output: $OUTPUT_IMG"
    log "- IMG size: $IMG_SIZE"
    
    setup_directories
    build_pxe_environment
    build_os_images
    create_img_files
    create_pxe_config
    
    # Generate integration configuration
    log "Generating PXE integration configuration..."
    "${SCRIPT_DIR}/generate-pxe-config.sh"
    
    # Create legacy deployment package (deprecated)
    if [[ "${CREATE_LEGACY_PACKAGE:-false}" == "true" ]]; then
        warn "Creating legacy deployment package (deprecated)"
        create_deployment_package
    fi
    
    log "PXE system creation complete!"
    log ""
    log "=== NEW ARCHITECTURE (RECOMMENDED) ==="
    log "1. Set up PXE server using: https://github.com/cicorias/pxe-server-setup"
    log "2. Deploy to PXE server: ./scripts/deploy-to-pxe-server.sh <server-ip>"
    log "3. Or follow manual instructions in: artifacts/pxe-integration/"
    log ""
    log "=== FILES CREATED ==="
    log "Build artifacts: ${ARTIFACTS}"
    if [[ "$OUTPUT_IMG" == "true" ]]; then
        log "IMG files: ${IMAGES_DIR}"
    fi
    if [[ "$OUTPUT_SQUASHFS" == "true" ]]; then
        log "Legacy PXE files: ${PXE_DIR}"
    fi
    log "Integration config: ${INTEGRATION_DIR}"
    if [[ -d "${ARTIFACTS}/server-deployment" ]]; then
        log "Legacy package: ${ARTIFACTS}/server-deployment/ (deprecated)"
    fi
    log ""
    log "=== WHAT'S INCLUDED ==="
    log "- Custom installation system with dual-boot capability"
    if [[ "$OUTPUT_IMG" == "true" ]]; then
        log "- IMG files for HTTP serving (modern approach)"
    fi
    if [[ "$OUTPUT_SQUASHFS" == "true" ]]; then
        log "- SquashFS live boot system (legacy compatibility)"
    fi
    log "- Pre-built Ubuntu and Debian OS images"
    log "- PXE integration configuration and deployment scripts"
}

# Run main function
main "$@"
