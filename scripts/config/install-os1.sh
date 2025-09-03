#!/bin/bash
# install-os1.sh
# Primary Ubuntu 24.04.3 LTS installation script for OS1 partition
# Uses debootstrap for minimal system installation following PXE server instructions

set -euo pipefail

# Configuration
TARGET_PARTITION="/dev/sda4"  # OS1 partition
MOUNT_POINT="/mnt/os1"
UBUNTU_RELEASE="noble"  # Ubuntu 24.04.3 LTS
UBUNTU_MIRROR="http://archive.ubuntu.com/ubuntu"
KERNEL_PACKAGE="linux-generic"

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
║                   Ubuntu OS1 Installation                   ║
║                                                              ║
║  Installing Ubuntu 24.04.3 LTS on the primary OS1          ║
║  partition using debootstrap for minimal system.            ║
║                                                              ║
║  This will be the primary operating system with:            ║
║  - Minimal Ubuntu base system                               ║
║  - Essential packages and tools                             ║
║  - Network configuration support                            ║
║  - SSH server for remote access                             ║
║  - Basic security hardening                                 ║
║                                                              ║
║  Installation will take approximately 10-20 minutes         ║
║  depending on network speed and hardware.                   ║
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
    
    # Check if debootstrap is available
    if ! command -v debootstrap &> /dev/null; then
        warn "debootstrap not found, installing..."
        apt-get update
        apt-get install -y debootstrap
    fi
    
    # Check if target partition exists
    if [[ ! -b "$TARGET_PARTITION" ]]; then
        error "Target partition $TARGET_PARTITION not found. Run partition-disk.sh first."
    fi
    
    # Check if partition is formatted
    if ! blkid "$TARGET_PARTITION" | grep -q "TYPE="; then
        error "Target partition $TARGET_PARTITION is not formatted. Run partition-disk.sh first."
    fi
    
    # Check internet connectivity
    if ! ping -c 1 google.com &> /dev/null; then
        warn "No internet connectivity detected. Installation may fail."
        echo "Continue anyway? (y/N): "
        read continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            error "Installation cancelled"
        fi
    fi
    
    log "Prerequisites check completed"
}

