# L8Labs Backup System - Backlog

This document tracks technical debt, future features, and known issues that aren't part of the current sprint.

## Technical Debt

### Hardcoded database credentials in mariadb module
**Added:** 2026-02-28
**Status:** Ready to implement

The `modules/mariadb.sh` file contains hardcoded `DB_USER` and `DB_PASS` values in plain text.

**Context:** Credentials were embedded directly in the script for simplicity during initial development.

**Action:** Move credentials to a separate config file (e.g., `/etc/backup-credentials.conf`) that is excluded from version control. Source it at runtime.

**Reference:** `modules/mariadb.sh:6-7`

---

### Module filename/function name mismatch
**Added:** 2026-02-28
**Status:** Ready to implement

`proxmox-pve.sh` defines `backup_pve()` and `proxmox-network.sh` defines `backup_network()`. The orchestrator derives the expected function name from the filename, so it looks for `backup_proxmox-pve()` and `backup_proxmox-network()`, which don't exist. These modules silently fall back to config-only backup on deployment.

**Context:** The files were originally named `pve.sh` and `network.sh` (per their in-file comments) and were renamed in the repo without updating the function names.

**Action:** Either rename files back to `pve.sh`/`network.sh`, or rename the functions to `backup_proxmox-pve()`/`backup_proxmox-network()`. Also update the in-file path comments.

**Reference:** `modules/proxmox-pve.sh:4`, `modules/proxmox-network.sh:4`, `backup.sh:274`

---

### Deployment tracking shows hosts on v2.0.0
**Added:** 2026-02-28
**Status:** Needs investigation

Three hosts (`bas1`, `podman-db1`, `podman-srv1`) are still on v2.0.0 per `backup-deployment-tracking.md`. The v3 upgrade plan has no scheduled dates.

**Context:** v3.0.0 added automatic mount point validation which fixes boot-time mount issues that `podman-srv1` has experienced.

**Action:** Schedule and execute v3 upgrades, prioritizing `podman-srv1`.

**Reference:** `backup-deployment-tracking.md`

---

## Future Features

### Selective module enablement via command-line arguments
**Added:** 2026-02-28
**Priority:** Low

Allow running specific modules via CLI args (e.g., `backup.sh --only mariadb grafana`) for ad-hoc or debug runs, without needing to modify `/etc/backup-modules.conf`.

**Value:** Simplifies testing individual modules and manual recovery scenarios.

**Dependencies:** None

---

### Pre/post backup hooks
**Added:** 2026-02-28
**Priority:** Low

Support optional `pre_backup_<module>()` and `post_backup_<module>()` functions in modules for actions like stopping services before backup or restarting after.

**Value:** Some services (e.g., databases without hot-backup support) need quiescence for consistent backups.

**Dependencies:** None

---

### Backup verification/restore test module
**Added:** 2026-02-28
**Priority:** Medium

A module or standalone script that periodically validates backup integrity by testing decompression and/or restoring to a scratch area.

**Value:** Detects silent backup corruption before a real restore is needed.

**Dependencies:** None

---

## Known Issues

### No error handling for missing jq during module execution
**Added:** 2026-02-28
**Severity:** Low

The `jq` dependency check happens at script start, but if `jq` is removed or unavailable mid-execution (e.g., on a network-mounted binary), `update_component_status` calls will fail silently with corrupted JSON.

**Workaround:** Ensure `jq` is installed locally (not via network mount).

**Root Cause:** Single upfront dependency check with no runtime guards.

---

### OpenHAB incremental backups may produce empty archives
**Added:** 2026-02-28
**Severity:** Low

The `--newer-mtime "1 day ago"` flag in `modules/openhab.sh` can produce empty tar archives if no files changed. These are still recorded as successful with size 0.

**Workaround:** None needed operationally; full backups run every Sunday.

**Root Cause:** `tar` exits 0 for empty archives, and the module doesn't check for minimum size.

---

## Resolved Items

*Move completed backlog items here with resolution date and notes*

---

## Usage Guidelines

- **Technical Debt**: Code that works but needs improvement (patches, workarounds, temporary fixes)
- **Future Features**: Ideas that aren't urgent but would add value
- **Known Issues**: Bugs or problems that aren't blocking but should be tracked
- **Resolved Items**: Archive of completed items (preserve for historical context)

When starting a new sprint, review this backlog and promote items to CURRENT_SPRINT.md as appropriate.
