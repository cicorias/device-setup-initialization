# Integration with PXE Server

This document explains how to integrate the device-setup-initialization system with an existing PXE server setup.

## Overview

The `device-setup-initialization` repository creates custom installation images and boot configurations. These artifacts need to be deployed to a PXE server that handles the network boot infrastructure.

## Architecture

### Separation of Concerns

- **cicorias/pxe-server-setup**: Handles PXE server infrastructure
  - DHCP server configuration
  - TFTP server setup
  - HTTP server configuration
  - NFS server setup
  - Service management and monitoring

- **cicorias/device-setup-initialization**: Creates installation artifacts
  - Custom Linux installation environments
  - Dual-OS installation systems
  - IMG files for HTTP serving
  - SquashFS files for live boot (legacy)
  - Integration configuration

## Prerequisites

1. **PXE Server Setup**
   
   Set up a PXE server using the dedicated repository:
   ```bash
   git clone https://github.com/cicorias/pxe-server-setup.git
   cd pxe-server-setup
   
   # Configure network settings
   cp scripts/config.sh.example scripts/config.sh
   nano scripts/config.sh  # Edit network configuration
   
   # Install PXE server
   sudo ./install.sh --uefi --local-dhcp
   ```

2. **Network Configuration**
   
   Ensure both systems use compatible network configuration:
   - PXE server IP: `10.1.1.1` (or as configured)
   - Client network: `10.1.1.0/24`
   - DHCP range: `10.1.1.100-10.1.1.200`

3. **SSH Access**
   
   Configure SSH access to the PXE server:
   ```bash
   # Copy SSH key to PXE server
   ssh-copy-id root@10.1.1.1
   
   # Test connectivity
   ssh root@10.1.1.1 'echo "Connected successfully"'
   ```

## Build and Deployment Process

### 1. Build Installation Images

```bash
# Build artifacts (both IMG and SquashFS formats)
./scripts/create-pxe-system.sh

# Build only IMG files (recommended)
./scripts/create-pxe-system.sh --no-squashfs

# Build only SquashFS (legacy compatibility)
./scripts/create-pxe-system.sh --no-img

# Custom IMG size
./scripts/create-pxe-system.sh --img-size 8G
```

**Output artifacts:**
```
artifacts/
├── images/                    # IMG files for HTTP serving
│   ├── dual-os-installer.img # Main dual-OS installation system
│   ├── ubuntu-minimal.img    # Ubuntu filesystem image
│   └── debian-minimal.img    # Debian filesystem image
├── pxe-files/                # Legacy PXE files
│   ├── vmlinuz              # Linux kernel
│   ├── initrd               # Initial ramdisk
│   └── filesystem.squashfs  # Live boot filesystem
└── pxe-integration/          # Integration configuration
    ├── grub-entries.cfg     # GRUB menu entries
    ├── deployment-instructions.md
    ├── copy-commands.sh
    └── manifest.txt
```

### 2. Deploy to PXE Server

#### Automated Deployment (Recommended)

```bash
# Deploy all artifacts to PXE server
./scripts/deploy-to-pxe-server.sh 10.1.1.1

# Deploy with custom SSH user and path
./scripts/deploy-to-pxe-server.sh 10.1.1.1 ubuntu /opt/pxe-server-setup
```

#### Manual Deployment

1. **Copy artifacts to PXE server:**
   ```bash
   # Copy IMG files
   scp artifacts/images/*.img root@10.1.1.1:/tmp/
   
   # Copy integration configuration
   scp -r artifacts/pxe-integration/ root@10.1.1.1:/tmp/
   ```

2. **On PXE server, add IMG files:**
   ```bash
   cd /home/cicorias/g/pxe-server-setup
   sudo ./scripts/08-iso-manager.sh add /tmp/dual-os-installer.img
   sudo ./scripts/08-iso-manager.sh add /tmp/ubuntu-minimal.img
   sudo ./scripts/08-iso-manager.sh add /tmp/debian-minimal.img
   ```

3. **Apply custom GRUB configuration:**
   ```bash
   # Append custom entries to GRUB configuration
   sudo cat /tmp/pxe-integration/grub-entries.cfg >> /var/lib/tftpboot/grub/grub.cfg
   
   # Restart TFTP service
   sudo systemctl restart tftpd-hpa
   ```

### 3. Verify Deployment

```bash
# Check PXE server status
ssh root@10.1.1.1 'cd /home/cicorias/g/pxe-server-setup && sudo ./scripts/08-iso-manager.sh status'

# Validate configuration
ssh root@10.1.1.1 'cd /home/cicorias/g/pxe-server-setup && sudo ./scripts/validate-pxe.sh'

# Test TFTP access
tftp 10.1.1.1 -c get grub/grub.cfg

# Test HTTP access
curl http://10.1.1.1/images/
```

