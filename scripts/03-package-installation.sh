#!/bin/bash
# 03-package-installation.sh
# Install essential packages and software for the device initialization system
# Part of the device initialization build process

set -euo pipefail

# Script configuration
SCRIPT_NAME="03-package-installation"
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
    info "Installing essential packages and software"
}

# Check prerequisites from previous script
check_prerequisites() {
    log "Checking prerequisites from previous build stages..."
    
    # Check that system configuration completed
    if [[ ! -f "$BUILD_LOG_DIR/02-system-configuration.log" ]]; then
        error "System configuration script has not completed successfully"
    fi
    
    # Check rootfs exists
    if [[ ! -d "$BUILD_DIR/rootfs" ]]; then
        error "Root filesystem directory not found"
    fi
    
    # Check chroot environment is available
    if ! chroot "$BUILD_DIR/rootfs" /bin/bash -c "echo 'Chroot test'" &>/dev/null; then
        error "Chroot environment not properly configured"
    fi
    
    log "Prerequisites check completed"
}

# Install host build tools needed for testing and validation
install_host_build_tools() {
    log "Installing host build tools for image creation, testing and validation..."
    
    # Core system tools needed for build environment
    local core_tools=(
        "debootstrap"      # For creating minimal Ubuntu systems
        "parted"           # For disk partitioning
        "fdisk"            # For disk manipulation  
        "util-linux"       # Provides losetup, mount, umount
        "e2fsprogs"        # Provides mkfs.ext4, resize2fs, e2fsck
        "dosfstools"       # Provides mkfs.fat for EFI partitions
    )
    
    # Compression and archive tools
    local compression_tools=(
        "gzip"             # For creating .gz compressed images
    )
    
    # File and data management tools
    local file_tools=(
        "rsync"            # For efficient file copying
        "file"             # For file type detection
        "pv"               # For progress viewing during operations
        "bc"               # For arithmetic calculations
        "jq"               # For JSON processing
    )
    
    # Virtualization and testing tools
    local virt_tools=(
        "qemu-system-x86"  # For virtualization testing
        "qemu-utils"       # For disk image utilities (qemu-img)
    )
    
    # Combine all tool lists
    local all_host_tools=("${core_tools[@]}" "${compression_tools[@]}" "${file_tools[@]}" "${virt_tools[@]}")
    
    # Update package lists once
    info "Updating package lists..."
    apt-get update -qq || warn "Failed to update package lists"
    
    # Install each tool if not already present
    for tool in "${all_host_tools[@]}"; do
        if ! dpkg -l | grep -q "^ii  $tool "; then
            info "Installing host tool: $tool"
            apt-get install -y "$tool" || warn "Failed to install $tool"
        else
            info "Host tool already installed: $tool"
        fi
    done
    
    # Verify critical tools are available
    local critical_commands=("debootstrap" "parted" "losetup" "mkfs.ext4" "mkfs.fat" "rsync" "gzip")
    local missing_tools=()
    
    for cmd in "${critical_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_tools+=("$cmd")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        error "Critical build tools are missing: ${missing_tools[*]}"
        error "Build environment setup failed"
        return 1
    fi
    
    log "Host build tools installation completed successfully"
}

# Setup chroot environment
setup_chroot_environment() {
    log "Setting up chroot environment for package installation..."
    
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
    
    # Ensure /dev/null exists and has proper permissions
    if [[ ! -c "$root_fs_dir/dev/null" ]]; then
        mknod "$root_fs_dir/dev/null" c 1 3
        chmod 666 "$root_fs_dir/dev/null"
    fi
    
    # Copy resolv.conf for internet access
    cp /etc/resolv.conf "$root_fs_dir/etc/resolv.conf"
    
    # Configure non-interactive mode for package installation
    cat > "$root_fs_dir/etc/environment" << EOF
DEBIAN_FRONTEND=noninteractive
DEBCONF_NONINTERACTIVE_SEEN=true
EOF
    
    # Pre-configure timezone to avoid interactive prompts
    echo "${TIMEZONE:-UTC}" > "$root_fs_dir/etc/timezone"
    chroot "$root_fs_dir" ln -sf "/usr/share/zoneinfo/${TIMEZONE:-UTC}" /etc/localtime
    
    # Pre-configure debconf for non-interactive installation
    cat > "$root_fs_dir/tmp/debconf-set-selections" << EOF
tzdata tzdata/Areas select Etc
tzdata tzdata/Zones/Etc select UTC
locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8
locales locales/default_environment_locale select en_US.UTF-8
keyboard-configuration keyboard-configuration/layoutcode string us
keyboard-configuration keyboard-configuration/variantcode string
EOF
    
    chroot "$root_fs_dir" debconf-set-selections < "$root_fs_dir/tmp/debconf-set-selections"
    rm -f "$root_fs_dir/tmp/debconf-set-selections"
    
    log "Chroot environment ready with non-interactive configuration"
}

