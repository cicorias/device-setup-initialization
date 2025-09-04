## PXE Boot Device Initialization Sequence Diagram

┌─────────┐     ┌────────────┐     ┌────────────┐     ┌─────────────┐     ┌───────────┐
│  Device │     │ PXE Server │     │TFTP Server │     │ HTTP/NFS    │     │   GRUB2   │
└────┬────┘     └─────┬──────┘     └─────┬──────┘     └──────┬──────┘     └─────┬─────┘
     │                │                   │                    │                  │
     │ Power On       │                   │                    │                  │
     ├───────────────►│                   │                    │                  │
     │                │                   │                    │                  │
     │ DHCP Request   │                   │                    │                  │
     ├───────────────►│                   │                    │                  │
     │                │                   │                    │                  │
     │ IP + PXE Info  │                   │                    │                  │
     │◄───────────────┤                   │                    │                  │
     │                │                   │                    │                  │
     │ Request UEFI Bootloader            │                    │                  │
     ├───────────────────────────────────►│                    │                  │
     │                │                   │                    │                  │
     │ grubx64.efi    │                   │                    │                  │
     │◄───────────────────────────────────┤                    │                  │
     │                │                   │                    │                  │
     │ Load GRUB2     │                   │                    │                  │
     ├──────────────────────────────────────────────────────────────────────────►│
     │                │                   │                    │                  │
     │ Request grub.cfg                   │                    │                  │
     ├───────────────────────────────────►│                    │                  │
     │                │                   │                    │                  │
     │ grub.cfg       │                   │                    │                  │
     │◄───────────────────────────────────┤                    │                  │
     │                │                   │                    │                  │
     │ Display GRUB Menu                  │                    │                  │
     │◄───────────────────────────────────────────────────────────────────────────┤
     │                │                   │                    │                  │
     │ User Selection │                   │                    │                  │
     ├──────────────────────────────────────────────────────────────────────────►│
     │                │                   │                    │                  │
     │ Request Init IMG                   │                    │                  │
     ├──────────────────────────────────────────────────────────►│                  │
     │                │                   │                    │                  │
     │ SquashFS IMG   │                   │                    │                  │
     │◄────────────────────────────────────────────────────────┤                  │
     │                │                   │                    │                  │
     │ Boot Init System                   │                    │                  │
     ├──────────────────────────────────────────────────────────────────────────►│
     │                │                   │                    │                  │
     │ Run Config Scripts                 │                    │                  │
     │◄───────────────────────────────────────────────────────────────────────────┤
     │                │                   │                    │                  │
     │ Partition Disk │                   │                    │                  │
     │ Install OS1/OS2│                   │                    │                  │
     │ Update GRUB    │                   │                    │                  │
     │◄───────────────────────────────────────────────────────────────────────────┤
     │                │                   │                    │                  │
     │ Reboot         │                   │                    │                  │
     ├──────────────────────────────────────────────────────────────────────────►│
     │                │                   │                    │                  │
     │ Boot OS1/OS2   │                   │                    │                  │
     │◄───────────────────────────────────────────────────────────────────────────┤

## Step-by-Step Process (Pseudo Code/English)

### Phase 1: Initial PXE Boot
1. Device Powers On
   - UEFI firmware initiates network boot
   - Sends DHCP discover request

2. DHCP Server Response
   - Assigns IP address to device
   - Provides PXE boot server IP
   - Specifies UEFI boot file (grubx64.efi)

3. TFTP Boot File Transfer
   - Device requests grubx64.efi from TFTP server
   - Downloads and executes GRUB2 bootloader

### Phase 2: GRUB Menu Presentation
4. GRUB Configuration Load
   - GRUB requests grub.cfg from TFTP server
   - Loads menu configuration with options:
     - Configure Device
     - Partition Disk
     - Install OS1
     - Install OS2
     - Boot into OS1
     - Boot into OS2
     - Factory Reset

5. User Menu Selection
   - Display menu with 30-second timeout
   - Default to "Boot into OS1" if no selection

### Phase 3: Initial Configuration (First Run)
6. Load Initialization Image
   IF user selects "Configure Device" THEN
      Download SquashFS init image via HTTP/NFS
      Boot into minimal Linux environment
      Mount SquashFS as root filesystem

7. Device Configuration
   RUN configuration scripts:
      - Prompt for hostname
      - Configure network settings (static/DHCP)
      - Set timezone
      - Configure SSH keys (optional)
      - Save configuration to persistent storage

### Phase 4: Disk Partitioning
8. Partition Disk
   IF user selects "Partition Disk" THEN
      Detect available disks
      Create GPT partition table
      Create partitions:
         - ESP (200MB, FAT32) at /dev/sdX1
         - Root (2GB, ext4) at /dev/sdX2
         - Swap (4GB) at /dev/sdX3
         - OS1 (3.7GB, ext4) at /dev/sdX4
         - OS2 (3.7GB, ext4) at /dev/sdX5
         - Data (remaining, ext4) at /dev/sdX6
      Format all partitions
      Mount ESP at /boot/efi

### Phase 5: OS Installation
9. Install OS1/OS2
   IF user selects "Install OS1" THEN
      target_partition = /dev/sdX4
   ELSE IF user selects "Install OS2" THEN
      target_partition = /dev/sdX5
   
   Mount target_partition at /mnt
   Run debootstrap:
      - Download Ubuntu 24.04 base system
      - Install to /mnt
      - Configure fstab
      - Install kernel and essential packages
      - Set root password
      - Configure network

10. GRUB Installation and Configuration
    Install GRUB to ESP:
       - grub-install --target=x86_64-efi --efi-directory=/boot/efi
    
    Create /etc/grub.d/40_custom entries:
       - Entry for OS1 pointing to /dev/sdX4
       - Entry for OS2 pointing to /dev/sdX5
       - Set default boot to OS1
       - Set timeout to 5 seconds
    
    Run update-grub to generate grub.cfg

### Phase 6: Normal Boot Operation
11. Subsequent Boots
    ON device reboot:
       Load GRUB from local ESP
       Display menu:
          - OS1 (default)
          - OS2
          - Advanced Options
          - PXE Boot (for re-initialization)
       
       IF timeout expires:
          Boot into OS1
       ELSE
          Boot selected option

### Phase 7: Factory Reset
12. Factory Reset Process
    IF user selects "Factory Reset" THEN
       Boot into initialization image via PXE
       Wipe all partitions except ESP
       Return to Phase 4 (Disk Partitioning)
       Recreate partitions
       Reinstall OS1 and OS2
       Restore default GRUB configuration

### Error Handling Throughout
FOR each critical operation:
   TRY operation
   IF failure THEN
      Log error to console
      Display recovery options:
         - Retry operation
         - Skip to next step
         - Reboot to PXE menu
         - Drop to shell for manual intervention

This flow ensures a complete device initialization experience from bare metal to a dual-OS setup with fallback and recovery options.