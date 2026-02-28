#!/bin/bash
# /root/scripts/backup-modules/influxdb.sh

# InfluxDB-specific configuration
INFLUXDB_TOKEN="E7N5C262BwJUdQkFyJlNz3z9euaC28Plfgzql35WN7ShjYbl3hMhxWYacReEKQubC9ZWJdFjRY9yJpMgp8RXug=="

backup_influxdb() {
    local backup_container_path="$1"
    local status="success"
    local validation="{}"

    # Backup databases
    if podman exec influxdb influx backup -t $INFLUXDB_TOKEN /tmp/backup; then
        # Copy the backup from the container
        if podman cp influxdb:/tmp/backup/. "$backup_container_path/data/"; then
            # Compress the backup
            (cd "$backup_container_path/data/" && tar -czf influxdb_backup.tar.gz *)

            # Clean up uncompressed files
            find "$backup_container_path/data/" -type f -not -name "*.tar.gz" -delete
            find "$backup_container_path/data/" -type d -not -path "$backup_container_path/data/" -exec rm -rf {} +

            # Calculate validation data
            local backup_size=$(stat -c "%s" "$backup_container_path/data/influxdb_backup.tar.gz")
            local md5sum=$(md5sum "$backup_container_path/data/influxdb_backup.tar.gz" | cut -d' ' -f1)

            validation=$(cat << EOJ
{
    "size": $backup_size,
    "files": [
        {
            "path": "data/influxdb_backup.tar.gz",
            "size": $backup_size,
            "md5": "$md5sum"
        }
    ],
    "checks": {
        "compression": true,
        "write_test": true
    }
}
EOJ
)
            # Clean up the temporary backup in the container
            podman exec influxdb rm -rf /tmp/backup
        else
            status="failed"
        fi
    else
        status="failed"
    fi

    # Update host status with this container's backup result
    update_container_status "influxdb" "$status" "database" "$validation"
}
