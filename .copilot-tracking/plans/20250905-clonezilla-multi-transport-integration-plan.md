# Clonezilla Multi-Transport Integration Plan

## 1. Goal
Add Clonezilla Live based imaging (manual + unattended) to the UEFI-only PXE + GRUB2 environment, supporting TFTP (kernel/initrd only), HTTP (fetch=), and NFS (netboot + rw image repo) without disrupting existing device initialization build pipeline.

## 2. Scope
In-scope:
- ISO acquisition, extraction, versioned artifacts
- GRUB menu entries (manual + automated restore variants)
- Transport-specific handling (tftp, http, nfs)
- Safety & validation (disk match, confirmation gating)
- Image import & manifest generation
- Test scaffolding (QEMU dry-run)
- Documentation & verification scripts

Out-of-scope (documented future): multicast (Clonezilla SE), encryption, signing, bittorrent.

## 3. Configuration Model
New variables appended to `config.sh`:
```
clonezilla_version="2025.01.01"          # example; actual version string
clonezilla_iso_url="https://downloads.sourceforge.net/clonezilla/clonezilla-live-${clonezilla_version}-amd64.iso"
clonezilla_iso_sha256=""                # optional expected checksum
clonezilla_transport="http"             # http|nfs|tftp
clonezilla_server_host="192.168.1.10"   # authoritative server
clonezilla_http_base="http://${clonezilla_server_host}/images"
clonezilla_nfs_export="/srv/images"     # export path on PXE server
clonezilla_target_disk="/dev/sda"       # primary device
clonezilla_image_default="base-os-a"    # directory name under images/
clonezilla_mode="manual"                # manual|auto_full|auto_parts
clonezilla_confirm="NO"                 # must be YES for destructive unattended
clonezilla_layout_file="artifacts/clonezilla/layouts/edge-default.json"
CLONEZILLA_DRY_RUN=""                  # if set, echo actions instead of running ocs-sr
```

## 4. Artifact Layout
```
artifacts/clonezilla/
  iso/                               # downloaded ISOs
  extracted/<version>/               # vmlinuz, initrd.img, filesystem.squashfs, sha256sums.txt, manifest.json
  images/<image-name>/               # Clonezilla image directory structure
  manifests/                         # consolidated manifests per run
  layouts/                           # partition layout descriptors (json)
```
No symlinks; all copies.

## 5. Scripts (Device Initialization Repo)
```
10-clonezilla-fetch.sh        # Download & extract ISO, hash, manifest
11-clonezilla-image-import.sh # Import or list images
12-clonezilla-sync-artifacts.sh # Prepare transport-specific copies
13-clonezilla-generate-grub.sh  # Produce GRUB entries file
14-clonezilla-guard.sh          # Runtime safety helpers (size checks)
15-test-clonezilla-qemu.sh      # QEMU PXE dry-run test harness
16-clonezilla-verify.sh         # Integrity and accessibility validation
```
Supporting helpers can live under `scripts/config/` if needed.

### 5.1 Script Behaviors (Key Points)
- All scripts source `config.sh`.
- Idempotent: check existing files + hashes before rework.
- Exit non-zero on validation failures.

#### 10-clonezilla-fetch.sh
1. Ensure directories.
2. Download ISO (curl -L --fail --continue-at -).
3. If `clonezilla_iso_sha256` set -> verify; else compute and store.
4. Mount loop, copy `live/vmlinuz`, `live/initrd.img`, `live/filesystem.squashfs`.
5. Generate `sha256sums.txt` and `manifest.json` (keys: version, timestamp, files[], checksums, size_bytes).
6. Unmount loop cleanly; handle stale mounts.

#### 11-clonezilla-image-import.sh
Subcommands:
- `add <path>`: copy image dir, compute per-file sha256, store `images/<name>/SHA256SUMS`.
- `list`: enumerate available image names.
- `verify <name>`: re-hash and compare.
Validates Clonezilla required structure (`info`, `parts`, subdirs per partition image).

#### 12-clonezilla-sync-artifacts.sh
Depending on `clonezilla_transport`:
- Common: copy kernel+initrd to `artifacts/pxe-files/clonezilla/<version>/` (for later deployment to TFTP).
- HTTP: copy squashfs + images to `artifacts/images/clonezilla/<version>/` and `artifacts/images/clonezilla/images/`.
- NFS: ensure local staging under `artifacts/clonezilla/images/` (server export will map to `/srv/images`).
- TFTP: (fallback) also copy squashfs into `artifacts/pxe-files/clonezilla/<version>/` with warning about performance.
Writes per-transport manifest + aggregated SHA256 file.

#### 13-clonezilla-generate-grub.sh
Outputs `artifacts/pxe-integration/grub-entries-clonezilla.cfg` containing entries:
- Manual:
  - Kernel: (path resolved by PXE server after deploy)
  - Cmdline additions per transport:
    - HTTP: `fetch=${clonezilla_http_base}/clonezilla/${clonezilla_version}/filesystem.squashfs`
    - NFS: `boot=live netboot=nfs nfsroot=${clonezilla_server_host}:${clonezilla_nfs_export}`
    - TFTP: `fetch=tftp://${clonezilla_server_host}/clonezilla/${clonezilla_version}/filesystem.squashfs`
- Auto Full Restore (if `clonezilla_confirm==YES` and mode matches): adds
  - `ocs_prerun="/clonezilla/guard/disk-check.sh"`
  - `ocs_live_run="ocs-live-general" ocs_live_batch=yes`
  - Restore command via `ocs-sr`.
