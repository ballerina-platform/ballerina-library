"""
Trigger the `build-with-java25.yml` workflow on the `java-25` branch
for every module in stdlib_modules.json (excluding generated_connectors and driver_modules).

Requires:
  - The java-25 branch to exist in each repo (run add_java25_workflows.py first)
  - `gh` CLI authenticated with write access to ballerina-platform

Usage:
    python3 trigger_java25_workflows.py
    python3 trigger_java25_workflows.py --from-module module-ballerina-io
    python3 trigger_java25_workflows.py --up-to-module module-ballerina-http
    python3 trigger_java25_workflows.py --dry-run
"""

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

from colorama import Fore, Style, init

init(autoreset=True)

SCRIPT_DIR = Path(__file__).parent
STDLIB_MODULES_JSON = SCRIPT_DIR.parent.parent / "release" / "resources" / "stdlib_modules.json"

GITHUB_ORG = "ballerina-platform"
WORKFLOW_FILE = "build-with-java25.yml"
BRANCH = "java-25"

# Pause between triggers to avoid hitting GitHub rate limits
TRIGGER_DELAY_SECONDS = 1


def main():
    parser = argparse.ArgumentParser(description="Trigger Java 25 test workflows")
    parser.add_argument("--from-module", help="Start from this module name")
    parser.add_argument("--up-to-module", help="Stop after this module name")
    parser.add_argument("--dry-run", action="store_true", help="Print commands without executing")
    parser.add_argument("--skip-modules", help="Comma-separated substrings of module names to skip")
    args = parser.parse_args()

    skip_patterns = []
    if args.skip_modules:
        skip_patterns = [s.strip() for s in args.skip_modules.split(",") if s.strip()]

    modules = load_modules()
    modules = filter_modules(modules, args.from_module, args.up_to_module, skip_patterns)

    info(f"Triggering workflows for {len(modules)} modules on branch '{BRANCH}'")
    if args.dry_run:
        warn("DRY RUN — no workflows will be triggered")

    triggered = []
    skipped = []

    for module in modules:
        name = module["name"]
        repo = f"{GITHUB_ORG}/{name}"
        cmd = ["gh", "workflow", "run", WORKFLOW_FILE, "--repo", repo, "--ref", BRANCH]

        if args.dry_run:
            info(f"[DRY RUN] {' '.join(cmd)}")
            triggered.append(name)
            continue

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            info(f"Triggered: {name}")
            triggered.append(name)
        else:
            stderr = result.stderr.strip()
            if "Could not find any workflows" in stderr or "does not have any workflow" in stderr:
                warn(f"No workflow found (branch not pushed yet?): {name}")
                skipped.append(name)
            else:
                warn(f"Failed to trigger {name}: {stderr}")
                skipped.append(name)

        time.sleep(TRIGGER_DELAY_SECONDS)

    print()
    info(f"Triggered: {len(triggered)}")
    if skipped:
        warn(f"Skipped / failed: {len(skipped)}")
        for s in skipped:
            warn(f"  - {s}")


def load_modules():
    with open(STDLIB_MODULES_JSON) as f:
        data = json.load(f)
    modules = []
    for category in ("library_modules", "extended_modules", "handwritten_connectors", "tools"):
        modules.extend(data.get(category, []))
    return modules


def filter_modules(modules, from_module, up_to_module, skip_patterns):
    result = []
    started = from_module is None
    for m in modules:
        name = m["name"]
        if not started:
            if name == from_module:
                started = True
            else:
                continue
        if any(pat in name for pat in skip_patterns):
            warn(f"Skipping: {name}")
            continue
        result.append(m)
        if up_to_module and name == up_to_module:
            break
    return result


def info(msg):
    print(f"{Fore.GREEN}[INFO] {msg}{Style.RESET_ALL}")


def warn(msg):
    print(f"{Fore.YELLOW}[WARN] {msg}{Style.RESET_ALL}")


if __name__ == "__main__":
    main()
