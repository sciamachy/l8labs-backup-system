# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

L8Labs Modular Backup System — a bash-based backup framework deployed on Linux servers. Developed on Windows, deployed to Linux targets via manual copy. There is no build system, test framework, or CI pipeline.

The companion monitoring stack lives at `C:\Users\da_bi\Claude_Workspace\l8labs-monitoring-stack` and consumes the `host_status.json` files this system produces via `backup_exporter.py`.

## Architecture

**`backup.sh`** is the orchestrator. It:
1. Validates and mounts the CIFS backup share at `/mnt/backup`
2. Discovers module files from `/root/scripts/backup-modules/*.sh`
3. Sources each module, then calls `backup_<module_name>()` where `<module_name>` is the filename without `.sh`
4. Writes `host_status.json` with per-component results (the monitoring integration contract)
5. Cleans up backups older than 30 days

**Modules** (in `modules/`) are sourced into the main script's shell. They share all variables and helper functions from `backup.sh`, notably:
- `update_component_status <name> <status> <type> <validation_json>` — reports results
- `BACKUP_PATH`, `DATE`, `HOST_NAME` — available globals

### Critical naming rule

The module **filename** determines the function name the orchestrator calls. A file named `foo.sh` must define `backup_foo()`. If these don't match, the module silently falls back to config-only backup.

**Current issue:** The repo files `proxmox-pve.sh` and `proxmox-network.sh` define `backup_pve()` and `backup_network()` respectively. Their in-file comments show the original deployed names were `pve.sh` and `network.sh`. When deploying, either rename the files back or rename the functions to `backup_proxmox-pve` / `backup_proxmox-network`.

### Module patterns

Modules fall into three categories:
- **Container-based** (mariadb, grafana, prometheus): use `podman exec` or `podman cp` to extract data from running containers
- **Filesystem-based** (openhab, zigbee2mqtt, proxmox-*): tar/copy files directly from the host
- **Config-only** (dummy modules): no `backup_*` function; the orchestrator auto-copies from `/etc/containers/<name>` and `/etc/<name>`

All modules produce a validation JSON with `size`, `files` (array of path/size/md5), and `checks`.

### host_status.json contract

This JSON file at `/mnt/backup/host_status.json` is consumed by the monitoring stack's `backup_exporter.py` to expose Prometheus metrics. Its schema (`host`, `backup_id`, `timestamp`, `status`, `components`, `metrics`) must remain stable. The Windows host "advantage" writes the same format via a separate restic-based approach.

## Deployment

There is no automated deployment. Files are manually copied to target servers:
```bash
# Main script
cp backup.sh /root/scripts/backup.sh

# Modules
cp modules/*.sh /root/scripts/backup-modules/
chmod +x /root/scripts/backup.sh /root/scripts/backup-modules/*.sh
```

Runs via cron at 1 AM daily. Requires `jq` and Bash 4+. See `backup-deployment-tracking.md` for per-server version status.

## Selective module control

If `/etc/backup-modules.conf` exists on a target host, only modules listed there (one per line) will run. Otherwise all discovered modules run.

## Shell scripting conventions

- All scripts use `#!/bin/bash` and target Bash 4+
- Use `local` for function variables
- Heredocs for building JSON (no jq for construction, only jq for mutation in the orchestrator)
- `stat -c%s` for file sizes, `md5sum` for checksums (Linux coreutils)
- Error status values: `"success"`, `"failed"`, `"partial_failure"`

## Security note

The mariadb module contains hardcoded database credentials. These should eventually be moved to a separate config file excluded from version control.
