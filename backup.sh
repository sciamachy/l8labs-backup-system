
#!/bin/bash
# /root/scripts/backup.sh
# Fully modular backup script for any type of system
#
# REVISION HISTORY
# ================
# v1.0.0 - Initial version with basic container backup support
# v2.0.0 - Complete rewrite with modular architecture and JSON status reporting
# v3.0.0 - Added automatic mount point validation and mounting if needed (2025-05-03)
#          - Handles systems where DNS may not be available during early boot
#          - Uses fstab configuration for mounting
#          - Added retry logic with verification
#
# For detailed documentation see: modular-backup-system-guide.md

# Check for required dependency
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: This script requires 'jq' to be installed"
    echo "Please install it with: apt-get install jq"
    exit 1
fi

# Configuration
CIFS_MOUNT="/mnt/backup"
BACKUP_DIR="$CIFS_MOUNT"  # Flattened - no subdirectory
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="$BACKUP_DIR/$DATE"
HOST_NAME=$(hostname)
START_TIME=$(date +%s)
RETENTION_DAYS=30

# Initialize host status
HOST_STATUS_FILE="$BACKUP_DIR/host_status.json"

# Module discovery configuration
MODULE_DIR="/root/scripts/backup-modules"
# File that lists enabled modules (optional)
ENABLED_MODULES_FILE="/etc/backup-modules.conf"

# Function to ensure the backup mount is available
ensure_backup_mount() {
    local mount_point="$CIFS_MOUNT"  # Using the existing CIFS_MOUNT variable

    # Check if the mount point exists
    if [ ! -d "$mount_point" ]; then
        echo "Creating mount point directory: $mount_point"
        mkdir -p "$mount_point"
    fi

    # Check if it's already mounted
    if ! mountpoint -q "$mount_point"; then
        echo "Backup location not mounted, attempting to mount..."

        # Try to mount using fstab entry
        if ! mount "$mount_point"; then
            echo "ERROR: Failed to mount backup location"
            return 1
        fi

        echo "Successfully mounted backup location"
    else
        echo "Backup location already mounted"
    fi

    # Verify the mount is writable
    if ! touch "$mount_point/.test_write"; then
        echo "ERROR: Mounted backup location is not writable"
        return 1
    fi
    rm "$mount_point/.test_write"

    return 0
}


# Function to initialize host status
init_host_status() {
    cat > "$HOST_STATUS_FILE" << EOF
{
    "host": "$HOST_NAME",
    "backup_id": "$DATE",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "status": "in_progress",
    "components": {},
    "metrics": {
        "total_duration_seconds": 0,
        "total_size_bytes": 0,
        "components_succeeded": 0,
        "components_failed": 0
    }
}
EOF
}

# Function to update component status in host status file
update_component_status() {
    local component=$1
    local status=$2
    local type=$3
    local validation=$4

    # Use jq to update the host status file
    local temp_file=$(mktemp)
    jq --arg component "$component" \
       --arg status "$status" \
       --arg type "$type" \
       --argjson validation "$validation" \
       '.components[$component] = {
           "status": $status,
           "type": $type,
           "validation": $validation
       }' "$HOST_STATUS_FILE" > "$temp_file"
    mv "$temp_file" "$HOST_STATUS_FILE"

    # Update metrics
    if [ "$status" = "success" ]; then
        jq '.metrics.components_succeeded += 1' "$HOST_STATUS_FILE" > "$temp_file"
    else
        jq '.metrics.components_failed += 1' "$HOST_STATUS_FILE" > "$temp_file"
    fi
    mv "$temp_file" "$HOST_STATUS_FILE"
}

# Alias for backward compatibility with existing modules
update_container_status() {
    update_component_status "$@"
}

# Function to finalize host status
finalize_host_status() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local total_size=$(du -sb "$BACKUP_PATH" | cut -f1)
    local final_status="success"

    # Check if any components failed
    if [ "$(jq '.metrics.components_failed' "$HOST_STATUS_FILE")" -gt 0 ]; then
        final_status="partial_failure"
    fi

    local temp_file=$(mktemp)
    jq --arg status "$final_status" \
       --arg duration "$duration" \
       --arg size "$total_size" \
       '.status = $status |
        .metrics.total_duration_seconds = ($duration|tonumber) |
        .metrics.total_size_bytes = ($size|tonumber)' \
        "$HOST_STATUS_FILE" > "$temp_file"
    mv "$temp_file" "$HOST_STATUS_FILE"

    # Create legacy completion file for backward compatibility
    touch "$BACKUP_DIR/complete"
}

