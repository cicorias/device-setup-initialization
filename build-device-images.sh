#!/bin/bash
# Device Initialization Build System
# Creates PXE-bootable images for edge device initialization
# Follows the 6-partition layout: EFI, Root, Swap, OS1, OS2, Data

set -euo pipefail

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
SCRIPTS_DIR="$PROJECT_ROOT/scripts"

# Default configuration
ARTIFACTS="${ARTIFACTS:-$PROJECT_ROOT/artifacts}"
BUILD_ENV="${ARTIFACTS}/build-env"
IMAGES_DIR="${ARTIFACTS}/images"
OS_IMAGES_DIR="${ARTIFACTS}/os-images"
PXE_FILES_DIR="${ARTIFACTS}/pxe-files"
INTEGRATION_DIR="${ARTIFACTS}/pxe-integration"

# Partition sizes (can be overridden)
EFI_SIZE="${EFI_SIZE:-200M}"
ROOT_SIZE="${ROOT_SIZE:-2G}"
SWAP_SIZE="${SWAP_SIZE:-4G}"
OS1_SIZE="${OS1_SIZE:-3.7G}"
OS2_SIZE="${OS2_SIZE:-3.7G}"

# Build options
UBUNTU_RELEASE="${UBUNTU_RELEASE:-noble}"  # Ubuntu 24.04.3 LTS
TARGET_ARCH="${TARGET_ARCH:-amd64}"
PARALLEL_BUILDS="${PARALLEL_BUILDS:-true}"
DEBUG="${DEBUG:-false}"
VERBOSE="${VERBOSE:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    
    # Run cleanup on error
    local cleanup_script="$SCRIPTS_DIR/99-cleanup.sh"
    if [[ -f "$cleanup_script" ]]; then
        echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] Running cleanup due to error...${NC}"
        sudo "$cleanup_script" 2>/dev/null || echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] Cleanup script failed${NC}"
    fi
    
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

debug() {
    if [[ "$DEBUG" == "true" ]]; then
        echo -e "${BLUE}[DEBUG] $1${NC}"
    fi
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [options]

Build device initialization images for PXE deployment.

Options:
  --efi-size SIZE      EFI partition size (default: 200M)
  --root-size SIZE     Root partition size (default: 2G)
  --swap-size SIZE     Swap partition size (default: 4G)
  --os1-size SIZE      OS1 partition size (default: 3.7G)
  --os2-size SIZE      OS2 partition size (default: 3.7G)
  --ubuntu-release REL Ubuntu release (default: noble)
  --target-arch ARCH   Target architecture (default: amd64)
  --debug              Enable debug output
  --verbose            Enable verbose output
  --clean              Clean artifacts before building
  --help, -h           Show this help

Examples:
  $0                                    # Build with defaults
  $0 --clean --debug                    # Clean build with debug
  $0 --os1-size 5G --os2-size 5G        # Custom OS partition sizes
  $0 --ubuntu-release jammy             # Use Ubuntu 22.04 LTS

Build Phases:
  1. Bootstrap Environment
  2. Create InitRD
  3. Build Root Filesystem
  4. Build OS Images
  5. Create GRUB Configuration
  6. Package Images
  7. Generate Integration Files

Output:
  artifacts/images/                     # IMG files for HTTP serving
  artifacts/pxe-integration/            # PXE server integration
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --efi-size)
                EFI_SIZE="$2"
                shift 2
                ;;
            --root-size)
                ROOT_SIZE="$2"
                shift 2
                ;;
            --swap-size)
                SWAP_SIZE="$2"
                shift 2
                ;;
            --os1-size)
                OS1_SIZE="$2"
                shift 2
                ;;
            --os2-size)
                OS2_SIZE="$2"
                shift 2
                ;;
            --ubuntu-release)
                UBUNTU_RELEASE="$2"
                shift 2
                ;;
            --target-arch)
                TARGET_ARCH="$2"
                shift 2
                ;;
            --debug)
                DEBUG="true"
                shift
                ;;
            --verbose)
                VERBOSE="true"
                shift
                ;;
            --clean)
                CLEAN_BUILD="true"
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log "Checking build prerequisites..."
    
    # Check OS
    if ! grep -q "Ubuntu\|Debian" /etc/os-release; then
        error "This build system requires Ubuntu or Debian"
    fi
    
    # Check architecture
    if [[ "$(uname -m)" != "x86_64" ]]; then
        error "This build system requires x86_64 architecture"
    fi
    
    # Check sudo access
    if ! sudo -n true 2>/dev/null; then
        warn "sudo access required for build operations"
        sudo -v
    fi
    
    # Check disk space (require 20GB minimum)
    local available=$(df --output=avail "$PROJECT_ROOT" | tail -1)
    local required=$((20 * 1024 * 1024))  # 20GB in KB
    if [[ "$available" -lt "$required" ]]; then
        error "Insufficient disk space. Required: 20GB, Available: $((available / 1024 / 1024))GB"
    fi
    
    # Check required commands
    local required_commands=("debootstrap" "parted" "mkfs.fat" "mkfs.ext4" "losetup")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            error "Required command not found: $cmd"
        fi
    done
    
    info "Prerequisites check passed"
}

