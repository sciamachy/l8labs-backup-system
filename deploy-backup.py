#!/usr/bin/env python3
"""Deploy backup script and modules to L8Labs Linux hosts.

Reads host configuration from deploy-config.json to determine which
modules belong on each host. Deploys the orchestrator (backup.sh) and
syncs the correct set of modules per host.

Existing scripts and modules are backed up with a timestamped suffix
before overwriting.
"""

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime

REPO_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE = os.path.join(REPO_DIR, "deploy-config.json")
SOURCE_SCRIPT = os.path.join(REPO_DIR, "backup.sh")
MODULES_DIR = os.path.join(REPO_DIR, "modules")
REMOTE_MODULES_DIR = "/root/scripts/backup-modules"

SSH_OPTS = ["-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=10"]


def load_config():
    """Load and return the deploy configuration."""
    if not os.path.exists(CONFIG_FILE):
        print(f"ERROR: Config not found: {CONFIG_FILE}", file=sys.stderr)
        sys.exit(1)
    with open(CONFIG_FILE) as f:
        return json.load(f)


def ssh_key(config):
    return os.path.expanduser(config["ssh_key"])


def ssh_cmd(key, host_cfg, command):
    """Build an SSH command list."""
    return [
        "ssh", "-i", key, *SSH_OPTS,
        f"{host_cfg['ssh_user']}@{host_cfg['fqdn']}",
        command,
    ]


def scp_cmd(key, local_path, host_cfg, remote_path):
    """Build an SCP command list."""
    return [
        "scp", "-i", key, *SSH_OPTS,
        local_path,
        f"{host_cfg['ssh_user']}@{host_cfg['fqdn']}:{remote_path}",
    ]


def run(cmd, dry_run=False, check=True):
    """Run a command, or print it in dry-run mode."""
    if dry_run:
        print(f"  [dry-run] {' '.join(cmd)}")
        return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if check and result.returncode != 0:
        print(f"  FAILED: {result.stderr.strip()}")
    return result


def maybe_sudo(host_cfg, command):
    """Prefix command with sudo if the host requires it."""
    if host_cfg["needs_sudo"]:
        return f"sudo {command}"
    return command


def upload_file(key, host_cfg, local_path, remote_path, dry_run=False):
    """Upload a file to a host, using sudo + temp file if needed."""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    if host_cfg["needs_sudo"]:
        tmp_path = f"/tmp/deploy_{os.path.basename(local_path)}_{timestamp}"
        result = run(scp_cmd(key, local_path, host_cfg, tmp_path), dry_run=dry_run)
        if not dry_run and result.returncode != 0:
            return False
        result = run(
            ssh_cmd(key, host_cfg, f"sudo cp {tmp_path} {remote_path} && rm {tmp_path}"),
            dry_run=dry_run,
        )
        if not dry_run and result.returncode != 0:
            return False
    else:
        result = run(scp_cmd(key, local_path, host_cfg, remote_path), dry_run=dry_run)
        if not dry_run and result.returncode != 0:
            return False
    return True


def check_connectivity(key, host_cfg, dry_run=False):
    """Verify SSH connectivity to a host."""
    result = run(ssh_cmd(key, host_cfg, "echo ok"), dry_run=dry_run)
    if not dry_run and (result.returncode != 0 or "ok" not in result.stdout):
        return False
    return True


