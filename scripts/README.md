# General notes on scripts

## Script Execution Order

The scripts are designed to run in numerical order:

1. `01-bootstrap-environment.sh` - Sets up build environment
2. `02-system-configuration.sh` - Configures system settings
3. `03-package-installation.sh` - Installs required packages
4. `04-grub-configuration.sh` - Configures GRUB bootloader
5. `05-image-creation.sh` - Creates device images
6. `06-testing-validation.sh` - Tests and validates images
7. `07-generate-integration.sh` - Generates integration files
8. `99-cleanup.sh` - Comprehensive cleanup script

## Cleanup Script (99-cleanup.sh)

The cleanup script handles comprehensive cleanup when builds fail or when manually cleaning up:

### Usage:
```bash
sudo ./scripts/99-cleanup.sh [options]
```

### Options:
- `--mounts-only` - Clean up mounted filesystems only
- `--loops-only` - Clean up loop devices only  
- `--packages-only` - Clean up packages only
- `--force-artifacts` - Force cleanup of artifacts directory only
- `--help` - Show help message
- (no args) - Run full cleanup

### What it cleans:
- Mounted filesystems in artifacts directory
- Loop devices associated with build process
- Busy directories that can't be removed normally
- Conflicting BIOS boot packages
- Package cache and temporary files
- Build environment artifacts

### When it runs automatically:
- When build scripts encounter errors
- During normal build cleanup (mounts and loops only)
- When starting a clean build

## Warnings emitted during run

### Perl locale warnings:
Locale settings warnings in the chroot environment
Common in minimal chroot environments, won't affect boot

### Debconf frontend warnings:
Falls back from Dialog → Readline → Teletype
Normal in minimal chroot without full terminal capabilities

### systemd chroot warnings:
"Running in chroot, ignoring command 'daemon-reload'"
Expected behavior when installing systemd in chroot

### mksquashfs xattr warnings:
"Unrecognised xattr prefix system.posix_acl_access"
These extended attributes aren't critical for boot

## Troubleshooting Build Issues

If you encounter the error:
```
rm: cannot remove 'artifacts/build-env/rootfs/dev/mqueue': Device or resource busy
```

Run the cleanup script to fix busy mounts and loop devices:
```bash
sudo ./scripts/99-cleanup.sh
```

For specific issues:
- Busy mounts: `sudo ./scripts/99-cleanup.sh --mounts-only`
- Loop devices: `sudo ./scripts/99-cleanup.sh --loops-only`
- Force artifacts removal: `sudo ./scripts/99-cleanup.sh --force-artifacts`
