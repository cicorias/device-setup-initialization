# PXE Boot System Strategy & Implementation

## Overview

This system provides a complete PXE (Preboot Execution Environment) solution for automated dual-OS installation on target machines. The strategy combines the best of both original scripts into a unified approach.

## System Architecture

### Build System (Development/Build Machine)
- Runs `create-pxe-system.sh` to build all components
- Creates deployment package for PXE server
- Builds OS images and boot files

### PXE Server (Network Boot Server)
- DHCP Server: Assigns IP addresses and PXE boot options
- TFTP Server: Serves initial boot files (pxelinux.0, kernel, initrd)
- HTTP Server: Serves large files (squashfs, OS images)

### Target Machine (Installation Target)
- Boots from network (PXE)
- Downloads and runs Debian-based installer environment
- Partitions disk and installs dual-boot system

## Partition Layout Strategy

The target machine will have this partition layout:

```
/dev/sda1 - GRUB Partition (512MB, FAT32)
  ├── GRUB bootloader (UEFI + BIOS)
  ├── Boot configuration
  └── System utilities

/dev/sda2 - OS1 Root (Ubuntu, 3.5GB, ext4)
  ├── Complete Ubuntu system
  └── Mounted at / when booting Ubuntu

/dev/sda3 - OS2 Root (Debian, 3.5GB, ext4)  
  ├── Complete Debian system
  └── Mounted at / when booting Debian

/dev/sda4 - Data Partition (Remaining space, ext4)
  ├── Shared data between both OS
  ├── User home directories
  ├── Logs and backups
  └── Mounted at /data in both OS
```

## Key Differences from Original Scripts

### From `01-build-rootfs-on-build-box.sh`:
- ✅ **Kept**: SquashFS live system approach
- ✅ **Kept**: Debian Trixie base for installer
- ✅ **Enhanced**: Added disk partitioning and installation tools
- ✅ **Enhanced**: Added dual-boot capability

### From `make-image.sh`:
- ✅ **Kept**: Dual-OS concept (Ubuntu + Debian)
- ✅ **Kept**: Partition management strategy
- ✅ **Enhanced**: Network-based installation instead of local image
- ✅ **Enhanced**: Separate GRUB partition for better management

## File Outputs & Usage

### Build Phase (`create-pxe-system.sh`)

**Artifacts Created:**
```
artifacts/
├── pxe-files/                    # TFTP boot files
│   ├── vmlinuz                   # Linux kernel
│   ├── initrd                    # Initial ramdisk
│   ├── filesystem.squashfs       # Live system
│   ├── pxelinux.cfg/default      # PXE menu
│   └── boot.ipxe                 # iPXE script
├── os-images/                    # HTTP downloadable OS
│   ├── ubuntu-os.tar.gz          # Ubuntu filesystem
│   └── debian-os.tar.gz          # Debian filesystem
└── server-deployment/            # Complete deployment package
    ├── deploy-pxe-server.sh      # Main deployment script
    ├── config/server-config.env  # Network configuration
    ├── scripts/                  # Service setup scripts
    ├── pxe-files/               # Copy of PXE files
    └── os-images/               # Copy of OS images
```

### Deployment Phase (On PXE Server)

**Server Configuration Files:**

1. **DHCP Configuration** (`/etc/dhcp/dhcpd.conf`):
```bash
subnet 192.168.1.0 netmask 255.255.255.0 {
    range 192.168.1.100 192.168.1.200;
    option routers 192.168.1.1;
    next-server 192.168.1.10;  # TFTP server
    filename "pxelinux.0";     # Initial boot file
}
```

2. **TFTP Configuration** (`/etc/default/tftpd-hpa`):
```bash
TFTP_DIRECTORY="/var/lib/tftpboot"
TFTP_ADDRESS="0.0.0.0:69"
```

3. **HTTP Configuration** (nginx):
```bash
server {
    listen 80;
    root /var/www/html;
    location /pxe-files/ { autoindex on; }
    location /images/ { autoindex on; }
}
```

## Network Services Required

### DHCP Server
- **Purpose**: Assign IP addresses and PXE boot options
- **Port**: 67/68 (UDP)
- **Configuration**: Points clients to TFTP server

