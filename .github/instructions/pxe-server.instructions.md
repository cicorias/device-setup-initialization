---
applyTo: '**/*'
---

## Overview

The purpose of this project is to generate the supporting IMG files that can be placed on a PXE server and provide a initialization experience for a new Edge device.

## Requirements

### Device Partition 
- 1 x EFI System Partition (ESP) - FAT32, 512MB
- 1 x Root Partition - ext4, ~1-2GB
- 1 x Swap Partition - ~2-4GB (optional, depending on RAM)
- 1 x OS1 Partition - ext4, ~3.7GB
- 1 x OS2 Partition - ext4, ~3.7GB
- 1 x Data Partition - ext4, remaining space
- The device should be set to UEFI boot mode only (no legacy BIOS support)

### IMG Requirements
- This image should be small, perhaps with SquashFS or some image that can provide the first run experience at initialization and during a re-initialization of the device

### Approach
- GRUB2 will be used as the bootloader, configured to present a menu durint initialization
- All GRUB2 configuration files will be stored in /boot/grub/ for the bootloader
- Initial GRUB2 menu will offer:
  - Configure Device (network, hostname, etc.)
  - Ideally using Bash Scripts -- avoid cloud-init, autoinstall, or casper - Suggest only
  - Partition Disk based on [Device Partition](#device-partition) scheme
  - Install OS1 -- this will be a minimal Ubuntu 24.04.3 LTS (Noble Numbat) installation
  - Install OS2 -- this will be a minimal Ubuntu 24.04.3 LTS (Noble Numbat) installation
  - Both OS1 and OS2 will be installed using debootstrap or a similar tool to create a minimal filesystem
    - After installation, GRUB2 will be reconfigured to boot into the installed OS by default
  - Boot into OS1 or Boot into OS2 -- are GRUB2 menu entries to boot into the installed OS1 or OS2
  - GRUB2 shold be configured to timeout and boot into OS1 by default after a short delay
    - Advanced Options: future support for recovery mode or other advanced boot options for OS1 and OS2
    - Reconfigure GRUB2 -- to allow re-running the configuration steps if needed
  - GRUB2 Menu entries needed to boot into OS1 and OS2 are to be placed in /etc/grub.d/40_custom
  - Factory Reset (re-initialize device)

### General Flow -- Suggested

- any changes to this flow should be documented.
The General flow is articulated at [PXE Boot Process](./pxe-boot-process.md)


### Future Features
- A/B fault tolerance for OS1 and OS2 


## Directives
- NEVER suggest or expect that iPXE is to be used - it is to be the default PXE implementation in Debian or Ubuntu only
- UEFI Boot is the priority - BIOS Boot is NOT NEEDED
- Build scripts in steps using numbered scripts

## Build output
- Output should go to a `./artifacts` directory, which would not be committed to git.
- ideally follow the pattern below

**Artifacts Created:**
```
artifacts/
├── images/                       # Modern IMG files for HTTP serving
├── pxe-files/                    # Legacy PXE boot files
│   ├── vmlinuz                   # Linux kernel
│   ├── initrd                    # Initial ramdisk
├── os-images/                    # OS filesystem archives - these are to be placed on the device after partitioning
└── pxe-integration/              # Integration configuration
    ├── grub-entries.cfg          # GRUB menu entries
    ├── deployment-instructions.md # Manual deployment guide
    ├── copy-commands.sh          # Automated setup script
    └── manifest.txt              # File inventory
```

## PXE Server 
- PXE server is to be a distinct environment
- PXE server is to be setup using [cicorias/pxe-server-setup](https://github.com/cicorias/pxe-server-setup)
- IMG files served via HTTP for fast, reliable boot
- TFTP used as needed for initial boot image, such as the kernel and initrd
- Provide instructions for integrating with the PXE server and perhaps a script in Bash
