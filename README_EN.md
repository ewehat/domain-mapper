# Quick Start Guide

This file contains instructions for quickly setting up and running Domain Router in development mode.

## What Was Created

For testing and development of Domain Router, the following files were created:

### Main Scripts:
- `dev-setup.sh` - development environment setup
- `test-runner.sh` - automated functionality testing
- `mock-api-server.sh` - Keenetic API mock server for realistic testing

### Test Data (`test-data/`):
- `settings.conf` - configuration with test connection parameters
- `domains.txt` - list of popular domains for testing
- `ip-cache.txt` - example IP address cache
- `domain-router.log` - example log file

### Documentation:
- `DEVELOPMENT.md` - detailed developer guide
- `QUICKSTART.md` - Russian quick start guide
- `README_EN.md` - this file

## Quick Start

### 1. Automated Testing
```bash
# Run full test suite
./test-runner.sh
```

### 2. Manual Testing
```bash
# Set up development environment
./dev-setup.sh

# Navigate to working directory
cd /tmp/domain-router-dev

# Check status
./dr status

# Test configuration
./dr test-config

# Add domain
./dr add example.org

# Update routes
./dr update

# Show help
./dr
```

### 3. Testing with Mock Server
```bash
# First terminal - start mock server
./mock-api-server.sh 8080

# Second terminal - setup and test
./dev-setup.sh
cd /tmp/domain-router-dev

# Change settings to use mock server
sed -i 's/KEENETIC_HOST="192.168.1.1"/KEENETIC_HOST="localhost:8080"/' settings.conf

# Now API requests will work
./dr test-config
./dr update
```

## Available Commands

| Command | Description |
|---------|-------------|
| `test-config` | Test configuration and connectivity |
| `status` | Show current status and cache |
| `add <domain>` | Add domain to the list |
| `remove <domain>` | Remove domain from the list |
| `update` | Update routes for all domains |
| `force-update` | Force update all routes |
| `cleanup` | Remove unused routes |

## Features

✅ **Complete isolation** - all files in `/tmp`, doesn't affect system  
✅ **Ready data** - configuration files filled with examples  
✅ **Automated tests** - verification of all main functions  
✅ **Mock server** - Keenetic API simulation for realistic testing  
✅ **Logging** - all operations recorded in log  
✅ **Quick access** - `./dr` command for convenience  

Enjoy developing with Domain Router! 🚀