def deploy_script(key, name, host_cfg, dry_run=False):
    """Deploy the orchestrator script to a host. Returns True on success."""
    script_path = host_cfg["script_path"]
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_path = f"{script_path}.bak.{timestamp}"

    # Back up existing script
    print(f"\n  Backing up {script_path}")
    result = run(
        ssh_cmd(key, host_cfg, maybe_sudo(host_cfg, f"cp {script_path} {backup_path}")),
        dry_run=dry_run,
    )
    if not dry_run and result.returncode != 0:
        print(f"  ERROR: Failed to back up existing script on {name}")
        return False

    # Upload new script
    print(f"  Uploading backup.sh -> {script_path}")
    if not upload_file(key, host_cfg, SOURCE_SCRIPT, script_path, dry_run):
        print(f"  ERROR: Failed to upload script to {name}")
        return False

    # Set ownership and permissions
    run(
        ssh_cmd(
            key, host_cfg,
            maybe_sudo(host_cfg, f"chown root:root {script_path}")
            + " && "
            + maybe_sudo(host_cfg, f"chmod 755 {script_path}"),
        ),
        dry_run=dry_run,
    )

    # Verify
    if not dry_run:
        result = run(
            ssh_cmd(
                key, host_cfg,
                maybe_sudo(host_cfg, f"grep -c 'ensure_backup_mount' {script_path}"),
            ),
            check=False,
        )
        if result.returncode != 0 or result.stdout.strip() in ("", "0"):
            print(f"  ERROR: Verification failed — ensure_backup_mount not found")
            return False
        print(f"  VERIFIED: ensure_backup_mount() present in deployed script")

    return True


def deploy_modules(key, name, host_cfg, dry_run=False):
    """Sync modules to a host. Returns True on success."""
    modules = host_cfg.get("modules", [])
    dummy_modules = host_cfg.get("dummy_modules", [])
    all_modules = modules + dummy_modules

    if not all_modules:
        print(f"  No modules configured for {name}, skipping")
        return True

    dummy_source = os.path.join(MODULES_DIR, "dummy.sh")

    # Ensure remote modules directory exists
    run(
        ssh_cmd(key, host_cfg, maybe_sudo(host_cfg, f"mkdir -p {REMOTE_MODULES_DIR}")),
        dry_run=dry_run,
    )

    # Get list of currently deployed modules
    result = run(
        ssh_cmd(key, host_cfg, maybe_sudo(host_cfg, f"ls {REMOTE_MODULES_DIR}/")),
        dry_run=dry_run, check=False,
    )
    remote_modules = set()
    if not dry_run and result.returncode == 0:
        remote_modules = {
            f.replace(".sh", "") for f in result.stdout.split() if f.endswith(".sh")
        }

    expected = set(all_modules)
    extra = remote_modules - expected

    if extra:
        print(f"  NOTE: Extra modules on {name} not in config: {', '.join(sorted(extra))}")
        print(f"        (leaving them in place)")

    # Upload real modules
    failed = []
    for module_name in sorted(modules):
        local_path = os.path.join(MODULES_DIR, f"{module_name}.sh")
        if not os.path.exists(local_path):
            print(f"  WARNING: Module {module_name}.sh not found in repo, skipping")
            failed.append(module_name)
            continue

        remote_path = f"{REMOTE_MODULES_DIR}/{module_name}.sh"
        print(f"  Deploying module: {module_name}.sh")
        if not upload_file(key, host_cfg, local_path, remote_path, dry_run):
            print(f"  ERROR: Failed to upload {module_name}.sh")
            failed.append(module_name)
            continue

        run(
            ssh_cmd(
                key, host_cfg,
                maybe_sudo(host_cfg, f"chown root:root {remote_path}")
                + " && "
                + maybe_sudo(host_cfg, f"chmod 755 {remote_path}"),
            ),
            dry_run=dry_run,
        )

    # Upload dummy modules (all use modules/dummy.sh as source)
    for module_name in sorted(dummy_modules):
        remote_path = f"{REMOTE_MODULES_DIR}/{module_name}.sh"
        print(f"  Deploying module: {module_name}.sh (dummy)")
        if not upload_file(key, host_cfg, dummy_source, remote_path, dry_run):
            print(f"  ERROR: Failed to upload {module_name}.sh")
            failed.append(module_name)
            continue

        run(
            ssh_cmd(
                key, host_cfg,
                maybe_sudo(host_cfg, f"chown root:root {remote_path}")
                + " && "
                + maybe_sudo(host_cfg, f"chmod 755 {remote_path}"),
            ),
            dry_run=dry_run,
        )

    total = len(modules) + len(dummy_modules)
    if failed:
        print(f"  WARNING: Failed modules: {', '.join(failed)}")
        return False

    print(f"  All {total} modules deployed ({len(modules)} real, {len(dummy_modules)} dummy)")
    return True


