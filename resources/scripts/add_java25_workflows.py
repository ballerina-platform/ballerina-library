"""
Add Java 25 test workflows to all Ballerina library repos.

For each module in stdlib_modules.json (excluding generated_connectors):
  1. Clone the repo if not present
  2. Create and push a `java-25` branch
  3. Add .github/workflows/build-with-java25.yml
  4. Commit and push

The workflow file calls the appropriate centralized template from
ballerina-platform/ballerina-library@java-25 based on whether the repo
currently uses pr-build-connector-template.yml or the standard one.

Usage:
    python3 add_java25_workflows.py <path>
    python3 add_java25_workflows.py <path> --from-module module-ballerina-io
    python3 add_java25_workflows.py <path> --up-to-module module-ballerina-http
    python3 add_java25_workflows.py <path> --dry-run
"""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

from colorama import Fore, Style

SCRIPT_DIR = Path(__file__).parent
STDLIB_MODULES_JSON = SCRIPT_DIR.parent.parent / "release" / "resources" / "stdlib_modules.json"

JAVA25_BRANCH = "java-25"
GITHUB_ORG = "ballerina-platform"

STANDARD_TEMPLATE = "ballerina-platform/ballerina-library/.github/workflows/build-with-java25-template.yml@java-25"
CONNECTOR_TEMPLATE = "ballerina-platform/ballerina-library/.github/workflows/build-with-java25-connector-template.yml@java-25"

STANDARD_TEMPLATE_MARKER = "pull-request-build-template.yml"
CONNECTOR_TEMPLATE_MARKER = "pr-build-connector-template.yml"

WORKFLOW_FILE = ".github/workflows/build-with-java25.yml"

STANDARD_WORKFLOW = """\
name: Build with Java 25

on:
  workflow_dispatch:

jobs:
  build:
    uses: {template}
    secrets: inherit
"""

CONNECTOR_WORKFLOW = """\
name: Build with Java 25

on:
  workflow_dispatch:

jobs:
  build:
    uses: {template}
    secrets: inherit
"""


def main():
    parser = argparse.ArgumentParser(description="Add Java 25 test workflows to Ballerina library repos")
    parser.add_argument("path", help="Directory where repos are (or will be) cloned")
    parser.add_argument("--from-module", help="Start processing from this module name")
    parser.add_argument("--up-to-module", help="Stop processing after this module name")
    parser.add_argument("--dry-run", action="store_true", help="Print actions without executing git operations")
    parser.add_argument("--continue-on-error", action="store_true", help="Continue even if a repo fails")
    parser.add_argument("--skip-modules", help="Comma-separated list of module name substrings to skip")
    args = parser.parse_args()

    repo_dir = Path(args.path)
    if not repo_dir.exists():
        repo_dir.mkdir(parents=True)

    os.chdir(repo_dir)

    skip_patterns = []
    if args.skip_modules:
        skip_patterns = [s.strip() for s in args.skip_modules.split(",") if s.strip()]

    modules = load_modules()
    modules = filter_modules(modules, args.from_module, args.up_to_module, skip_patterns)

    info(f"Processing {len(modules)} modules")
    if args.dry_run:
        warn("DRY RUN — no git operations will be executed")

    failures = []
    for module in modules:
        name = module["name"]
        default_branch = module.get("default_branch", "master")
        try:
            process_module(name, default_branch, repo_dir, args.dry_run)
        except Exception as e:
            error_msg = f"{name}: {e}"
            if args.continue_on_error:
                warn(f"FAILED (continuing): {error_msg}")
                failures.append(error_msg)
            else:
                err(f"FAILED: {error_msg}")

    print()
    if failures:
        warn(f"{len(failures)} module(s) failed:")
        for f in failures:
            warn(f"  - {f}")
    else:
        info("All modules processed successfully")


def load_modules():
    with open(STDLIB_MODULES_JSON) as f:
        data = json.load(f)

    # Collect all categories except generated_connectors and driver_modules
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
            warn(f"Skipping (pattern match): {name}")
            continue

        result.append(m)

        if up_to_module and name == up_to_module:
            break

    return result


