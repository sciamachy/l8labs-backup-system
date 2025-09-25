# Modular Backup System: Technical Guide

## Overview

The Modular Backup System is a flexible, component-based approach to system backups that works across multiple server types. The system creates consistent backups with standardized status reporting that integrates with our Prometheus monitoring infrastructure.

## Key Features

- **Fully modular design** - Simply add module files to enable backup of new components
- **Auto-discovery** - The system automatically finds and runs appropriate backup modules
- **Standardized reporting** - All backups generate consistent JSON status files
- **Simplified directory structure** - Flattened backup storage approach
- **Unified approach** - Same framework for container-based and traditional services
- **Integrated monitoring** - Works seamlessly with existing Prometheus monitoring
- **Error handling** - Robust error detection and validation
- **Automatic mounting** - Ensures backup storage is available, even when DNS is not yet available

## System Architecture

The backup system consists of:

1. **Main backup script** (`backup.sh`) - Core engine that orchestrates backups
2. **Backup modules** - Individual scripts for each component (MariaDB, OpenHAB, etc.)
3. **Status reporting** - JSON-formatted status files for monitoring
4. **Prometheus exporter** - Existing monitoring infrastructure

### Directory Structure

```
/root/scripts/
├── backup.sh                    # Main backup script
└── backup-modules/              # Modules directory
    ├── mariadb.sh               # Database backup module
    ├── grafana.sh               # Grafana backup module
    ├── prometheus.sh            # Prometheus backup module
    ├── openhab.sh               # OpenHAB backup module
    ├── svn.sh                   # SVN repository backup module
    ├── pve.sh                   # Proxmox VE backup module
    ├── network.sh               # Network config backup module
    └── zigbee2mqtt.sh           # Zigbee2MQTT backup module
```

### Backup Storage Structure

```
/mnt/backup/
├── host_status.json             # Status file for monitoring
├── complete                     # Legacy completion marker
├── 20250308_010001/             # Date-stamped backup directory
│   ├── mariadb/                 # Component directory
│   │   ├── config/              # Config backups
│   │   └── data/                # Data backups
│   ├── grafana/
│   ├── openhab/
│   └── backup_report.txt        # Plain text backup report
└── 20250309_010001/             # Next day's backup
```

## Using the System

### Initial Setup

1. Deploy the main script:
   ```bash
   cp backup.sh /root/scripts/
   chmod +x /root/scripts/backup.sh
   ```

2. Create modules directory:
   ```bash
   mkdir -p /root/scripts/backup-modules
   ```

3. Deploy appropriate modules:
   ```bash
   cp *.sh /root/scripts/backup-modules/
   chmod +x /root/scripts/backup-modules/*.sh
   ```

4. Configure the backup mount in fstab:
   ```bash
   # Edit the system fstab file
   nano /etc/fstab
   
   # Add a line similar to this (adjust for your environment)
   //192.168.1.100/backup /mnt/backup cifs username=backupuser,password=your-password,uid=0,gid=0,_netdev 0 0
   
   # Note: Using an IP address instead of hostname avoids DNS issues during early boot
   ```

5. Update crontab:
   ```bash
   # Edit the system crontab
   nano /etc/crontab
   
   # Add or update this line
   0 1 * * * root /root/scripts/backup.sh
   ```

### Adding a New Backup Component

To add backup support for a new component:

1. Create a new module file:
   ```bash
   nano /root/scripts/backup-modules/myservice.sh
   ```

2. Implement the backup function (template):
   ```bash
   #!/bin/bash
   # /root/scripts/backup-modules/myservice.sh
   
   backup_myservice() {
       local backup_component_path="$1"
       local status="success"
       local validation="{}"
       
       echo "Backing up My Service..."
       
       # Create backup directories
       mkdir -p "$backup_component_path/data"
       
       # [YOUR BACKUP LOGIC HERE]
       
       # Create validation JSON
       validation=$(cat << EOF
   {
       "size": $backup_size,
       "files": [
           {
               "path": "data/mybackup.tar.gz",
               "size": $backup_size,
               "md5": "$md5sum"
           }
       ],
       "checks": {
           "compression": true,
           "write_test": true
       }
   }
   EOF
   )
       
       # Update status
       update_component_status "myservice" "$status" "config" "$validation"
   }
   ```

