# PXE Server Integration Guide

## Overview

This guide explains how to integrate device initialization images with a PXE server infrastructure. The integration assumes the PXE server is already set up using [cicorias/pxe-server-setup](https://github.com/cicorias/pxe-server-setup).

## Prerequisites

### PXE Server Setup

1. **Install PXE Server Infrastructure**
   ```bash
   git clone https://github.com/cicorias/pxe-server-setup.git
   cd pxe-server-setup
   
   # Configure network settings
   cp scripts/config.sh.example scripts/config.sh
   nano scripts/config.sh  # Edit network configuration
   
   # Install PXE server (UEFI-only)
   sudo ./install.sh --uefi --local-dhcp
   ```

2. **Verify Services**
   ```bash
   # Check DHCP server
   sudo systemctl status isc-dhcp-server
   
   # Check TFTP server
   sudo systemctl status tftpd-hpa
   
   # Check HTTP server
   sudo systemctl status nginx
   ```

3. **Test Network Configuration**
   ```bash
   # Verify DHCP configuration
   sudo dhcpd -t
   
   # Test TFTP access
   tftp localhost -c get grub/grub.cfg
   
   # Test HTTP access
   curl -I http://localhost/
   ```

### SSH Access Configuration

1. **Set up SSH Key Authentication**
   ```bash
   # Generate SSH key if needed
   ssh-keygen -t ed25519 -C "device-init-deployment"
   
   # Copy to PXE server
   ssh-copy-id root@<pxe-server-ip>
   
   # Test connectivity
   ssh root@<pxe-server-ip> 'echo "Connection successful"'
   ```

2. **Verify PXE Server Path**
   ```bash
   # Default path should exist
   ssh root@<pxe-server-ip> 'ls -la /home/cicorias/g/pxe-server-setup'
   ```

## Build and Deployment Process

### 1. Build Device Images

```bash
# Build all device initialization images
./build-device-images.sh

# Build with custom options
./build-device-images.sh --os1-size 4G --os2-size 4G --root-size 2G
```

This creates the following artifacts:
```
artifacts/
├── images/
│   ├── device-init-environment.img     # Main initialization system
│   ├── os1-ubuntu-minimal.img          # OS1 filesystem
│   └── os2-ubuntu-minimal.img          # OS2 filesystem
├── pxe-files/
│   ├── vmlinuz                         # Kernel for initialization
│   └── initrd                          # Initial ramdisk
└── pxe-integration/
    ├── grub-entries.cfg                # GRUB menu entries
    ├── deploy-to-pxe-server.sh         # Deployment script
    └── manifest.txt                    # File inventory
```

### 2. Deploy to PXE Server

#### Automated Deployment (Recommended)

```bash
# Deploy all artifacts to PXE server
./scripts/deploy-to-pxe-server.sh <pxe-server-ip>

# Deploy with custom SSH user and path
./scripts/deploy-to-pxe-server.sh <pxe-server-ip> ubuntu /opt/pxe-server-setup
```

#### Manual Deployment

If automated deployment fails, use manual steps:

```bash
# 1. Copy IMG files to PXE server
scp artifacts/images/*.img root@<pxe-server-ip>:/tmp/

# 2. Copy integration files
scp -r artifacts/pxe-integration/ root@<pxe-server-ip>:/tmp/

# 3. On PXE server, add IMG files
ssh root@<pxe-server-ip> << 'EOF'
cd /home/cicorias/g/pxe-server-setup
sudo ./scripts/08-iso-manager.sh add /tmp/device-init-environment.img
sudo ./scripts/08-iso-manager.sh add /tmp/os1-ubuntu-minimal.img
sudo ./scripts/08-iso-manager.sh add /tmp/os2-ubuntu-minimal.img
EOF

# 4. Apply GRUB configuration
ssh root@<pxe-server-ip> << 'EOF'
# Append custom entries to GRUB configuration
sudo cat /tmp/pxe-integration/grub-entries.cfg >> /var/lib/tftpboot/grub/grub.cfg

# Restart TFTP service
sudo systemctl restart tftpd-hpa
EOF
```

### 3. Verify Deployment

```bash
# Check PXE server status
ssh root@<pxe-server-ip> 'cd /home/cicorias/g/pxe-server-setup && sudo ./scripts/validate-pxe.sh'

# Test TFTP access
tftp <pxe-server-ip> -c get grub/grub.cfg

# Test HTTP access to images
curl -I http://<pxe-server-ip>/images/device-init-environment.img

# Check GRUB menu content
ssh root@<pxe-server-ip> 'cat /var/lib/tftpboot/grub/grub.cfg'
```

## Device Boot Process

### UEFI PXE Boot Flow

1. **Network Boot Initiation**
   - Configure device BIOS/UEFI for network boot
   - Device broadcasts DHCP request
   - DHCP server responds with IP and boot filename (`bootx64.efi`)

2. **GRUB Bootloader Load**
   - Device downloads `bootx64.efi` via TFTP
   - GRUB2 EFI bootloader initializes
   - GRUB loads configuration from TFTP server

3. **Initialization Menu**
   - GRUB displays device initialization menu
   - User selects "Configure Device" or other options
   - GRUB downloads kernel and initrd via TFTP

4. **Environment Download**
   - Kernel boots and initializes network
   - Downloads device initialization IMG via HTTP
   - Mounts IMG as installation source

5. **Device Configuration**
   - Interactive configuration scripts run
   - User configures network, hostname, etc.
   - Disk partitioning and OS installation begin

6. **Local Boot Setup**
   - OS1 and OS2 installed to local partitions
   - GRUB2 reconfigured for local boot
   - Device reboots to installed system

### Boot Menu Options

After deployment, the PXE boot menu includes:

```
Edge Device Initialization
├── Configure Device                    # Interactive device setup
├── Partition Disk                      # Automatic disk partitioning
├── Install OS1 (Ubuntu 24.04.3 LTS)   # Install primary OS
├── Install OS2 (Ubuntu 24.04.3 LTS)   # Install secondary OS
├── Factory Reset                       # Re-initialize device
└── Advanced Options
    ├── Boot from Local Disk            # Boot installed OS
    ├── Memory Test                     # System diagnostics
    └── System Information              # Hardware details
```

## Network Requirements

### DHCP Configuration

The PXE server DHCP must be configured for UEFI boot:

```bash
# Example DHCP configuration
subnet 10.1.1.0 netmask 255.255.255.0 {
    range 10.1.1.100 10.1.1.200;
    option routers 10.1.1.1;
    option domain-name-servers 8.8.8.8, 8.8.4.4;
    
    # UEFI PXE boot configuration
    option architecture-type code 93 = unsigned integer 16;
    if option architecture-type = 00:07 {
        filename "bootx64.efi";
    }
    next-server 10.1.1.1;  # TFTP server IP
}
```

### Firewall Configuration

Ensure these ports are open on the PXE server:

- **Port 67/68 (UDP)**: DHCP service
- **Port 69 (UDP)**: TFTP service  
- **Port 80 (TCP)**: HTTP service for IMG files
- **Port 22 (TCP)**: SSH for deployment (optional)

### Network Performance

For optimal performance:

- **Gigabit Network**: Use gigabit ethernet for faster IMG downloads
- **Local DHCP**: Run DHCP server on same subnet as devices
- **HTTP Optimization**: Configure nginx for large file serving

## Troubleshooting

### Common Issues

1. **Device Not Getting DHCP Response**
   ```bash
   # Check DHCP server logs
   ssh root@<pxe-server-ip> 'sudo journalctl -u isc-dhcp-server -f'
   
   # Verify DHCP configuration
   ssh root@<pxe-server-ip> 'sudo dhcpd -t'
   
   # Check network connectivity
   ping <pxe-server-ip>
   ```

2. **TFTP Download Failures**
   ```bash
   # Test TFTP manually
   tftp <pxe-server-ip> -c get bootx64.efi
   
   # Check TFTP logs
   ssh root@<pxe-server-ip> 'sudo journalctl -u tftpd-hpa -f'
   
   # Verify file permissions
   ssh root@<pxe-server-ip> 'ls -la /var/lib/tftpboot/'
   ```

3. **HTTP Download Failures**
   ```bash
   # Test HTTP access
   curl -v http://<pxe-server-ip>/images/device-init-environment.img
   
   # Check nginx logs
   ssh root@<pxe-server-ip> 'sudo tail -f /var/log/nginx/access.log'
   
   # Verify nginx configuration
   ssh root@<pxe-server-ip> 'sudo nginx -t'
   ```

4. **GRUB Menu Not Appearing**
   ```bash
   # Check GRUB configuration
   ssh root@<pxe-server-ip> 'cat /var/lib/tftpboot/grub/grub.cfg'
   
   # Verify EFI boot file
   ssh root@<pxe-server-ip> 'ls -la /var/lib/tftpboot/bootx64.efi'
   
   # Test GRUB configuration syntax
   ssh root@<pxe-server-ip> 'grub-script-check /var/lib/tftpboot/grub/grub.cfg'
   ```

### Log Files

Monitor these log files for troubleshooting:

```bash
# On PXE server
sudo journalctl -u isc-dhcp-server -f    # DHCP logs
sudo journalctl -u tftpd-hpa -f          # TFTP logs
sudo tail -f /var/log/nginx/access.log   # HTTP access logs
sudo tail -f /var/log/nginx/error.log    # HTTP error logs

# On device (after boot)
dmesg | grep -i pxe                      # PXE boot messages
journalctl -u systemd-networkd           # Network configuration
```

### Performance Optimization

1. **Build Performance**
   - Use SSD storage for build artifacts
   - Increase available RAM for build processes
   - Consider parallel image creation

2. **Network Performance**
   - Use gigabit ethernet for PXE server
   - Optimize nginx for large file transfers
   - Consider caching for repeated deployments

3. **Boot Performance**
   - Minimize IMG file sizes where possible
   - Use compressed filesystems appropriately
   - Optimize kernel and initrd for target hardware

## Security Considerations

### Build Security

- **Base Image Verification**: Verify Ubuntu base images
- **Package Integrity**: Use signed package repositories
- **Build Environment**: Isolate build environment

### Network Security

- **PXE Network Isolation**: Use dedicated VLAN for PXE boot
- **Access Control**: Restrict PXE server access
- **Secure Boot**: Compatible with UEFI Secure Boot

### Deployment Security

- **SSH Key Management**: Use dedicated deployment keys
- **Server Access**: Limit administrative access to PXE server
- **Image Integrity**: Consider checksums for IMG files

## Advanced Configuration

### Multiple Server Deployment

Deploy to multiple PXE servers:

```bash
# Deploy to multiple servers
for server in 10.1.1.1 10.2.1.1 10.3.1.1; do
    echo "Deploying to $server..."
    ./scripts/deploy-to-pxe-server.sh "$server"
done
```

### Custom Build Options

```bash
# Build with custom sizes
./build-device-images.sh \
    --os1-size 5G \
    --os2-size 5G \
    --root-size 3G \
    --swap-size 8G

# Build for specific hardware
./build-device-images.sh --target-arch x86_64 --include-drivers intel,nvidia
```

### Configuration Templates

Create custom configuration templates:

```bash
# Create custom network template
cat > artifacts/config-templates/network-static.conf << EOF
INTERFACE=eth0
IP_ADDRESS=192.168.1.100
NETMASK=255.255.255.0
GATEWAY=192.168.1.1
DNS_SERVERS="8.8.8.8 8.8.4.4"
EOF

# Deploy with custom template
./scripts/deploy-to-pxe-server.sh <server-ip> --config-template network-static
```

This integration guide provides comprehensive instructions for connecting device initialization with PXE server infrastructure while maintaining security and performance best practices.
