# Edge Device Initialization System

A comprehensive build system for creating bootable edge device initialization images with dual-OS capabilities. This repository provides a complete solution for automated device provisioning via PXE boot or direct storage deployment.

## Overview

The Edge Device Initialization System creates specialized installation environments that can:

- **Initialize Edge Devices**: Complete device setup from bare metal
- **Dual-OS Installation**: Install Ubuntu Primary and Secondary systems
- **Physical Partitioning**: Create optimized 6-partition GPT layout
- **Network Deployment**: PXE boot integration for mass provisioning
- **Storage Imaging**: Direct device imaging for standalone deployment

## Architecture

### Numbered Build Script System (01-07)

The build process follows a sequential numbered script architecture:

```
01-bootstrap-environment.sh    → Environment setup and dependencies
02-system-configuration.sh    → Base system configuration  
03-package-installation.sh    → Essential package installation
04-grub-configuration.sh      → GRUB bootloader configuration
05-image-creation.sh          → Bootable image creation
06-testing-validation.sh      → Comprehensive testing suite
07-generate-integration.sh    → Deployment artifact generation
```

### Device Partition Layout

Creates a 6-partition GPT layout optimized for edge computing:

```
Partition 1: EFI System (512MB, FAT32)
├── UEFI bootloader
├── Boot configuration  
└── System recovery tools

Partition 2: Root/Init (2GB, ext4)
├── Initialization system
├── Device configuration tools
└── Partitioning utilities

Partition 3: Swap (4GB, swap)
├── Virtual memory
└── Hibernation support

Partition 4: OS1 Primary (3.7GB, ext4)
├── Ubuntu 24.04.3 LTS
├── Production environment
└── Default boot target

Partition 5: OS2 Secondary (3.7GB, ext4)
├── Ubuntu 24.04.3 LTS  
├── Development/backup environment
└── Fault tolerance

Partition 6: Data (Remaining, ext4)
├── Persistent configuration
├── Application data
└── Shared between OS1/OS2
```

## Quick Start


### Prerequisites

0. Up the limits for your user if using VS Code and Remote SSH -- by editing or other ways.

```bash
sudo nano /etc/security/limits.conf

youruser     soft     nofile     65535
youruser     hard     nofile     65535
youruser     soft     nproc      65535
youruser     hard     nproc      65535
```


1. **Build Environment Requirements**
```bash
# Ubuntu/Debian build system
sudo apt-get update
sudo apt-get install -y \
   debootstrap squashfs-tools qemu-utils rsync \
   parted dosfstools e2fsprogs grub-efi-amd64 \
   curl wget git build-essential
```

2. **Configuration Setup**
```bash
# Copy and customize configuration
cp scripts/config/config.sh.example config.sh
# Edit config.sh for your environment
```

### Build Process

Execute the numbered scripts sequentially:

```bash
# Complete build process
./scripts/01-bootstrap-environment.sh
./scripts/02-system-configuration.sh  
./scripts/03-package-installation.sh
./scripts/04-grub-configuration.sh
./scripts/05-image-creation.sh
./scripts/06-testing-validation.sh
./scripts/07-generate-integration.sh
```

Or use the master build script:
```bash
# Automated sequential execution
./build-all.sh
```

### Deployment Options

#### Option 1: PXE Server Deployment
```bash
# Extract integration package
tar -xzf build/edge-device-*.tar.gz

# Deploy to PXE server
cd deployment/
./deploy-to-pxe-server.sh --host your-pxe-server-ip
```

#### Option 2: Direct Device Imaging
```bash
# Write to USB/SD card
cd deployment/
./write-to-device.sh /dev/sdX
```

## Features

### Device Initialization Capabilities

- **Network Configuration**: DHCP or static IP setup
- **Security Configuration**: User accounts, SSH keys, firewall
- **Service Configuration**: Docker, SSH, monitoring services
- **Automatic Partitioning**: GPT layout with optimal sizing
- **Dual-OS Installation**: Automated Ubuntu installation to both partitions
- **GRUB Configuration**: Local boot menu for OS selection

### Build Artifacts

The build process creates comprehensive deployment artifacts:

```
build/
├── images/
│   ├── raw/                    # Raw disk images
│   │   └── edge-device-init.img
│   ├── compressed/             # Compressed format  
│   │   └── edge-device-init.img.gz
│   └── pxe/                    # PXE boot files
│       ├── vmlinuz
│       └── initrd.img
├── integration/                # Deployment package
│   ├── pxe-server/            # PXE integration files
│   ├── deployment/            # Deployment scripts
│   ├── config/                # Configuration templates
│   └── documentation/         # Deployment guides
└── logs/                      # Build process logs
```

### Integration Support

