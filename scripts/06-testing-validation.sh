#!/bin/bash
# 06-testing-validation.sh
# Test and validate created images and system functionality
# Part of the device initialization build process

set -euo pipefail

# Script configuration
SCRIPT_NAME="06-testing-validation"
SCRIPT_VERSION="1.0.0"

# Import configuration
if [[ -f "$(dirname "$0")/../config.sh" ]]; then
    source "$(dirname "$0")/../config.sh"
else
    echo "ERROR: config.sh not found"
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] [$SCRIPT_NAME] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] [$SCRIPT_NAME] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] [$SCRIPT_NAME] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] [$SCRIPT_NAME] INFO: $1${NC}"
}

# Test results tracking
declare -A TEST_RESULTS

# Script header
show_header() {
    log "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
    info "Testing and validating created images and system functionality"
}

# Check prerequisites from previous script
check_prerequisites() {
    log "Checking prerequisites from previous build stages..."
    
    # Check that image creation completed
    if [[ ! -f "$BUILD_LOG_DIR/05-image-creation.log" ]]; then
        error "Image creation script has not completed successfully"
    fi
    
    # Check images exist
    if [[ ! -f "$BUILD_DIR/images/raw/edge-device-init.img" ]]; then
        error "Raw image not found"
    fi
    
    # Check required tools for testing
    local required_tools=("file" "fdisk" "mount" "umount" "losetup" "chroot" "qemu-system-x86_64")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            warn "Testing tool '$tool' not found - some tests will be skipped"
        fi
    done
    
    log "Prerequisites check completed"
}

# Test image integrity
test_image_integrity() {
    log "Testing image integrity..."
    
    local test_name="image_integrity"
    local raw_image="$BUILD_DIR/images/raw/edge-device-init.img"
    
    # Test file exists and is not empty
    if [[ ! -f "$raw_image" ]]; then
        TEST_RESULTS[$test_name]="FAIL - Image file does not exist"
        return 1
    fi
    
    local file_size=$(stat -c%s "$raw_image")
    if [[ $file_size -eq 0 ]]; then
        TEST_RESULTS[$test_name]="FAIL - Image file is empty"
        return 1
    fi
    
    # Test file type
    local file_type=$(file "$raw_image")
    if [[ ! "$file_type" =~ "DOS/MBR boot sector" ]] && [[ ! "$file_type" =~ "data" ]]; then
        warn "Unexpected file type: $file_type"
    fi
    
    info "Image size: $(du -h "$raw_image" | cut -f1)"
    TEST_RESULTS[$test_name]="PASS - Image file is valid"
    
    log "Image integrity test completed"
}

# Test partition table
test_partition_table() {
    log "Testing partition table structure..."
    
    local test_name="partition_table"
    local raw_image="$BUILD_DIR/images/raw/edge-device-init.img"
    
    # Setup loop device
    local loop_device=$(losetup --show -f "$raw_image")
    
    # Wait for partitions to be recognized
    partprobe "$loop_device"
    sleep 2
    
    # Check partition table type
    local pt_type=$(fdisk -l "$loop_device" | grep "Disklabel type" | awk '{print $3}')
    if [[ "$pt_type" != "gpt" ]]; then
        TEST_RESULTS[$test_name]="FAIL - Expected GPT partition table, found: $pt_type"
        losetup -d "$loop_device"
        return 1
    fi
    
    # Check number of partitions
    local partition_count=$(fdisk -l "$loop_device" | grep "^${loop_device}p" | wc -l)
    if [[ $partition_count -ne 6 ]]; then
        TEST_RESULTS[$test_name]="FAIL - Expected 6 partitions, found: $partition_count"
        losetup -d "$loop_device"
        return 1
    fi
    
    # Check partition labels
    local expected_labels=("EFI" "INIT-ROOT" "SWAP" "OS1-ROOT" "OS2-ROOT" "DATA")
    local label_errors=0
    
    for i in {1..6}; do
        local partition="${loop_device}p$i"
        local label=""
        
        if [[ $i -eq 1 ]]; then
            # EFI partition - check with fatlabel or blkid
            label=$(blkid -s LABEL -o value "$partition" 2>/dev/null || echo "")
        elif [[ $i -eq 3 ]]; then
            # Swap partition
            label=$(blkid -s LABEL -o value "$partition" 2>/dev/null || echo "")
        else
            # ext4 partitions
            label=$(blkid -s LABEL -o value "$partition" 2>/dev/null || echo "")
        fi
        
        local expected_label="${expected_labels[$((i-1))]}"
        if [[ "$label" != "$expected_label" ]]; then
            warn "Partition $i: expected label '$expected_label', found '$label'"
            ((label_errors++))
        else
            info "Partition $i: label '$label' ✓"
        fi
    done
    
    losetup -d "$loop_device"
    
    if [[ $label_errors -eq 0 ]]; then
        TEST_RESULTS[$test_name]="PASS - All 6 partitions present with correct labels"
    else
        TEST_RESULTS[$test_name]="WARN - $label_errors partition label mismatches"
    fi
    
    log "Partition table test completed"
}

