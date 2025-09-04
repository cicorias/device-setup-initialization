#!/bin/bash
# config.sh
# Configuration file for device initialization build system

# Project paths (use environment variables if set by build-device-images.sh)
if [[ -n "${ARTIFACTS:-}" ]]; then
    # Variables already set by build-device-images.sh, use them
    BUILD_DIR="${BUILD_DIR:-$ARTIFACTS/build-env}"
    BUILD_LOG_DIR="${BUILD_LOG_DIR:-$ARTIFACTS/logs}"
    IMAGES_DIR="${IMAGES_DIR:-$ARTIFACTS/images}"
    OS_IMAGES_DIR="${OS_IMAGES_DIR:-$ARTIFACTS/os-images}"
    PXE_FILES_DIR="${PXE_FILES_DIR:-$ARTIFACTS/pxe-files}"
    INTEGRATION_DIR="${INTEGRATION_DIR:-$ARTIFACTS/pxe-integration}"
else
    # Fallback for standalone script execution
    SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
    PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}"
    ARTIFACTS="${ARTIFACTS:-$PROJECT_ROOT/artifacts}"
    BUILD_DIR="${BUILD_DIR:-$ARTIFACTS/build-env}"
    BUILD_LOG_DIR="${BUILD_LOG_DIR:-$ARTIFACTS/logs}"
    IMAGES_DIR="${IMAGES_DIR:-$ARTIFACTS/images}"
    OS_IMAGES_DIR="${OS_IMAGES_DIR:-$ARTIFACTS/os-images}"
    PXE_FILES_DIR="${PXE_FILES_DIR:-$ARTIFACTS/pxe-files}"
    INTEGRATION_DIR="${INTEGRATION_DIR:-$ARTIFACTS/pxe-integration}"
fi

# Ubuntu configuration
ubuntu_release="${UBUNTU_RELEASE:-noble}"  # Ubuntu 24.04.3 LTS
ubuntu_mirror="${UBUNTU_MIRROR:-http://archive.ubuntu.com/ubuntu}"
TARGET_ARCH="${TARGET_ARCH:-amd64}"

# Partition sizes
EFI_SIZE="${EFI_SIZE:-200M}"
ROOT_SIZE="${ROOT_SIZE:-2G}"
SWAP_SIZE="${SWAP_SIZE:-2G}"
OS1_SIZE="${OS1_SIZE:-2.7G}"
OS2_SIZE="${OS2_SIZE:-2.7G}"

# Build options
PARALLEL_BUILDS="${PARALLEL_BUILDS:-true}"
DEBUG="${DEBUG:-false}"
VERBOSE="${VERBOSE:-false}"

# Device configuration
DEVICE_HOSTNAME="${DEVICE_HOSTNAME:-edge-device}"
DEFAULT_USER="${DEFAULT_USER:-ubuntu}"
SSH_ENABLE="${SSH_ENABLE:-true}"

# Network configuration
NETWORK_CONFIG="${NETWORK_CONFIG:-dhcp}"  # dhcp or static
STATIC_IP="${STATIC_IP:-}"
STATIC_NETMASK="${STATIC_NETMASK:-}"
STATIC_GATEWAY="${STATIC_GATEWAY:-}"
STATIC_DNS="${STATIC_DNS:-8.8.8.8}"

# Logging
LOG_LEVEL="${LOG_LEVEL:-INFO}"  # DEBUG, INFO, WARN, ERROR
