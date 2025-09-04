# Physical Partitioning Process and Architecture Clarification

## Overview

This document clarifies how the Edge Device Initialization system performs physical disk partitioning during the PXE boot process and explains the separation between PXE GRUB and local device GRUB menus.

## PXE Boot Architecture

### Phase 1: PXE Network Boot (Initialization Only)

```
Device Power On → DHCP Request → PXE GRUB Menu (Network Boot)
                                       ↓
                              Small SquashFS Image
                                       ↓
                              Physical Disk Partitioning
                                       ↓
                              OS Installation (OS1 & OS2)
                                       ↓
                              Local GRUB Installation
```

### Phase 2: Local Boot (Post-Initialization)

```
Device Reboot → Local GRUB Menu (Device Storage)
                       ↓
               ┌─── Boot OS1 ───┐
               │                │
               └─── Boot OS2 ───┘
```

## Physical Partitioning Process

### How Small PXE Image Creates GPT Partitions

The physical partitioning is accomplished through the following process:

#### 1. PXE Boot Delivers Small Image
- **PXE GRUB** loads a small (~200-500MB) SquashFS initialization image
- This image contains:
  - Minimal Ubuntu system with partitioning tools
  - `parted`, `fdisk`, `mkfs.*` utilities
  - Configuration scripts for device setup
  - `debootstrap` for OS installation

#### 2. Physical Disk Detection and Partitioning
The small image runs scripts that:

```bash
# Detect target storage device
DISK=$(lsblk -d -n -o NAME,TYPE | grep disk | head -1 | awk '{print "/dev/"$1}')

# Create GPT partition table
parted "$DISK" mklabel gpt

# Create 6-partition layout
parted "$DISK" mkpart primary fat32 1MiB 513MiB        # EFI (512MB)
parted "$DISK" mkpart primary ext4 513MiB 2.5GiB       # Root (2GB)
parted "$DISK" mkpart primary linux-swap 2.5GiB 6.5GiB # Swap (4GB)
parted "$DISK" mkpart primary ext4 6.5GiB 10.2GiB      # OS1 (3.7GB)
parted "$DISK" mkpart primary ext4 10.2GiB 13.9GiB     # OS2 (3.7GB)
parted "$DISK" mkpart primary ext4 13.9GiB 100%        # Data (remaining)

# Set EFI partition flag
parted "$DISK" set 1 esp on
```

#### 3. Filesystem Creation
```bash
# Format partitions
mkfs.fat -F32 -n "EFI" "${DISK}1"          # EFI System Partition
mkfs.ext4 -L "ROOT" "${DISK}2"             # Root partition
mkswap -L "SWAP" "${DISK}3"                # Swap partition
mkfs.ext4 -L "OS1" "${DISK}4"              # OS1 partition
mkfs.ext4 -L "OS2" "${DISK}5"              # OS2 partition
mkfs.ext4 -L "DATA" "${DISK}6"             # Data partition
```

#### 4. OS Installation via debootstrap
The small image then installs Ubuntu systems:

```bash
# Mount target partitions
mount "${DISK}4" /mnt/os1
mount "${DISK}5" /mnt/os2
mount "${DISK}1" /mnt/efi

# Install OS1 (Ubuntu Primary)
debootstrap --arch=amd64 noble /mnt/os1 http://archive.ubuntu.com/ubuntu/

# Install OS2 (Ubuntu Secondary)  
debootstrap --arch=amd64 noble /mnt/os2 http://archive.ubuntu.com/ubuntu/

# Configure both systems
chroot /mnt/os1 apt-get install -y linux-generic grub-efi-amd64
chroot /mnt/os2 apt-get install -y linux-generic grub-efi-amd64
```

#### 5. Local GRUB Installation
```bash
# Install GRUB to EFI partition
grub-install --target=x86_64-efi --efi-directory=/mnt/efi --boot-directory=/mnt/os1/boot

# Create local GRUB menu for OS1/OS2 selection
cat > /mnt/os1/etc/grub.d/40_custom << 'EOF'
menuentry 'Ubuntu Primary (OS1)' {
    search --set=root --label OS1
    linux /boot/vmlinuz root=LABEL=OS1 ro quiet splash
    initrd /boot/initrd.img
}

menuentry 'Ubuntu Secondary (OS2)' {
    search --set=root --label OS2
    linux /boot/vmlinuz root=LABEL=OS2 ro quiet splash
    initrd /boot/initrd.img
}
EOF

update-grub
```