# Install GPG verification tools in chroot
install_gpg_tools() {
    log "Installing GPG verification tools in chroot..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    
    # Temporarily disable signature verification to install gpg tools
    cat > "$root_fs_dir/etc/apt/apt.conf.d/99-disable-gpg-verify" << EOF
APT::Get::AllowUnauthenticated "true";
Acquire::AllowInsecureRepositories "true";
Acquire::AllowDowngradeToInsecureRepositories "true";
EOF
    
    # Install GPG verification tools
    info "Installing gnupg and gpgv packages..."
    chroot "$root_fs_dir" apt-get update -o APT::Get::AllowUnauthenticated=true
    chroot "$root_fs_dir" apt-get install -y -o APT::Get::AllowUnauthenticated=true gnupg gpgv
    
    # Re-enable signature verification
    rm -f "$root_fs_dir/etc/apt/apt.conf.d/99-disable-gpg-verify"
    
    log "GPG verification tools installed successfully"
}

# Update package lists
update_package_lists() {
    log "Updating package lists..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    
    # Update package database
    chroot "$root_fs_dir" apt-get update || error "Failed to update package lists"
    
    log "Package lists updated successfully"
}

# Install essential system packages
install_essential_packages() {
    log "Installing essential system packages..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    
    # Essential system packages
    local essential_packages=(
        # Core system
        "systemd"
        "systemd-sysv"
        "udev"
        "kmod"
        "util-linux"
        "coreutils"
        "findutils"
        "grep"
        "sed"
        "gawk"
        "bash-completion"
        
        # Hardware support
        "linux-firmware"
        "firmware-linux-free"
        "pciutils"
        "usbutils"
        "lshw"
        "dmidecode"
        
        # File systems
        "e2fsprogs"
        "dosfstools"
        "ntfs-3g"
        "parted"
        "gdisk"
        
        # Compression and archiving
        "tar"
        "gzip"
        
        # Text editors and tools
        "nano"
        "vim-tiny"
        "less"
        "more"
        
        # Process management
        "procps"
        "psmisc"
        "htop"
        
        # Network tools
        "iproute2"
        "iputils-ping"
        "net-tools"
        "wget"
        "curl"
        "openssh-client"
        "rsync"
    )
    
    # Install packages in chunks to handle potential failures
    for package in "${essential_packages[@]}"; do
        info "Installing: $package"
        chroot "$root_fs_dir" env DEBIAN_FRONTEND=noninteractive apt-get install -y "$package" || warn "Failed to install $package"
    done
    
    log "Essential packages installed"
}

# Install kernel and boot packages
install_kernel_packages() {
    log "Installing kernel and boot packages..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    local kernel_package="${KERNEL_PACKAGE:-linux-generic}"
    
    # Kernel and boot packages
    local kernel_packages=(
        "$kernel_package"
        "linux-firmware"
        "initramfs-tools"
        "grub-efi-amd64"
        "grub-efi-amd64-signed"
        "shim-signed"
        "os-prober"
        "efibootmgr"
    )
    
    for package in "${kernel_packages[@]}"; do
        info "Installing kernel package: $package"
        chroot "$root_fs_dir" env DEBIAN_FRONTEND=noninteractive apt-get install -y "$package" || warn "Failed to install $package"
    done
    
    # Generate initramfs for the installed kernel
    generate_initramfs
    
    log "Kernel and boot packages installed"
}

# Generate initramfs for the kernel
generate_initramfs() {
    log "Generating initramfs..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    
    # Find the kernel version
    local kernel_version=$(chroot "$root_fs_dir" find /lib/modules -maxdepth 1 -type d -name "*-generic" | head -1 | sed 's|.*/||')
    
    if [[ -n "$kernel_version" ]]; then
        info "Generating initramfs for kernel: $kernel_version"
        chroot "$root_fs_dir" update-initramfs -c -k "$kernel_version" || warn "Failed to generate initramfs"
    else
        warn "No kernel version found for initramfs generation"
    fi
    
    log "Initramfs generation completed"
}

# Install network packages
install_network_packages() {
    log "Installing network packages..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    
    # Network packages
    local network_packages=(
        "systemd-resolved"
        "systemd-networkd"
        "networkd-dispatcher"
        "bridge-utils"
        "vlan"
        "ethtool"
        "wireless-tools"
        "wpasupplicant"
        "dnsutils"
        "nmap"
        "tcpdump"
        "iptables"
        "netfilter-persistent"
        "iptables-persistent"
    )
    
    for package in "${network_packages[@]}"; do
        info "Installing network package: $package"
        chroot "$root_fs_dir" env DEBIAN_FRONTEND=noninteractive apt-get install -y "$package" || warn "Failed to install $package"
    done
    
    log "Network packages installed"
}

