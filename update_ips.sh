#!/bin/sh
# Script for maintaining ipset and resolved IPs
# Place in /opt/bin/update_ips.sh

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