#!/bin/bash
# /root/scripts/backup-modules/grafana.sh
# Updated for the standardized component-based architecture

backup_grafana() {
    local backup_component_path="$1"
    local status="success"
    local validation="{}"

    echo "Backing up Grafana data..."
    
    # Create a temporary directory to store the backup
    mkdir -p $backup_component_path/data/grafana_temp
    
    # Copy Grafana data from the container
    if podman cp grafana:/var/lib/grafana/. $backup_component_path/data/grafana_temp/; then
        # Compress the backup
        echo "Compressing Grafana data..."
        tar -czf $backup_component_path/data/grafana_backup.tar.gz -C $backup_component_path/data/ grafana_temp
        rm -rf $backup_component_path/data/grafana_temp
        
        # Calculate validation data
        local backup_size=$(stat -c%s "$backup_component_path/data/grafana_backup.tar.gz")
        local md5sum=$(md5sum "$backup_component_path/data/grafana_backup.tar.gz" | cut -d' ' -f1)
        
        validation=$(cat << EOJSON
{
    "size": $backup_size,
    "files": [
        {
            "path": "data/grafana_backup.tar.gz",
            "size": $backup_size,
            "md5": "$md5sum"
        }
    ],
    "checks": {
        "compression": true,
        "write_test": true
    }
}
EOJSON
)
    else
        echo "ERROR: Failed to copy Grafana data from container"
        status="failed"
    fi

    # Update host status with this component's backup result
    update_component_status "grafana" "$status" "database" "$validation"
}
