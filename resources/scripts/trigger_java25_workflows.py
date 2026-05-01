"""
Trigger the `build-with-java25.yml` workflow on the `java-25` branch
for every module in stdlib_modules.json (excluding generated_connectors and driver_modules).

GitHub's workflow_dispatch event only works when the workflow file exists on the
default branch. Because build-with-java25.yml lives exclusively on the java-25
branch, we trigger it instead by creating an empty commit on that branch via the
GitHub Git API. This fires the push event and starts the workflow without needing
a local clone.

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

        ok, detail = push_empty_commit(repo, BRANCH, dry_run=args.dry_run)
        if ok:
            info(f"Triggered: {name}  ({detail})")
            triggered.append(name)
        else:
            warn(f"Failed to trigger {name}: {detail}")
            skipped.append(name)

        time.sleep(TRIGGER_DELAY_SECONDS)

    print()
    info(f"Triggered: {len(triggered)}")
    if skipped:
        warn(f"Skipped / failed: {len(skipped)}")
        for s in skipped:
            warn(f"  - {s}")


def push_empty_commit(repo, branch, dry_run=False):
    """Trigger push-event workflows by creating an empty commit on the branch.

    Returns (success: bool, detail: str).
    """
    # Step 1: resolve current branch HEAD
    r = subprocess.run(
        ["gh", "api", f"/repos/{repo}/git/ref/heads/{branch}"],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        return False, f"branch not found: {r.stderr.strip()}"
    current_sha = json.loads(r.stdout)["object"]["sha"]

    # Step 2: get tree SHA from that commit
    r = subprocess.run(
        ["gh", "api", f"/repos/{repo}/git/commits/{current_sha}"],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        return False, f"commit lookup failed: {r.stderr.strip()}"
    tree_sha = json.loads(r.stdout)["tree"]["sha"]

    if dry_run:
        return True, f"[DRY RUN] would push empty commit (tree={tree_sha[:7]}, parent={current_sha[:7]})"

    # Step 3: create an empty commit (same tree, new message)
    r = subprocess.run(
        [
            "gh", "api", "--method", "POST",
            f"/repos/{repo}/git/commits",
            "-f", "message=chore: trigger Java 25 build [ci]",
            "-f", f"tree={tree_sha}",
            "-f", f"parents[]={current_sha}",
        ],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        return False, f"commit creation failed: {r.stderr.strip()}"
    new_sha = json.loads(r.stdout)["sha"]

    # Step 4: advance the branch ref
    r = subprocess.run(
        [
            "gh", "api", "--method", "PATCH",
            f"/repos/{repo}/git/refs/heads/{branch}",
            "-f", f"sha={new_sha}",
        ],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        return False, f"ref update failed: {r.stderr.strip()}"

    return True, f"empty commit {new_sha[:7]}"


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
