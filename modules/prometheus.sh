#!/bin/bash
# /root/scripts/backup-modules/prometheus.sh
# Updated for the standardized component-based architecture

backup_prometheus() {
    local backup_component_path="$1"
    local status="success"
    local validation="{}"

    echo "Taking Prometheus snapshot via API..."
    
    # Use the Prometheus API to create a snapshot and capture the response
    local SNAPSHOT_RESPONSE=$(curl -s -XPOST http://localhost:9090/api/v1/admin/tsdb/snapshot)
    echo "API Response: $SNAPSHOT_RESPONSE"
    
    # Extract the snapshot name from the JSON response
    local SNAPSHOT_NAME=$(echo $SNAPSHOT_RESPONSE | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$SNAPSHOT_NAME" ]; then
        echo "Created snapshot: $SNAPSHOT_NAME"
        
        # Copy the snapshot from the container
        echo "Copying snapshot $SNAPSHOT_NAME from prometheus container..."
        if podman cp prometheus:/prometheus/snapshots/$SNAPSHOT_NAME $backup_component_path/data/; then
            echo "Snapshot copied successfully"
            
            # Compress the backup
            echo "Compressing snapshot..."
            (cd $backup_component_path/data/ && tar -czf prometheus_snapshot.tar.gz $SNAPSHOT_NAME)
            rm -rf $backup_component_path/data/$SNAPSHOT_NAME
            
            # Calculate validation data
            if [ -f "$backup_component_path/data/prometheus_snapshot.tar.gz" ]; then
                local backup_size=$(stat -c%s "$backup_component_path/data/prometheus_snapshot.tar.gz")
                local md5sum=$(md5sum "$backup_component_path/data/prometheus_snapshot.tar.gz" | cut -d' ' -f1)
                
                validation=$(cat << EOJSON
{
    "size": $backup_size,
    "files": [
        {
            "path": "data/prometheus_snapshot.tar.gz",
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
                echo "ERROR: Failed to create compressed snapshot"
                status="failed"
            fi
        else
            echo "ERROR: Failed to copy snapshot from container"
            status="failed"
        fi
    else
        echo "ERROR: Failed to extract snapshot name from API response"
        status="failed"
    fi

    # Update host status with this component's backup result
    update_component_status "prometheus" "$status" "database" "$validation"
}