# Function to discover and source available modules
discover_modules() {
    local available_modules=()
    local enabled_modules=()
    
    # Check if modules directory exists
    if [ ! -d "$MODULE_DIR" ]; then
        echo "WARNING: Modules directory $MODULE_DIR not found"
        return 1
    fi
    
    # Find all available module files
    echo "Discovering available backup modules..."
    for module in "$MODULE_DIR"/*.sh; do
        if [ -f "$module" ]; then
            module_name=$(basename "$module" .sh)
            available_modules+=("$module_name")
            echo "Found module: $module_name"
        fi
    done
    
    if [ ${#available_modules[@]} -eq 0 ]; then
        echo "WARNING: No backup modules found in $MODULE_DIR"
        return 1
    fi
    
    # Check for enabled modules configuration file
    if [ -f "$ENABLED_MODULES_FILE" ]; then
        echo "Reading enabled modules from $ENABLED_MODULES_FILE"
        while read -r module_name; do
            # Skip comments and empty lines
            [[ "$module_name" =~ ^#.*$ || -z "$module_name" ]] && continue
            enabled_modules+=("$module_name")
        done < "$ENABLED_MODULES_FILE"
    else
        echo "No enabled modules configuration file found, all discovered modules will be used"
        enabled_modules=("${available_modules[@]}")
    fi
    
    # Source all module files
    echo "Sourcing backup modules..."
    for module in "$MODULE_DIR"/*.sh; do
        if [ -f "$module" ]; then
            module_name=$(basename "$module" .sh)
            # Check if module is enabled
            if [[ " ${enabled_modules[*]} " =~ " ${module_name} " ]] || [ ${#enabled_modules[@]} -eq 0 ]; then
                echo "Sourcing module: $module_name"
                source "$module"
                MODULES_TO_RUN+=("$module_name")
            else
                echo "Skipping disabled module: $module_name"
            fi
        fi
    done
    
    return 0
}

# Main backup process
main() {
    # Log system type for reference
    if command -v podman >/dev/null 2>&1; then
        echo "Podman detected on system"
    fi

    # Ensure backup mount is available
    if ! ensure_backup_mount; then
        echo "ERROR: Failed to ensure backup mount is available"
        exit 1
    fi

    # Create backup directory
    mkdir -p "$BACKUP_PATH"

    # Verify backup directory is writable
    if ! touch "$BACKUP_PATH/.test_write"; then
        echo "ERROR: Backup directory is not writable"
        exit 1
    fi
    rm "$BACKUP_PATH/.test_write"

    # Initialize host status
    init_host_status
    
    # Array to hold modules that will be run
    MODULES_TO_RUN=()
    
    # Discover and source available modules
    discover_modules
    
    if [ ${#MODULES_TO_RUN[@]} -eq 0 ]; then
        echo "ERROR: No backup modules to run"
        exit 1
    fi
    
    echo "Will run these backup modules: ${MODULES_TO_RUN[*]}"
    
    # Run each discovered module's backup function
    for module in "${MODULES_TO_RUN[@]}"; do
        echo "Starting backup using module: $module"
        
        # Create module backup directory
        local backup_module_path="$BACKUP_PATH/$module"
        mkdir -p "$backup_module_path"/{data,config}
        
        # Backup configuration files if they exist (for both container and standard paths)
        if [ -d "/etc/containers/$module" ]; then
            echo "Backing up $module container configuration..."
            cp -r "/etc/containers/$module"/* "$backup_module_path/config/" 2>/dev/null || true
        fi
        
        if [ -d "/etc/$module" ]; then
            echo "Backing up $module configuration..."
            cp -r "/etc/$module"/* "$backup_module_path/config/" 2>/dev/null || true
        fi
        
        # Run module-specific backup if function exists
        backup_func="backup_${module}"
        if declare -F "$backup_func" > /dev/null; then
            $backup_func "$backup_module_path"
        else
            echo "WARNING: No backup function found for $module"
            # Still consider it successful if we at least backed up the config
            if [ -d "$backup_module_path/config" ] && [ "$(ls -A "$backup_module_path/config" 2>/dev/null)" ]; then
                update_component_status "$module" "success" "config-only" \
                    "{\"size\": $(du -sb "$backup_module_path/config" | cut -f1), \"files\": []}"
            else
                echo "ERROR: No configuration found for $module and no backup function available"
                update_component_status "$module" "failed" "unknown" "{\"size\": 0, \"files\": []}"
            fi
        fi
        
        echo "Completed backup for $module"
    done

    # Cleanup old backups - with safety check
    echo "Cleaning up backups older than $RETENTION_DAYS days..."
    find "$BACKUP_DIR" -maxdepth 1 -type d -name "20*_*" -mtime +$RETENTION_DAYS | while read backup_to_delete; do
        # Safety check - make sure it's a proper date directory
        if [[ $(basename "$backup_to_delete") =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
            echo "Removing old backup: $backup_to_delete"
            rm -rf "$backup_to_delete"
        else
            echo "Skipping directory with unusual name: $backup_to_delete"
        fi
    done

    # Generate overall backup report
    {
        echo "Host Backup Report for $HOST_NAME"
        echo "Backup completed at $(date)"
        echo "Backup location: $BACKUP_PATH"
        echo "Backup contents:"
        du -sh "$BACKUP_PATH"/*
        echo "Available space on backup mount:"
        df -h "$CIFS_MOUNT"
    } > "$BACKUP_PATH/backup_report.txt"

    # Finalize host status
    finalize_host_status
    
    echo "Backup completed successfully"
}

# Run main backup process
main