# Clean previous artifacts
clean_artifacts() {
    if [[ "${CLEAN_BUILD:-false}" == "true" ]]; then
        log "Cleaning previous artifacts..."
        if [[ -d "$ARTIFACTS" ]]; then
            # Use comprehensive cleanup script if available
            local cleanup_script="$SCRIPTS_DIR/99-cleanup.sh"
            if [[ -f "$cleanup_script" ]]; then
                log "Using comprehensive cleanup script..."
                sudo "$cleanup_script" --force-artifacts || {
                    warn "Comprehensive cleanup failed, falling back to basic cleanup"
                    basic_cleanup_artifacts
                }
            else
                basic_cleanup_artifacts
            fi
        fi
    fi
}

# Basic cleanup function (fallback)
basic_cleanup_artifacts() {
    # Unmount any loop devices
    for mount_point in $(mount | grep "$ARTIFACTS" | awk '{print $3}'); do
        debug "Unmounting $mount_point"
        sudo umount "$mount_point" 2>/dev/null || true
    done
    
    # Clean up loop devices
    for loop in $(losetup -a | grep "$ARTIFACTS" | cut -d: -f1); do
        debug "Detaching loop device $loop"
        sudo losetup -d "$loop" 2>/dev/null || true
    done
    
    rm -rf "$ARTIFACTS"
}

# Setup build environment
setup_build_environment() {
    log "Setting up build environment..."
    
    # Create directory structure
    mkdir -p "$BUILD_ENV" "$IMAGES_DIR" "$OS_IMAGES_DIR" "$PXE_FILES_DIR" "$INTEGRATION_DIR"
    mkdir -p "$ARTIFACTS/logs" "$ARTIFACTS/temp"
    
    # Create build configuration
    cat > "$BUILD_ENV/config.env" << EOF
# Device Initialization Build Configuration
# Generated on $(date)

# Ubuntu configuration
UBUNTU_RELEASE="$UBUNTU_RELEASE"
UBUNTU_MIRROR="http://archive.ubuntu.com/ubuntu"
TARGET_ARCH="$TARGET_ARCH"

# Partition sizes
EFI_SIZE="$EFI_SIZE"
ROOT_SIZE="$ROOT_SIZE"
SWAP_SIZE="$SWAP_SIZE"
OS1_SIZE="$OS1_SIZE"
OS2_SIZE="$OS2_SIZE"

# Build options
PARALLEL_BUILDS="$PARALLEL_BUILDS"
DEBUG="$DEBUG"
VERBOSE="$VERBOSE"

# Build environment
ARTIFACTS="$ARTIFACTS"
BUILD_ENV="$BUILD_ENV"
IMAGES_DIR="$IMAGES_DIR"
OS_IMAGES_DIR="$OS_IMAGES_DIR"
PXE_FILES_DIR="$PXE_FILES_DIR"
INTEGRATION_DIR="$INTEGRATION_DIR"
EOF
    
    # Set permissions
    chmod 644 "$BUILD_ENV/config.env"
    
    debug "Build environment created at: $BUILD_ENV"
}

# Execute build script with logging
execute_build_script() {
    local script_name="$1"
    local script_path="$SCRIPTS_DIR/$script_name"
    local log_file="$ARTIFACTS/logs/${script_name%.sh}.log"
    
    if [[ ! -f "$script_path" ]]; then
        error "Build script not found: $script_path"
    fi
    
    log "Executing: $script_name"
    debug "Script path: $script_path"
    debug "Log file: $log_file"
    
    # Source build configuration
    source "$BUILD_ENV/config.env"
    
    # Export environment variables for child scripts
    export ARTIFACTS
    export BUILD_ENV
    export IMAGES_DIR
    export OS_IMAGES_DIR
    export PXE_FILES_DIR
    export INTEGRATION_DIR
    export UBUNTU_RELEASE
    export TARGET_ARCH
    export DEBUG
    export VERBOSE
    
    # Execute script with logging
    if [[ "$VERBOSE" == "true" ]]; then
        bash "$script_path" 2>&1 | tee "$log_file"
    else
        bash "$script_path" > "$log_file" 2>&1
    fi
    
    # Check exit status
    local exit_code=${PIPESTATUS[0]}
    if [[ $exit_code -ne 0 ]]; then
        error "Build script failed: $script_name (exit code: $exit_code)"
    fi
    
    info "Completed: $script_name"
}