## Boot Process

### UEFI PXE Boot Flow

1. **Client boots from network**
   - Client requests IP via DHCP
   - DHCP server responds with IP and boot filename (`bootx64.efi`)

2. **GRUB loads**
   - Client downloads `bootx64.efi` via TFTP
   - GRUB displays menu with available options

3. **Installation begins**
   - User selects installation option
   - GRUB downloads kernel and initrd via TFTP
   - Kernel boots and downloads IMG file via HTTP
   - Installation system partitions disk and installs OS

### Available Boot Options

After deployment, the PXE menu will include:

- **Dual-OS Installation System**
  - Partitions disk with GRUB, Ubuntu, Debian, and data partitions
  - Installs both operating systems
  - Configures dual-boot menu

- **Ubuntu Installation**
  - Installs Ubuntu from custom image
  - Customized for specific requirements

- **Debian Installation**
  - Installs Debian from custom image
  - Customized for specific requirements

- **Boot from Local Hard Drive**
  - Standard option to boot installed OS

## Troubleshooting

### Common Issues

1. **IMG files not accessible via HTTP**
   ```bash
   # Check HTTP server status
   ssh root@10.1.1.1 'systemctl status nginx'
   
   # Check file permissions
   ssh root@10.1.1.1 'ls -la /var/www/html/pxe/images/'
   
   # Test HTTP access
   curl -I http://10.1.1.1/images/dual-os-installer.img
   ```

2. **GRUB menu not showing custom entries**
   ```bash
   # Check GRUB configuration
   ssh root@10.1.1.1 'cat /var/lib/tftpboot/grub/grub.cfg'
   
   # Restart TFTP service
   ssh root@10.1.1.1 'sudo systemctl restart tftpd-hpa'
   ```

3. **Boot fails after GRUB selection**
   ```bash
   # Check kernel and initrd files
   ssh root@10.1.1.1 'ls -la /var/lib/tftpboot/kernels/device-setup/'
   
   # Check TFTP logs
   ssh root@10.1.1.1 'sudo journalctl -u tftpd-hpa -f'
   ```

### Log Files

Monitor these log files on the PXE server:

```bash
# TFTP service logs
sudo journalctl -u tftpd-hpa -f

# HTTP server logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log

# DHCP server logs (if using local DHCP)
sudo journalctl -u isc-dhcp-server -f

# NFS server logs
sudo journalctl -u nfs-kernel-server -f
```

## Advanced Configuration

### Custom Boot Parameters

Edit the generated GRUB configuration to customize boot parameters:

```bash
# Edit GRUB entries before deployment
nano artifacts/pxe-integration/grub-entries.cfg

# Common parameters to modify:
# - ip=dhcp          # Network configuration
# - console=tty0     # Console output
# - debug            # Enable debug output
# - inst.text        # Text-mode installation
```

### Multiple Server Deployment

Deploy to multiple PXE servers:

```bash
# Deploy to multiple servers
for server in 10.1.1.1 10.2.1.1 10.3.1.1; do
    echo "Deploying to $server..."
    ./scripts/deploy-to-pxe-server.sh "$server"
done
```

### Selective Deployment

Deploy specific artifacts:

```bash
# Deploy only dual-OS installer
scp artifacts/images/dual-os-installer.img root@10.1.1.1:/tmp/
ssh root@10.1.1.1 'cd /path/to/pxe-server-setup && sudo ./scripts/08-iso-manager.sh add /tmp/dual-os-installer.img'
```

## Migration from Legacy Approach

If migrating from the old monolithic approach:

1. **Set up separate PXE server using pxe-server-setup**
2. **Build new artifacts with device-setup-initialization**
3. **Deploy using new integration scripts**
4. **Test thoroughly before decommissioning old setup**

### Legacy Compatibility

The system maintains backward compatibility:

```bash
# Create legacy deployment package (deprecated)
CREATE_LEGACY_PACKAGE=true ./scripts/create-pxe-system.sh

# Use archived legacy scripts
./scripts/archive/create-legacy-deployment.sh
```

## Best Practices

1. **Version Control**
   - Tag releases of both repositories
   - Document which versions work together
   - Test integration before production deployment

2. **Testing**
   - Test deployment in staging environment
   - Verify all boot options work correctly
   - Test recovery procedures

3. **Monitoring**
   - Monitor PXE server logs during deployment
   - Set up alerting for service failures
   - Regular health checks of PXE services

4. **Backup**
   - Backup PXE server configuration
   - Keep copies of working IMG files
   - Document recovery procedures

## Support

For issues specific to:
- **PXE server infrastructure**: See [pxe-server-setup repository](https://github.com/cicorias/pxe-server-setup)
- **Image building**: See this repository's issues
- **Integration**: Check both repositories' documentation