def process_module(name, default_branch, repo_dir, dry_run):
    print()
    print("=" * 60)
    info(f"Processing: {name}")

    module_path = repo_dir / name

    # Clone if missing
    if not module_path.exists():
        info(f"Cloning {name}...")
        clone_url = f"https://github.com/{GITHUB_ORG}/{name}.git"
        run(["git", "clone", clone_url], dry_run=False)  # always clone

    os.chdir(module_path)

    try:
        # Fetch latest
        run(["git", "fetch", "origin"], dry_run=False)

        # Check out the default branch and reset to origin
        run(["git", "checkout", default_branch], dry_run=False)
        run(["git", "reset", "--hard", f"origin/{default_branch}"], dry_run=False)

        # Create or reset the java-25 branch
        branch_exists = branch_exists_on_origin(JAVA25_BRANCH)
        if branch_exists:
            info(f"Branch {JAVA25_BRANCH} already exists on origin — checking out and resetting")
            run(["git", "checkout", JAVA25_BRANCH], dry_run=False)
            run(["git", "reset", "--hard", f"origin/{JAVA25_BRANCH}"], dry_run=False)
        else:
            info(f"Creating branch {JAVA25_BRANCH} from {default_branch}")
            run(["git", "checkout", "-b", JAVA25_BRANCH], dry_run=dry_run)

        # Determine which template to use
        template = pick_template(module_path)
        info(f"Using template: {template}")

        # Write the workflow file
        workflow_path = module_path / WORKFLOW_FILE
        workflow_path.parent.mkdir(parents=True, exist_ok=True)

        content = STANDARD_WORKFLOW.format(template=template)
        if dry_run:
            info(f"[DRY RUN] Would write {WORKFLOW_FILE}")
        else:
            workflow_path.write_text(content)
            info(f"Written: {WORKFLOW_FILE}")

        # Commit and push only if there are actual changes
        run(["git", "add", WORKFLOW_FILE], dry_run=dry_run)

        staged = subprocess.run(["git", "diff", "--cached", "--quiet"])
        if staged.returncode == 0:
            info(f"Workflow already up to date on {JAVA25_BRANCH}, skipping commit: {name}")
        else:
            run(["git", "commit", "-m", "Add Java 25 compatibility test workflow"], dry_run=dry_run)
            run(["git", "push", "origin", JAVA25_BRANCH], dry_run=dry_run)

        info(f"Done: {name}")
    finally:
        os.chdir(repo_dir)


def pick_template(module_path):
    """Return the centralized template URL to use.

    Scans every workflow file under .github/workflows/ for a reference to
    any centralized ballerina-library template. If any file calls the connector
    template, the connector variant is returned. Returns the standard template
    if no workflow files are found or none reference a connector template.
    """
    workflows_dir = module_path / ".github" / "workflows"
    if not workflows_dir.is_dir():
        warn(f"No .github/workflows/ directory found in {module_path.name}, defaulting to standard template")
        return STANDARD_TEMPLATE

    yml_files = list(workflows_dir.glob("*.yml")) + list(workflows_dir.glob("*.yaml"))
    # Exclude the file we are about to write
    yml_files = [f for f in yml_files if f.name != Path(WORKFLOW_FILE).name]

    if not yml_files:
        warn(f"No existing workflow files found in {module_path.name}, defaulting to standard template")
        return STANDARD_TEMPLATE

    found_standard = False
    for wf_file in yml_files:
        try:
            content = wf_file.read_text()
            if CONNECTOR_TEMPLATE_MARKER in content:
                return CONNECTOR_TEMPLATE
            if STANDARD_TEMPLATE_MARKER in content:
                found_standard = True
        except OSError:
            continue

    if not found_standard:
        warn(f"Neither PR build template reference found in {module_path.name}, defaulting to standard template")
    return STANDARD_TEMPLATE


def branch_exists_on_origin(branch):
    result = subprocess.run(
        ["git", "ls-remote", "--heads", "origin", branch],
        capture_output=True, text=True
    )
    return bool(result.stdout.strip())


def run(cmd, dry_run=False):
    if dry_run:
        info(f"[DRY RUN] {' '.join(cmd)}")
        return
    result = subprocess.run(cmd)
    if result.returncode != 0:
        raise RuntimeError(f"Command failed (exit {result.returncode}): {' '.join(cmd)}")


def info(msg):
    print(f"{Fore.GREEN}[INFO] {msg}{Style.RESET_ALL}")


def warn(msg):
    print(f"{Fore.YELLOW}[WARN] {msg}{Style.RESET_ALL}")


def err(msg):
    print(f"{Fore.RED}[ERROR] {msg}{Style.RESET_ALL}")
    sys.exit(1)


if __name__ == "__main__":
    main()