# Main build process
main_build() {
    log "Starting device initialization build process..."
    info "Build configuration:"
    info "  Ubuntu Release: $UBUNTU_RELEASE"
    info "  Target Architecture: $TARGET_ARCH"
    info "  EFI Size: $EFI_SIZE"
    info "  Root Size: $ROOT_SIZE"
    info "  Swap Size: $SWAP_SIZE"
    info "  OS1 Size: $OS1_SIZE"
    info "  OS2 Size: $OS2_SIZE"
    info "  Artifacts: $ARTIFACTS"
    
    # Execute build phases in order
    local build_scripts=(
        "01-bootstrap-environment.sh"
        "02-system-configuration.sh"
        "03-package-installation.sh"
        "04-grub-configuration.sh"
        "05-image-creation.sh"
        "06-testing-validation.sh"
        "07-generate-integration.sh"
    )
    
    local start_time=$(date +%s)
    
    for script in "${build_scripts[@]}"; do
        execute_build_script "$script"
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log "Build process completed successfully!"
    info "Total build time: $((duration / 60))m $((duration % 60))s"
    
    # Show build summary
    show_build_summary
}

# Show build summary
show_build_summary() {
    log "Build Summary:"
    echo
    echo -e "${GREEN}=== Artifacts Created ===${NC}"
    
    if [[ -d "$IMAGES_DIR" ]]; then
        echo "IMG Files:"
        find "$IMAGES_DIR" -name "*.img" -exec ls -lh {} \; | while read -r line; do
            echo "  $line"
        done
    fi
    
    if [[ -d "$OS_IMAGES_DIR" ]]; then
        echo
        echo "OS Archives:"
        find "$OS_IMAGES_DIR" -name "*.tar.gz" -exec ls -lh {} \; | while read -r line; do
            echo "  $line"
        done
    fi
    
    if [[ -d "$PXE_FILES_DIR" ]]; then
        echo
        echo "PXE Files:"
        find "$PXE_FILES_DIR" -type f -exec ls -lh {} \; | while read -r line; do
            echo "  $line"
        done
    fi
    
    echo
    echo -e "${GREEN}=== Integration Files ===${NC}"
    if [[ -d "$INTEGRATION_DIR" ]]; then
        find "$INTEGRATION_DIR" -type f | while read -r file; do
            echo "  $(basename "$file")"
        done
    fi
    
    echo
    echo -e "${GREEN}=== Next Steps ===${NC}"
    echo "1. Deploy to PXE server:"
    echo "   ./scripts/deploy-to-pxe-server.sh <pxe-server-ip>"
    echo
    echo "2. Or follow manual instructions:"
    echo "   cat $INTEGRATION_DIR/deployment-instructions.md"
    echo
    echo "3. Configure device for PXE boot and power on"
    echo
}

# Cleanup function
cleanup() {
    if [[ "${CLEANUP_ON_EXIT:-true}" == "true" ]]; then
        debug "Performing cleanup..."
        
        # Use comprehensive cleanup script if available
        local cleanup_script="$SCRIPTS_DIR/99-cleanup.sh"
        if [[ -f "$cleanup_script" ]]; then
            debug "Using comprehensive cleanup script for exit cleanup..."
            sudo "$cleanup_script" --mounts-only --loops-only 2>/dev/null || {
                warn "Comprehensive cleanup failed, falling back to basic cleanup"
                basic_exit_cleanup
            }
        else
            basic_exit_cleanup
        fi
    fi
}

# Basic exit cleanup function (fallback)
basic_exit_cleanup() {
    # Unmount any remaining mounts
    for mount_point in $(mount | grep "$ARTIFACTS" | awk '{print $3}' 2>/dev/null || true); do
        debug "Unmounting $mount_point"
        sudo umount "$mount_point" 2>/dev/null || true
    done
    
    # Clean up temporary files in artifacts/temp
    if [[ -d "$ARTIFACTS/temp" ]]; then
        rm -rf "$ARTIFACTS/temp"/* 2>/dev/null || true
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Main execution
main() {
    parse_args "$@"
    check_prerequisites
    clean_artifacts
    setup_build_environment
    main_build
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