def deploy_host(key, name, host_cfg, deploy_what, dry_run=False):
    """Deploy to a single host. Returns True on success."""
    print(f"\n{'=' * 60}")
    print(f"Deploying to {name} ({host_cfg['fqdn']})")
    print(f"  Script: {host_cfg['script_path']}")
    print(f"  Modules: {', '.join(host_cfg.get('modules', []))}")
    print(f"  SSH: {host_cfg['ssh_user']}"
          f"{'  (sudo)' if host_cfg['needs_sudo'] else ''}")
    print(f"  Scope: {deploy_what}")
    print(f"{'=' * 60}")

    # Check connectivity
    print(f"\n  Checking connectivity...")
    if not check_connectivity(key, host_cfg, dry_run):
        print(f"  ERROR: Cannot reach {name}")
        return False
    print(f"  Connected")

    script_ok = True
    modules_ok = True

    if deploy_what in ("all", "script"):
        print(f"\n  --- Orchestrator Script ---")
        script_ok = deploy_script(key, name, host_cfg, dry_run)

    if deploy_what in ("all", "modules"):
        print(f"\n  --- Modules ---")
        modules_ok = deploy_modules(key, name, host_cfg, dry_run)

    success = script_ok and modules_ok
    status = "SUCCESS" if success else "PARTIAL" if (script_ok or modules_ok) else "FAILED"
    print(f"\n  {status}: {name}")
    return success


def main():
    config = load_config()
    hosts = config["hosts"]

    parser = argparse.ArgumentParser(
        description="Deploy backup script and modules to L8Labs Linux hosts.",
        epilog=(
            "examples:\n"
            "  %(prog)s                          Deploy script + modules to all hosts\n"
            "  %(prog)s podman-srv1               Deploy to podman-srv1 only\n"
            "  %(prog)s --modules-only            Deploy only modules to all hosts\n"
            "  %(prog)s --script-only bas1        Deploy only the script to bas1\n"
            "  %(prog)s --dry-run                 Show what would be done\n"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "host",
        nargs="?",
        choices=list(hosts.keys()),
        metavar="HOST",
        help=f"Deploy to a specific host. Choices: {', '.join(hosts.keys())}. "
        "Omit to deploy to all hosts.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show commands that would run without making changes.",
    )
    parser.add_argument(
        "--script-only",
        action="store_true",
        help="Deploy only the orchestrator script, skip modules.",
    )
    parser.add_argument(
        "--modules-only",
        action="store_true",
        help="Deploy only modules, skip the orchestrator script.",
    )
    args = parser.parse_args()

    if args.script_only and args.modules_only:
        parser.error("--script-only and --modules-only are mutually exclusive")

    if not os.path.exists(SOURCE_SCRIPT):
        print(f"ERROR: Source script not found: {SOURCE_SCRIPT}", file=sys.stderr)
        sys.exit(1)

    deploy_what = "all"
    if args.script_only:
        deploy_what = "script"
    elif args.modules_only:
        deploy_what = "modules"

    targets = {args.host: hosts[args.host]} if args.host else hosts
    key = ssh_key(config)

    print(f"Config:  {CONFIG_FILE}")
    print(f"Source:  {SOURCE_SCRIPT}")
    print(f"Modules: {MODULES_DIR}")
    print(f"Targets: {', '.join(targets.keys())}")
    print(f"Scope:   {deploy_what}")
    if args.dry_run:
        print("Mode:    DRY RUN (no changes will be made)")

    results = {}
    for name, cfg in targets.items():
        results[name] = deploy_host(key, name, cfg, deploy_what, dry_run=args.dry_run)

    # Summary
    print(f"\n{'=' * 60}")
    print("Deployment Summary")
    print(f"{'=' * 60}")
    for name, success in results.items():
        status = "OK" if success else "FAILED"
        print(f"  {name:20s} {status}")

    if not all(results.values()):
        sys.exit(1)


if __name__ == "__main__":
    main()
