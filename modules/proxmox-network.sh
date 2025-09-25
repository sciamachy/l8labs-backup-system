#!/bin/bash
# /root/scripts/backup-modules/network.sh
# Proxmox network configuration backup module

backup_network() {
    local backup_component_path="$1"
    local status="success"
    local validation="{}"

    echo "Backing up network configuration..."
    
    # Create target directory
    local network_backup_dir="$backup_component_path/data/network"
    mkdir -p "$network_backup_dir"
    
    # List of network configuration files to back up
    local network_files=(
        "/etc/network/interfaces"
        "/etc/hosts"
        "/etc/hostname"
        "/etc/resolv.conf"
    )
    
    # Backup each network file
    local total_size=0
    local validation_files="[]"
    local success_count=0
    local failed_count=0
    
    for file in "${network_files[@]}"; do
        if [ -f "$file" ]; then
            local filename=$(basename "$file")
            local dest_file="$network_backup_dir/$filename"
            
            if cp "$file" "$dest_file" 2>/dev/null; then
                echo "Backed up $file"
                local file_size=$(stat -c%s "$dest_file")
                local md5sum=$(md5sum "$dest_file" | cut -d' ' -f1)
                total_size=$((total_size + file_size))
                success_count=$((success_count + 1))
                
                # Add to validation files array
                if [ "$validation_files" = "[]" ]; then
                    validation_files="[
                    {
                        \"path\": \"data/network/$filename\",
                        \"size\": $file_size,
                        \"md5\": \"$md5sum\"
                    }"
                else
                    validation_files="$validation_files,
                    {
                        \"path\": \"data/network/$filename\",
                        \"size\": $file_size,
                        \"md5\": \"$md5sum\"
                    }"
                fi
            else
                echo "WARNING: Failed to backup $file"
                failed_count=$((failed_count + 1))
            fi
        fi
    done
    
    # Close the validation files array
    if [ "$validation_files" != "[]" ]; then
        validation_files="$validation_files
        ]"
    fi
    
    # Also backup VLAN configurations and bridges if present
    if [ -d "/etc/vlan" ]; then
        cp -r "/etc/vlan" "$network_backup_dir/" 2>/dev/null
    fi
    
    if [ -d "/etc/sysconfig/network-scripts" ]; then
        mkdir -p "$network_backup_dir/network-scripts"
        cp -r "/etc/sysconfig/network-scripts/ifcfg-*" "$network_backup_dir/network-scripts/" 2>/dev/null
    fi
    
    # Backup iptables rules if available
    if command -v iptables-save >/dev/null 2>&1; then
        iptables-save > "$network_backup_dir/iptables-rules.txt" 2>/dev/null
    fi
    
    # Get the total size of the network backup directory
    local dir_size=$(du -sb "$network_backup_dir" | cut -f1)
    
    # Create validation JSON
    validation=$(cat << EOF
{
    "size": $dir_size,
    "files": $validation_files,
    "checks": {
        "compression": false,
        "write_test": true
    }
}
EOF
)

    # If any files failed, mark as partial failure
    if [ $failed_count -gt 0 ]; then
        if [ $success_count -gt 0 ]; then
            status="partial_failure"
        else
            status="failed"
        fi
    fi
    
    # Update host status with this component's backup result
    update_component_status "network" "$status" "config" "$validation"
}
