#!/bin/bash
# 02-system-configuration.sh
# Configure base system settings and prepare chroot environment
# Part of the device initialization build process

set -euo pipefail

# Script configuration
SCRIPT_NAME="02-system-configuration"
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
    info "Configuring base system settings and chroot environment"
}

# Check prerequisites from previous script
check_prerequisites() {
    log "Checking prerequisites from previous build stages..."
    
    # Check that bootstrap completed
    if [[ ! -f "$BUILD_LOG_DIR/01-bootstrap-environment.log" ]]; then
        error "Bootstrap environment script has not completed successfully"
    fi
    
    # Check required tools are available
    local required_tools=("debootstrap" "chroot" "mount" "umount")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error "Required tool '$tool' not found"
        fi
    done
    
    # Check build directories exist
    if [[ ! -d "$BUILD_DIR" ]]; then
        error "Build directory $BUILD_DIR not found"
    fi
    
    log "Prerequisites check completed"
}

# Create base filesystem structure
create_filesystem_structure() {
    log "Creating base filesystem structure..."
    
    # Create root filesystem directory
    local root_fs_dir="$BUILD_DIR/rootfs"
    mkdir -p "$root_fs_dir"
    
    # Create standard Linux directory structure
    # Note: bin, sbin, lib, lib64 are excluded as debootstrap creates them as symlinks to usr/*
    local directories=(
        "usr/bin" "usr/sbin" "usr/lib" "usr/lib64" "usr/share"
        "etc" "var/log" "var/lib" "var/cache" "var/tmp"
        "tmp" "home" "root" "boot" "boot/efi"
        "dev" "proc" "sys" "run"
        "opt" "srv" "mnt" "media"
        "data" "config"
    )
    
    for dir in "${directories[@]}"; do
        mkdir -p "$root_fs_dir/$dir"
        info "Created directory: $dir"
    done
    
    log "Filesystem structure created"
}

