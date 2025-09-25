# L8Labs Modular Backup System

A flexible, component-based backup system designed for heterogeneous server environments with integrated monitoring and standardized reporting.

## Overview

The Modular Backup System provides consistent backups across multiple server types through:

- **Fully modular design** - Add new components by dropping in module files
- **Auto-discovery** - Automatic detection and execution of available backup modules
- **Standardized reporting** - JSON status files for monitoring integration
- **Prometheus integration** - Works with existing monitoring infrastructure
- **Unified approach** - Same framework for containers and traditional services
- **Robust error handling** - Built-in validation and retry logic

## Quick Start

1. **Deploy the main script:**
   ```bash
   cp backup.sh /root/scripts/
   chmod +x /root/scripts/backup.sh
   ```

2. **Create modules directory:**
   ```bash
   mkdir -p /root/scripts/backup-modules
   ```

3. **Deploy modules:**
   ```bash
   cp modules/*.sh /root/scripts/backup-modules/
   chmod +x /root/scripts/backup-modules/*.sh
   ```

4. **Configure backup mount in fstab:**
   ```bash
   # Add to /etc/fstab (adjust for your environment):
   //192.168.1.100/backup /mnt/backup cifs username=backupuser,password=your-password,uid=0,gid=0,_netdev 0 0
   ```

5. **Set up cron job:**
   ```bash
   # Add to /etc/crontab:
   0 1 * * * root /root/scripts/backup.sh
   ```

## System Architecture

```
/root/scripts/
├── backup.sh              # Main backup orchestrator
└── backup-modules/         # Auto-discovered modules
    ├── mariadb.sh         # Database backups
    ├── grafana.sh         # Grafana backups
    ├── prometheus.sh      # Prometheus backups
    ├── openhab.sh         # OpenHAB backups
    └── ...                # Additional service modules
```

## Current Modules

- **mariadb.sh** - MariaDB/MySQL database backups with compression
- **grafana.sh** - Grafana configuration and dashboard backups
- **prometheus.sh** - Prometheus data and configuration backups
- **openhab.sh** - OpenHAB home automation system backups
- **svn.sh** - Subversion repository backups
- **proxmox-pve.sh** - Proxmox VE configuration backups
- **proxmox-network.sh** - Proxmox network configuration backups
- **zigbee2mqtt.sh** - Zigbee2MQTT configuration backups

## Documentation

- **[Technical Guide](modular-backup-system-guide.md)** - Complete system documentation
- **[Deployment Tracking](backup-deployment-tracking.md)** - Server deployment status

## Monitoring Integration

The system generates standardized JSON status files that integrate with Prometheus monitoring:

- Backup success/failure tracking
- Component-level status reporting
- Size and duration metrics
- Age-based alerting

## Adding New Components

Create a new module file in `modules/` directory:

```bash
#!/bin/bash
# modules/myservice.sh

backup_myservice() {
    local backup_component_path="$1"
    
    # Your backup logic here
    # Use update_component_status to report results
}
```

The system will automatically discover and execute your module on the next run.

## Requirements

- **jq** - JSON processing (required)
- **Bash 4+** - Modern bash features
- **Network storage** - CIFS/NFS mount for backup storage
- **cron** - Scheduled execution

## License

Internal L8Labs system - Not for external distribution.

---

**Current Version:** 3.0.0  
**Last Updated:** 2025-09-24  
**Maintained by:** L8Labs Infrastructure Team
