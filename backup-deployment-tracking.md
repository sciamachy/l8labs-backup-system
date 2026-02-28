# Backup Script Deployment Tracking

This document tracks which servers are running specific versions of the backup script system.

## Current Deployment Status

### Linux Hosts (bash backup framework)

| Server | Version | Last Updated | Notes |
|--------|---------|--------------|-------|
| bas1.bas.l8labs.ca | v2.0.0 | 2025-05-03 | |
| podman-db1.is.l8labs.ca | v2.0.0 | 2025-05-03 | |
| podman-srv1.is.l8labs.ca | v2.0.0 | 2025-05-03 | |
| prox1.is.l8labs.ca | v3.0.0 | 2025-05-03 | Testing mount improvements |

### Windows (restic-based, separate approach)

| Host | Method | Schedule | Added | Notes |
|------|--------|----------|-------|-------|
| advantage | Restic (PowerShell) | Daily 1 AM | 2026-02-28 | 7d/4w/3m retention. See [l8labs-monitoring-stack](https://github.com/sciamachy/l8labs-monitoring-stack) |

## v3 Upgrade Plan

| Server | Target Version | Planned Date | Priority | Notes |
|--------|---------------|--------------|----------|-------|
| bas1.bas.l8labs.ca | v3.0.0 | TBD | Medium | |
| podman-db1.is.l8labs.ca | v3.0.0 | TBD | Medium | |
| podman-srv1.is.l8labs.ca | v3.0.0 | TBD | High | Has experienced mount issues during boot |

