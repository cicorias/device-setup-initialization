#!/bin/bash

# DEPRECATED: Legacy PXE Server Deployment Package Creation
# This script is deprecated and provided for backward compatibility only.
# 
# For new installations, use:
# 1. Set up PXE server: https://github.com/cicorias/pxe-server-setup
# 2. Deploy images: ./scripts/deploy-to-pxe-server.sh
#
# This script creates a complete deployment package with DHCP, TFTP, and HTTP
# server configurations. It includes redundant functionality that is now
# better handled by the dedicated pxe-server-setup repository.

set -eo pipefail

warn() {
    echo -e "\033[1;33m[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1\033[0m"
}

error() {
    echo -e "\033[0;31m[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1\033[0m"
    exit 1
}

warn "This script is DEPRECATED"
warn "The legacy deployment package approach has been superseded by:"
warn "1. cicorias/pxe-server-setup - for PXE server infrastructure"
warn "2. ./scripts/deploy-to-pxe-server.sh - for deploying built images"
warn ""
warn "Continue only if you need the legacy deployment package"

read -p "Continue with deprecated functionality? (y/N): " -r
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted. Please use the recommended approach:"
    echo "  https://github.com/cicorias/pxe-server-setup"
    exit 0
fi

# Get the directory of this script and the artifacts directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ARTIFACTS="${PROJECT_ROOT}/artifacts"

if [[ ! -d "$ARTIFACTS" ]]; then
    error "Artifacts directory not found. Run ../create-pxe-system.sh first."
fi

# Source the original function (this would need to be extracted)
error "Legacy deployment package creation not implemented in archive."
error "If you need this functionality, use an older version of the script"
error "or set CREATE_LEGACY_PACKAGE=true when running create-pxe-system.sh"
