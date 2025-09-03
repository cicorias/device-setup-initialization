# Ubuntu OS Naming and Differentiation Strategy

## Overview

Both OS1 and OS2 partitions contain identical Ubuntu 24.04.3 LTS installations initially. They are differentiated only through naming and configuration after the installation is complete.

## Installation Process

### Phase 1: Identical Base Installation
Both OS1 and OS2 receive the same debootstrap installation:

```bash
# Install identical Ubuntu base system to both partitions
debootstrap --arch=amd64 noble /mnt/os1 http://archive.ubuntu.com/ubuntu/
debootstrap --arch=amd64 noble /mnt/os2 http://archive.ubuntu.com/ubuntu/

# Install identical packages to both
chroot /mnt/os1 apt-get install -y linux-generic grub-efi-amd64 openssh-server
chroot /mnt/os2 apt-get install -y linux-generic grub-efi-amd64 openssh-server
```

### Phase 2: Post-Installation Differentiation
After the base installation, the systems are differentiated through configuration:

#### System Identification
```bash
# OS1 Configuration
chroot /mnt/os1 hostnamectl set-hostname "${DEVICE_HOSTNAME}-primary"
echo 'NAME="Ubuntu Primary"' >> /mnt/os1/etc/os-release
echo 'VERSION_CODENAME_SUFFIX="primary"' >> /mnt/os1/etc/os-release

# OS2 Configuration  
chroot /mnt/os2 hostnamectl set-hostname "${DEVICE_HOSTNAME}-secondary"
echo 'NAME="Ubuntu Secondary"' >> /mnt/os2/etc/os-release
echo 'VERSION_CODENAME_SUFFIX="secondary"' >> /mnt/os2/etc/os-release
```

#### MOTD Customization
```bash
# OS1 MOTD
cat > /mnt/os1/etc/motd << 'EOF'
==========================================
  Ubuntu Primary System (OS1)
  Edge Device: ${DEVICE_HOSTNAME}
==========================================
EOF

# OS2 MOTD
cat > /mnt/os2/etc/motd << 'EOF'
==========================================
  Ubuntu Secondary System (OS2)  
  Edge Device: ${DEVICE_HOSTNAME}
==========================================
EOF
```

#### Boot Menu Entries
The local GRUB menu (post-initialization) shows both systems with clear naming:

```grub
menuentry 'Ubuntu Primary (OS1)' --class ubuntu --class os {
    echo 'Loading Ubuntu Primary System...'
    search --set=root --label OS1
    linux /boot/vmlinuz root=LABEL=OS1 ro quiet splash
    initrd /boot/initrd.img
}

menuentry 'Ubuntu Secondary (OS2)' --class ubuntu --class os {
    echo 'Loading Ubuntu Secondary System...'
    search --set=root --label OS2  
    linux /boot/vmlinuz root=LABEL=OS2 ro quiet splash
    initrd /boot/initrd.img
}
```

## Use Cases for Dual Ubuntu Systems

### A/B Update Strategy
- **OS1 (Primary)**: Production system running current workloads
- **OS2 (Secondary)**: Target for system updates and testing
- Switch between systems for zero-downtime updates

### Development/Production Split
- **OS1 (Primary)**: Stable production environment
- **OS2 (Secondary)**: Development and testing environment

### Fault Tolerance
- **OS1 (Primary)**: Main operating system
- **OS2 (Secondary)**: Backup system for hardware/software failures

### Configuration Variants
- **OS1 (Primary)**: Standard configuration
- **OS2 (Secondary)**: Custom configuration for specific workloads

## Shared Resources

### Data Partition
Both systems share the data partition (`/dev/disk/by-label/DATA`):

```bash
# Mounted identically in both systems
/dev/disk/by-label/DATA /data ext4 defaults 0 2
```

### Configuration Persistence
Device-level configuration is stored on the shared data partition:

```
/data/
├── config/
│   ├── device.conf          # Device-wide settings
│   ├── network.conf         # Network configuration
│   └── security.conf        # Security settings
├── logs/                    # System logs
├── docker/                  # Docker data (if enabled)
└── user-data/              # User application data
```

### SSH Keys and Users
User accounts and SSH keys can be synchronized between systems:

```bash
# Shared user configuration
/data/config/users/
├── authorized_keys
├── edge-user.conf
└── sudo.conf
```

## Runtime Differentiation

### System Information Commands
```bash
# Identify current system
cat /etc/os-release | grep NAME
# Output: NAME="Ubuntu Primary" or NAME="Ubuntu Secondary"

hostname
# Output: edge-device-primary or edge-device-secondary

# Check partition
df / | grep -o 'OS[12]'
# Output: OS1 or OS2
```

### Service Configuration
Systems can have different service configurations:

```bash
# OS1: Production services
systemctl enable docker
systemctl enable monitoring-agent

# OS2: Development services  
systemctl enable docker
systemctl enable development-tools
```

### Environment Variables
```bash
# OS1 Environment
export SYSTEM_ROLE="primary"
export ENVIRONMENT="production"

# OS2 Environment
export SYSTEM_ROLE="secondary"  
export ENVIRONMENT="development"
```

## Boot Process Workflow

### 1. Power On
```
Device Boot → Local GRUB Menu (5-second timeout)
```

### 2. Default Boot (OS1)
```
GRUB Timeout → Ubuntu Primary (OS1) → Production Environment
```

### 3. Manual Selection (OS2)
```
User Selection → Ubuntu Secondary (OS2) → Development Environment
```

### 4. Shared Data Access
```
Both Systems → Mount /data → Shared Configuration & Data
```

## Management Commands

### Switch Default Boot Target
```bash
# Set OS2 as default
grub-set-default "Ubuntu Secondary (OS2)"
update-grub

# Set OS1 as default (restore)
grub-set-default "Ubuntu Primary (OS1)"
update-grub
```

### Cross-System Updates
```bash
# Update OS2 while running OS1
mount /dev/disk/by-label/OS2 /mnt
chroot /mnt apt update && apt upgrade -y
umount /mnt
```

### Configuration Synchronization
```bash
# Sync configuration from OS1 to OS2
rsync -av /data/config/ /mnt/os2/etc/edge-config/
```

This approach provides maximum flexibility while maintaining simplicity in the initial installation process. Both systems start identical but can diverge based on operational requirements.