3. Make the module executable:
   ```bash
   chmod +x /root/scripts/backup-modules/myservice.sh
   ```

4. Done! The module will be automatically discovered and used in the next backup run.

### Config-Only Backups Using Dummy Modules

For components that only need their configuration backed up without custom logic:

1. Create a dummy module file:
   ```bash
   nano /root/scripts/backup-modules/nginx.sh
   ```

2. Add minimal content (no function needed):
   ```bash
   #!/bin/bash
   # /root/scripts/backup-modules/nginx.sh
   
   # This is a dummy module for nginx
   # The main backup script will automatically back up:
   # - /etc/containers/nginx (for container-based services)
   # - /etc/nginx (for traditional services)
   
   # No backup_nginx() function is needed for config-only backups
   ```

3. Make the module executable:
   ```bash
   chmod +x /root/scripts/backup-modules/nginx.sh
   ```

### Selectively Enabling Modules

You can optionally control which modules run by creating a configuration file:

```bash
# Create a configuration file
nano /etc/backup-modules.conf

# Add one module name per line
mariadb
grafana
# Comment out modules to disable them
# prometheus
```

## Status Reporting

Each backup generates a standardized JSON status file at `/mnt/backup/host_status.json`:

```json
{
  "host": "hostname",
  "backup_id": "20250308_010001",
  "timestamp": "2025-03-08T01:00:01Z",
  "status": "success",
  "components": {
    "mariadb": {
      "status": "success",
      "type": "database",
      "validation": {
        "size": 1024,
        "files": [
          {
            "path": "data/all_databases.sql.gz",
            "size": 1024,
            "md5": "7bc1c5a24f90a7f0b7e1bac7a1398d6b"
          }
        ],
        "checks": {
          "compression": true,
          "write_test": true
        }
      }
    }
  },
  "metrics": {
    "total_duration_seconds": 2,
    "total_size_bytes": 952055,
    "components_succeeded": 1,
    "components_failed": 0
  }
}
```

## Monitoring Integration

The status files are automatically read by the existing backup_exporter.py script, which exposes metrics to Prometheus. This provides:

- Backup status monitoring
- Age tracking (time since last successful backup)
- Failure alerts
- Size and duration trends
- Component-level success rates

## Automatic Mount Handling

The backup script includes built-in functionality to ensure the backup storage is properly mounted before starting the backup process:

1. **Automatic mount check** - Checks if the backup location is already mounted
2. **Mount point creation** - Creates the mount point directory if it doesn't exist
3. **Automatic mounting** - Attempts to mount the backup location using the system's fstab configuration
4. **Retry logic** - Includes multiple retry attempts with delays to handle network initialization
5. **Mount validation** - Verifies the mount is writable before proceeding

## Troubleshooting

If backups fail or behave unexpectedly:

1. Check the backup log:
   ```bash
   cat /var/log/backup.log
   ```

2. Examine the backup directory:
   ```bash
   ls -la /mnt/backup/
   ls -la /mnt/backup/$(ls -t /mnt/backup | grep -E '^[0-9]{8}_[0-9]{6}$' | head -1)/
   ```

3. Verify JSON status file:
   ```bash
   cat /mnt/backup/host_status.json | jq
   ```

4. Check if modules are discovered:
   ```bash
   /root/scripts/backup.sh | grep "Found module"
   ```

5. Ensure backup mount is accessible:
   ```bash
   mount | grep backup
   touch /mnt/backup/.test && rm /mnt/backup/.test
   ```
   
6. Check for mount errors in the system log:
   ```bash
   journalctl | grep -i 'mount'
   dmesg | grep -i 'cifs'
   ```

## Module-Specific Notes

### MariaDB

- Requires podman and a MariaDB container named "mariadb"
- Uses a read-only DB user for consistent backups
- Backs up all databases with procedures and triggers

### OpenHAB

- Backs up configuration files from /etc/openhab/
- Full backup on Sundays, incremental other days
- Preserves directory structure

### SVN

- Backs up repositories from /var/lib/svn/
- Full backup on Sundays, incremental other days
- Preserves repository structure

### Proxmox

- The PVE module backs up Proxmox configuration files
- The Network module backs up network configuration

### Component Configuration Files

In addition to data, the system automatically backs up configuration files from:
- /etc/containers/[component] (for container-based services)
- /etc/[component] (for traditional services)
