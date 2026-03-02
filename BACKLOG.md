# L8Labs Backup System - Backlog

This document tracks technical debt, future features, and known issues that aren't part of the current sprint.

## Technical Debt

### Hardcoded credentials in backup modules
**Added:** 2026-02-28
**Status:** Ready to implement

`modules/mariadb.sh` contains hardcoded `DB_USER` and `DB_PASS` values. `modules/influxdb.sh` contains a hardcoded `INFLUXDB_TOKEN`.

**Context:** Credentials were embedded directly in the scripts for simplicity during initial development.

**Action:** Move credentials to a separate config file (e.g., `/etc/backup-credentials.conf`) that is excluded from version control. Source it at runtime.

**Reference:** `modules/mariadb.sh:6-7`, `modules/influxdb.sh:5`

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

## Pending Verification

### Confirm shebang fix resolves backup failures on all hosts
**Added:** 2026-03-02
**Verify after:** 2026-03-03 1:00 AM (next cron run)

Blank line before shebang caused backups to run under dash instead of bash. Fix deployed to all 4 hosts on 2026-03-02. Need to confirm:
- [ ] prox1: `host_status.json` shows `success` (was the host that reported the error)
- [ ] podman-srv1: backup completed successfully
- [ ] podman-db1: backup completed successfully
- [ ] bas1: backup completed successfully

**How to check:** Review `host_status.json` on each host's backup share, or check the monitoring stack for backup status after 1 AM.

---

## Resolved Items

### All Linux hosts upgraded to v3.0.0
**Added:** 2026-02-28
**Resolved:** 2026-03-01

Three hosts (`bas1`, `podman-db1`, `podman-srv1`) were on v2.0.0 and vulnerable to silent backup failures when CIFS mounts drop.

**Resolution:** Deployed v3 to all hosts via `deploy-backup.py`. Also redeployed prox1 to sync script and modules from repo.

---

### Module filename/function name mismatch
**Added:** 2026-02-28
**Resolved:** 2026-02-28

Repo files `proxmox-pve.sh` and `proxmox-network.sh` didn't match their function names `backup_pve()` and `backup_network()`.

**Resolution:** Renamed repo files back to `pve.sh` and `network.sh` to match what's deployed on prox1 and the function names.

---

### Blank line before shebang broke all host backups
**Added:** 2026-03-02
**Resolved:** 2026-03-02

`backup.sh` had a blank line 1, pushing `#!/bin/bash` to line 2. The kernel didn't find the shebang, so cron ran the script under `/bin/sh` (dash on Debian). Dash can't handle bash arrays (`local arr=()`), causing `Syntax error: "(" unexpected` on prox1 and likely silent failures on other hosts.

**Resolution:** Removed the blank line so the shebang is on line 1. Redeployed to all 4 hosts with `deploy-backup.py --script-only`.

---

## Usage Guidelines

- **Technical Debt**: Code that works but needs improvement (patches, workarounds, temporary fixes)
- **Future Features**: Ideas that aren't urgent but would add value
- **Known Issues**: Bugs or problems that aren't blocking but should be tracked
- **Resolved Items**: Archive of completed items (preserve for historical context)

When starting a new sprint, review this backlog and promote items to CURRENT_SPRINT.md as appropriate.
