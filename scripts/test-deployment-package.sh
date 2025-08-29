#!/bin/bash
# shellcheck disable=SC2043,SC2043
# Test script for PXE deployment package verification

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR/../artifacts/server-deployment"

echo "=== PXE Deployment Package Test ==="
echo

# Check if deployment package exists
if [ ! -d "$DEPLOY_DIR" ]; then
    echo "❌ Deployment package not found at: $DEPLOY_DIR"
    echo "Run create-pxe-system.sh first to generate the deployment package."
    exit 1
fi

echo "✅ Deployment package found"

# Check main scripts
echo "Checking main deployment scripts..."
for script in "deploy-pxe-server.sh"; do
    if [ -x "$DEPLOY_DIR/$script" ]; then
        echo "  ✅ $script (executable)"
    else
        echo "  ❌ $script (missing or not executable)"
    fi
done

# Check configuration files
echo "Checking configuration files..."
for config in "config/server-config.env"; do
    if [ -f "$DEPLOY_DIR/$config" ]; then
        echo "  ✅ $config"
    else
        echo "  ❌ $config (missing)"
    fi
done

# Check service scripts
echo "Checking service scripts..."
for script in "install-services.sh" "setup-tftp.sh" "setup-http.sh" "configure-dhcp.sh"; do
    if [ -x "$DEPLOY_DIR/scripts/$script" ]; then
        echo "  ✅ scripts/$script (executable)"
    else
        echo "  ❌ scripts/$script (missing or not executable)"
    fi
done

# Check PXE files
echo "Checking PXE files..."
pxe_files=("vmlinuz" "initrd" "filesystem.squashfs" "pxelinux.cfg/default")
for file in "${pxe_files[@]}"; do
    if [ -f "$DEPLOY_DIR/pxe-files/$file" ]; then
        size=$(du -h "$DEPLOY_DIR/pxe-files/$file" | cut -f1)
        echo "  ✅ pxe-files/$file ($size)"
    else
        echo "  ❌ pxe-files/$file (missing)"
    fi
done

# Check OS images
echo "Checking OS images..."
os_images=("ubuntu-os.tar.gz" "debian-os.tar.gz")
for image in "${os_images[@]}"; do
    if [ -f "$DEPLOY_DIR/os-images/$image" ]; then
        size=$(du -h "$DEPLOY_DIR/os-images/$image" | cut -f1)
        echo "  ✅ os-images/$image ($size)"
    else
        echo "  ❌ os-images/$image (missing)"
    fi
done

echo
echo "=== Package Summary ==="
total_size=$(du -sh "$DEPLOY_DIR" | cut -f1)
echo "Total package size: $total_size"
echo "Package location: $DEPLOY_DIR"

# Show next steps
echo
echo "=== Next Steps ==="
echo "1. Copy the entire 'server-deployment' directory to your PXE server:"
echo "   scp -r $DEPLOY_DIR user@pxe-server:/tmp/"
echo
echo "2. On the PXE server, edit the configuration:"
echo "   nano /tmp/server-deployment/config/server-config.env"
echo
echo "3. Run the deployment script:"
echo "   cd /tmp/server-deployment && sudo ./deploy-pxe-server.sh"
echo
echo "=== Manual Verification Commands ==="
echo "# Check TFTP server:"
echo "tftp pxe-server-ip -c get pxelinux.0"
echo
echo "# Check HTTP server:"
echo "curl http://pxe-server-ip/pxe-files/"
echo "curl http://pxe-server-ip/images/"
echo
echo "# Check DHCP server:"
echo "sudo systemctl status isc-dhcp-server"
echo
echo "=== Test Complete ==="
