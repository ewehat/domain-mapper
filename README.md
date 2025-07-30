# Keenetic Domain Routing

A minimalist script for Keenetic routers with Entware that implements selective routing of traffic for 1000+ domains through a VPN connection, similar to KVAS but simpler.

## Features

- Uses dnsmasq to resolve domains and auto-populate an ipset
- Stores resolved IPs in a file for debugging
- Clears the ipset hourly to manage size
- Routes traffic from the ipset through VPN using iptables
- Supports subdomains and can scale to 1000+ domains
- Minimizes router load

## Requirements

- Keenetic router with KeeneticOS 3.7+ or 4.1.7
- Entware installed on USB storage or internal memory
- Required packages: dnsmasq-full, ipset, iptables, bind-dig, cron
- VPN connection (WireGuard or other) already configured

## Installation

1. Make sure Entware is installed on your router
2. Download and run the installation script:

```bash
wget -O /tmp/install.sh https://raw.githubusercontent.com/yourusername/keenetic-domain-routing/master/install.sh
chmod +x /tmp/install.sh
sh /tmp/install.sh
```

Alternatively, you can manually install each component following the steps below.

## Uninstallation

To remove the domain routing configuration while preserving installed packages:

```bash
wget -O /tmp/uninstall.sh https://raw.githubusercontent.com/yourusername/keenetic-domain-routing/master/uninstall.sh
chmod +x /tmp/uninstall.sh
sh /tmp/uninstall.sh
```

The uninstall script will:
- Stop domain routing services
- Remove custom iptables rules and ipsets
- Remove configuration files and directories
- Remove cron jobs
- Clean up log files
- **Preserve installed packages** (dnsmasq-full, ipset, iptables, bind-dig, cron)

After uninstallation, you may need to manually check your router's DNS settings.

### Manual Installation

1. Install required packages:

```bash
opkg update
opkg install dnsmasq-full ipset iptables bind-dig cron
```

2. Create required directories:

```bash
mkdir -p /opt/etc/unblock.d
mkdir -p /opt/var/log
```

3. Create configuration files:
   - Put `dnsmasq.conf` in `/opt/etc/`
   - Put `unblock.conf` in `/opt/etc/unblock.d/`
   - Put `update_ips.sh` in `/opt/bin/` and make it executable: `chmod +x /opt/bin/update_ips.sh`
   - Put `S56routing` in `/opt/etc/init.d/` and make it executable: `chmod +x /opt/etc/init.d/S56routing`

4. Set up cron job for hourly ipset clearing:

```bash
(crontab -l 2>/dev/null; echo "0 * * * * /opt/bin/update_ips.sh") | crontab -
```

5. Disable built-in DNS resolver on Keenetic:

```bash
opkg dns-override
```

6. Start services:

```bash
/opt/etc/init.d/S56routing start
/opt/etc/init.d/S10dnsmasq restart
```

## Configuration

### Adding Domains

Edit `/opt/etc/unblock.d/unblock.conf` to add domains that should be routed through VPN:

```
# Format for exact domains:
ipset=/domain.com/unblock

# Format for domain and all subdomains:
ipset=/.domain.com/unblock
```

For better organization with 1000+ domains, create multiple files in `/opt/etc/unblock.d/` (e.g., social.conf, streaming.conf).

### Changing VPN Interface

Edit `/opt/etc/init.d/S56routing` and change the `VPN_INTERFACE` variable to match your VPN interface:

```bash
VPN_INTERFACE="wg0"  # Change to your VPN interface (e.g., wg0, tun0, etc.)
```

## Troubleshooting

### Check dnsmasq logs:

```bash
cat /opt/var/log/dnsmasq.log
```

### Check update script logs:

```bash
cat /opt/var/log/update_ips.log
```

### View current ipset entries:

```bash
ipset list unblock
```

### Check resolved IP addresses:

```bash
cat /opt/etc/resolved_ips.list
```

### Test domain resolution:

```bash
dig example.com @192.168.1.1
```

### Restart services:

```bash
/opt/etc/init.d/S10dnsmasq restart
/opt/etc/init.d/S56routing restart
```

## Advanced Configuration

### Changing cache settings

Edit `/opt/etc/dnsmasq.conf` to adjust cache settings:

```
cache-size=4096
min-cache-ttl=3600
```

### Storing resolved_ips.list in RAM for performance

Edit `/opt/bin/update_ips.sh` and change:

```bash
RESOLVED_IPS_FILE="/opt/etc/resolved_ips.list"
```

To:

```bash
RESOLVED_IPS_FILE="/tmp/resolved_ips.list"
```

Don't forget to update the reference in `dnsmasq.conf` as well.

## Support

For issues, please check the logs at:
- `/opt/var/log/dnsmasq.log`
- `/opt/var/log/update_ips.log`