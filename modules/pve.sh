#!/bin/bash
# /root/scripts/backup-modules/pve.sh
# Proxmox PVE configuration backup module

backup_pve() {
    local backup_component_path="$1"
    local status="success"
    local validation="{}"

    echo "Backing up Proxmox VE configuration..."
    
    # Create target directory if it doesn't exist
    mkdir -p "$backup_component_path/data"
    
    # Define the source directory for PVE config
    local source_dir="/etc/pve"
    local backup_file="$backup_component_path/data/pve_etc.tar.gz"
    
    # Backup PVE configuration files
    if tar czf "$backup_file" "$source_dir" 2>/dev/null; then
        echo "Successfully backed up PVE configuration"
        
        # Calculate validation data
        local backup_size=$(stat -c%s "$backup_file")
        local md5sum=$(md5sum "$backup_file" | cut -d' ' -f1)
        
        validation=$(cat << EOF
{
    "size": $backup_size,
    "files": [
        {
            "path": "data/pve_etc.tar.gz",
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
        echo "ERROR: Failed to backup PVE configuration"
        status="failed"
    fi
    
    # Additional PVE-specific files to backup
    local qemu_conf="/etc/libvirt/qemu.conf"
    if [ -f "$qemu_conf" ]; then
        mkdir -p "$backup_component_path/data/libvirt"
        cp "$qemu_conf" "$backup_component_path/data/libvirt/"
    fi
    
    # Backup cluster configuration if it exists
    local cluster_conf="/etc/cluster/cluster.conf"
    if [ -f "$cluster_conf" ]; then
        mkdir -p "$backup_component_path/data/cluster"
        cp "$cluster_conf" "$backup_component_path/data/cluster/"
    fi
    
    # Backup storage configuration
    local storage_cfg="/etc/pve/storage.cfg"
    if [ -f "$storage_cfg" ]; then
        mkdir -p "$backup_component_path/data/storage"
        cp "$storage_cfg" "$backup_component_path/data/storage/"
    fi
    
    # Update host status with this component's backup result
    update_component_status "pve" "$status" "config" "$validation"
}
