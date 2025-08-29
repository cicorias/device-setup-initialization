# GitHub Workflows

This directory contains GitHub Actions workflows for the PXE system project.

## Workflows

### 1. PXE System CI (`pxe-system-ci.yml`)
**Main workflow for continuous integration**

- **Triggers**: 
  - Push to `split-and-merge-scripts` branch (currently)
  - PRs to `split-and-merge-scripts` branch (currently)
  - Manual dispatch

- **Jobs**:
  - **validate-scripts**: Runs shellcheck on all shell scripts
  - **test-pxe-system**: Creates PXE system and tests deployment package
  - **test-deployment-scripts**: Tests deployment scripts in dry-run mode

- **Artifacts**: Uploads PXE files, server deployment, and OS images (7-day retention)

### 2. Full PXE System Build (`full-build.yml`)
**Comprehensive build workflow for releases**

- **Triggers**:
  - Manual dispatch (with options for IMG building)
  - Release published events

- **Features**:
  - Optional IMG file creation (time-intensive)
  - Configurable IMG size
  - Creates compressed archives
  - Generates checksums
  - 2-hour timeout for full builds
  - Uploads to releases automatically

### 3. Quick Tests (`quick-tests.yml`)
**Fast validation workflow**

- **Triggers**:
  - Push/PR affecting `scripts/` or workflow files
  - Manual dispatch

- **Checks**:
  - Script syntax validation
  - Shellcheck linting
  - TODO/FIXME comment detection
  - Script executability verification

## Configuration

### Branch Configuration
Currently configured for the `split-and-merge-scripts` branch. To switch to main:

1. Edit `pxe-system-ci.yml`
2. Comment out current branch lines
3. Uncomment the main branch lines

### Environment Variables
- `ARTIFACTS`: Set to `${{ github.workspace }}/artifacts`
- `OUTPUT_SQUASHFS`: Always `true` in CI
- `OUTPUT_IMG`: `false` by default (configurable in full build)
- `CI`: Set to `true` for CI-specific behavior

### Manual Workflow Dispatch
Both the main CI and full build workflows can be triggered manually:
1. Go to Actions tab in GitHub
2. Select the workflow
3. Click "Run workflow"
4. Configure options (for full build)

## Artifacts
- **Quick retention** (7 days): CI artifacts
- **Long retention** (30 days): Full build artifacts
- **Release artifacts**: Permanent (attached to releases)

## Prerequisites
The workflows install required system packages:
- `debootstrap`
- `squashfs-tools` 
- `qemu-utils`
- `syslinux-utils`
- `isolinux`
- `xorriso`
- `shellcheck`

## Troubleshooting

### Disk Space Issues
The full build workflow includes disk cleanup steps. If you encounter space issues:
- The workflow removes unnecessary packages
- Consider reducing `IMG_SIZE` parameter
- Set `OUTPUT_IMG=false` to skip IMG creation

### Timeout Issues
- Quick tests: ~10 minutes
- CI workflow: ~30 minutes  
- Full build: Up to 2 hours

### Script Execution Issues
Ensure scripts have proper permissions:
```bash
chmod +x scripts/*.sh
```

The workflows automatically set executable permissions, but local testing may require manual setup.