# Install base Ubuntu system
install_base_system() {
    log "Installing base Ubuntu system with debootstrap..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    local ubuntu_mirror="${UBUNTU_MIRROR:-http://archive.ubuntu.com/ubuntu}"
    local ubuntu_release="${UBUNTU_RELEASE:-noble}"
    
    # Create cache directory for debootstrap
    mkdir -p "$BUILD_DIR/cache"
    
    # Check memory and create larger swap if needed
    local available_memory=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    local total_memory=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local required_memory=$((2 * 1024 * 1024))  # 2GB in KB
    local temp_swap=""
    
    info "Memory status: Total=${total_memory}KB, Available=${available_memory}KB, Required=${required_memory}KB"
    
    if [[ "$available_memory" -lt "$required_memory" ]]; then
        warn "Low memory detected. Creating larger temporary swap file..."
        
        # Check available disk space in /tmp
        local tmp_available=$(df /tmp | tail -1 | awk '{print $4}')
        local swap_size_mb=4096  # 4GB swap for very low memory systems
        local swap_size_kb=$((swap_size_mb * 1024))
        
        if [[ "$tmp_available" -lt "$swap_size_kb" ]]; then
            warn "Insufficient disk space in /tmp. Reducing swap size to 2GB"
            swap_size_mb=2048
        fi
        
        temp_swap="/tmp/build-swap-$$"
        info "Creating ${swap_size_mb}MB temporary swap file..."
        
        # Create swap with better error handling
        if dd if=/dev/zero of="$temp_swap" bs=1M count="$swap_size_mb" 2>/dev/null; then
            chmod 600 "$temp_swap"
            if mkswap "$temp_swap" >/dev/null 2>&1; then
                if swapon "$temp_swap" >/dev/null 2>&1; then
                    info "Temporary swap file activated successfully"
                    # Verify swap is active
                    swapon --show | grep "$temp_swap" && info "Swap verification successful"
                else
                    warn "Could not activate temporary swap file"
                    rm -f "$temp_swap"
                    temp_swap=""
                fi
            else
                warn "Could not format temporary swap file"
                rm -f "$temp_swap"
                temp_swap=""
            fi
        else
            warn "Could not create temporary swap file"
            temp_swap=""
        fi
        
        # Force memory cleanup before proceeding
        sync
        echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
        sleep 2
    fi
    
    # Run debootstrap to install minimal Ubuntu system with memory optimizations
    debootstrap \
        --arch=amd64 \
        --variant=minbase \
        --include=systemd,systemd-sysv,dbus,apt-utils,locales,ca-certificates,gnupg,gpgv \
        --cache-dir="$BUILD_DIR/cache" \
        "$ubuntu_release" \
        "$root_fs_dir" \
        "$ubuntu_mirror" || {
            # Clean up temporary swap on failure
            if [[ -n "$temp_swap" && -f "$temp_swap" ]]; then
                swapoff "$temp_swap" 2>/dev/null || true
                rm -f "$temp_swap"
            fi
            error "debootstrap installation failed"
        }
    
    # Clean up temporary swap on success
    if [[ -n "$temp_swap" && -f "$temp_swap" ]]; then
        swapoff "$temp_swap" 2>/dev/null || true
        rm -f "$temp_swap"
        info "Temporary swap file cleaned up"
    fi
    
    log "Base Ubuntu system installed successfully"
}

# Configure APT sources
configure_apt_sources() {
    log "Configuring APT package sources..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    local ubuntu_mirror="${UBUNTU_MIRROR:-http://archive.ubuntu.com/ubuntu}"
    local ubuntu_release="${UBUNTU_RELEASE:-noble}"
    
    # Create sources.list with all repositories
    cat > "$root_fs_dir/etc/apt/sources.list" << EOF
# Ubuntu Package Repositories
deb $ubuntu_mirror $ubuntu_release main restricted universe multiverse
deb $ubuntu_mirror $ubuntu_release-updates main restricted universe multiverse
deb $ubuntu_mirror $ubuntu_release-security main restricted universe multiverse
deb $ubuntu_mirror $ubuntu_release-backports main restricted universe multiverse

# Source packages (commented out by default)
# deb-src $ubuntu_mirror $ubuntu_release main restricted universe multiverse
# deb-src $ubuntu_mirror $ubuntu_release-updates main restricted universe multiverse
# deb-src $ubuntu_mirror $ubuntu_release-security main restricted universe multiverse
# deb-src $ubuntu_mirror $ubuntu_release-backports main restricted universe multiverse
EOF
    
    # Configure APT preferences if needed
    mkdir -p "$root_fs_dir/etc/apt/preferences.d"
    
    # Set up APT configuration for non-interactive operation
    cat > "$root_fs_dir/etc/apt/apt.conf.d/99noninteractive" << EOF
APT::Get::Assume-Yes "true";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
DPkg::Options {
    "--force-confdef";
    "--force-confold";
}
Dpkg::Use-Pty "0";
EOF
    
    log "APT sources configured"
}

# Configure system locales
configure_locales() {
    log "Configuring system locales..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    
    # Configure locales
    echo "en_US.UTF-8 UTF-8" > "$root_fs_dir/etc/locale.gen"
    echo "C.UTF-8 UTF-8" >> "$root_fs_dir/etc/locale.gen"
    
    # Set default locale
    cat > "$root_fs_dir/etc/locale.conf" << EOF
LANG=en_US.UTF-8
LC_ALL=en_US.UTF-8
EOF
    
    # Also create environment file for compatibility
    cat > "$root_fs_dir/etc/environment" << EOF
LANG=en_US.UTF-8
LC_ALL=en_US.UTF-8
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EOF
    
    log "Locales configured"
}

# Configure timezone
configure_timezone() {
    log "Configuring timezone..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    local default_timezone="${DEFAULT_TIMEZONE:-UTC}"
    
    # Set timezone to UTC by default (will be configurable later)
    ln -sf "/usr/share/zoneinfo/$default_timezone" "$root_fs_dir/etc/localtime"
    echo "$default_timezone" > "$root_fs_dir/etc/timezone"
    
    log "Timezone set to $default_timezone"
}

# Configure hostname and hosts
configure_hostname() {
    log "Configuring hostname and hosts file..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    local default_hostname="${DEFAULT_HOSTNAME:-edge-device}"
    
    # Set hostname
    echo "$default_hostname" > "$root_fs_dir/etc/hostname"
    
    # Configure hosts file
    cat > "$root_fs_dir/etc/hosts" << EOF
127.0.0.1   localhost
127.0.1.1   $default_hostname
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF
    
    log "Hostname configured as $default_hostname"
}

# Setup chroot environment
setup_chroot_environment() {
    log "Setting up chroot environment..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    
    # Mount necessary filesystems for chroot
    mount --bind /dev "$root_fs_dir/dev"
    mount --bind /dev/pts "$root_fs_dir/dev/pts"
    mount --bind /proc "$root_fs_dir/proc"
    mount --bind /sys "$root_fs_dir/sys"
    
    # Create a script to clean up mounts
    cat > "$BUILD_DIR/cleanup-chroot.sh" << EOF
#!/bin/bash
# Cleanup script for chroot environment
umount "$root_fs_dir/sys" 2>/dev/null || true
umount "$root_fs_dir/proc" 2>/dev/null || true
umount "$root_fs_dir/dev/pts" 2>/dev/null || true
umount "$root_fs_dir/dev" 2>/dev/null || true
EOF
    chmod +x "$BUILD_DIR/cleanup-chroot.sh"
    
    # Test chroot environment
    chroot "$root_fs_dir" /bin/bash -c "echo 'Chroot environment test successful'" || error "Chroot environment setup failed"
    
    log "Chroot environment ready"
}

# Configure network settings
configure_network() {
    log "Configuring network settings..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    
    # Create systemd-networkd configuration for DHCP
    mkdir -p "$root_fs_dir/etc/systemd/network"
    
    cat > "$root_fs_dir/etc/systemd/network/10-dhcp.network" << EOF
[Match]
Name=eth* en* em*

[Network]
DHCP=yes
LinkLocalAddressing=yes

[DHCP]
UseDNS=yes
UseNTP=yes
UseHostname=false
EOF
    
    # Configure systemd-resolved
    mkdir -p "$root_fs_dir/etc/systemd/resolved.conf.d"
    cat > "$root_fs_dir/etc/systemd/resolved.conf.d/10-custom.conf" << EOF
[Resolve]
DNS=8.8.8.8 8.8.4.4
FallbackDNS=1.1.1.1 1.0.0.1
Domains=~.
DNSSEC=no
DNSOverTLS=no
Cache=yes
DNSStubListener=yes
EOF
    
    log "Network configuration completed"
}

# Create device configuration scripts
create_device_config_scripts() {
    log "Installing device configuration scripts..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    local config_scripts_dir="$root_fs_dir/usr/local/bin"
    
    mkdir -p "$config_scripts_dir"
    
    # Copy configuration scripts from our config directory
    local script_source_dir="$(dirname "$0")/config"
    if [[ -d "$script_source_dir" ]]; then
        cp "$script_source_dir"/*.sh "$config_scripts_dir/"
        chmod +x "$config_scripts_dir"/*.sh
        
        info "Installed configuration scripts:"
        ls -la "$config_scripts_dir"/*.sh | while read line; do
            info "  $(basename $(echo $line | awk '{print $NF}'))"
        done
    else
        warn "Configuration scripts directory not found: $script_source_dir"
    fi
    
    # Create config directory structure
    mkdir -p "$root_fs_dir/data/config"
    mkdir -p "$root_fs_dir/data/logs"
    mkdir -p "$root_fs_dir/data/backup"
    
    log "Device configuration scripts installed"
}

# Configure systemd services
configure_systemd_services() {
    log "Configuring systemd services..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    
    # Create first-boot configuration service
    cat > "$root_fs_dir/etc/systemd/system/first-boot-config.service" << EOF
[Unit]
Description=First Boot Device Configuration
After=network-online.target
Wants=network-online.target
ConditionFirstBoot=yes

[Service]
Type=oneshot
ExecStart=/usr/local/bin/configure-device.sh --first-boot
RemainAfterExit=yes
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable systemd services
    local chroot_enable_services="systemd-networkd systemd-resolved first-boot-config"
    
    for service in $chroot_enable_services; do
        chroot "$root_fs_dir" systemctl enable "$service" || warn "Failed to enable $service"
    done
    
    log "Systemd services configured"
}

# Create fstab template
create_fstab_template() {
    log "Creating fstab template..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    
    # Create a template fstab that will be updated during installation
    cat > "$root_fs_dir/etc/fstab.template" << EOF
# Filesystem table template for edge device
# This template will be populated with actual UUIDs during installation
# <file system> <mount point> <type> <options> <dump> <pass>

# Root filesystem (Root partition)
UUID=__ROOT_UUID__ / ext4 defaults,noatime 0 1

# EFI System Partition
UUID=__EFI_UUID__ /boot/efi vfat defaults,noatime 0 2

# Swap partition
UUID=__SWAP_UUID__ none swap sw 0 0

# Data partition (shared between OS1 and OS2)
UUID=__DATA_UUID__ /data ext4 defaults,noatime 0 2

# Temporary filesystems
tmpfs /tmp tmpfs defaults,nodev,nosuid,size=1G 0 0
tmpfs /var/tmp tmpfs defaults,nodev,nosuid,size=512M 0 0
EOF
    
    log "Fstab template created"
}

# Cleanup and finalize
cleanup_and_finalize() {
    log "Cleaning up and finalizing system configuration..."
    
    local root_fs_dir="$BUILD_DIR/rootfs"
    
    # Clean up any temporary files
    rm -rf "$root_fs_dir/tmp"/*
    rm -rf "$root_fs_dir/var/tmp"/*
    
    # Clear logs that might have been created during setup
    find "$root_fs_dir/var/log" -type f -exec truncate -s 0 {} \;
    
    # Set proper permissions
    chmod 755 "$root_fs_dir"
    chmod 755 "$root_fs_dir/data"
    chmod 1777 "$root_fs_dir/tmp"
    chmod 1777 "$root_fs_dir/var/tmp"
    
    log "System configuration cleanup completed"
}

# Save configuration log
save_configuration_log() {
    local log_file="$BUILD_LOG_DIR/$SCRIPT_NAME.summary.log"
    
    cat > "$log_file" << EOF
# System Configuration Log
# Generated by $SCRIPT_NAME v$SCRIPT_VERSION on $(date)

Build Configuration:
- Build Directory: $BUILD_DIR
- Ubuntu Release: ${UBUNTU_RELEASE:-noble}
- Ubuntu Mirror: ${UBUNTU_MIRROR:-http://archive.ubuntu.com/ubuntu}
- Default Hostname: ${DEFAULT_HOSTNAME:-edge-device}
- Default Timezone: ${DEFAULT_TIMEZONE:-UTC}

Actions Completed:
- Base Ubuntu system installed via debootstrap
- APT sources configured
- Locales configured (en_US.UTF-8)
- Timezone set
- Hostname configured
- Chroot environment prepared
- Network configuration created
- Device configuration scripts installed
- Systemd services configured
- Fstab template created

Files Created:
$(find "$BUILD_DIR/rootfs" -type f -newer "$BUILD_DIR" 2>/dev/null | head -20)

Configuration completed: $(date)
Next step: Run 03-package-installation.sh
EOF
    
    info "Configuration log saved to $log_file"
}

# Main execution function
main() {
    show_header
    check_prerequisites
    create_filesystem_structure
    install_base_system
    configure_apt_sources
    configure_locales
    configure_timezone
    configure_hostname
    setup_chroot_environment
    configure_network
    create_device_config_scripts
    configure_systemd_services
    create_fstab_template
    cleanup_and_finalize
    save_configuration_log
    
    log "$SCRIPT_NAME completed successfully"
    info "System base configuration ready for package installation"
    info "Next: Run 03-package-installation.sh"
}

# Trap to cleanup on exit
cleanup_on_exit() {
    if [[ -f "$BUILD_DIR/cleanup-chroot.sh" ]]; then
        "$BUILD_DIR/cleanup-chroot.sh"
    fi
}
trap cleanup_on_exit EXIT

# Run main function
main "$@"
