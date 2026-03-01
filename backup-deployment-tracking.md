# Backup Script Deployment Tracking

This document tracks which servers are running specific versions of the backup script system.

## Current Deployment Status

### Linux Hosts (bash backup framework)

| Server | Version | Last Updated | Notes |
|--------|---------|--------------|-------|
| bas1.bas.l8labs.ca | v3.0.0 | 2026-03-01 | Upgraded from v2 via deploy-backup.py |
| podman-db1.is.l8labs.ca | v3.0.0 | 2026-03-01 | Upgraded from v2 via deploy-backup.py |
| podman-srv1.is.l8labs.ca | v3.0.0 | 2026-03-01 | Upgraded from v2 via deploy-backup.py |
| prox1.is.l8labs.ca | v3.0.0 | 2026-03-01 | Script + modules redeployed via deploy-backup.py |

### Windows (restic-based, separate approach)

| Host | Method | Schedule | Added | Notes |
|------|--------|----------|-------|-------|
| advantage | Restic (PowerShell) | Daily 1 AM | 2026-02-28 | 7d/4w/3m retention. See [l8labs-monitoring-stack](https://github.com/sciamachy/l8labs-monitoring-stack) |

## v3 Upgrade Plan

All Linux hosts upgraded to v3.0.0 on 2026-03-01. No outstanding upgrades.
