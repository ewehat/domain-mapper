#!/bin/sh
# Uninstall script for Keenetic Domain Routing
# This script removes system components while preserving user configurations

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
IPSET_NAME="unblock"
ROUTE_TABLE="100"
MARK="0x1"
VPN_INTERFACE="wg0"  # Default, will try to detect from config

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# Check for Entware
if [ ! -d "/opt" ]; then
    log_error "Entware is not installed or not accessible."
    exit 1
fi

log "Starting uninstall process for Keenetic Domain Routing..."

# Detect VPN interface from existing config if available
if [ -f "/opt/etc/init.d/S56routing" ]; then
    DETECTED_VPN=$(grep '^VPN_INTERFACE=' /opt/etc/init.d/S56routing | cut -d'"' -f2)
    if [ -n "$DETECTED_VPN" ]; then
        VPN_INTERFACE="$DETECTED_VPN"
        log "Detected VPN interface: $VPN_INTERFACE"
    fi
fi

# Stop services
log "Stopping services..."

# Stop routing service
if [ -f "/opt/etc/init.d/S56routing" ]; then
    log "Stopping domain routing service..."
    /opt/etc/init.d/S56routing stop 2>/dev/null || log_warning "Failed to stop routing service cleanly"
fi

# Stop dnsmasq
log "Stopping dnsmasq service..."
/opt/etc/init.d/S10dnsmasq stop 2>/dev/null || log_warning "Failed to stop dnsmasq cleanly"

# Remove iptables rules
log "Removing iptables rules..."
iptables -t mangle -D PREROUTING -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark "$MARK" 2>/dev/null || log_warning "iptables rule not found or already removed"

# Remove ip rules
log "Removing ip rules..."
ip rule del fwmark "$MARK" table "$ROUTE_TABLE" 2>/dev/null || log_warning "ip rule not found or already removed"

# Remove routing table entry
log "Removing routing table entries..."
if grep -q "^$ROUTE_TABLE vpn" /opt/etc/iproute2/rt_tables 2>/dev/null; then
    sed -i "/^$ROUTE_TABLE vpn/d" /opt/etc/iproute2/rt_tables
    log_success "Removed routing table entry"
fi

# Flush and destroy ipset
log "Removing ipset..."
if ipset list "$IPSET_NAME" &>/dev/null; then
    ipset flush "$IPSET_NAME" 2>/dev/null
    ipset destroy "$IPSET_NAME" 2>/dev/null
    log_success "Removed ipset '$IPSET_NAME'"
else
    log_warning "ipset '$IPSET_NAME' not found"
fi

# Remove cron job
log "Removing cron job..."
if crontab -l 2>/dev/null | grep -q "/opt/bin/update_ips.sh"; then
    (crontab -l 2>/dev/null | grep -v "/opt/bin/update_ips.sh") | crontab -
    log_success "Removed cron job for update_ips.sh"
else
    log_warning "Cron job not found"
fi

# Remove system files (but preserve user configurations)
log "Removing system files..."

# Remove init script
if [ -f "/opt/etc/init.d/S56routing" ]; then
    rm -f "/opt/etc/init.d/S56routing"
    log_success "Removed init script S56routing"
fi

# Remove update script
if [ -f "/opt/bin/update_ips.sh" ]; then
    rm -f "/opt/bin/update_ips.sh"
    log_success "Removed update script"
fi

# Remove main dnsmasq config (but backup first if it contains user modifications)
if [ -f "/opt/etc/dnsmasq.conf" ]; then
    # Check if the config has been modified from default
    if grep -q "# Custom user configuration" /opt/etc/dnsmasq.conf 2>/dev/null || 
       ! grep -q "listen-address=192.168.1.1,127.0.0.1" /opt/etc/dnsmasq.conf 2>/dev/null; then
        # Config appears to be modified, backup instead of removing
        mv /opt/etc/dnsmasq.conf /opt/etc/dnsmasq.conf.backup
        log_warning "dnsmasq.conf appears modified, backed up to dnsmasq.conf.backup"
    else
        rm -f /opt/etc/dnsmasq.conf
        log_success "Removed default dnsmasq.conf"
    fi
fi

# Clean up temporary and log files
log "Cleaning up temporary files and logs..."

# Remove logs
if [ -f "/opt/var/log/dnsmasq.log" ]; then
    rm -f "/opt/var/log/dnsmasq.log"
    log_success "Removed dnsmasq log"
fi

if [ -f "/opt/var/log/update_ips.log" ]; then
    rm -f "/opt/var/log/update_ips.log"
    log_success "Removed update_ips log"
fi

# Remove resolved IPs file (this can be regenerated)
if [ -f "/opt/etc/resolved_ips.list" ]; then
    rm -f "/opt/etc/resolved_ips.list"
    log_success "Removed resolved IPs list"
fi

# Preserve user configurations
log "Preserving user configurations..."

if [ -d "/opt/etc/unblock.d" ]; then
    if [ "$(ls -A /opt/etc/unblock.d)" ]; then
        log_success "Preserved user domain configurations in /opt/etc/unblock.d/"
        log "The following configuration files were preserved:"
        ls -la /opt/etc/unblock.d/
    else
        log_warning "No user configurations found in /opt/etc/unblock.d/"
        rmdir /opt/etc/unblock.d 2>/dev/null
    fi
else
    log_warning "User configuration directory /opt/etc/unblock.d not found"
fi

# Re-enable built-in DNS resolver on Keenetic (reverse the dns-override)
log "Re-enabling built-in DNS resolver..."
opkg dns-override disable 2>/dev/null || log_warning "Could not disable DNS override"

# Restart remaining services
log "Restarting dnsmasq with default configuration..."
/opt/etc/init.d/S10dnsmasq start 2>/dev/null || log_warning "Could not restart dnsmasq"

log_success "Uninstall completed successfully!"
echo
log "Summary:"
log "✓ Removed system components (init scripts, cron jobs, routing rules)"
log "✓ Cleaned up temporary files and logs"
log "✓ Preserved user configurations in /opt/etc/unblock.d/"
echo
log_warning "Note: User domain configurations are preserved in /opt/etc/unblock.d/"
log_warning "If you want to completely remove everything, manually delete:"
log_warning "  - /opt/etc/unblock.d/ (contains your domain lists)"
log_warning "  - /opt/etc/dnsmasq.conf.backup (if exists)"
echo
log "To reinstall, run the install.sh script again."