## Updated Partition Layout (512MB EFI)

| Partition | Size    | Type      | Label | Purpose                    |
|-----------|---------|-----------|-------|----------------------------|
| 1         | 512MB   | FAT32     | EFI   | UEFI System Partition      |
| 2         | 2GB     | ext4      | ROOT  | Initialization system      |
| 3         | 4GB     | swap      | SWAP  | Virtual memory             |
| 4         | 3.7GB   | ext4      | OS1   | Ubuntu Primary System      |
| 5         | 3.7GB   | ext4      | OS2   | Ubuntu Secondary System    |
| 6         | Remaining| ext4     | DATA  | Persistent data storage    |

## GRUB Menu Separation

### PXE GRUB Menu (Network Boot - Initialization Only)
```
Edge Device Initialization Menu
├── Configure Device (network, hostname, security)
├── Partition Disk (create 6-partition GPT layout)
├── Install OS1 (Ubuntu Primary via debootstrap)
├── Install OS2 (Ubuntu Secondary via debootstrap)
├── Factory Reset (re-partition and re-install)
└── Rescue Mode (troubleshooting)
```

### Local GRUB Menu (Device Storage - Post-Initialization)
```
Edge Device Boot Menu
├── Ubuntu Primary (OS1) [DEFAULT]
├── Ubuntu Secondary (OS2)
├── Advanced Options for Ubuntu Primary
├── Advanced Options for Ubuntu Secondary
└── System Recovery
    ├── Memory Test
    ├── Boot from Network (re-initialization)
    └── Emergency Shell
```

## OS Naming Strategy

Both OS1 and OS2 are Ubuntu 24.04.3 LTS systems, differentiated by:

### System Identification
- **OS1**: `hostnamectl set-hostname "${DEVICE_HOSTNAME}-primary"`
- **OS2**: `hostnamectl set-hostname "${DEVICE_HOSTNAME}-secondary"`

### GRUB Menu Labels
- **OS1**: "Ubuntu Primary (OS1)" 
- **OS2**: "Ubuntu Secondary (OS2)"

### System Files
- **OS1**: `/etc/os-release` → `NAME="Ubuntu Primary"`
- **OS2**: `/etc/os-release` → `NAME="Ubuntu Secondary"`

### Boot Priority
- Default boot: OS1 (Ubuntu Primary)
- Fallback: OS2 (Ubuntu Secondary)
- Timeout: 5 seconds

## Implementation Flow

### 1. First Boot (PXE Network)
```
Power On → DHCP → PXE TFTP → GRUB Network Boot → SquashFS Image
                                    ↓
                        Physical Disk Partitioning
                                    ↓
                        Ubuntu OS1 & OS2 Installation  
                                    ↓
                        Local GRUB Configuration
                                    ↓
                        Reboot to Local Storage
```

### 2. Subsequent Boots (Local Storage)
```
Power On → Local GRUB → OS1/OS2 Selection → Ubuntu Boot
```

### 3. Re-initialization (Optional)
```
Local GRUB → "Boot from Network" → PXE Network Boot → Factory Reset
```

## Key Technical Details

### Small Image Contents
The PXE-delivered image contains:
- **Base System**: Minimal Ubuntu with essential tools
- **Partitioning Tools**: `parted`, `fdisk`, `lsblk`, `blkid`
- **Filesystem Tools**: `mkfs.ext4`, `mkfs.fat`, `mkswap`
- **Installation Tools**: `debootstrap`, `chroot`
- **Network Tools**: `curl`, `wget` for package downloads
- **Configuration Scripts**: Device setup and OS installation

### Storage Requirements
- **PXE Image**: ~200-500MB (SquashFS compressed)
- **Target Device**: Minimum 16GB for full 6-partition layout
- **Network**: Internet access for Ubuntu package downloads

### Automated Process
The entire process from PXE boot to dual-OS installation is automated through bash scripts, requiring minimal user interaction for basic deployments.

This approach ensures that devices can be completely provisioned from bare metal through network boot, while maintaining local boot capabilities for day-to-day operations.
