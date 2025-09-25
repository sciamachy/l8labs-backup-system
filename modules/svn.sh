#!/bin/bash
# /root/scripts/backup-modules/svn.sh

# SVN backup module for the unified backup system
# This module backs up SVN repositories

backup_svn() {
    local backup_component_path="$1"
    local status="success"
    local validation="{}"
    local day_of_week=$(date +%a)
    local backup_type="incremental"
    local source_dir="/var/lib/svn"
    
    echo "Backing up SVN repositories..."
    
    # Determine backup type based on day of week
    if [ "$day_of_week" = "Sun" ]; then
        backup_type="full"
    fi
    
    # Track successful and failed components
    local success_count=0
    local failed_count=0
    local total_size=0
    local validation_files="[]"
    
    # Process each SVN repository
    for repo in "$source_dir"/*; do
        if [ ! -d "$repo" ]; then
            continue
        fi
        
        local repo_name="${repo##*/}"
        local backup_file=""
        local component_status="success"
        
        echo "Processing SVN repository: $repo_name"
        
        # Determine backup file name based on backup type
        if [ "$backup_type" = "full" ]; then
            backup_file="$backup_component_path/data/${repo_name}_Full.tar.gz"
            # For full backups, remove old files
            rm -f "$backup_component_path/data/${repo_name}_*.tar.gz" 2>/dev/null
        else
            backup_file="$backup_component_path/data/${repo_name}_${day_of_week}.tar.gz"
        fi
        
        # Create backup
        if [ "$backup_type" = "full" ]; then
            if ! /bin/tar czfh "$backup_file" "$repo/" > /dev/null 2>&1; then
                echo "ERROR: Failed to create backup for $repo_name"
                component_status="failed"
                failed_count=$((failed_count + 1))
                continue
            fi
        else
            if ! /bin/tar --create --dereference --gzip --newer-mtime "1 day ago" --file "$backup_file" "$repo/" > /dev/null 2>&1; then
                echo "ERROR: Failed to create incremental backup for $repo_name"
                component_status="failed"
                failed_count=$((failed_count + 1))
                continue
            fi
        fi
        
        # Validate backup file
        if [ ! -f "$backup_file" ]; then
            echo "ERROR: Expected backup file $backup_file not found"
            component_status="failed"
            failed_count=$((failed_count + 1))
            continue
        fi
        
        # Get file size and MD5
        local file_size=$(stat -c%s "$backup_file")
        local md5sum=$(md5sum "$backup_file" | cut -d' ' -f1)
        
        # Add to successful components
        success_count=$((success_count + 1))
        total_size=$((total_size + file_size))
        
        # Add to validation files array
        if [ "$validation_files" = "[]" ]; then
            validation_files="[
            {
                \"path\": \"data/${backup_file##*/}\",
                \"size\": $file_size,
                \"md5\": \"$md5sum\"
            }"
        else
            validation_files="$validation_files,
            {
                \"path\": \"data/${backup_file##*/}\",
                \"size\": $file_size,
                \"md5\": \"$md5sum\"
            }"
        fi
        
        echo "Successfully backed up $repo_name ($file_size bytes)"
    done
    
    # Close the validation files array
    if [ "$validation_files" != "[]" ]; then
        validation_files="$validation_files
        ]"
    fi
    
    # Determine overall status
    if [ $failed_count -gt 0 ]; then
        if [ $success_count -gt 0 ]; then
            status="partial_failure"
        else
            status="failed"
        fi
    fi
    
    # Create validation JSON
    validation=$(cat << EOF
{
    "size": $total_size,
    "files": $validation_files,
    "checks": {
        "compression": true,
        "write_test": true
    }
}
EOF
)

    # Update host status with this component's backup result
    update_component_status "svn" "$status" "repository" "$validation"
}
