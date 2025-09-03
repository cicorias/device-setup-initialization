# Edge Device Initialization Strategy

## Overview

This document outlines the approach for creating PXE-bootable device initialization images that provide first-run configuration and dual-OS installation for edge devices.

## Architecture

### Design Principles

The device initialization system follows these key principles:

1. **UEFI-Only Boot**: No legacy BIOS support, focusing on modern UEFI systems
2. **Bash-Based Configuration**: Avoiding cloud-init and autoinstall for simple, transparent configuration scripts
3. **Dual-OS Support**: Installing two identical Ubuntu 24.04.3 LTS systems for A/B fault tolerance
4. **Partition-Based Isolation**: Clear partition separation for different components and data
5. **Factory Reset Capability**: Ability to re-initialize devices to factory state

### Separation of Concerns

The system maintains clear separation between infrastructure and device initialization:

- **PXE Server Infrastructure** ([cicorias/pxe-server-setup](https://github.com/cicorias/pxe-server-setup))
  - DHCP server configuration
  - TFTP server setup for initial boot files
  - HTTP server for large file serving
  - Network infrastructure management

- **Device Initialization** (This Repository)
  - Custom initialization environment creation
  - Device partition layout and OS installation
  - Configuration scripts and menu systems
  - IMG file generation for HTTP serving

## Device Partition Layout

The target device uses a 6-partition layout optimized for dual-OS edge computing:

```
/dev/sda1 - EFI System Partition (200MB, FAT32)
  ├── GRUB2 bootloader (UEFI)
  ├── Boot configuration files
  └── System utilities

/dev/sda2 - Root Partition (2GB, ext4)
  ├── Initialization system
  ├── Configuration scripts
  └── Temporary boot environment

/dev/sda3 - Swap Partition (4GB, swap)
  ├── Virtual memory for system operations
  └── Hibernation support (optional)

/dev/sda4 - OS1 Partition (3.7GB, ext4)
  ├── Primary Ubuntu 24.04.3 LTS system
  └── Production operating system

/dev/sda5 - OS2 Partition (3.7GB, ext4)
  ├── Secondary Ubuntu 24.04.3 LTS system
  └── Backup/failover operating system

/dev/sda6 - Data Partition (Remaining space, ext4)
  ├── Persistent application data
  ├── Configuration backups
  ├── User data and logs
  └── Shared storage between OS1 and OS2
```

## Boot Flow and GRUB2 Configuration

### Initial Boot Sequence

1. **PXE Boot Phase**
   - Device boots via PXE and gets IP from DHCP
   - Downloads GRUB2 EFI bootloader via TFTP
   - GRUB2 loads configuration and displays initialization menu

2. **Initialization Phase**
   - User selects initialization option from GRUB menu
   - Downloads initialization image via HTTP
   - Boots into temporary initialization environment

3. **Configuration Phase**
   - Device configuration (network, hostname, etc.)
   - Disk partitioning according to layout above
   - OS installation to designated partitions

4. **Production Phase**
   - GRUB2 reconfigured for local boot
   - Default boot to OS1 with timeout
   - Menu options for OS2, recovery, and factory reset

### GRUB2 Menu Structure

#### During Initialization
```
┌─────────────────────────────────────────────┐
│  Edge Device Initialization                │
│                                             │
│  > Configure Device                         │
│    Partition Disk                           │
│    Install OS1 (Ubuntu 24.04.3 LTS)        │
│    Install OS2 (Ubuntu 24.04.3 LTS)        │
│    Factory Reset                            │
│                                             │
│  Advanced Options >                         │
│    Boot from Local Disk                     │
│    Memory Test                              │
│    System Information                       │
│                                             │
│  Timeout: 30 seconds                        │
└─────────────────────────────────────────────┘
```

#### After Installation (Local Boot)
```
┌─────────────────────────────────────────────┐
│  Edge Device Boot Menu                      │
│                                             │
│  > Boot OS1 (Primary)                       │
│    Boot OS2 (Secondary)                     │
│                                             │
│  Advanced Options >                         │
│    OS1 Recovery Mode                        │
│    OS2 Recovery Mode                        │
│    Configure Device                         │
│    Factory Reset                            │
│                                             │
│  Timeout: 5 seconds                         │
└─────────────────────────────────────────────┘
```

## Build System Architecture

### Build Phases

The build system follows a numbered script approach:

1. **01-bootstrap-environment.sh** - Create base build environment
2. **02-create-initrd.sh** - Build custom initrd with initialization tools
3. **03-build-root-filesystem.sh** - Create root partition filesystem
4. **04-build-os-images.sh** - Build OS1 and OS2 filesystem images
5. **05-create-grub-config.sh** - Generate GRUB2 configuration files
6. **06-package-images.sh** - Package IMG files for HTTP serving
7. **07-generate-integration.sh** - Create PXE server integration files

### Output Structure

```
artifacts/
├── images/                           # IMG files for HTTP serving
│   ├── device-init-environment.img   # Main initialization environment
│   ├── os1-ubuntu-minimal.img        # OS1 filesystem image
│   └── os2-ubuntu-minimal.img        # OS2 filesystem image
├── pxe-files/                        # Legacy compatibility files
│   ├── vmlinuz                       # Linux kernel
│   └── initrd                        # Initial ramdisk
├── os-images/                        # OS filesystem archives
│   ├── os1-ubuntu.tar.gz             # OS1 filesystem archive
│   └── os2-ubuntu.tar.gz             # OS2 filesystem archive
└── pxe-integration/                  # PXE server integration
    ├── grub-entries.cfg              # GRUB menu entries
    ├── deployment-instructions.md    # Deployment guide
    ├── deploy-to-pxe-server.sh       # Automated deployment
    └── manifest.txt                  # File inventory
```

## Configuration System

### Bash-Based Configuration Scripts

The system uses bash scripts for device configuration, avoiding complex tools:

- **Network Configuration** (`configure-network.sh`)
  - Static IP or DHCP configuration
  - DNS server settings
  - Network interface management

- **System Configuration** (`configure-system.sh`)
  - Hostname configuration
  - SSH key management
  - Timezone and locale settings

- **Storage Configuration** (`configure-storage.sh`)
  - Disk partitioning validation
  - Filesystem mounting
  - Data directory initialization

### Configuration Persistence

Configuration data is stored in the Data partition and shared between OS1 and OS2:

```
/data/
├── config/
│   ├── network.conf              # Network settings
│   ├── system.conf               # System settings
│   └── ssh/                      # SSH keys
├── logs/                         # System logs
└── backups/                      # Configuration backups
```

## Integration with PXE Server

### Deployment Process

1. **Build Phase** (Development Machine)
   ```bash
   ./build-device-images.sh
   ```

2. **Deployment Phase** (To PXE Server)
   ```bash
   ./scripts/deploy-to-pxe-server.sh <server-ip>
   ```

3. **Device Initialization** (Target Device)
   - Boot device with PXE enabled
   - Select initialization option from GRUB menu
   - Follow configuration prompts

### PXE Server Requirements

- **DHCP Server**: Provides IP addresses and PXE boot information
- **TFTP Server**: Serves GRUB2 bootloader and kernel files
- **HTTP Server**: Serves large IMG files and filesystem archives
- **Network Access**: Device must have network connectivity during initialization

## Factory Reset and Re-initialization

### Factory Reset Process

1. **Trigger Reset**
   - Select "Factory Reset" from GRUB menu
   - Or use PXE boot for complete re-initialization

2. **Data Preservation Options**
   - Option to preserve data in Data partition
   - Option to backup configuration before reset

3. **Re-initialization**
   - Repartition disk (if requested)
   - Reinstall OS1 and OS2
   - Restore or reconfigure system settings

### A/B Fault Tolerance

The dual-OS approach provides fault tolerance:

- **Primary Operation**: Boot to OS1 by default
- **Automatic Failover**: Boot to OS2 if OS1 fails
- **Manual Selection**: User can choose OS1 or OS2 from GRUB menu
- **Independent Updates**: Update one OS while the other remains stable

## Security Considerations

### Boot Security

- **UEFI Secure Boot**: Compatible with secure boot when enabled
- **Verified Boot**: Option to verify filesystem integrity
- **Network Security**: Secure communication with PXE server

### Configuration Security

- **SSH Key Management**: Secure key generation and deployment
- **Network Isolation**: Option for isolated management networks
- **Access Control**: User and permission management

## Future Enhancements

### Planned Features

- **Remote Management**: Integration with device management systems
- **Update Mechanisms**: Over-the-air updates for OS1/OS2
- **Monitoring Integration**: Health monitoring and alerting
- **Container Support**: Docker/Podman runtime in OS installations

### Extensibility

- **Custom OS Images**: Support for different Linux distributions
- **Plugin System**: Extensible configuration script framework
- **Hardware Support**: Additional hardware driver integration

This strategy provides a robust, maintainable approach to edge device initialization while maintaining simplicity and reliability through bash-based configuration and clear architectural separation.