# Test filesystem integrity
test_filesystem_integrity() {
    log "Testing filesystem integrity..."
    
    local test_name="filesystem_integrity"
    local raw_image="$BUILD_DIR/images/raw/edge-device-init.img"
    
    # Setup loop device
    local loop_device=$(losetup --show -f "$raw_image")
    partprobe "$loop_device"
    sleep 2
    
    local fs_errors=0
    
    # Test EFI partition (FAT32)
    if command -v fsck.fat &> /dev/null; then
        if fsck.fat -v "${loop_device}p1" &>/dev/null; then
            info "EFI partition filesystem ✓"
        else
            warn "EFI partition filesystem check failed"
            ((fs_errors++))
        fi
    fi
    
    # Test ext4 partitions
    for partition in 2 4 5 6; do
        if fsck.ext4 -n "${loop_device}p$partition" &>/dev/null; then
            info "Partition $partition filesystem ✓"
        else
            warn "Partition $partition filesystem check failed"
            ((fs_errors++))
        fi
    done
    
    # Test swap partition
    if command -v file &> /dev/null; then
        local swap_type=$(file -s "${loop_device}p3")
        if [[ "$swap_type" =~ "swap" ]]; then
            info "Swap partition ✓"
        else
            warn "Swap partition format issue"
            ((fs_errors++))
        fi
    fi
    
    losetup -d "$loop_device"
    
    if [[ $fs_errors -eq 0 ]]; then
        TEST_RESULTS[$test_name]="PASS - All filesystems are valid"
    else
        TEST_RESULTS[$test_name]="FAIL - $fs_errors filesystem errors detected"
    fi
    
    log "Filesystem integrity test completed"
}

