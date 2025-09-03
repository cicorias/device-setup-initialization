#!/bin/bash
# configure-device.sh
# Interactive device configuration script
# Avoids cloud-init and autoinstall as per requirements

set -euo pipefail

# Configuration files
CONFIG_DIR="/data/config"
DEVICE_CONFIG="$CONFIG_DIR/device.conf"
NETWORK_CONFIG="$CONFIG_DIR/network.conf"
SYSTEM_CONFIG="$CONFIG_DIR/system.conf"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Initialize configuration directory
init_config_dir() {
    log "Initializing configuration directory..."
    
    # Mount data partition if not already mounted
    if ! mountpoint -q /data 2>/dev/null; then
        mkdir -p /data
        mount LABEL=DATA /data || error "Failed to mount data partition"
    fi
    
    # Create configuration directory
    mkdir -p "$CONFIG_DIR"
    
    # Create default configuration if it doesn't exist
    if [[ ! -f "$DEVICE_CONFIG" ]]; then
        cat > "$DEVICE_CONFIG" << 'EOF'
# Device Configuration
# Edit values as needed

[network]
hostname=edge-device
interface=eth0
dhcp=true
ip_address=
netmask=
gateway=
dns_servers=8.8.8.8,8.8.4.4

[system]
timezone=UTC
default_os=os1
boot_timeout=5

[security]
ssh_enabled=true
root_password_set=false

[monitoring]
logs_enabled=true
log_rotation=weekly
EOF
    fi
}

# Display welcome message
show_welcome() {
    clear
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║                  Edge Device Configuration                   ║
║                                                              ║
║  This script will help you configure your edge device for   ║
║  first-time use. You can run this script again later to     ║
║  update settings.                                            ║
║                                                              ║
║  Current Status:                                             ║
EOF
    
    echo "║  - Hostname: $(hostname)"
    echo "║  - IP Address: $(hostname -I | awk '{print $1}' || echo 'Not configured')"
    echo "║  - Interface: $(ip route | grep default | awk '{print $5}' || echo 'Not found')"
    
    cat << 'EOF'
║                                                              ║
╚══════════════════════════════════════════════════════════════╝

EOF
}

# Configure network settings
configure_network() {
    log "Configuring network settings..."
    
    echo
    echo "=== Network Configuration ==="
    
    # Get current hostname
    local current_hostname=$(hostname)
    echo -n "Enter hostname (current: $current_hostname): "
    read hostname_input
    local new_hostname="${hostname_input:-$current_hostname}"
    
    # Configure network interface
    echo
    echo "Network Interface Configuration:"
    echo "1) DHCP (automatic)"
    echo "2) Static IP"
    echo -n "Choose option (1-2): "
    read net_choice
    
    case $net_choice in
        1)
            configure_dhcp "$new_hostname"
            ;;
        2)
            configure_static "$new_hostname"
            ;;
        *)
            warn "Invalid choice, using DHCP"
            configure_dhcp "$new_hostname"
            ;;
    esac
}

# Configure DHCP network
configure_dhcp() {
    local hostname="$1"
    
    log "Configuring DHCP network..."
    
    # Set hostname
    echo "$hostname" > /etc/hostname
    hostnamectl set-hostname "$hostname"
    
    # Configure netplan for DHCP
    cat > /etc/netplan/01-netcfg.yaml << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: true
      dhcp6: true
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOF
    
    # Save to device config
    sed -i "s/hostname=.*/hostname=$hostname/" "$DEVICE_CONFIG"
    sed -i "s/dhcp=.*/dhcp=true/" "$DEVICE_CONFIG"
    
    info "DHCP configuration saved"
}

