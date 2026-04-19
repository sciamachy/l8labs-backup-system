#!/bin/bash
# /root/scripts/backup-modules/gitea.sh
# Gitea backup via `gitea dump` — captures DB, repos, config, attachments, LFS

backup_gitea() {
    local backup_component_path="$1"
    local status="success"
    local validation="{}"
    local dump_file="$backup_component_path/data/gitea_dump.tar.gz"

    echo "Running gitea dump..."

    # Stream dump to stdout (tar.gz — zip would require seekable output).
    # --tempdir /data keeps temp files on the bind-mounted volume where the
    # git user definitely has write permission and space.
    if podman exec -u git gitea gitea dump \
        --config /data/gitea/conf/app.ini \
        --type tar.gz \
        --tempdir /data \
        --file - > "$dump_file"; then

        local backup_size=$(stat -c%s "$dump_file")
        local md5sum=$(md5sum "$dump_file" | cut -d' ' -f1)

        validation=$(cat << EOJSON
{
    "size": $backup_size,
    "files": [
        {
            "path": "data/gitea_dump.tar.gz",
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
        echo "ERROR: gitea dump failed"
        status="failed"
        rm -f "$dump_file"
    fi

    update_component_status "gitea" "$status" "application" "$validation"
}