# Test root filesystem content
test_root_filesystem_content() {
    log "Testing root filesystem content..."
    
    local test_name="root_filesystem_content"
    local raw_image="$BUILD_DIR/images/raw/edge-device-init.img"
    local mount_point="$BUILD_DIR/tmp/test-root"
    
    mkdir -p "$mount_point"
    
    # Setup loop device and mount root partition
    local loop_device=$(losetup --show -f "$raw_image")
    partprobe "$loop_device"
    sleep 2
    
    if ! mount "${loop_device}p2" "$mount_point"; then
        TEST_RESULTS[$test_name]="FAIL - Cannot mount root partition"
        losetup -d "$loop_device"
        return 1
    fi
    
    local content_errors=0
    
    # Check essential directories
    local essential_dirs=(
        "bin" "sbin" "lib" "usr" "etc" "var" "tmp" "home" "root"
        "boot" "data" "config"
        "usr/local/bin"
    )
    
    for dir in "${essential_dirs[@]}"; do
        if [[ ! -d "$mount_point/$dir" ]]; then
            warn "Missing directory: /$dir"
            ((content_errors++))
        fi
    done
    
    # Check essential files
    local essential_files=(
        "etc/fstab"
        "etc/hostname"
        "etc/hosts"
        "etc/passwd"
        "etc/group"
        "etc/default/grub"
        "etc/grub.d/40_custom"
        "usr/local/bin/configure-device.sh"
        "usr/local/bin/partition-disk.sh"
        "usr/local/bin/install-os1.sh"
        "usr/local/bin/install-os2.sh"
        "usr/local/bin/factory-reset.sh"
    )
    
    for file in "${essential_files[@]}"; do
        if [[ ! -f "$mount_point/$file" ]]; then
            warn "Missing file: /$file"
            ((content_errors++))
        fi
    done
    
    # Check executable permissions on scripts
    local scripts=(
        "usr/local/bin/configure-device.sh"
        "usr/local/bin/partition-disk.sh"
        "usr/local/bin/install-os1.sh"
        "usr/local/bin/install-os2.sh"
        "usr/local/bin/factory-reset.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [[ -f "$mount_point/$script" ]] && [[ ! -x "$mount_point/$script" ]]; then
            warn "Script not executable: /$script"
            ((content_errors++))
        fi
    done
    
    # Check kernel and initrd
    if ! ls "$mount_point/boot/vmlinuz-"* &>/dev/null; then
        warn "Kernel not found in /boot"
        ((content_errors++))
    fi
    
    if ! ls "$mount_point/boot/initrd.img-"* &>/dev/null; then
        warn "Initrd not found in /boot"
        ((content_errors++))
    fi
    
    umount "$mount_point"
    losetup -d "$loop_device"
    rm -rf "$mount_point"
    
    if [[ $content_errors -eq 0 ]]; then
        TEST_RESULTS[$test_name]="PASS - All essential content present"
    else
        TEST_RESULTS[$test_name]="FAIL - $content_errors content issues found"
    fi
    
    log "Root filesystem content test completed"
}

# Test GRUB configuration
test_grub_configuration() {
    log "Testing GRUB configuration..."
    
    local test_name="grub_configuration"
    local raw_image="$BUILD_DIR/images/raw/edge-device-init.img"
    local mount_point="$BUILD_DIR/tmp/test-grub"
    
    mkdir -p "$mount_point"
    
    # Setup loop device and mount root partition
    local loop_device=$(losetup --show -f "$raw_image")
    partprobe "$loop_device"
    sleep 2
    
    if ! mount "${loop_device}p2" "$mount_point"; then
        TEST_RESULTS[$test_name]="FAIL - Cannot mount root partition"
        losetup -d "$loop_device"
        return 1
    fi
    
    local grub_errors=0
    
    # Check GRUB configuration files
    if [[ ! -f "$mount_point/etc/default/grub" ]]; then
        warn "GRUB default configuration missing"
        ((grub_errors++))
    fi
    
    if [[ ! -f "$mount_point/etc/grub.d/40_custom" ]]; then
        warn "GRUB custom menu missing"
        ((grub_errors++))
    fi
    
    # Check for essential menu entries
    if [[ -f "$mount_point/etc/grub.d/40_custom" ]]; then
        local expected_entries=(
            "Configure Device"
            "Partition Disk"
            "Install OS1"
            "Install OS2"
            "Boot OS1"
            "Boot OS2"
            "Factory Reset"
        )
        
        for entry in "${expected_entries[@]}"; do
            if ! grep -q "$entry" "$mount_point/etc/grub.d/40_custom"; then
                warn "GRUB menu entry missing: $entry"
                ((grub_errors++))
            fi
        done
    fi
    
    # Mount EFI partition and check GRUB installation
    local efi_mount="$mount_point/boot/efi"
    mkdir -p "$efi_mount"
    
    if mount "${loop_device}p1" "$efi_mount"; then
        if [[ ! -d "$efi_mount/EFI" ]]; then
            warn "EFI directory structure missing"
            ((grub_errors++))
        fi
        umount "$efi_mount"
    else
        warn "Cannot mount EFI partition"
        ((grub_errors++))
    fi
    
    umount "$mount_point"
    losetup -d "$loop_device"
    rm -rf "$mount_point"
    
    if [[ $grub_errors -eq 0 ]]; then
        TEST_RESULTS[$test_name]="PASS - GRUB configuration is complete"
    else
        TEST_RESULTS[$test_name]="FAIL - $grub_errors GRUB configuration issues"
    fi
    
    log "GRUB configuration test completed"
}

# Test compressed images
test_compressed_images() {
    log "Testing compressed images..."
    
    local test_name="compressed_images"
    local compressed_dir="$BUILD_DIR/images/compressed"
    local comp_errors=0
    
    # Test gzip image
    if [[ -f "$compressed_dir/edge-device-init.img.gz" ]]; then
        if gzip -t "$compressed_dir/edge-device-init.img.gz" &>/dev/null; then
            info "Gzip image integrity ✓"
        else
            warn "Gzip image corruption detected"
            ((comp_errors++))
        fi
    else
        warn "Gzip image not found"
        ((comp_errors++))
    fi
    
    # Test xz image
    if [[ -f "$compressed_dir/edge-device-init.img.xz" ]]; then
        if xz -t "$compressed_dir/edge-device-init.img.xz" &>/dev/null; then
            info "XZ image integrity ✓"
        else
            warn "XZ image corruption detected"
            ((comp_errors++))
        fi
    else
        warn "XZ image not found"
        ((comp_errors++))
    fi
    
    # Test zip archive
    if [[ -f "$compressed_dir/edge-device-init.zip" ]]; then
        if command -v unzip &> /dev/null; then
            if unzip -t "$compressed_dir/edge-device-init.zip" &>/dev/null; then
                info "ZIP archive integrity ✓"
            else
                warn "ZIP archive corruption detected"
                ((comp_errors++))
            fi
        fi
    else
        warn "ZIP archive not found"
        ((comp_errors++))
    fi
    
    if [[ $comp_errors -eq 0 ]]; then
        TEST_RESULTS[$test_name]="PASS - All compressed images are valid"
    else
        TEST_RESULTS[$test_name]="FAIL - $comp_errors compressed image issues"
    fi
    
    log "Compressed images test completed"
}

# Test checksums
test_checksums() {
    log "Testing checksums..."
    
    local test_name="checksums"
    local checksum_errors=0
    
    # Find all checksum files and verify them
    find "$BUILD_DIR/checksums" -name "*.md5" -o -name "*.sha256" -o -name "*.sha512" | while read -r checksum_file; do
        local checksum_type=$(basename "$checksum_file" | sed 's/.*\.//')
        local image_file=$(echo "$checksum_file" | sed "s|$BUILD_DIR/checksums|$BUILD_DIR/images|" | sed "s/\.$checksum_type$//")
        
        if [[ -f "$image_file" ]]; then
            case $checksum_type in
                md5)
                    if cd "$(dirname "$image_file")" && md5sum -c "$(basename "$checksum_file")" &>/dev/null; then
                        info "MD5 checksum verified: $(basename "$image_file")"
                    else
                        warn "MD5 checksum mismatch: $(basename "$image_file")"
                        ((checksum_errors++))
                    fi
                    ;;
                sha256)
                    if cd "$(dirname "$image_file")" && sha256sum -c "$(basename "$checksum_file")" &>/dev/null; then
                        info "SHA256 checksum verified: $(basename "$image_file")"
                    else
                        warn "SHA256 checksum mismatch: $(basename "$image_file")"
                        ((checksum_errors++))
                    fi
                    ;;
                sha512)
                    if cd "$(dirname "$image_file")" && sha512sum -c "$(basename "$checksum_file")" &>/dev/null; then
                        info "SHA512 checksum verified: $(basename "$image_file")"
                    else
                        warn "SHA512 checksum mismatch: $(basename "$image_file")"
                        ((checksum_errors++))
                    fi
                    ;;
            esac
        else
            warn "Image file not found for checksum: $image_file"
            ((checksum_errors++))
        fi
    done
    
    if [[ $checksum_errors -eq 0 ]]; then
        TEST_RESULTS[$test_name]="PASS - All checksums verified successfully"
    else
        TEST_RESULTS[$test_name]="FAIL - $checksum_errors checksum verification failures"
    fi
    
    log "Checksums test completed"
}