# Configure static IP
configure_static() {
    local hostname="$1"
    
    log "Configuring static IP network..."
    
    echo -n "Enter IP address: "
    read ip_address
    echo -n "Enter netmask (e.g., 255.255.255.0): "
    read netmask
    echo -n "Enter gateway: "
    read gateway
    echo -n "Enter DNS servers (comma separated, default: 8.8.8.8,8.8.4.4): "
    read dns_input
    local dns_servers="${dns_input:-8.8.8.8,8.8.4.4}"
    
    # Convert comma-separated DNS to array format
    local dns_array=""
    IFS=',' read -ra DNS_ARRAY <<< "$dns_servers"
    for dns in "${DNS_ARRAY[@]}"; do
        dns_array="$dns_array        - $dns\n"
    done
    
    # Set hostname
    echo "$hostname" > /etc/hostname
    hostnamectl set-hostname "$hostname"
    
    # Configure netplan for static IP
    cat > /etc/netplan/01-netcfg.yaml << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: false
      dhcp6: false
      addresses:
        - $ip_address/$(netmask_to_cidr "$netmask")
      gateway4: $gateway
      nameservers:
        addresses:
$(echo -e "$dns_array")
EOF
    
    # Save to device config
    sed -i "s/hostname=.*/hostname=$hostname/" "$DEVICE_CONFIG"
    sed -i "s/dhcp=.*/dhcp=false/" "$DEVICE_CONFIG"
    sed -i "s/ip_address=.*/ip_address=$ip_address/" "$DEVICE_CONFIG"
    sed -i "s/netmask=.*/netmask=$netmask/" "$DEVICE_CONFIG"
    sed -i "s/gateway=.*/gateway=$gateway/" "$DEVICE_CONFIG"
    sed -i "s/dns_servers=.*/dns_servers=$dns_servers/" "$DEVICE_CONFIG"
    
    info "Static IP configuration saved"
}

# Convert netmask to CIDR notation
netmask_to_cidr() {
    local netmask="$1"
    local cidr=0
    
    IFS='.' read -ra ADDR <<< "$netmask"
    for octet in "${ADDR[@]}"; do
        case $octet in
            255) cidr=$((cidr + 8)) ;;
            254) cidr=$((cidr + 7)) ;;
            252) cidr=$((cidr + 6)) ;;
            248) cidr=$((cidr + 5)) ;;
            240) cidr=$((cidr + 4)) ;;
            224) cidr=$((cidr + 3)) ;;
            192) cidr=$((cidr + 2)) ;;
            128) cidr=$((cidr + 1)) ;;
            0) ;;
            *) echo "24"; return ;;
        esac
    done
    
    echo "$cidr"
}

# Configure system settings
configure_system() {
    log "Configuring system settings..."
    
    echo
    echo "=== System Configuration ==="
    
    # Configure timezone
    echo "Available timezones (examples):"
    echo "  UTC, America/New_York, America/Los_Angeles, Europe/London"
    echo -n "Enter timezone (default: UTC): "
    read timezone_input
    local timezone="${timezone_input:-UTC}"
    
    # Set timezone
    timedatectl set-timezone "$timezone" || warn "Failed to set timezone"
    sed -i "s/timezone=.*/timezone=$timezone/" "$DEVICE_CONFIG"
    
    # Configure default OS
    echo
    echo "Default OS Selection:"
    echo "1) OS1 (Primary Ubuntu)"
    echo "2) OS2 (Secondary Ubuntu)"
    echo -n "Choose default OS (1-2, default: 1): "
    read os_choice
    
    local default_os="os1"
    case $os_choice in
        2) default_os="os2" ;;
        *) default_os="os1" ;;
    esac
    
    sed -i "s/default_os=.*/default_os=$default_os/" "$DEVICE_CONFIG"
    
    # Configure boot timeout
    echo -n "Enter boot timeout in seconds (default: 5): "
    read timeout_input
    local boot_timeout="${timeout_input:-5}"
    
    sed -i "s/boot_timeout=.*/boot_timeout=$boot_timeout/" "$DEVICE_CONFIG"
    
    info "System configuration saved"
}

# Configure security settings
configure_security() {
    log "Configuring security settings..."
    
    echo
    echo "=== Security Configuration ==="
    
    # SSH configuration
    echo "SSH Service Configuration:"
    echo "1) Enable SSH"
    echo "2) Disable SSH"
    echo -n "Choose option (1-2, default: 1): "
    read ssh_choice
    
    case $ssh_choice in
        2)
            systemctl disable ssh
            systemctl stop ssh
            sed -i "s/ssh_enabled=.*/ssh_enabled=false/" "$DEVICE_CONFIG"
            info "SSH disabled"
            ;;
        *)
            systemctl enable ssh
            systemctl start ssh
            sed -i "s/ssh_enabled=.*/ssh_enabled=true/" "$DEVICE_CONFIG"
            info "SSH enabled"
            ;;
    esac
    
    # Root password configuration
    echo
    echo "Root Password Configuration:"
    echo "Would you like to set a root password? (y/N): "
    read set_root_password
    
    if [[ "$set_root_password" =~ ^[Yy]$ ]]; then
        passwd root
        sed -i "s/root_password_set=.*/root_password_set=true/" "$DEVICE_CONFIG"
        info "Root password set"
    else
        info "Root password not changed"
    fi
    
    # SSH keys configuration
    echo
    echo "SSH Keys Configuration:"
    echo "Would you like to add SSH public keys? (y/N): "
    read add_ssh_keys
    
    if [[ "$add_ssh_keys" =~ ^[Yy]$ ]]; then
        configure_ssh_keys
    fi
}