# Install security packages
install_security_packages() {
    log "Installing security packages..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    
    # Security packages
    local security_packages=(
        "openssh-server"
        "ufw"
        "fail2ban"
        "sudo"
        "passwd"
        "shadow-utils"
        "ca-certificates"
        "gnupg"
        "openssl"
        "unattended-upgrades"
        "apt-listchanges"
    )
    
    for package in "${security_packages[@]}"; do
        info "Installing security package: $package"
        chroot "$root_fs_dir" env DEBIAN_FRONTEND=noninteractive apt-get install -y "$package" || warn "Failed to install $package"
    done
    
    log "Security packages installed"
}

# Install development and debugging tools
install_development_packages() {
    log "Installing development and debugging tools..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    
    # Development packages
    local dev_packages=(
        "build-essential"
        "git"
        "python3"
        "python3-pip"
        "python3-venv"
        "nodejs"
        "npm"
        "jq"
        "yq"
        "strace"
        "ltrace"
        "gdb"
        "valgrind"
        "tmux"
        "screen"
    )
    
    for package in "${dev_packages[@]}"; do
        info "Installing development package: $package"
        chroot "$root_fs_dir" env DEBIAN_FRONTEND=noninteractive apt-get install -y "$package" || warn "Failed to install $package"
    done
    
    log "Development packages installed"
}

# Install monitoring and logging packages
install_monitoring_packages() {
    log "Installing monitoring and logging packages..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    
    # Monitoring packages
    local monitoring_packages=(
        "rsyslog"
        "logrotate"
        "sysstat"
        "iotop"
        "iftop"
        "nethogs"
        "dstat"
        "lsof"
        "tree"
        "ncdu"
        "smartmontools"
        "hdparm"
    )
    
    for package in "${monitoring_packages[@]}"; do
        info "Installing monitoring package: $package"
        chroot "$root_fs_dir" env DEBIAN_FRONTEND=noninteractive apt-get install -y "$package" || warn "Failed to install $package"
    done
    
    log "Monitoring packages installed"
}

# Install edge computing specific packages
install_edge_packages() {
    log "Installing edge computing specific packages..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    
    # Edge computing packages
    local edge_packages=(
        "docker.io"
        "docker-compose"
        "containerd"
        "podman"
        "skopeo"
        "runc"
        "criu"
        "lxc"
        "qemu-user-static"
        "binfmt-support"
    )
    
    for package in "${edge_packages[@]}"; do
        info "Installing edge package: $package"
        chroot "$root_fs_dir" env DEBIAN_FRONTEND=noninteractive apt-get install -y "$package" || warn "Failed to install $package"
    done
    
    log "Edge computing packages installed"
}

# Configure installed packages
configure_packages() {
    log "Configuring installed packages..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    
    # Configure SSH server
    configure_ssh_server "$root_fs_dir"
    
    # Configure firewall
    configure_firewall "$root_fs_dir"
    
    # Configure Docker
    configure_docker "$root_fs_dir"
    
    # Configure automatic updates
    configure_automatic_updates "$root_fs_dir"
    
    # Configure logging
    configure_logging "$root_fs_dir"
    
    log "Package configuration completed"
}

# Configure SSH server
configure_ssh_server() {
    local root_fs_dir="$1"
    
    info "Configuring SSH server..."
    
    # Create SSH configuration
    cat > "$root_fs_dir/etc/ssh/sshd_config.d/99-edge-device.conf" << EOF
# SSH configuration for edge device
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
    chroot "$root_fs_dir" systemctl enable ssh || warn "Failed to enable SSH service"
}

# Configure firewall
configure_firewall() {
    local root_fs_dir="$1"
    
    info "Configuring firewall..."
    
    # Create UFW configuration
    cat > "$root_fs_dir/etc/ufw/user.rules" << EOF
# UFW rules for edge device
*filter
:ufw-user-input - [0:0]
:ufw-user-output - [0:0]
:ufw-user-forward - [0:0]
:ufw-user-limit - [0:0]
:ufw-user-limit-accept - [0:0]

# Allow SSH
-A ufw-user-input -p tcp --dport 22 -j ACCEPT

# Allow DHCP client
-A ufw-user-input -p udp --sport 67 --dport 68 -j ACCEPT

# Allow established connections
-A ufw-user-input -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

COMMIT
EOF
    
    # Enable UFW service
    chroot "$root_fs_dir" systemctl enable ufw || warn "Failed to enable UFW service"
}

