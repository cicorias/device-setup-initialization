# Device Setup Initialization

A specialized system for creating custom PXE boot environments and dual-OS installation images. This repository focuses on building installation artifacts that integrate with existing PXE server infrastructure.

## Overview

This project creates custom installation systems for network deployment via PXE boot. It builds specialized installation environments that can:

- Install dual-boot systems (Ubuntu + Debian)
- Create custom OS images
- Generate IMG files for HTTP serving
- Provide SquashFS live boot systems (legacy compatibility)

## Architecture

This repository works in conjunction with [cicorias/pxe-server-setup](https://github.com/cicorias/pxe-server-setup):

- **pxe-server-setup**: Provides PXE server infrastructure (DHCP, TFTP, HTTP, NFS)
- **device-setup-initialization**: Creates installation images and deployment configurations

## Quick Start

### Prerequisites

1. **PXE Server Setup**
   
   First, set up a PXE server using the dedicated repository:
   ```bash
   # On your PXE server
   git clone https://github.com/cicorias/pxe-server-setup.git
   cd pxe-server-setup
   sudo ./install.sh --uefi --local-dhcp
   ```

2. **Build Environment**
   
   On your build machine:
   ```bash
   # Install required packages
   sudo apt-get update
   sudo apt-get install -y debootstrap squashfs-tools qemu-utils rsync
   ```

### Build and Deploy

1. **Build Installation Images**
   ```bash
   # Build all formats (IMG + SquashFS)
   ./scripts/create-pxe-system.sh
   
   # Build only IMG files (recommended)
   ./scripts/create-pxe-system.sh --no-squashfs
   
   # Custom IMG size
   ./scripts/create-pxe-system.sh --img-size 8G
   ```

2. **Deploy to PXE Server**
   ```bash
   # Automated deployment
   ./scripts/deploy-to-pxe-server.sh 10.1.1.1
   
   # Manual deployment (see INTEGRATION.md)
   ./scripts/generate-pxe-config.sh
   # Follow instructions in artifacts/pxe-integration/
   ```

3. **Test PXE Boot**
   
   Boot a client machine from network and verify the custom installation options appear in the GRUB menu.

## Features

### Dual-OS Installation System

Creates a partition layout optimized for dual-boot systems:

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
└── Mounted at /data in both OS
```

### Output Formats

- **IMG Files**: Modern approach using HTTP serving
  - `dual-os-installer.img` - Complete installation system
  - `ubuntu-minimal.img` - Ubuntu filesystem image
  - `debian-minimal.img` - Debian filesystem image

- **SquashFS Files**: Legacy live boot compatibility
  - `filesystem.squashfs` - Live boot filesystem
  - `vmlinuz` - Linux kernel
  - `initrd` - Initial ramdisk

### Integration Support

- **Automated deployment** scripts for existing PXE servers
- **GRUB configuration** generation
- **HTTP server** optimization for large file transfers
- **Legacy compatibility** for existing PXE setups

## Project Structure

```
device-setup-initialization/
├── scripts/
│   ├── create-pxe-system.sh        # Main build script
│   ├── deploy-to-pxe-server.sh     # Automated deployment
│   ├── generate-pxe-config.sh      # Integration configuration
│   ├── test-deployment-package.sh  # Testing utilities
│   └── archive/                    # Deprecated scripts
│       ├── 01-build-rootfs-on build-box.sh
│       ├── make-image.sh
│       └── create-legacy-deployment.sh
├── artifacts/                      # Generated build artifacts
│   ├── images/                     # IMG files for HTTP serving
│   ├── pxe-files/                  # Legacy PXE files
│   ├── os-images/                  # OS filesystem archives
│   └── pxe-integration/            # Integration configuration
├── INTEGRATION.md                  # Detailed integration guide
├── PXE_STRATEGY.md                # Technical strategy document
└── README.md                      # This file
```

## Usage Examples

### Standard Dual-OS Installation

```bash
# Build dual-OS installation system
./scripts/create-pxe-system.sh

# Deploy to PXE server
./scripts/deploy-to-pxe-server.sh 10.1.1.1

# Boot client from network
# Select "Dual-OS Installation System" from GRUB menu
# Follow installation prompts
```

### Custom Image Size

```bash
# Create larger installation images
./scripts/create-pxe-system.sh --img-size 8G

# Create minimal images (SquashFS only)
./scripts/create-pxe-system.sh --no-img
```

### Multiple Server Deployment

```bash
# Deploy to multiple PXE servers
for server in 10.1.1.1 10.2.1.1 10.3.1.1; do
    ./scripts/deploy-to-pxe-server.sh "$server"
done
```

## Configuration

### Build Options

Set environment variables to customize the build:

```bash
# Output format control
export OUTPUT_SQUASHFS=true    # Create SquashFS files
export OUTPUT_IMG=true         # Create IMG files
export IMG_SIZE=4G            # Default IMG size

# Build environment
export ARTIFACTS=/custom/path  # Custom artifacts directory

# PXE server integration
export PXE_SERVER_IP=10.1.1.1 # Target PXE server IP
export NFS_ROOT=/srv/nfs       # NFS root directory
export HTTP_ROOT=/var/www/html/pxe  # HTTP root directory
```

### Network Configuration

The system assumes standard PXE network configuration:

- **PXE Server IP**: `10.1.1.1`
- **Client Network**: `10.1.1.0/24`
- **DHCP Range**: `10.1.1.100-10.1.1.200`

These can be customized in the PXE server setup.

## Integration Guide

For detailed integration instructions, see [INTEGRATION.md](INTEGRATION.md).

Key integration points:

1. **PXE Server Setup**: Use [cicorias/pxe-server-setup](https://github.com/cicorias/pxe-server-setup)
2. **Build Artifacts**: Run `./scripts/create-pxe-system.sh`
3. **Deploy**: Use `./scripts/deploy-to-pxe-server.sh`
4. **Test**: Boot client from network

## Migration from Legacy Setup

If migrating from previous versions:

1. **Archive old scripts**: Moved to `scripts/archive/`
2. **Set up PXE server**: Use dedicated pxe-server-setup repository
3. **Build new artifacts**: Use updated `create-pxe-system.sh`
4. **Deploy**: Use new deployment scripts

### Legacy Compatibility

For backward compatibility:

```bash
# Force creation of legacy deployment package
CREATE_LEGACY_PACKAGE=true ./scripts/create-pxe-system.sh

# Use archived scripts (deprecated)
./scripts/archive/create-legacy-deployment.sh
```

## Troubleshooting

### Build Issues

```bash
# Check build dependencies
sudo apt-get install -y debootstrap squashfs-tools qemu-utils rsync

# Clean artifacts and rebuild
sudo rm -rf artifacts/
./scripts/create-pxe-system.sh
```

### Deployment Issues

```bash
# Test SSH connectivity
ssh root@10.1.1.1 echo "Connected"

# Check PXE server status
ssh root@10.1.1.1 'cd /path/to/pxe-server-setup && sudo ./scripts/validate-pxe.sh'

# Manual deployment
./scripts/generate-pxe-config.sh
# Follow instructions in artifacts/pxe-integration/deployment-instructions.md
```

### Boot Issues

```bash
# Check GRUB configuration
tftp 10.1.1.1 -c get grub/grub.cfg

# Test HTTP access
curl http://10.1.1.1/images/

# Monitor PXE server logs
ssh root@10.1.1.1 'sudo journalctl -u tftpd-hpa -f'
```

## Contributing

1. **Fork** the repository
2. **Create** a feature branch
3. **Test** with existing PXE server setup
4. **Submit** a pull request

### Development Guidelines

- Follow existing script structure and error handling
- Test integration with pxe-server-setup repository
- Update documentation for any new features
- Maintain backward compatibility where possible

## Related Projects

- **[cicorias/pxe-server-setup](https://github.com/cicorias/pxe-server-setup)**: PXE server infrastructure
- **Debian Live**: Live system creation tools
- **GRUB**: Network boot loader
- **Standard PXE**: Network boot protocols (no iPXE dependency)

## License

[Specify license here]

## Support

- **Issues**: Use GitHub issues for bug reports and feature requests
- **Integration**: See INTEGRATION.md for detailed setup instructions
- **PXE Server**: See pxe-server-setup repository for server-side issues