# Configure SSH keys
configure_ssh_keys() {
    local ssh_dir="/root/.ssh"
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    
    echo "Enter SSH public keys (one per line, empty line to finish):"
    local key_count=0
    
    > "$ssh_dir/authorized_keys"
    
    while true; do
        echo -n "SSH Key $((key_count + 1)): "
        read ssh_key
        
        if [[ -z "$ssh_key" ]]; then
            break
        fi
        
        # Basic validation
        if [[ "$ssh_key" =~ ^ssh- ]]; then
            echo "$ssh_key" >> "$ssh_dir/authorized_keys"
            ((key_count++))
            info "SSH key $key_count added"
        else
            warn "Invalid SSH key format, skipping"
        fi
    done
    
    if [[ $key_count -gt 0 ]]; then
        chmod 600 "$ssh_dir/authorized_keys"
        info "$key_count SSH keys configured"
        
        # Backup keys to data partition
        mkdir -p "$CONFIG_DIR/ssh"
        cp "$ssh_dir/authorized_keys" "$CONFIG_DIR/ssh/"
    fi
}

# Apply network configuration
apply_network_config() {
    log "Applying network configuration..."
    
    echo
    echo "=== Applying Configuration ==="
    
    # Apply netplan configuration
    if netplan apply; then
        info "Network configuration applied successfully"
    else
        warn "Network configuration failed, check settings"
    fi
    
    # Wait for network to stabilize
    sleep 3
    
    # Show new network status
    echo
    echo "Current network status:"
    echo "  Hostname: $(hostname)"
    echo "  IP Address: $(hostname -I | awk '{print $1}' || echo 'Not assigned')"
    echo "  Gateway: $(ip route | grep default | awk '{print $3}' || echo 'Not configured')"
}

# Save configuration summary
save_config_summary() {
    log "Saving configuration summary..."
    
    cat > "$CONFIG_DIR/config-summary.txt" << EOF
# Device Configuration Summary
# Generated on $(date)

Hostname: $(hostname)
IP Configuration: $(grep "dhcp=" "$DEVICE_CONFIG" | cut -d'=' -f2)
Timezone: $(timedatectl show --property=Timezone --value)
Default OS: $(grep "default_os=" "$DEVICE_CONFIG" | cut -d'=' -f2)
SSH Enabled: $(grep "ssh_enabled=" "$DEVICE_CONFIG" | cut -d'=' -f2)

Network Interface Status:
$(ip addr show | grep -E '^[0-9]+:|inet ')

Configuration completed: $(date)
EOF
    
    info "Configuration summary saved to $CONFIG_DIR/config-summary.txt"
}

# Show completion message
show_completion() {
    log "Device configuration completed!"
    
    echo
    echo "=== Configuration Complete ==="
    echo
    echo "Device has been configured with the following settings:"
    echo "  - Hostname: $(hostname)"
    echo "  - Network: $(if grep -q "dhcp=true" "$DEVICE_CONFIG"; then echo "DHCP"; else echo "Static IP"; fi)"
    echo "  - SSH: $(if grep -q "ssh_enabled=true" "$DEVICE_CONFIG"; then echo "Enabled"; else echo "Disabled"; fi)"
    echo "  - Default OS: $(grep "default_os=" "$DEVICE_CONFIG" | cut -d'=' -f2 | tr '[:lower:]' '[:upper:]')"
    echo
    echo "Configuration files saved to: $CONFIG_DIR"
    echo
    echo "Next steps:"
    echo "1. Run 'partition-disk' if disk partitioning is needed"
    echo "2. Run 'install-os1' to install primary Ubuntu system"
    echo "3. Run 'install-os2' to install secondary Ubuntu system"
    echo "4. Reboot to use the new configuration"
    echo
    echo "Press Enter to continue..."
    read
}

# Main execution
main() {
    init_config_dir
    show_welcome
    configure_network
    configure_system
    configure_security
    apply_network_config
    save_config_summary
    show_completion
}

# Run main function
main "$@"
