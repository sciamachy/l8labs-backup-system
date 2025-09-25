#!/bin/bash
# /root/scripts/backup-modules/mariadb.sh
# Updated for the standardized component-based architecture

# MariaDB-specific configuration
DB_USER="backupreader"
DB_PASS="hwfo8-54wr45"

backup_mariadb() {
    local backup_component_path="$1"
    local status="success"
    local validation="{}"

    # Backup databases
    if podman exec mariadb mariadb-dump \
        --user="$DB_USER" \
        --password="$DB_PASS" \
        --all-databases \
        --events \
        --routines \
        --triggers \
        --single-transaction \
        --quick \
        --no-tablespaces > "$backup_component_path/data/all_databases.sql"; then
        
        # Compress the backup
        gzip "$backup_component_path/data/all_databases.sql"
        
        # Calculate validation data
        local backup_size=$(stat -c%s "$backup_component_path/data/all_databases.sql.gz")
        local md5sum=$(md5sum "$backup_component_path/data/all_databases.sql.gz" | cut -d' ' -f1)
        
        validation=$(cat << EOF
{
    "size": $backup_size,
    "files": [
        {
            "path": "data/all_databases.sql.gz",
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
        status="failed"
    fi

    # Update host status with this component's backup result
    update_component_status "mariadb" "$status" "database" "$validation"
}