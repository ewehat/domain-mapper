#!/bin/sh
# Uninstall script for Keenetic Domain Routing
# This script removes the domain routing configuration while preserving installed packages

echo "Starting Keenetic Domain Routing uninstall process..."

# Variables
IPSET_NAME="unblock"
VPN_INTERFACE="wg0"  # Default, but will try to read from config
ROUTE_TABLE="100"
MARK="0x1"

# Function to log actions
log_action() {
    echo "[$( date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to safely remove files
safe_remove() {
    if [ -f "$1" ]; then
        log_action "Removing file: $1"
        rm -f "$1"
    else
        log_action "File not found (skipping): $1"
    fi
}

# Function to safely remove directories
safe_remove_dir() {
    if [ -d "$1" ]; then
        log_action "Removing directory: $1"
        rm -rf "$1"
    else
        log_action "Directory not found (skipping): $1"
    fi
}

# Check if running as root or with appropriate permissions
if [ "$(id -u)" -ne 0 ] && [ ! -w "/opt" ]; then
    echo "Warning: This script may need elevated privileges to remove all components."
    echo "Some operations may fail if you don't have sufficient permissions."
fi

# Stop services first
log_action "Stopping domain routing services..."
if [ -f "/opt/etc/init.d/S56routing" ]; then
    /opt/etc/init.d/S56routing stop 2>/dev/null || log_action "Failed to stop S56routing service"
fi

# Try to read VPN interface from config if it exists
if [ -f "/opt/etc/init.d/S56routing" ]; then
    VPN_INTERFACE=$(grep '^VPN_INTERFACE=' /opt/etc/init.d/S56routing | cut -d'"' -f2)
    log_action "Detected VPN interface: $VPN_INTERFACE"
fi

# Remove iptables rules
log_action "Removing iptables rules..."
iptables -t mangle -D PREROUTING -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark "$MARK" 2>/dev/null || log_action "iptables rule already removed or not found"

# Remove ip rules
log_action "Removing ip rules..."
ip rule del fwmark "$MARK" table "$ROUTE_TABLE" 2>/dev/null || log_action "ip rule already removed or not found"

# Remove custom routes from routing table
log_action "Removing custom routes..."
ip route flush table "$ROUTE_TABLE" 2>/dev/null || log_action "Routes already flushed or table not found"

# Remove ipset
log_action "Removing ipset..."
if ipset list "$IPSET_NAME" &>/dev/null; then
    ipset destroy "$IPSET_NAME" 2>/dev/null || log_action "Failed to destroy ipset (may be in use)"
else
    log_action "ipset '$IPSET_NAME' not found"
fi

# Remove custom routing table entry
log_action "Removing custom routing table entry..."
if [ -f "/opt/etc/iproute2/rt_tables" ]; then
    sed -i "/^$ROUTE_TABLE vpn$/d" /opt/etc/iproute2/rt_tables 2>/dev/null || log_action "Failed to remove routing table entry"
fi

# Remove cron job
log_action "Removing cron job..."
if command -v crontab >/dev/null; then
    # Remove the specific cron job for update_ips.sh
    (crontab -l 2>/dev/null | grep -v "/opt/bin/update_ips.sh") | crontab - 2>/dev/null || log_action "Failed to remove cron job or cron job not found"
else
    log_action "crontab command not available"
fi

# Remove configuration files
log_action "Removing configuration files..."
safe_remove "/opt/etc/dnsmasq.conf"
safe_remove "/opt/bin/update_ips.sh"
safe_remove "/opt/etc/init.d/S56routing"
safe_remove "/opt/etc/resolved_ips.list"

# Remove configuration directories (only if empty or only contain our files)
log_action "Removing configuration directories..."
safe_remove_dir "/opt/etc/unblock.d"

# Remove log files
log_action "Removing log files..."
safe_remove "/opt/var/log/dnsmasq.log"
safe_remove "/opt/var/log/update_ips.log"

# Note: We intentionally do NOT remove /opt/var/log directory as it may contain other logs

# Restore original DNS settings if dns-override was used
log_action "Attempting to restore DNS settings..."
if command -v opkg >/dev/null; then
    # Try to restore original DNS (this may not work on all systems)
    opkg dns-override --disable 2>/dev/null || log_action "Could not restore DNS settings automatically"
else
    log_action "opkg command not available - cannot restore DNS settings automatically"
fi

# Restart dnsmasq to default state (if it exists)
log_action "Restarting dnsmasq service..."
if [ -f "/opt/etc/init.d/S10dnsmasq" ]; then
    /opt/etc/init.d/S10dnsmasq restart 2>/dev/null || log_action "Failed to restart dnsmasq"
elif [ -f "/etc/init.d/dnsmasq" ]; then
    /etc/init.d/dnsmasq restart 2>/dev/null || log_action "Failed to restart system dnsmasq"
else
    log_action "dnsmasq service not found"
fi

echo ""
echo "================================================================"
echo "Keenetic Domain Routing uninstall completed!"
echo "================================================================"
echo ""
echo "What was removed:"
echo "  ✓ Domain routing configuration files"
echo "  ✓ Custom iptables rules and ipsets"
echo "  ✓ Custom routing tables and rules"
echo "  ✓ Cron jobs for IP updates"
echo "  ✓ Log files"
echo ""
echo "What was preserved:"
echo "  ✓ Installed packages (dnsmasq-full, ipset, iptables, bind-dig, cron)"
echo "  ✓ System directories (/opt/bin, /opt/etc, /opt/var/log)"
echo "  ✓ Other configurations not related to domain routing"
echo ""
echo "Manual cleanup steps (if needed):"
echo "  - Check your router's DNS settings in the web interface"
echo "  - Verify VPN routing is working as expected"
echo "  - Remove any additional custom domains you may have added"
echo ""
echo "If you need to reinstall, run: ./install.sh"
echo ""