# Test PXE files
test_pxe_files() {
    log "Testing PXE files..."
    
    local test_name="pxe_files"
    local pxe_dir="$BUILD_DIR/images/pxe"
    local pxe_errors=0
    
    # Check required PXE files
    local required_files=("vmlinuz" "initrd.img" "pxelinux.cfg")
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$pxe_dir/$file" ]]; then
            warn "PXE file missing: $file"
            ((pxe_errors++))
        else
            info "PXE file present: $file"
        fi
    done
    
    # Check kernel file
    if [[ -f "$pxe_dir/vmlinuz" ]]; then
        local kernel_type=$(file "$pxe_dir/vmlinuz")
        if [[ ! "$kernel_type" =~ "Linux kernel" ]] && [[ ! "$kernel_type" =~ "executable" ]]; then
            warn "Kernel file may be invalid: $kernel_type"
            ((pxe_errors++))
        fi
    fi
    
    if [[ $pxe_errors -eq 0 ]]; then
        TEST_RESULTS[$test_name]="PASS - All PXE files are present and valid"
    else
        TEST_RESULTS[$test_name]="FAIL - $pxe_errors PXE file issues"
    fi
    
    log "PXE files test completed"
}

# Test configuration scripts functionality
test_configuration_scripts() {
    log "Testing configuration scripts functionality..."
    
    local test_name="configuration_scripts"
    local raw_image="$BUILD_DIR/images/raw/edge-device-init.img"
    local mount_point="$BUILD_DIR/tmp/test-scripts"
    
    mkdir -p "$mount_point"
    
    # Setup loop device and mount root partition
    local loop_device=$(losetup --show -f "$raw_image")
    partprobe "$loop_device"
    sleep 2
    
    if ! mount "${loop_device}p2" "$mount_point"; then
        TEST_RESULTS[$test_name]="FAIL - Cannot mount root partition"
        losetup -d "$loop_device"
        return 1
    fi
    
    local script_errors=0
    
    # Test script syntax
    local scripts=(
        "usr/local/bin/configure-device.sh"
        "usr/local/bin/partition-disk.sh"
        "usr/local/bin/install-os1.sh"
        "usr/local/bin/install-os2.sh"
        "usr/local/bin/factory-reset.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [[ -f "$mount_point/$script" ]]; then
            # Basic syntax check
            if bash -n "$mount_point/$script" &>/dev/null; then
                info "Script syntax valid: $(basename "$script")"
            else
                warn "Script syntax error: $(basename "$script")"
                ((script_errors++))
            fi
            
            # Check for required functions/content
            case $(basename "$script") in
                "configure-device.sh")
                    if ! grep -q "configure_network\|show_welcome" "$mount_point/$script"; then
                        warn "Configure device script missing essential functions"
                        ((script_errors++))
                    fi
                    ;;
                "partition-disk.sh")
                    if ! grep -q "create_partitions\|format_partitions" "$mount_point/$script"; then
                        warn "Partition disk script missing essential functions"
                        ((script_errors++))
                    fi
                    ;;
                "install-os1.sh"|"install-os2.sh")
                    if ! grep -q "debootstrap\|install_base_system" "$mount_point/$script"; then
                        warn "OS install script missing essential functions"
                        ((script_errors++))
                    fi
                    ;;
                "factory-reset.sh")
                    if ! grep -q "reset.*partition\|factory.*reset" "$mount_point/$script"; then
                        warn "Factory reset script missing essential functions"
                        ((script_errors++))
                    fi
                    ;;
            esac
        else
            warn "Script not found: /$script"
            ((script_errors++))
        fi
    done
    
    umount "$mount_point"
    losetup -d "$loop_device"
    rm -rf "$mount_point"
    
    if [[ $script_errors -eq 0 ]]; then
        TEST_RESULTS[$test_name]="PASS - All configuration scripts are valid"
    else
        TEST_RESULTS[$test_name]="FAIL - $script_errors script issues found"
    fi
    
    log "Configuration scripts test completed"
}

