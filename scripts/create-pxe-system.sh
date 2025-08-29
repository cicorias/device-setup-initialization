#!/bin/bash

set -eo pipefail

# Configuration
ARTIFACTS="${ARTIFACTS:-$(pwd -P)/artifacts}"
CHROOT_DIR="${ARTIFACTS}/pxe-rootfs"
PXE_DIR="${ARTIFACTS}/pxe-files"
OS_IMAGES_DIR="${ARTIFACTS}/os-images"

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
    mkdir -p "${ARTIFACTS}" "${PXE_DIR}" "${OS_IMAGES_DIR}"
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
    log "Creating SquashFS filesystem..."
    sudo mksquashfs "${CHROOT_DIR}" "${PXE_DIR}/filesystem.squashfs" -e boot
    
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

# Generate server deployment package
create_deployment_package() {
    log "Creating server deployment package..."
    
    DEPLOY_DIR="${ARTIFACTS}/server-deployment"
    mkdir -p "${DEPLOY_DIR}/config"
    
    # Create deployment README
    cat > "${DEPLOY_DIR}/README.md" << 'EOF'
# PXE Server Deployment Package

This package contains everything needed to set up a complete PXE boot server using standard PXE implementation (PXELINUX).

## Quick Setup
1. Copy this entire directory to your server
2. Edit `config/server-config.env` with your network settings
3. Run `./deploy-pxe-server.sh`

## Manual Setup
- Run individual scripts in order:
  1. `./install-services.sh`
  2. `./configure-dhcp.sh` 
  3. `./setup-tftp.sh`
  4. `./setup-http.sh`

## Files Structure
- `pxe-files/` - Boot files for TFTP (PXELINUX)
- `os-images/` - OS tarballs for HTTP download
- `config/` - Configuration templates
- `scripts/` - Installation scripts

## Network Requirements
- DHCP server capability
- Ports 69 (TFTP), 80 (HTTP), 67/68 (DHCP)
- Uses standard PXELINUX bootloader (no iPXE)
EOF

    # Create server configuration file
    cat > "${DEPLOY_DIR}/config/server-config.env" << 'EOF'
# PXE Server Configuration
# Edit these values for your environment

# Network Configuration
SERVER_IP="192.168.1.10"
NETWORK="192.168.1.0"
NETMASK="255.255.255.0"
GATEWAY="192.168.1.1"
DNS_SERVERS="8.8.8.8,8.8.4.4"
DHCP_RANGE_START="192.168.1.100"
DHCP_RANGE_END="192.168.1.200"

# Service Configuration
TFTP_ROOT="/var/lib/tftpboot"
HTTP_ROOT="/var/www/html"
DHCP_INTERFACE="eth0"

# File URLs (adjust if using different server)
PXE_BASE_URL="http://${SERVER_IP}"
EOF

    # Main deployment script
    cat > "${DEPLOY_DIR}/deploy-pxe-server.sh" << 'EOF'
#!/bin/bash

set -e

# Load configuration
source config/server-config.env

echo "=== PXE Server Deployment ==="
echo "Server IP: $SERVER_IP"
echo "Network: $NETWORK/$NETMASK"
echo "DHCP Range: $DHCP_RANGE_START - $DHCP_RANGE_END"
echo

read -p "Continue with deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 1
fi

echo "Installing services..."
./scripts/install-services.sh

echo "Setting up TFTP..."
./scripts/setup-tftp.sh

echo "Setting up HTTP..."
./scripts/setup-http.sh

echo "Configuring DHCP..."
./scripts/configure-dhcp.sh

echo
echo "=== Deployment Complete ==="
echo "PXE server is ready!"
echo
echo "Test URLs:"
echo "  TFTP: tftp://$SERVER_IP/pxelinux.0"
echo "  HTTP: http://$SERVER_IP/pxe-files/"
echo "  HTTP: http://$SERVER_IP/images/"
echo
echo "DHCP will serve PXE clients on network $NETWORK/$NETMASK"
EOF

    # Service installation script
    mkdir -p "${DEPLOY_DIR}/scripts"
    cat > "${DEPLOY_DIR}/scripts/install-services.sh" << 'EOF'
#!/bin/bash

source config/server-config.env

echo "Updating package list..."
sudo apt-get update

echo "Installing required packages..."
sudo apt-get install -y \
    isc-dhcp-server \
    tftpd-hpa \
    syslinux-common \
    pxelinux \
    nginx \
    rsync

echo "Services installed successfully."
EOF

    # TFTP setup script
    cat > "${DEPLOY_DIR}/scripts/setup-tftp.sh" << 'EOF'
#!/bin/bash

source config/server-config.env

echo "Configuring TFTP server..."

# Stop service for configuration
sudo systemctl stop tftpd-hpa

# Configure TFTP
cat > /tmp/tftpd-hpa << TFTP_EOF
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="$TFTP_ROOT"
TFTP_ADDRESS="0.0.0.0:69"
TFTP_OPTIONS="--secure"
TFTP_EOF

sudo cp /tmp/tftpd-hpa /etc/default/tftpd-hpa

# Create TFTP directory
sudo mkdir -p "$TFTP_ROOT"

# Copy syslinux files (PXELINUX - standard PXE implementation)
sudo cp /usr/lib/PXELINUX/pxelinux.0 "$TFTP_ROOT/"
sudo cp /usr/lib/syslinux/modules/bios/*.c32 "$TFTP_ROOT/"

# Copy our PXE files
echo "Copying PXE boot files..."
sudo rsync -av pxe-files/ "$TFTP_ROOT/"

# Set permissions
sudo chown -R tftp:tftp "$TFTP_ROOT"
sudo chmod -R 755 "$TFTP_ROOT"

# Start and enable service
sudo systemctl start tftpd-hpa
sudo systemctl enable tftpd-hpa

echo "TFTP server configured and started."
echo "Files available at: tftp://$SERVER_IP/"
EOF

    # HTTP setup script  
    cat > "${DEPLOY_DIR}/scripts/setup-http.sh" << 'EOF'
#!/bin/bash

source config/server-config.env

echo "Configuring HTTP server..."

# Create web directories
sudo mkdir -p "$HTTP_ROOT/pxe-files"
sudo mkdir -p "$HTTP_ROOT/images"

# Copy files
echo "Copying PXE files..."
sudo rsync -av pxe-files/ "$HTTP_ROOT/pxe-files/"

echo "Copying OS images..."
sudo rsync -av os-images/ "$HTTP_ROOT/images/"

# Create nginx configuration
cat > /tmp/pxe-nginx.conf << NGINX_EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    root $HTTP_ROOT;
    index index.html index.htm;
    server_name _;
    
    # Increase limits for large file transfers
    client_max_body_size 10G;
    client_body_timeout 300s;
    send_timeout 300s;
    keepalive_timeout 300s;
    
    # Enable directory listing
    location / {
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
        try_files \$uri \$uri/ =404;
    }
    
    # Specific locations for PXE files
    location /pxe-files/ {
        autoindex on;
        autoindex_exact_size off;
        add_header Cache-Control "public, max-age=3600";
    }
    
    location /images/ {
        autoindex on;
        autoindex_exact_size off;
        add_header Cache-Control "public, max-age=86400";
    }
    
    # Logging
    access_log /var/log/nginx/pxe_access.log;
    error_log /var/log/nginx/pxe_error.log;
}
NGINX_EOF

sudo cp /tmp/pxe-nginx.conf /etc/nginx/sites-available/pxe
sudo ln -sf /etc/nginx/sites-available/pxe /etc/nginx/sites-enabled/pxe
sudo rm -f /etc/nginx/sites-enabled/default

# Set permissions
sudo chown -R www-data:www-data "$HTTP_ROOT"
sudo chmod -R 755 "$HTTP_ROOT"

# Test and restart nginx
sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx

echo "HTTP server configured and started."
echo "Files available at: http://$SERVER_IP/"
EOF

    # DHCP configuration script
    cat > "${DEPLOY_DIR}/scripts/configure-dhcp.sh" << 'EOF'
#!/bin/bash

source config/server-config.env

echo "Configuring DHCP server..."

# Backup original config
sudo cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.backup 2>/dev/null || true

# Create DHCP configuration
cat > /tmp/dhcpd.conf << DHCP_EOF
# PXE DHCP Configuration
option domain-name "pxe.local";
option domain-name-servers $DNS_SERVERS;
default-lease-time 600;
max-lease-time 7200;
authoritative;

# PXE Boot Options
option space pxelinux;
option pxelinux.magic code 208 = string;
option pxelinux.configfile code 209 = text;
option pxelinux.pathprefix code 210 = text;
option pxelinux.reboottime code 211 = unsigned integer 32;
option architecture-type code 93 = unsigned integer 16;

subnet $NETWORK netmask $NETMASK {
    range $DHCP_RANGE_START $DHCP_RANGE_END;
    option routers $GATEWAY;
    option broadcast-address $(echo $NETWORK | cut -d. -f1-3).255;
    
    # PXE Boot Configuration
    next-server $SERVER_IP;
    
    # Boot filename based on client architecture (standard PXE only)
    if option architecture-type = 00:07 or option architecture-type = 00:09 {
        # UEFI x64 - use standard EFI bootloader
        filename "bootx64.efi";
    } else {
        # Legacy BIOS - use PXELINUX
        filename "pxelinux.0";
    }
}

# Static reservations example (uncomment and modify as needed)
# host client1 {
#     hardware ethernet 00:11:22:33:44:55;
#     fixed-address 192.168.1.50;
# }
DHCP_EOF

sudo cp /tmp/dhcpd.conf /etc/dhcp/dhcpd.conf

# Configure interface
echo "INTERFACESv4=\"$DHCP_INTERFACE\"" | sudo tee /etc/default/isc-dhcp-server

# Test configuration
sudo dhcpd -t -cf /etc/dhcp/dhcpd.conf

# Start and enable service
sudo systemctl restart isc-dhcp-server
sudo systemctl enable isc-dhcp-server

echo "DHCP server configured and started."
echo "Serving network: $NETWORK/$NETMASK"
echo "IP range: $DHCP_RANGE_START - $DHCP_RANGE_END"
EOF

    # Make scripts executable
    chmod +x "${DEPLOY_DIR}"/*.sh
    chmod +x "${DEPLOY_DIR}/scripts"/*.sh
    
    # Copy PXE files and OS images to deployment package
    cp -r "${PXE_DIR}" "${DEPLOY_DIR}/pxe-files"
    cp -r "${OS_IMAGES_DIR}" "${DEPLOY_DIR}/os-images"
    
    log "Deployment package created in: ${DEPLOY_DIR}"
}

# Main execution
main() {
    log "Starting PXE system creation..."
    
    setup_directories
    build_pxe_environment
    build_os_images
    create_deployment_package
    
    log "PXE system creation complete!"
    log ""
    log "=== DEPLOYMENT INSTRUCTIONS ==="
    log "1. Copy 'artifacts/server-deployment/' to your PXE server"
    log "2. Edit 'server-deployment/config/server-config.env' with your network settings"
    log "3. Run 'server-deployment/deploy-pxe-server.sh' on the target server"
    log ""
    log "=== FILES CREATED ==="
    log "Build artifacts: ${ARTIFACTS}"
    log "Deployment package: ${ARTIFACTS}/server-deployment/"
    log "PXE boot files: ${PXE_DIR}"
    log "OS images: ${OS_IMAGES_DIR}"
    log ""
    log "=== WHAT'S INCLUDED ==="
    log "- Complete PXE boot environment with disk installer"
    log "- Pre-built Ubuntu and Debian OS images"
    log "- DHCP, TFTP, and HTTP server configurations"
    log "- Automated deployment scripts"
}

# Run main function
main "$@"