### TFTP Server  
- **Purpose**: Serve initial boot files (small, fast)
- **Port**: 69 (UDP)
- **Files Served**:
  - `pxelinux.0` - PXE bootloader
  - `vmlinuz` - Linux kernel (~8MB)
  - `initrd` - Initial ramdisk (~50MB)
  - `*.c32` - Syslinux modules

### HTTP Server
- **Purpose**: Serve large files (efficient for big downloads)
- **Port**: 80 (TCP)
- **Files Served**:
  - `filesystem.squashfs` - Live system (~200MB)
  - `ubuntu-os.tar.gz` - Ubuntu OS (~800MB)
  - `debian-os.tar.gz` - Debian OS (~600MB)

## Installation Process Flow

1. **PXE Boot**: Target machine requests IP via DHCP
2. **DHCP Response**: Server provides IP + TFTP server info
3. **TFTP Download**: Client downloads `pxelinux.0`, `vmlinuz`, `initrd`
4. **HTTP Download**: Client downloads `filesystem.squashfs` via HTTP
5. **Live Boot**: Machine boots into Debian installer environment
6. **Disk Setup**: Installer partitions target disk (4 partitions)
7. **OS Download**: Installer downloads OS images via HTTP
8. **Installation**: OS images extracted to partitions
9. **GRUB Setup**: Bootloader installed with dual-boot menu
10. **Reboot**: Machine reboots into installed dual-OS system

## Usage Instructions

### 1. Build Phase (Development Machine)
```bash
# Create the PXE system
cd /path/to/project
chmod +x scripts/create-pxe-system.sh
sudo ./scripts/create-pxe-system.sh

# Test the deployment package
./scripts/test-deployment-package.sh
```

### 2. Deployment Phase (PXE Server)
```bash
# Copy deployment package to server
scp -r artifacts/server-deployment/ user@pxe-server:/tmp/

# On PXE server, configure network settings
ssh user@pxe-server
cd /tmp/server-deployment
nano config/server-config.env

# Deploy all services
sudo ./deploy-pxe-server.sh
```

### 3. Target Machine Installation
```bash
# Set machine to PXE boot (BIOS/UEFI setting)
# Boot machine - it will:
# 1. Get IP from DHCP
# 2. Download boot files via TFTP
# 3. Download installer via HTTP
# 4. Boot into installer environment
# 5. Run automatic installation (or manual if interactive)
```

## Customization Options

### Modify OS Images
- Edit the `build_os_images()` function in `create-pxe-system.sh`
- Add/remove packages during debootstrap
- Configure users, services, etc.

### Change Partition Layout
- Edit the `create_partitions()` function in disk installer
- Adjust partition sizes and filesystem types
- Modify mount points in `/etc/fstab`

### Network Configuration
- Edit `config/server-config.env` before deployment
- Adjust IP ranges, server addresses, etc.
- Modify DHCP options for specific requirements

### Auto vs Manual Installation
- Installer supports both interactive and automatic modes
- Enable auto-install by uncommenting line in installer script
- Use DHCP vendor classes for conditional auto-install

## Security Considerations

1. **Network Security**: Use isolated network for PXE operations
2. **File Integrity**: Consider checksums for downloaded images
3. **Access Control**: Restrict TFTP/HTTP access if needed
4. **Default Passwords**: Change default passwords in OS images

## Troubleshooting

### Common Issues:
1. **DHCP conflicts**: Ensure only one DHCP server on network
2. **Firewall blocking**: Open ports 67/68 (DHCP), 69 (TFTP), 80 (HTTP)
3. **Large file timeouts**: Increase nginx timeouts for slow networks
4. **Boot failures**: Check PXE boot order in BIOS/UEFI
5. **Kernel panics**: Verify initrd and kernel compatibility

### Verification Commands:
```bash
# Test TFTP
tftp pxe-server-ip -c get pxelinux.0

# Test HTTP
curl -I http://pxe-server-ip/pxe-files/filesystem.squashfs

# Check services
systemctl status isc-dhcp-server tftpd-hpa nginx

# Monitor logs
tail -f /var/log/syslog
tail -f /var/log/nginx/access.log
```

This strategy provides a complete, automated solution for deploying dual-boot systems via PXE while maintaining flexibility for customization and manual intervention when needed.