# Prepare mount point
prepare_mount_point() {
    log "Preparing mount point $MOUNT_POINT..."
    
    # Unmount if already mounted
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        umount "$MOUNT_POINT" || error "Failed to unmount $MOUNT_POINT"
    fi
    
    # Create mount point
    mkdir -p "$MOUNT_POINT"
    
    # Mount OS1 partition
    mount "$TARGET_PARTITION" "$MOUNT_POINT" || error "Failed to mount $TARGET_PARTITION"
    
    # Clear any existing content (with confirmation)
    if [[ -n "$(ls -A "$MOUNT_POINT" 2>/dev/null)" ]]; then
        echo "Target partition contains existing data:"
        ls -la "$MOUNT_POINT"
        echo
        echo "Remove existing data? (y/N): "
        read remove_data
        if [[ "$remove_data" =~ ^[Yy]$ ]]; then
            rm -rf "${MOUNT_POINT:?}"/*
            rm -rf "${MOUNT_POINT:?}"/.*
        else
            error "Installation cancelled"
        fi
    fi
    
    log "Mount point prepared: $MOUNT_POINT"
}

# Install base system with debootstrap
install_base_system() {
    log "Installing Ubuntu base system with debootstrap..."
    
    # Run debootstrap to install minimal system
    debootstrap \
        --arch=amd64 \
        --variant=minbase \
        --include=systemd,systemd-sysv,dbus,apt-utils,locales \
        "$UBUNTU_RELEASE" \
        "$MOUNT_POINT" \
        "$UBUNTU_MIRROR" || error "debootstrap failed"
    
    log "Base system installation completed"
}

# Configure system basics
configure_base_system() {
    log "Configuring base system..."
    
    # Set up chroot environment
    mount --bind /dev "$MOUNT_POINT/dev"
    mount --bind /dev/pts "$MOUNT_POINT/dev/pts"
    mount --bind /proc "$MOUNT_POINT/proc"
    mount --bind /sys "$MOUNT_POINT/sys"
    
    # Configure APT sources
    cat > "$MOUNT_POINT/etc/apt/sources.list" << EOF
deb $UBUNTU_MIRROR $UBUNTU_RELEASE main restricted universe multiverse
deb $UBUNTU_MIRROR $UBUNTU_RELEASE-updates main restricted universe multiverse
deb $UBUNTU_MIRROR $UBUNTU_RELEASE-security main restricted universe multiverse
deb $UBUNTU_MIRROR $UBUNTU_RELEASE-backports main restricted universe multiverse
EOF
    
    # Configure locale
    echo "en_US.UTF-8 UTF-8" > "$MOUNT_POINT/etc/locale.gen"
    chroot "$MOUNT_POINT" locale-gen
    echo "LANG=en_US.UTF-8" > "$MOUNT_POINT/etc/locale.conf"
    
    # Set timezone to UTC (will be configured later)
    chroot "$MOUNT_POINT" ln -sf /usr/share/zoneinfo/UTC /etc/localtime
    
    # Configure hostname (temporary, will be set during device config)
    echo "ubuntu-os1" > "$MOUNT_POINT/etc/hostname"
    
    # Configure basic hosts file
    cat > "$MOUNT_POINT/etc/hosts" << EOF
127.0.0.1   localhost
127.0.1.1   ubuntu-os1
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF
    
    log "Base system configuration completed"
}

# Install essential packages
install_essential_packages() {
    log "Installing essential packages..."
    
    # Update package lists
    chroot "$MOUNT_POINT" apt-get update
    
    # Install kernel and essential packages
    chroot "$MOUNT_POINT" apt-get install -y \
        "$KERNEL_PACKAGE" \
        linux-firmware \
        grub-efi-amd64 \
        openssh-server \
        network-manager \
        systemd-resolved \
        curl \
        wget \
        nano \
        vim-tiny \
        sudo \
        ufw \
        htop \
        rsync \
        ca-certificates \
        gnupg \
        lsb-release \
        software-properties-common \
        apt-transport-https
    
    log "Essential packages installed"
}

# Configure network
configure_network() {
    log "Configuring network settings..."
    
    # Enable NetworkManager
    chroot "$MOUNT_POINT" systemctl enable NetworkManager
    chroot "$MOUNT_POINT" systemctl enable systemd-resolved
    
    # Configure NetworkManager for automatic DHCP
    cat > "$MOUNT_POINT/etc/NetworkManager/conf.d/01-dhcp.conf" << EOF
[main]
dhcp=dhclient
dns=systemd-resolved

[connectivity]
uri=http://detectportal.firefox.com/canonical.html
response=canonical
EOF
    
    # Create default network connection
    mkdir -p "$MOUNT_POINT/etc/NetworkManager/system-connections"
    cat > "$MOUNT_POINT/etc/NetworkManager/system-connections/Wired connection 1.nmconnection" << EOF
[connection]
id=Wired connection 1
uuid=$(uuidgen)
type=ethernet
autoconnect=true
autoconnect-priority=999

[ethernet]

[ipv4]
method=auto

[ipv6]
method=auto

[proxy]
EOF
    chmod 600 "$MOUNT_POINT/etc/NetworkManager/system-connections/Wired connection 1.nmconnection"
    
    log "Network configuration completed"
}

# Configure SSH
configure_ssh() {
    log "Configuring SSH server..."
    
    # Configure SSH for security
    cat > "$MOUNT_POINT/etc/ssh/sshd_config.d/99-custom.conf" << EOF
# Custom SSH configuration for edge device
Port 22
Protocol 2
LoginGraceTime 60
PermitRootLogin no
StrictModes yes
MaxAuthTries 3
MaxSessions 10
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
X11Forwarding no
PrintMotd no
ClientAliveInterval 300
ClientAliveCountMax 2
UseDNS no
EOF
    
    # Enable SSH service
    chroot "$MOUNT_POINT" systemctl enable ssh
    
    log "SSH configuration completed"
}

# Configure users and security
configure_users() {
    log "Configuring users and security..."
    
    # Create edge user account
    chroot "$MOUNT_POINT" useradd -m -s /bin/bash edge
    chroot "$MOUNT_POINT" usermod -aG sudo edge
    
    # Set temporary password (will be changed during device config)
    echo "edge:edge" | chroot "$MOUNT_POINT" chpasswd
    
    # Force password change on first login
    chroot "$MOUNT_POINT" chage -d 0 edge
    
    # Configure sudo for edge user
    echo "edge ALL=(ALL:ALL) ALL" > "$MOUNT_POINT/etc/sudoers.d/edge"
    chmod 440 "$MOUNT_POINT/etc/sudoers.d/edge"
    
    # Configure basic firewall
    chroot "$MOUNT_POINT" ufw --force enable
    chroot "$MOUNT_POINT" ufw default deny incoming
    chroot "$MOUNT_POINT" ufw default allow outgoing
    chroot "$MOUNT_POINT" ufw allow ssh
    
    log "User and security configuration completed"
}

# Configure filesystem table
configure_fstab() {
    log "Configuring filesystem table..."
    
    # Get partition UUIDs
    local root_uuid=$(blkid -s UUID -o value "$TARGET_PARTITION")
    local efi_uuid=$(blkid -s UUID -o value "/dev/sda1")
    local swap_uuid=$(blkid -s UUID -o value "/dev/sda3")
    local data_uuid=$(blkid -s UUID -o value "/dev/sda6")
    
    # Create fstab
    cat > "$MOUNT_POINT/etc/fstab" << EOF
# Filesystem table for Ubuntu OS1
# <file system> <mount point> <type> <options> <dump> <pass>

# Root filesystem
UUID=$root_uuid / ext4 defaults,noatime 0 1

# EFI System Partition
UUID=$efi_uuid /boot/efi vfat defaults,noatime 0 2

# Swap partition
UUID=$swap_uuid none swap sw 0 0

# Data partition (shared)
UUID=$data_uuid /data ext4 defaults,noatime 0 2

# Temporary filesystems
tmpfs /tmp tmpfs defaults,nodev,nosuid,size=1G 0 0
tmpfs /var/tmp tmpfs defaults,nodev,nosuid,size=512M 0 0
EOF
    
    # Create mount points
    mkdir -p "$MOUNT_POINT/boot/efi"
    mkdir -p "$MOUNT_POINT/data"
    
    log "Filesystem table configured"
}

# Install and configure GRUB
configure_grub() {
    log "Configuring GRUB bootloader..."
    
    # Mount EFI partition
    mkdir -p "$MOUNT_POINT/boot/efi"
    mount /dev/sda1 "$MOUNT_POINT/boot/efi"
    
    # Install GRUB to EFI partition
    chroot "$MOUNT_POINT" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu-os1
    
    # Configure GRUB
    cat > "$MOUNT_POINT/etc/default/grub" << EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Ubuntu OS1"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
GRUB_TERMINAL_OUTPUT="console"
GRUB_DISABLE_SUBMENU=y
EOF
    
    # Generate GRUB configuration
    chroot "$MOUNT_POINT" update-grub
    
    # Unmount EFI partition
    umount "$MOUNT_POINT/boot/efi"
    
    log "GRUB configuration completed"
}

# Create post-install scripts
create_post_install_scripts() {
    log "Creating post-install scripts..."
    
    # Create firstboot script
    cat > "$MOUNT_POINT/usr/local/bin/firstboot-setup.sh" << 'EOF'
#!/bin/bash
# First boot setup script for Ubuntu OS1

set -euo pipefail

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/firstboot.log
}

log "Starting first boot setup..."

# Update package lists
log "Updating package lists..."
apt-get update

# Install any pending updates
log "Installing security updates..."
apt-get upgrade -y

# Configure automatic updates
log "Configuring automatic security updates..."
apt-get install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades

# Set proper permissions
log "Setting proper permissions..."
chmod 755 /data
chown root:root /data

# Create config directory on data partition
mkdir -p /data/config
chown edge:edge /data/config

# Generate SSH host keys if needed
log "Generating SSH host keys..."
dpkg-reconfigure openssh-server

# Remove this script from startup
systemctl disable firstboot-setup.service

log "First boot setup completed"
touch /var/log/firstboot-complete

# Signal completion
wall "Ubuntu OS1 first boot setup completed successfully"
EOF
    
    chmod +x "$MOUNT_POINT/usr/local/bin/firstboot-setup.sh"
    
    # Create systemd service for first boot
    cat > "$MOUNT_POINT/etc/systemd/system/firstboot-setup.service" << EOF
[Unit]
Description=First Boot Setup for Ubuntu OS1
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/firstboot-setup.sh
RemainAfterExit=yes
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable first boot service
    chroot "$MOUNT_POINT" systemctl enable firstboot-setup.service
    
    log "Post-install scripts created"
}

# Clean up installation
cleanup_installation() {
    log "Cleaning up installation..."
    
    # Clean package cache
    chroot "$MOUNT_POINT" apt-get clean
    chroot "$MOUNT_POINT" apt-get autoremove -y
    
    # Clean logs and temporary files
    rm -rf "$MOUNT_POINT/var/log"/*
    rm -rf "$MOUNT_POINT/tmp"/*
    rm -rf "$MOUNT_POINT/var/tmp"/*
    
    # Unmount bind mounts
    umount "$MOUNT_POINT/sys" 2>/dev/null || true
    umount "$MOUNT_POINT/proc" 2>/dev/null || true
    umount "$MOUNT_POINT/dev/pts" 2>/dev/null || true
    umount "$MOUNT_POINT/dev" 2>/dev/null || true
    
    # Unmount main filesystem
    umount "$MOUNT_POINT"
    
    log "Installation cleanup completed"
}

# Show completion message
show_completion() {
    log "Ubuntu OS1 installation completed successfully!"
    
    echo
    echo "=== Installation Complete ==="
    echo
    echo "Ubuntu 24.04.3 LTS has been installed on $TARGET_PARTITION"
    echo
    echo "System details:"
    echo "  - Release: Ubuntu 24.04.3 LTS (Noble)"
    echo "  - Kernel: linux-generic"
    echo "  - Default user: edge (password: edge - must be changed on first login)"
    echo "  - SSH server: enabled on port 22"
    echo "  - Firewall: enabled with SSH access allowed"
    echo "  - Network: DHCP configured via NetworkManager"
    echo
    echo "Next steps:"
    echo "1. Run 'install-os2' to install secondary Ubuntu system"
    echo "2. Boot into OS1 and complete initial configuration"
    echo "3. Change default password for 'edge' user"
    echo "4. Configure network settings if needed"
    echo
    echo "The system is ready for first boot."
    echo
    echo "Press Enter to continue..."
    read
}

# Save installation log
save_installation_log() {
    local log_file="/tmp/os1-install-$(date +%Y%m%d-%H%M%S).log"
    
    cat > "$log_file" << EOF
# Ubuntu OS1 Installation Log
# Generated on $(date)

Installation Details:
- Target Partition: $TARGET_PARTITION
- Ubuntu Release: $UBUNTU_RELEASE
- Mirror: $UBUNTU_MIRROR
- Kernel Package: $KERNEL_PACKAGE

Partition Information:
$(blkid | grep /dev/sda)

Installation completed: $(date)
EOF
    
    info "Installation log saved to $log_file"
    
    # Try to save to data partition
    if mkdir -p /mnt/data-temp && mount /dev/sda6 /mnt/data-temp 2>/dev/null; then
        mkdir -p /mnt/data-temp/logs
        cp "$log_file" /mnt/data-temp/logs/
        umount /mnt/data-temp
        info "Installation log also saved to data partition"
    fi
    
    rm -rf /mnt/data-temp
}

# Main execution
main() {
    show_welcome
    check_prerequisites
    prepare_mount_point
    install_base_system
    configure_base_system
    install_essential_packages
    configure_network
    configure_ssh
    configure_users
    configure_fstab
    configure_grub
    create_post_install_scripts
    cleanup_installation
    save_installation_log
    show_completion
}

# Run main function
main "$@"
