# General notes on scripts

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