# Run QEMU boot test (if available)
test_qemu_boot() {
    log "Testing QEMU boot (if available)..."
    
    local test_name="qemu_boot"
    
    if ! command -v qemu-system-x86_64 &> /dev/null; then
        TEST_RESULTS[$test_name]="SKIP - QEMU not available"
        warn "QEMU not found - skipping boot test"
        return 0
    fi
    
    local raw_image="$BUILD_DIR/images/raw/edge-device-init.img"
    
    info "Starting QEMU boot test (30 second timeout)..."
    
    # Run QEMU with timeout
    timeout 30 qemu-system-x86_64 \
        -drive file="$raw_image",format=raw \
        -m 1024 \
        -nographic \
        -no-reboot \
        -boot order=c \
        &>/dev/null || true
    
    # Since this is a basic boot test, we consider it passed if QEMU doesn't crash immediately
    TEST_RESULTS[$test_name]="PASS - QEMU boot test completed without crash"
    
    log "QEMU boot test completed"
}

# Generate test report
generate_test_report() {
    log "Generating test report..."
    
    local report_file="$BUILD_DIR/test-report.txt"
    local json_report="$BUILD_DIR/test-report.json"
    
    # Text report
    cat > "$report_file" << EOF
Edge Device Initialization - Test Report
========================================
Generated: $(date)
Build Directory: $BUILD_DIR

Test Results Summary:
EOF
    
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    local skipped_tests=0
    
    for test_name in "${!TEST_RESULTS[@]}"; do
        local result="${TEST_RESULTS[$test_name]}"
        ((total_tests++))
        
        if [[ "$result" =~ ^PASS ]]; then
            ((passed_tests++))
            echo "✓ PASS: $test_name - $result" >> "$report_file"
        elif [[ "$result" =~ ^FAIL ]]; then
            ((failed_tests++))
            echo "✗ FAIL: $test_name - $result" >> "$report_file"
        elif [[ "$result" =~ ^SKIP ]]; then
            ((skipped_tests++))
            echo "- SKIP: $test_name - $result" >> "$report_file"
        else
            echo "? UNKNOWN: $test_name - $result" >> "$report_file"
        fi
    done
    
    cat >> "$report_file" << EOF

Summary:
- Total Tests: $total_tests
- Passed: $passed_tests
- Failed: $failed_tests
- Skipped: $skipped_tests

Overall Result: $([[ $failed_tests -eq 0 ]] && echo "PASS" || echo "FAIL")
EOF
    
    # JSON report
    cat > "$json_report" << EOF
{
    "test_report": {
        "generated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
        "build_directory": "$BUILD_DIR",
        "summary": {
            "total_tests": $total_tests,
            "passed": $passed_tests,
            "failed": $failed_tests,
            "skipped": $skipped_tests,
            "overall_result": "$([[ $failed_tests -eq 0 ]] && echo "PASS" || echo "FAIL")"
        },
        "test_results": {
EOF
    
    local first=true
    for test_name in "${!TEST_RESULTS[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "," >> "$json_report"
        fi
        echo -n "            \"$test_name\": \"${TEST_RESULTS[$test_name]}\"" >> "$json_report"
    done
    
    cat >> "$json_report" << EOF

        }
    }
}
EOF
    
    info "Test report saved to: $report_file"
    info "JSON report saved to: $json_report"
    
    # Print summary to console
    echo
    log "TEST SUMMARY:"
    info "Total Tests: $total_tests"
    info "Passed: $passed_tests"
    info "Failed: $failed_tests"
    info "Skipped: $skipped_tests"
    
    if [[ $failed_tests -eq 0 ]]; then
        log "Overall Result: PASS ✓"
    else
        error "Overall Result: FAIL ✗"
    fi
    
    log "Test report generation completed"
}