# Configure Docker
configure_docker() {
    local root_fs_dir="$1"
    
    info "Configuring Docker..."
    
    # Create Docker configuration
    mkdir -p "$root_fs_dir/etc/docker"
    cat > "$root_fs_dir/etc/docker/daemon.json" << EOF
{
    "data-root": "/data/docker",
    "storage-driver": "overlay2",
    "log-driver": "journald",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "live-restore": true,
    "userland-proxy": false,
    "no-new-privileges": true
}
EOF
    
    # Enable Docker service
    chroot "$root_fs_dir" systemctl enable docker || warn "Failed to enable Docker service"
    chroot "$root_fs_dir" systemctl enable containerd || warn "Failed to enable containerd service"
}

# Configure automatic updates
configure_automatic_updates() {
    local root_fs_dir="$1"
    
    info "Configuring automatic updates..."
    
    # Configure unattended-upgrades
    cat > "$root_fs_dir/etc/apt/apt.conf.d/50unattended-upgrades" << EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
    "\${distro_id}:\${distro_codename}-updates";
};

Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";
EOF
    
    cat > "$root_fs_dir/etc/apt/apt.conf.d/20auto-upgrades" << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
EOF
}

# Configure logging
configure_logging() {
    local root_fs_dir="$1"
    
    info "Configuring logging..."
    
    # Configure logrotate for edge device
    cat > "$root_fs_dir/etc/logrotate.d/edge-device" << EOF
/data/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
    create 644 root root
}
EOF
    
    # Configure rsyslog for data partition logging
    cat > "$root_fs_dir/etc/rsyslog.d/10-edge-device.conf" << EOF
# Edge device logging configuration
# Log device-specific events to data partition
:programname, isequal, "edge-device" /data/logs/device.log
& stop
EOF
}

# Generate package manifest
generate_package_manifest() {
    log "Generating package manifest..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    local manifest_file="$BUILD_DIR/package-manifest.txt"
    
    # Generate package list
    chroot "$root_fs_dir" dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\t${Status}\n' > "$manifest_file"
    
    # Generate package summary
    local package_count=$(chroot "$root_fs_dir" dpkg-query -W | wc -l)
    local installed_size=$(chroot "$root_fs_dir" dpkg-query -W -f='${Installed-Size}\n' | awk '{sum+=$1} END {print sum}')
    
    cat > "$BUILD_DIR/package-summary.txt" << EOF
Package Installation Summary
Generated: $(date)

Total packages installed: $package_count
Total installed size: ${installed_size} KB

Categories installed:
- Essential system packages
- Kernel and boot packages  
- Network packages
- Security packages
- Development packages
- Monitoring packages
- Edge computing packages

Package manifest: package-manifest.txt
EOF
    
    info "Package manifest generated: $manifest_file"
    info "Package summary: $BUILD_DIR/package-summary.txt"
}

# Clean up package cache
cleanup_packages() {
    log "Cleaning up package cache..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    
    # Clean package cache
    chroot "$root_fs_dir" env DEBIAN_FRONTEND=noninteractive apt-get clean
    chroot "$root_fs_dir" env DEBIAN_FRONTEND=noninteractive apt-get autoremove -y
    
    # Remove package lists to save space (will be regenerated on first boot)
    rm -rf "$root_fs_dir/var/lib/apt/lists"/*
    
    log "Package cleanup completed"
}

# Save installation log
save_installation_log() {
    local log_file="$BUILD_LOG_DIR/$SCRIPT_NAME.log"
    
    cat > "$log_file" << EOF
# Package Installation Log
# Generated by $SCRIPT_NAME v$SCRIPT_VERSION on $(date)

Build Configuration:
- Build Directory: $BUILD_DIR
- Kernel Package: ${KERNEL_PACKAGE:-linux-generic}

Package Categories Installed:
- Essential system packages
- Kernel and boot packages
- Network packages
- Security packages
- Development packages
- Monitoring packages
- Edge computing packages

Configuration Applied:
- SSH server configured
- Firewall (UFW) configured
- Docker configured
- Automatic updates configured
- Logging configured

Artifacts Generated:
- $BUILD_DIR/package-manifest.txt
- $BUILD_DIR/package-summary.txt

Installation completed: $(date)
Next step: Run 04-grub-configuration.sh
EOF
    
    info "Installation log saved to $log_file"
}

# Main execution function
main() {
    show_header
    check_prerequisites
    install_host_build_tools
    setup_chroot_environment
    install_gpg_tools
    update_package_lists
    install_essential_packages
    install_kernel_packages
    install_network_packages
    install_security_packages
    install_development_packages
    install_monitoring_packages
    install_edge_packages
    configure_packages
    generate_package_manifest
    cleanup_packages
    save_installation_log
    
    log "$SCRIPT_NAME completed successfully"
    info "All packages installed and configured"
    info "Next: Run 04-grub-configuration.sh"
}

# Run main function
main "$@"
