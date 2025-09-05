# Clonezilla Deployment Integration

This document describes the Clonezilla Live integration added to the device initialization pipeline. It enables manual and unattended disk restoration via PXE + GRUB2 using HTTP, NFS, or (discouraged) TFTP for the SquashFS payload.

## Overview
Workflow:
1. Fetch Clonezilla ISO and extract core assets.
2. Import one or more Clonezilla images.
3. Sync artifacts for chosen transport.
4. Generate GRUB menu entries.
5. (Optional) Prepare guard scripts and test via QEMU.
6. Verify integrity prior to deployment.

## Scripts
| Script | Purpose |
|--------|---------|
| 10-clonezilla-fetch.sh | Download & extract ISO (vmlinuz, initrd, filesystem.squashfs) + manifest |
| 11-clonezilla-image-import.sh | Add/list/verify Clonezilla image directories |
| 12-clonezilla-sync-artifacts.sh | Copy assets into transport-specific layout |
| 13-clonezilla-generate-grub.sh | Emit GRUB entries file for integration |
| 14-clonezilla-guard.sh | Create safety helper scripts (disk checks, dry-run wrapper) |
| 15-test-clonezilla-qemu.sh | PXE dry-run boot harness (UEFI) |
| 16-clonezilla-verify.sh | Integrity and configuration verification |

## Configuration Variables (config.sh)
```
clonezilla_version
clonezilla_iso_url
clonezilla_iso_sha256 (optional)
clonezilla_transport=http|nfs|tftp
clonezilla_server_host
clonezilla_http_base
clonezilla_nfs_export
clonezilla_target_disk
clonezilla_image_default
clonezilla_mode=manual|auto_full|auto_parts|capture
clonezilla_confirm=NO|YES
clonezilla_layout_file
CLONEZILLA_DRY_RUN (non-empty enables echo of restore command)
```

Set `clonezilla_confirm=YES` to enable unattended destructive restore entries.

## Artifact Layout
```
artifacts/clonezilla/
  iso/
  extracted/<version>/
  images/<image-name>/
  manifests/
  layouts/
```
Operational copies placed under:
```
artifacts/pxe-files/clonezilla/<version>/ (kernel/initrd [+ squashfs for tftp])
artifacts/images/clonezilla/<version>/ (squashfs for http)
artifacts/images/clonezilla/images/ (imported image sets)
```

## Typical Usage
```
# 1. Fetch ISO
./scripts/10-clonezilla-fetch.sh

# 2. Import existing Clonezilla image (directory with info, parts, etc.)
./scripts/11-clonezilla-image-import.sh add /path/to/clonezilla/image/base-os-a

# 3. Sync artifacts for configured transport
./scripts/12-clonezilla-sync-artifacts.sh

# 4. Generate GRUB entries
./scripts/13-clonezilla-generate-grub.sh

# 5. Prepare guard scripts (optional but recommended for unattended)
./scripts/14-clonezilla-guard.sh

# 6. Verify
./scripts/16-clonezilla-verify.sh

# 7. (Optional) QEMU test (dry run)
CLONEZILLA_DRY_RUN=1 ./scripts/15-test-clonezilla-qemu.sh
```

Then copy integration outputs to PXE server according to existing deployment process (e.g., copy `artifacts/pxe-integration/grub-entries-clonezilla.cfg` and Clonezilla kernel/initrd/squashfs to GRUB accessible paths).

## GRUB Integration
Resulting file: `artifacts/pxe-integration/grub-entries-clonezilla.cfg`. Merge or include its entries in the master GRUB menu. A typical include approach:
```
# In main grub.cfg or 40_custom on PXE server
source ($root)/grub/grub-entries-clonezilla.cfg
```
Ensure kernel/initrd paths align with server deployment layout (current scripts assume `/grub/clonezilla/<version>/`).

## Safety
- Unattended modes require `clonezilla_confirm=YES`.
- Guard script stub (`disk-check.sh`) is installed; extend to parse image metadata for strict size validation.
- Dry-run via `CLONEZILLA_DRY_RUN=1` will echo restore command instead of executing.

## Transport Notes
- HTTP: fastest distribution; uses live-boot `fetch=`.
- NFS: required for image capture workflows and central logging.
- TFTP: only for minimal or constrained networks; performance warning emitted.

## Extensibility
Future enhancements (not implemented yet):
- Multicast Clonezilla SE integration
- Signed manifests and GPG verification
- Dynamic per-image GRUB generation
- Automated capture workflows

## Troubleshooting
| Issue | Check |
|-------|-------|
| Kernel not found | Run 10-clonezilla-fetch.sh again; verify ISO mount success |
| Hash mismatch | Delete extracted dir and re-run fetch script with known SHA256 |
| GRUB entry boots but no network | Ensure DHCP provides proper options and NIC supported |
| Unattended restore not starting | Confirm clonezilla_confirm=YES and mode=auto_full |

## Verification Matrix (Implemented)
`16-clonezilla-verify.sh` checks: extracted files, hashes, GRUB transport token, image presence (auto_full).

---
Generated: $(date -u)