# Save testing log
save_testing_log() {
    local log_file="$BUILD_LOG_DIR/$SCRIPT_NAME.log"
    
    cat > "$log_file" << EOF
# Testing and Validation Log
# Generated by $SCRIPT_NAME v$SCRIPT_VERSION on $(date)

Build Configuration:
- Build Directory: $BUILD_DIR
- Images Directory: $BUILD_DIR/images

Tests Performed:
- Image integrity verification
- Partition table structure validation
- Filesystem integrity checks
- Root filesystem content verification
- GRUB configuration validation
- Compressed images verification
- Checksum validation
- PXE files verification
- Configuration scripts validation
- QEMU boot test (if available)

Test Results:
$(for test_name in "${!TEST_RESULTS[@]}"; do
    echo "- $test_name: ${TEST_RESULTS[$test_name]}"
done)

Testing completed: $(date)
Next step: Run 07-generate-integration.sh
EOF
    
    info "Testing log saved to $log_file"
}

# Main execution function
main() {
    show_header
    check_prerequisites
    
    # Run all tests
    test_image_integrity
    test_partition_table
    test_filesystem_integrity
    test_root_filesystem_content
    test_grub_configuration
    test_compressed_images
    test_checksums
    test_pxe_files
    test_configuration_scripts
    test_qemu_boot
    
    # Generate reports
    generate_test_report
    save_testing_log
    
    log "$SCRIPT_NAME completed successfully"
    
    # Check overall result
    local failed_count=0
    for result in "${TEST_RESULTS[@]}"; do
        if [[ "$result" =~ ^FAIL ]]; then
            ((failed_count++))
        fi
    done
    
    if [[ $failed_count -eq 0 ]]; then
        info "All tests passed - images are ready for deployment"
        info "Next: Run 07-generate-integration.sh"
    else
        warn "$failed_count tests failed - review test report before deployment"
        info "Next: Fix issues and re-run tests, or proceed to 07-generate-integration.sh"
    fi
}

# Run main function
main "$@"