- Auto Partitions: similar but with `restoreparts` using layout or explicit partitions.
- Capture (optional, gated by `clonezilla_confirm==YES` + `clonezilla_mode=capture`).
All entries include `quiet noswap nomodeset nodmraid ip=dhcp` unless overridden.

#### 14-clonezilla-guard.sh
Provides runtime helper scripts placed into an overlay (future) or invoked via `ocs_prerun`:
- `disk-check.sh`: compares disk size vs image metadata (abort if smaller).
- `echo-mode.sh`: if `CLONEZILLA_DRY_RUN` set, replace `ocs-sr` with echo wrapper.

#### 15-test-clonezilla-qemu.sh
- Spins up UEFI QEMU client configured for network PXE.
- Captures serial output; scans for Clonezilla prompt or restore command line.
- Dry-run only (sets `CLONEZILLA_DRY_RUN=1`).

#### 16-clonezilla-verify.sh
- Verify extracted artifact hashes.
- Confirm GRUB entries contain expected transport clause.
- Transport reachability probes (curl HEAD / showmount / tftp get simulation).
- Summarize PASS/FAIL matrix.

## 6. GRUB Entry Examples (Template Snippets)
Manual (HTTP example):
```
menuentry 'Clonezilla Live (Manual)' {
    linuxefi /grub/clonezilla/${clonezilla_version}/vmlinuz boot=live union=overlay ip=dhcp net.ifnames=0 ocs_live_run="ocs-live-general" ocs_live_batch=no quiet
    initrdefi /grub/clonezilla/${clonezilla_version}/initrd.img
    # squashfs via HTTP
    # live-boot fetch mechanism
    set rootfs_url="${clonezilla_http_base}/clonezilla/${clonezilla_version}/filesystem.squashfs"
}
```
Auto Full (HTTP):
```
menuentry 'Clonezilla Auto Full Restore' {
    linuxefi /grub/clonezilla/${clonezilla_version}/vmlinuz boot=live ip=dhcp net.ifnames=0 fetch=${clonezilla_http_base}/clonezilla/${clonezilla_version}/filesystem.squashfs ocs_live_run="ocs-live-general" ocs_live_batch=yes ocs_prerun="/clonezilla/guard/disk-check.sh" ocs_live_extra_param="" quiet
    initrdefi /grub/clonezilla/${clonezilla_version}/initrd.img
}
```
NFS variant uses: `boot=live netboot=nfs nfsroot=${clonezilla_server_host}:${clonezilla_nfs_export}` (omit fetch).

## 7. Safety & Validation
- Disk size check: parse `images/<image>/info` for original disk geometry; ensure target ≥ source.
- Confirmation gating: any unattended restore requires `clonezilla_confirm=YES`.
- Hash verification prior to GRUB generation.
- Abort if transport mismatch (e.g., http chosen but squashfs not copied into images path).

## 8. Logging Strategy
- Prefer NFS for persistent logs: `--ocs-debug-dir /home/partimag/ocs-logs`.
- For HTTP/TFTP ephemeral sessions, instruct manual log capture (documented).
- Future: optional rsync/scp post-run hook.

## 9. Testing Matrix
| Test | Transport | Mode | Expectation |
|------|-----------|------|-------------|
| Boot Manual | HTTP | manual | Shell interface arrives |
| Auto Full Dry | HTTP | auto_full | Restore command echoed (dry-run) |
| Auto Parts Dry | NFS | auto_parts | Partition restore command shown |
| TFTP Manual | TFTP | manual | Fetch squashfs (slower) but boots |
| Disk Too Small | Any | auto_full | Abort before cloning |
| Missing Image | Any | auto_full | Generation script fails |
| Hash Corruption | Any | verify | 16 script flags failure |

## 10. Performance Notes
- HTTP vs NFS: measure time to retrieve squashfs (log to `artifacts/logs/perf-*.txt`).
- Recommend HTTP for distribution; NFS when capture or logs needed.
- Discourage TFTP for squashfs except very small images or airgap simplicity.

## 11. Deployment Flow Summary
1. Run `10-clonezilla-fetch.sh` (once per version).
2. Import or create image with `11-clonezilla-image-import.sh add`.
3. Sync artifacts `12-clonezilla-sync-artifacts.sh`.
4. Generate GRUB entries `13-clonezilla-generate-grub.sh`.
5. Deploy integration directory to PXE server (existing deployment script extended later).
6. Verify `16-clonezilla-verify.sh`.
7. QEMU dry-run `15-test-clonezilla-qemu.sh`.
8. Flip `clonezilla_confirm=YES` then redeploy for real unattended restore.

## 12. Future Enhancements (Document Only)
- Multicast imaging path with Lite Server / SE.
- Encrypted image repositories (ecryptfs or LUKS container).
- GPG signed manifests + verification in guard script.
- Dynamic GRUB generation per-image enumeration.
- Streaming capture back to server (named pipe + compression).

## 13. Risks & Mitigations
| Risk | Mitigation |
|------|------------|
| Slow TFTP squashfs | Warn + recommend HTTP/NFS |
| Wrong disk target | Guard script + explicit `clonezilla_target_disk` |
| Corrupt image | Hash verification before restore |
| Accidental mass wipe | `clonezilla_confirm` gate + dry-run support |
| Transport misconfig | Pre-flight checks in sync + verify scripts |

## 14. Acceptance Criteria
- Plan implemented via new scripts without breaking existing build.
- GRUB entries file produced matching selected transport.
- Dry-run QEMU test proves menu + command line generation.
- Integrity verification script passes for intact artifacts, fails when tampered.
- Clear documentation for operator to switch modes.

---
Generated: 2025-09-05
