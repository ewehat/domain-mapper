#!/bin/sh
# Installation script for Keenetic Domain Routing
# Place this script anywhere and run it to install the solution

# Check for Entware
if [ ! -d "/opt" ]; then
    echo "Error: Entware is not installed. Please install Entware first."
    exit 1
fi

# Install required packages
echo "Installing required packages..."
opkg update
opkg install dnsmasq-full ipset iptables bind-dig cron

# Create directories
mkdir -p /opt/etc/unblock.d
mkdir -p /opt/var/log
mkdir -p /opt/bin

# Create empty resolved IPs file
touch /opt/etc/resolved_ips.list

# Copy configuration files
echo "Setting up configuration files..."

# Create dnsmasq.conf
cat > /opt/etc/dnsmasq.conf << 'EOL'
# Main dnsmasq configuration file for selective routing
listen-address=192.168.1.1,127.0.0.1
bind-interfaces
no-resolv
no-hosts

# Upstream DNS servers
server=8.8.8.8
server=1.1.1.1

# Cache settings to reduce load
cache-size=4096
min-cache-ttl=3600
max-ttl=86400

# Load domains from directory
conf-dir=/opt/etc/unblock.d

# Use resolved IPs file
addn-hosts=/opt/etc/resolved_ips.list

# Logging
log-queries
log-facility=/opt/var/log/dnsmasq.log

# Don't use hosts file
no-hosts

# Don't become a DHCP server
no-dhcp-interface=

# Don't read /opt/etc/resolv.conf
no-resolv
EOL

# Create example domain list
cat > /opt/etc/unblock.d/unblock.conf << 'EOL'
# Example domain list for routing through VPN
# Add your domains here in the format:
# ipset=/domain.com/unblock (exact domain)
# or
# ipset=/.domain.com/unblock (domain and all subdomains)

# Example entries (uncomment or add your own)
#ipset=/.example.com/unblock
#ipset=/specific-domain.com/unblock
EOL

# Create update script
cat > /opt/bin/update_ips.sh << 'EOL'
#!/bin/sh
# Script for maintaining ipset and resolved IPs

LOG_FILE="/opt/var/log/update_ips.log"
RESOLVED_IPS_FILE="/opt/etc/resolved_ips.list"
DOMAINS_DIR="/opt/etc/unblock.d"
IPSET_NAME="unblock"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

ensure_ipset_exists() {
    if ! ipset list "$IPSET_NAME" &>/dev/null; then
        log "Creating ipset '$IPSET_NAME'"
        ipset create "$IPSET_NAME" hash:ip maxelem 10000 || {
            log "Failed to create ipset '$IPSET_NAME'"
            return 1
        }
    fi
    return 0
}

flush_ipset() {
    log "Flushing ipset '$IPSET_NAME'"
    ipset flush "$IPSET_NAME" || {
        log "Failed to flush ipset '$IPSET_NAME'"
        return 1
    }
    return 0
}

update_resolved_ips() {
    # Skip if no dig command
    if ! command -v dig >/dev/null; then
        log "dig command not found, skipping resolved IPs update"
        return 0
    fi

    log "Updating resolved IPs list"
    # Create a temporary file
    TEMP_FILE=$(mktemp)

    # Extract domains from all files in unblock.d
    find "$DOMAINS_DIR" -type f -name "*.conf" | while read -r conf_file; do
        grep -o 'ipset=/[^/]*/' "$conf_file" | sed 's/ipset=\///g' | sed 's/\///g' | while read -r domain; do
            # Remove leading dot for wildcard domains
            domain="${domain#.}"
            
            # Use dig to resolve domain
            ip=$(dig +short "$domain" @8.8.8.8 | grep -v '\.$' | head -n1)
            
            if [ -n "$ip" ]; then
                echo "$domain $ip" >> "$TEMP_FILE"
            fi
        done
    done

    # Replace the old file with the new one
    mv "$TEMP_FILE" "$RESOLVED_IPS_FILE"
    log "Updated resolved IPs list with $(wc -l < "$RESOLVED_IPS_FILE") entries"
}

main() {
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log "Starting IP update process"
    
    # Ensure ipset exists
    ensure_ipset_exists || exit 1
    
    # Flush the ipset
    flush_ipset || exit 1
    
    # Optionally update resolved IPs (can be commented out to reduce load)
    # update_resolved_ips
    
    log "IP update process completed successfully"
}

main
EOL

# Make script executable
chmod +x /opt/bin/update_ips.sh

# Create init script
cat > /opt/etc/init.d/S56routing << 'EOL'
#!/bin/sh
# Startup script for domain routing

IPSET_NAME="unblock"
VPN_INTERFACE="nwg0"  # Change to your VPN interface
ROUTE_TABLE="100"
MARK="0x1"

start() {
    echo "Starting domain-based routing..."
    
    # Create ipset if it doesn't exist
    if ! ipset list "$IPSET_NAME" &>/dev/null; then
        echo "Creating ipset '$IPSET_NAME'"
        ipset create "$IPSET_NAME" hash:ip maxelem 10000
    fi
    
    # Create routing table if it doesn't exist
    if ! grep -q "^$ROUTE_TABLE " /opt/etc/iproute2/rt_tables; then
        echo "$ROUTE_TABLE vpn" >> /opt/etc/iproute2/rt_tables
    fi
    
    # Set up iptables rules for marking packets
    iptables -t mangle -A PREROUTING -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark "$MARK"
    
    # Set up ip rule for marked packets
    ip rule add fwmark "$MARK" table "$ROUTE_TABLE"
    
    # Set up default route through VPN interface
    # Get VPN interface gateway
    VPN_GW=$(ip route | grep "dev $VPN_INTERFACE" | grep -v "link" | awk '{print $1}')
    if [ -n "$VPN_GW" ]; then
        ip route add default via "$VPN_GW" dev "$VPN_INTERFACE" table "$ROUTE_TABLE"
    else
        echo "Warning: Could not determine VPN gateway. Is VPN interface up?"
    fi
    
    echo "Domain-based routing started"
}

stop() {
    echo "Stopping domain-based routing..."
    
    # Remove ip rule
    ip rule del fwmark "$MARK" table "$ROUTE_TABLE" 2>/dev/null
    
    # Remove iptables rules
    iptables -t mangle -D PREROUTING -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark "$MARK" 2>/dev/null
    
    echo "Domain-based routing stopped"
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        start
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac

exit 0
EOL

# Make init script executable
chmod +x /opt/etc/init.d/S56routing

# Add cron job for hourly ipset clearing
echo "Setting up cron job..."
(crontab -l 2>/dev/null; echo "0 * * * * /opt/bin/update_ips.sh") | crontab -

# Disable built-in DNS resolver on Keenetic
echo "Disabling built-in DNS resolver..."
opkg dns-override

# Create ipset
echo "Creating initial ipset..."
ipset create unblock hash:ip maxelem 10000 2>/dev/null

# Start services
echo "Starting services..."
/opt/etc/init.d/S56routing start
/opt/etc/init.d/S10dnsmasq restart

echo "Installation completed successfully!"
echo "Please check /opt/etc/unblock.d/unblock.conf and add your domains."
echo "Make sure to set the correct VPN interface in /opt/etc/init.d/S56routing"
echo "Restart routing with: /opt/etc/init.d/S56routing restart"