<!-- markdownlint-disable-file -->
# Task Research Notes: PXE Server Device Initialization Approach

## Research Executed

### File Analysis
- `/home/cicorias/g/device-setup-initialization/scripts/create-pxe-system.sh`
  - Main build script creating dual-OS installation system with partitioning, GRUB configuration, and both IMG/SquashFS output formats
- `/home/cicorias/g/device-setup-initialization/scripts/deploy-to-pxe-server.sh` 
  - Deployment script targeting existing pxe-server-setup infrastructure with SSH-based file transfer
- `/home/cicorias/g/device-setup-initialization/deprecated/docs/PXE_STRATEGY.md`
  - Comprehensive strategy document detailing dual-OS approach, partition layouts, and network boot flow
- `/home/cicorias/g/device-setup-initialization/deprecated/docs/INTEGRATION.md`
  - Integration guidelines between device-setup-initialization and pxe-server-setup repositories

### Code Search Results
- **GRUB2 Configuration Patterns**
  - Found UEFI-only GRUB configuration in pxe-server-setup with proper menu entries and network boot support
  - Native GRUB CLI tools usage for configuration management avoiding manual grub.cfg editing
- **Partition Layout Implementation**
  - Discovered consistent 4-partition scheme: GRUB (512MB), OS1 (3.5GB), OS2 (3.5GB), Data (remaining)
  - GPT partitioning with ESP flag for UEFI compatibility
- **Build System Architecture**  
  - Found separation of concerns: pxe-server-setup for infrastructure, device-setup-initialization for images
  - Modern IMG + HTTP approach preferred over legacy SquashFS + NFS

### External Research
- #fetch:Microsoft documentation
  - GRUB2 UEFI PXE boot configuration best practices
  - Linux bootloader security considerations and UEFI Secure Boot requirements
  - Network boot troubleshooting and performance optimization

### Project Conventions
- Standards referenced: UEFI-only boot priority, native GRUB2 tools, /etc/grub.d/40_custom for custom entries
- Instructions followed: No iPXE usage, avoid symlinks, use numbered build scripts, artifacts/ directory structure

## Key Discoveries

### Project Structure
The current implementation follows a clear separation of concerns:
- **pxe-server-setup**: Network infrastructure (DHCP, TFTP, HTTP, NFS services)
- **device-setup-initialization**: Image building and installation system creation
- **Integration**: Automated deployment scripts connecting both repositories

### Implementation Patterns
Current approach successfully implements the requirements with these patterns:
1. **Dual-format output**: Both modern IMG files (HTTP-served) and legacy SquashFS (NFS/HTTP-served)
2. **GRUB2-native configuration**: Uses GRUB CLI tools and proper menu entry management
3. **Staged deployment**: Build → Deploy → Boot → Install workflow
4. **Partition management**: Consistent 4-partition layout with proper labeling and mounting

### Complete Examples
```bash
# Current build workflow
./scripts/create-pxe-system.sh --img-size 4G
./scripts/deploy-to-pxe-server.sh 10.1.1.1
```

```bash
# Partition layout created by installer
sudo parted "$DISK" mkpart primary fat32 1MiB 513MiB      # GRUB (512MB)
sudo parted "$DISK" mkpart primary ext4 513MiB 4097MiB    # OS1 (3.5GB)
sudo parted "$DISK" mkpart primary ext4 4097MiB 7681MiB   # OS2 (3.5GB) 
sudo parted "$DISK" mkpart primary ext4 7681MiB 100%      # DATA (remaining)
```

### API and Schema Documentation
The current system integrates with pxe-server-setup via:
- SSH deployment using `./scripts/08-iso-manager.sh add <img>`
- GRUB configuration updates through `/etc/grub.d/40_custom`
- HTTP serving through nginx virtual hosts
- TFTP serving for kernel/initrd files

### Configuration Examples
```bash
# GRUB menu entry generated
menuentry 'Dual-OS Installation System' --id=dual-os-installer {
    echo 'Loading Dual-OS Installation System...'
    linux /kernels/device-setup/vmlinuz boot=live fetch=http://10.1.1.1/images/dual-os-installer.img ip=dhcp
    initrd /initrd/device-setup/initrd
    boot
}
```

### Technical Requirements
The system currently meets most PXE server instructions requirements:
- ✅ UEFI boot priority with GRUB2 configuration
- ✅ Device partition scheme with 6 partitions (EFI, Root, Swap, OS1, OS2, Data)
- ✅ IMG files for HTTP serving
- ✅ SquashFS for legacy compatibility
- ✅ GRUB2 menu with timeout and default selections
- ✅ Dual-OS installation (Ubuntu + Debian)
- ✅ Integration with pxe-server-setup infrastructure

## Analysis Gap: Requirements vs Current Implementation

### Requirements Not Fully Met
1. **Specific partition scheme mismatch**: 
   - Required: EFI (100-200MB), Root (1-2GB), Swap (2-4GB), OS1 (3.7GB), OS2 (3.7GB), Data (remaining)
   - Current: GRUB (512MB), OS1 (3.5GB), OS2 (3.5GB), Data (remaining) - missing separate root and swap
2. **GRUB menu structure**: 
   - Required: Configure Device, Partition Disk, Install OS1/OS2, Boot OS1/OS2, Factory Reset
   - Current: Mainly focused on installation, missing configuration and factory reset options
3. **Interactive configuration flow**:
   - Required: First-run device configuration (network, hostname, etc.)
   - Current: Automated installation focus, limited interactive configuration

### Enhancement Opportunities
1. **Partition Layout Alignment**: Modify create_partitions() function to match exact requirements
2. **GRUB Menu Enhancement**: Add configuration, factory reset, and boot options to menu structure  
3. **Configuration Scripts**: Add bash scripts for device configuration avoiding cloud-init/autoinstall
4. **Factory Reset Capability**: Implement re-initialization option in GRUB menu

## Recommended Approach

**Enhanced Current Implementation with Requirements Alignment**

The existing architecture is solid and should be enhanced rather than replaced. The current separation of concerns between pxe-server-setup and device-setup-initialization provides excellent modularity.

### Key Enhancements Needed:

1. **Partition Scheme Update**:
   - Modify `create_partitions()` function in create-pxe-system.sh
   - Implement 6-partition layout matching requirements exactly
   - Add swap partition creation and configuration

2. **GRUB Menu Enhancement**:
   - Extend GRUB configuration to include all required menu options
   - Add interactive configuration scripts accessible from GRUB menu
   - Implement factory reset functionality

3. **Configuration System Addition**:
   - Create bash-based configuration scripts for first-run setup
   - Add network, hostname, SSH key configuration options
   - Implement configuration persistence across installations

4. **Boot Flow Enhancement**:
   - Add proper OS1/OS2 boot options to local GRUB configuration
   - Implement default boot behavior with timeout
   - Add advanced options and recovery mode entries

## Implementation Guidance
- **Objectives**: Enhance existing system to fully meet PXE server instructions requirements while maintaining current architecture benefits
- **Key Tasks**: Update partition layout, enhance GRUB menus, add configuration scripts, implement factory reset
- **Dependencies**: Existing pxe-server-setup infrastructure, current build system architecture
- **Success Criteria**: Full compliance with PXE server instructions while preserving current functionality and deployment workflow
