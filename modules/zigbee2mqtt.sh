#!/bin/bash
# /root/scripts/backup-modules/zigbee2mqtt.sh
# Backup module for Zigbee2MQTT

backup_zigbee2mqtt() {
    local backup_component_path="$1"
    local status="success"
    local validation="{}"
    local source_dir="/opt/zigbee2mqtt"
    
    echo "Backing up Zigbee2MQTT configuration..."
    
    # Create target directory
    mkdir -p "$backup_component_path/data"
    
    # Backup file path
    local backup_file="$backup_component_path/data/zigbee2mqtt_config.tar.gz"
    
    # Define important directories/files to back up
    # Typically, we want to back up the configuration but not the large log files
    
    if [ -d "$source_dir" ]; then
        # Create a backup focusing only on configuration files
        echo "Creating Zigbee2MQTT configuration backup..."
        
        # Backup primarily the data directory which contains configuration and device information
        if tar czf "$backup_file" \
            -C "$source_dir" \
            --exclude="data/log" \
            data 2>/dev/null; then
            
            echo "Successfully backed up Zigbee2MQTT configuration"
            
            # Calculate validation data
            local backup_size=$(stat -c%s "$backup_file")
            local md5sum=$(md5sum "$backup_file" | cut -d' ' -f1)
            
            validation=$(cat << EOF
{
    "size": $backup_size,
    "files": [
        {
            "path": "data/zigbee2mqtt_config.tar.gz",
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
        else
            echo "ERROR: Failed to create Zigbee2MQTT backup"
            status="failed"
        fi
    else
        echo "ERROR: Zigbee2MQTT directory $source_dir not found"
        status="failed"
    fi
    
    # Update host status with this component's backup result
    update_component_status "zigbee2mqtt" "$status" "config" "$validation"
}
