# Clonezilla-Only PXE Server Quickstart (UEFI, No iPXE)

This guide describes a minimal manual setup for serving Clonezilla Live over TFTP (kernel/initrd), HTTP (SquashFS), and optional NFS (image repository + logs). Assumes Ubuntu 24.04 server. Adjust paths as needed. BIOS legacy mode not supported.

## 1. Install Required Packages
```
sudo apt-get update
sudo apt-get install -y grub-efi-amd64-bin tftpd-hpa apache2 nfs-kernel-server
```

## 2. Directory Layout
```
/srv/tftp/grub/clonezilla/<version>/   # kernel+initrd (+ squashfs if TFTP only)
/var/www/html/images/clonezilla/<version>/  # filesystem.squashfs (HTTP)
/srv/clonezilla/images/                # (NFS export) Clonezilla image sets
/srv/tftp/grub/grub.cfg                # Main GRUB configuration
```

Create directories:
```
sudo mkdir -p /srv/tftp/grub/clonezilla /var/www/html/images/clonezilla /srv/clonezilla/images
sudo chown -R tftp:tftp /srv/tftp
```

## 3. Configure TFTP (grubx64.efi)
`tftpd-hpa` usually serves `/srv/tftp` when configured in `/etc/default/tftpd-hpa`:
```
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/srv/tftp"
TFTP_ADDRESS=":69"
TFTP_OPTIONS="--secure --create"
```
Restart:
```
sudo systemctl restart tftpd-hpa
```
Copy GRUB EFI binary:
```
sudo cp /usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed /srv/tftp/grubx64.efi || \
  sudo cp /usr/lib/grub/x86_64-efi/grubx64.efi /srv/tftp/grubx64.efi
```

## 4. HTTP Serving
Apache default doc root: `/var/www/html`. Ensure permissions:
```
sudo chown -R www-data:www-data /var/www/html/images
```

## 5. Optional NFS Export
Edit `/etc/exports`:
```
/srv/clonezilla/images  *(ro,no_subtree_check,fsid=10)
```
Then:
```
sudo exportfs -ra
sudo systemctl restart nfs-server
```

## 6. Place Clonezilla Assets
From your build artifacts (after running fetch + sync scripts):
```
# Variables
VERSION=2025.01.01
SRC=./artifacts

sudo mkdir -p /srv/tftp/grub/clonezilla/$VERSION
sudo cp $SRC/pxe-files/clonezilla/$VERSION/vmlinuz /srv/tftp/grub/clonezilla/$VERSION/
sudo cp $SRC/pxe-files/clonezilla/$VERSION/initrd.img /srv/tftp/grub/clonezilla/$VERSION/
# HTTP SquashFS
sudo mkdir -p /var/www/html/images/clonezilla/$VERSION
sudo cp $SRC/images/clonezilla/$VERSION/filesystem.squashfs /var/www/html/images/clonezilla/$VERSION/
```
For NFS images (optional):
```
sudo rsync -a $SRC/clonezilla/images/ /srv/clonezilla/images/
```

## 7. GRUB Configuration
Create `/srv/tftp/grub/grub.cfg` (or append) with entries produced by the build (`grub-entries-clonezilla.cfg`). Example manual minimal HTTP entry:
```
set timeout=10
set default=0
menuentry 'Clonezilla Live (Manual HTTP)' {
    linuxefi /grub/clonezilla/2025.01.01/vmlinuz boot=live ip=dhcp net.ifnames=0 \
      fetch=http://<server-ip>/images/clonezilla/2025.01.01/filesystem.squashfs \
      ocs_live_run="ocs-live-general" ocs_live_batch=no quiet
    initrdefi /grub/clonezilla/2025.01.01/initrd.img
}
```
Include auto restore entry only after setting confirmation in `config.sh` and verifying image path.

## 8. DHCP Configuration (External DHCP)
Ensure the DHCP server supplies:
- Option 67: `grubx64.efi`
- Option 66: PXE server IP

## 9. Testing
1. Boot UEFI client with network PXE first.
2. GRUB menu appears; choose Clonezilla entry.
3. For HTTP fetch, monitor with `sudo tail -f /var/log/apache2/access.log`.
4. For NFS, verify: `showmount -e <server-ip>`.

## 10. Troubleshooting
| Symptom | Action |
|---------|--------|
| GRUB not loading | Check DHCP options, TFTP logs (`journalctl -u tftpd-hpa`) |
| Kernel loads then drops to prompt | Verify fetch URL accessible (curl from another host) |
| Slow boot | Avoid TFTP for squashfs; prefer HTTP or NFS |
| NFS timeouts | Check firewall ports 2049/111 |

## 11. Security Notes
- Limit NFS exports to specific subnets in production.
- Consider HTTPS for image delivery (enable Apache SSL) if tampering risk.
- Validate checksums (`sha256sum filesystem.squashfs`).

## 12. Cleanup
To remove version:
```
sudo rm -rf /srv/tftp/grub/clonezilla/<version> \
  /var/www/html/images/clonezilla/<version>
```

---
Generated: $(date -u)