- **PXE Server Integration**: Works with [cicorias/pxe-server-setup](https://github.com/cicorias/pxe-server-setup)
- **Multiple Boot Systems**: pxelinux, GRUB, iPXE configurations
- **HTTP Optimization**: Efficient image serving for network deployment
- **Legacy Compatibility**: Support for existing PXE infrastructures
## Project Structure

```
device-setup-initialization/
├── scripts/                          # Build system
│   ├── 01-bootstrap-environment.sh   # Environment setup
│   ├── 02-system-configuration.sh    # System configuration
│   ├── 03-package-installation.sh    # Package installation
│   ├── 04-grub-configuration.sh      # GRUB setup
│   ├── 05-image-creation.sh          # Image creation
│   ├── 06-testing-validation.sh      # Testing suite
│   ├── 07-generate-integration.sh    # Integration generation
│   ├── config/                       # Configuration templates
│   └── README.md                     # Script documentation
├── build/                            # Generated artifacts (gitignored)
│   ├── images/                       # Bootable images
│   ├── integration/                  # Deployment package
│   └── logs/                         # Build logs
├── docs/                             # Documentation
│   ├── physical-partitioning-process.md
│   ├── ubuntu-os-naming-strategy.md
│   └── script-removal-analysis.md
├── config.sh                         # Build configuration
└── README.md                         # This file
```

## Usage Examples

### Standard Edge Device Build

```bash
# Complete build process
./scripts/01-bootstrap-environment.sh
./scripts/02-system-configuration.sh
./scripts/03-package-installation.sh
./scripts/04-grub-configuration.sh
./scripts/05-image-creation.sh
./scripts/06-testing-validation.sh
./scripts/07-generate-integration.sh

# Deployment package ready at:
# build/edge-device-initialization-YYYYMMDD-HHMMSS.tar.gz
```

### PXE Server Deployment

```bash
# Extract deployment package
tar -xzf build/edge-device-*.tar.gz

# Deploy to PXE server
cd deployment/
./deploy-to-pxe-server.sh --host 192.168.1.100

# Verify deployment
ssh root@192.168.1.100 'ls /var/lib/tftpboot/edge-device/'
```

### Direct Device Imaging

```bash
# Create bootable USB/SD card
cd deployment/
sudo ./write-to-device.sh /dev/sdb

# With verification
sudo ./write-to-device.sh --verify /dev/sdb

# Force write (skip confirmations)
sudo ./write-to-device.sh --force /dev/sdb
```

### Testing and Validation

```bash
# Run comprehensive tests
./scripts/06-testing-validation.sh

# Test specific components
./scripts/06-testing-validation.sh --test-images-only
./scripts/06-testing-validation.sh --test-grub-only
```

## Configuration

### Build Configuration

Customize the build process via `config.sh`:

```bash
# Device Configuration
DEVICE_HOSTNAME="edge-device"
DEFAULT_TIMEZONE="UTC"
UBUNTU_RELEASE="noble"        # 24.04.3 LTS

# Partition Sizes  
EFI_SIZE_MB=512
ROOT_SIZE_MB=2048
SWAP_SIZE_MB=4096
OS1_SIZE_MB=3788
OS2_SIZE_MB=3788

# Network Configuration
ENABLE_SSH=true
ENABLE_DOCKER=true
ENABLE_FIREWALL=true

# Build Options
BUILD_DIR="./build"
UBUNTU_MIRROR="http://archive.ubuntu.com/ubuntu"
```

### Device Configuration Templates

Customize device setup via configuration templates:

```bash
# Network configuration
scripts/config/network.conf.template

# Security configuration  
scripts/config/security.conf.template

# Service configuration
scripts/config/services.conf.template
```

## Device Initialization Workflow

### First Boot (PXE Network)

1. **Device Power On** → DHCP request
2. **PXE Boot** → Load GRUB from network
3. **Menu Selection** → Edge Device Initialization
4. **Image Download** → Small SquashFS system
5. **Configuration** → Network, hostname, security
6. **Partitioning** → Create 6-partition GPT layout
7. **OS Installation** → Install Ubuntu to OS1 and OS2
8. **Local GRUB** → Configure local boot menu
9. **Reboot** → Boot to installed system

### Subsequent Boots (Local Storage)

1. **Device Power On** → Local GRUB menu
2. **OS Selection** → Ubuntu Primary (default) or Secondary
3. **Normal Boot** → Selected Ubuntu system
4. **Shared Data** → Access persistent configuration

### Device Management

```bash
# Switch default OS
grub-set-default "Ubuntu Secondary (OS2)"
update-grub

# Factory reset (re-initialize)
# Boot from PXE → Select "Factory Reset"

# Configuration backup
rsync -av /data/config/ /backup/device-config/
```
## Integration with PXE Server

This repository works with [cicorias/pxe-server-setup](https://github.com/cicorias/pxe-server-setup):

- **pxe-server-setup**: Provides PXE infrastructure (DHCP, TFTP, HTTP, NFS)
- **device-setup-initialization**: Creates bootable images and deployment packages

### Integration Workflow

1. **Set up PXE Server**
   ```bash
   git clone https://github.com/cicorias/pxe-server-setup.git
   cd pxe-server-setup
   sudo ./install.sh --uefi --local-dhcp
   ```

2. **Build Device Images**
   ```bash
   cd device-setup-initialization
   ./scripts/01-bootstrap-environment.sh
   # ... continue with numbered scripts
   ./scripts/07-generate-integration.sh
   ```

3. **Deploy to PXE Server**
   ```bash
   tar -xzf build/edge-device-*.tar.gz
   cd deployment/
   ./deploy-to-pxe-server.sh --host your-pxe-server
   ```

4. **Boot Edge Devices**
   - Devices boot from network
   - Select "Edge Device Initialization" 
   - Follow automated setup process

## Troubleshooting

### Build Issues

```bash
# Check prerequisites
./scripts/01-bootstrap-environment.sh --check-only

# Clean build and restart
sudo rm -rf build/
./scripts/01-bootstrap-environment.sh

# Check specific script logs
tail -f build/logs/02-system-configuration.log
```

### Image Issues

```bash
# Test image integrity
./scripts/06-testing-validation.sh --test-images-only

# Manual image inspection
sudo mount -o loop build/images/raw/edge-device-init.img /mnt
ls -la /mnt/
sudo umount /mnt
```

### Deployment Issues

```bash
# Test PXE server connectivity
ssh root@your-pxe-server 'systemctl status tftpd-hpa'

# Verify deployment
ssh root@your-pxe-server 'ls -la /var/lib/tftpboot/edge-device/'

# Check PXE server logs
ssh root@your-pxe-server 'journalctl -u tftpd-hpa -f'
```

### Boot Issues

```bash
# Test QEMU boot
./scripts/06-testing-validation.sh --test-qemu-only

# Check GRUB configuration
grep -r "menuentry" build/integration/pxe-server/

# Monitor network boot
tcpdump -i eth0 port 67 or port 69
```

### Common Solutions

**Build fails during debootstrap:**
```bash
# Check network connectivity
curl -I http://archive.ubuntu.com/ubuntu

# Try different mirror
export UBUNTU_MIRROR="http://us.archive.ubuntu.com/ubuntu"
```

**Image too large:**
```bash
# Increase image size in config.sh
export IMAGE_SIZE_MB=8192
```

**PXE boot fails:**
```bash
# Verify DHCP configuration
# Check TFTP accessibility
tftp your-pxe-server -c get edge-device/vmlinuz /dev/null
```

## Development

### Script Development Guidelines

1. **Follow numbered script pattern**
2. **Use common functions** (log, warn, error, info)
3. **Implement proper error handling**
4. **Add comprehensive logging**
5. **Test with validation script**

### Adding New Features

```bash
# Modify appropriate numbered script
vim scripts/04-grub-configuration.sh

# Test changes
./scripts/04-grub-configuration.sh
./scripts/06-testing-validation.sh

# Update documentation
vim docs/script-api-reference.md
```

### Testing Changes

```bash
# Full build test
./build-all.sh

# Specific component test  
./scripts/06-testing-validation.sh --test-grub-only

# Integration test
./scripts/07-generate-integration.sh
```

## Security Considerations

### Build Security

- **Isolated environment**: Build in clean VM/container
- **Package verification**: GPG verification of downloaded packages
- **Checksum validation**: All artifacts include checksums
- **Minimal attack surface**: Only essential packages installed

### Deployment Security

- **SSH key authentication**: Disable password authentication
- **Firewall configuration**: UFW with minimal open ports
- **User privileges**: Non-root user with sudo access
- **Automatic updates**: Security patches enabled

### Runtime Security

- **Encrypted communication**: SSH, HTTPS where possible
- **Access logging**: Comprehensive audit trails
- **Configuration validation**: Input sanitization
- **Factory reset capability**: Secure device re-initialization

## Contributing

1. **Fork** the repository
2. **Create** feature branch from main
3. **Follow** numbered script architecture
4. **Test** with full build and validation
5. **Update** documentation
6. **Submit** pull request

### Development Environment

```bash
# Set up development environment
git clone https://github.com/your-fork/device-setup-initialization.git
cd device-setup-initialization

# Install development dependencies
sudo apt-get install -y shellcheck

# Run tests
./scripts/06-testing-validation.sh
```

## Related Projects

- **[cicorias/pxe-server-setup](https://github.com/cicorias/pxe-server-setup)**: PXE server infrastructure
- **Ubuntu**: Base operating system
- **GRUB**: Network and local bootloader
- **debootstrap**: Ubuntu system installation
- **SquashFS**: Compressed filesystem for PXE images

## License

[License to be specified]

## Support and Documentation

- **GitHub Issues**: Bug reports and feature requests
- **Documentation**: Complete guides in `docs/` directory
- **API Reference**: Script API documentation in `docs/script-api-reference.md`
- **Integration Guide**: PXE server integration in `docs/deployment-guide.md`
- **Architecture**: System design in `docs/physical-partitioning-process.md`

For comprehensive documentation, see the generated deployment package which includes complete setup guides and troubleshooting information.
