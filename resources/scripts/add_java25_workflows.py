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
import re
import subprocess
import sys
from pathlib import Path

from colorama import Fore, Style

SCRIPT_DIR = Path(__file__).parent
STDLIB_MODULES_JSON = SCRIPT_DIR.parent.parent / "release" / "resources" / "stdlib_modules.json"

JAVA25_BRANCH = "java-25"
BASE_BRANCH = "2201.12.x"
GITHUB_ORG = "ballerina-platform"
BALLERINA_GRADLE_PLUGIN_VERSION = "2.3.1"

STANDARD_TEMPLATE = "ballerina-platform/ballerina-library/.github/workflows/build-with-java25-template.yml@java-25"
CONNECTOR_TEMPLATE = "ballerina-platform/ballerina-library/.github/workflows/build-with-java25-connector-template.yml@java-25"

STANDARD_TEMPLATE_MARKER = "pull-request-build-template.yml"
CONNECTOR_TEMPLATE_MARKER = "pr-build-connector-template.yml"

WORKFLOW_FILE = ".github/workflows/build-with-java25.yml"

STANDARD_WORKFLOW = """\
name: Build with Java 25

on:
  push:
    branches:
      - java-25

jobs:
  build:
    uses: {template}
    secrets: inherit
"""

CONNECTOR_WORKFLOW = """\
name: Build with Java 25

on:
  push:
    branches:
      - java-25

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
    parser.add_argument("--distribution-repo", help="Path to ballerina-distribution repo (default: <path>/ballerina-distribution)")
    args = parser.parse_args()

    repo_dir = Path(args.path).resolve()
    if not repo_dir.exists():
        repo_dir.mkdir(parents=True)

    dist_repo = Path(args.distribution_repo).resolve() if args.distribution_repo else repo_dir / "ballerina-distribution"
    gradle_versions = load_gradle_properties(dist_repo)

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
        version_key = module.get("version_key")
        try:
            process_module(name, default_branch, version_key, gradle_versions, repo_dir, args.dry_run)
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


def load_gradle_properties(dist_repo_path):
    props_file = dist_repo_path / "gradle.properties"
    if not props_file.exists():
        err(f"gradle.properties not found at {props_file}")
    versions = {}
    with open(props_file) as f:
        for line in f:
            line = line.strip()
            if "=" in line and not line.startswith("#"):
                key, _, value = line.partition("=")
                versions[key.strip()] = value.strip()
    return versions


def get_version_tag(version_key, gradle_versions):
    if not version_key:
        return None
    version = gradle_versions.get(version_key)
    if not version:
        return None
    return f"v{version}"


def tag_exists_on_origin(tag):
    result = subprocess.run(
        ["git", "ls-remote", "--tags", "origin", tag],
        capture_output=True, text=True
    )
    return bool(result.stdout.strip())


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


def process_module(name, default_branch, version_key, gradle_versions, repo_dir, dry_run):
    print()
    print("=" * 60)
    info(f"Processing: {name}")

    module_path = repo_dir / name

    # Clone if missing
    if not module_path.exists():
        info(f"Cloning {name}...")
        clone_url = f"https://github.com/{GITHUB_ORG}/{name}.git"
        run(["git", "clone", clone_url], dry_run=False)

    os.chdir(module_path)

    try:
        run(["git", "fetch", "origin"], dry_run=False)

        # Determine base: use 2201.12.x branch if it exists, otherwise create it from the
        # module's release tag found in ballerina-distribution/gradle.properties, or fall
        # back to the default branch if neither is available.
        if branch_exists_on_origin(BASE_BRANCH):
            info(f"Using existing {BASE_BRANCH} branch")
            run(["git", "checkout", BASE_BRANCH], dry_run=False)
            run(["git", "reset", "--hard", f"origin/{BASE_BRANCH}"], dry_run=False)
        else:
            tag = get_version_tag(version_key, gradle_versions)
            if tag and tag_exists_on_origin(tag):
                base_ref = tag
                info(f"Branch {BASE_BRANCH} not found — creating from tag {tag}")
            else:
                if tag:
                    warn(f"Branch {BASE_BRANCH} not found and tag {tag} not found on origin — falling back to default branch")
                else:
                    warn(f"Branch {BASE_BRANCH} not found and no version tag available — falling back to default branch")
                run(["git", "checkout", default_branch], dry_run=False)
                run(["git", "reset", "--hard", f"origin/{default_branch}"], dry_run=False)
                base_ref = default_branch
            # Always do the local checkout so pick_template() can read the repo state.
            run(["git", "checkout", "-b", BASE_BRANCH, base_ref], dry_run=False)
            run(["git", "push", "origin", BASE_BRANCH], dry_run=dry_run)

        # Determine which template to use by inspecting the 2201.12.x state.
        # 2201.12.x is read-only here — the workflow is never committed to it.
        template = pick_template(module_path)
        info(f"Using template: {template}")

        workflow_path = module_path / WORKFLOW_FILE
        content = STANDARD_WORKFLOW.format(template=template)

        # Create java-25 from 2201.12.x (clean, no workflow yet), then add the workflow there.
        if branch_exists_on_origin(JAVA25_BRANCH):
            info(f"Branch {JAVA25_BRANCH} already exists on origin — deleting and recreating from {BASE_BRANCH}")
            run(["git", "push", "origin", "--delete", JAVA25_BRANCH], dry_run=dry_run)
        info(f"Creating branch {JAVA25_BRANCH} from {BASE_BRANCH}")
        run(["git", "checkout", "-b", JAVA25_BRANCH], dry_run=dry_run)

        workflow_path.parent.mkdir(parents=True, exist_ok=True)
        if dry_run:
            info(f"[DRY RUN] Would write {WORKFLOW_FILE} to {JAVA25_BRANCH}")
        else:
            workflow_path.write_text(content)
            info(f"Written: {WORKFLOW_FILE}")

        run(["git", "add", str(workflow_path)], dry_run=dry_run)

        patch_gradle_properties(module_path, dry_run)
        run(["git", "add", str(module_path / "gradle.properties")], dry_run=dry_run)

        staged = subprocess.run(["git", "diff", "--cached", "--quiet"])
        if staged.returncode == 0:
            info(f"Nothing changed on {JAVA25_BRANCH}, skipping commit")
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


def patch_gradle_properties(module_path, dry_run):
    """Ensure ballerinaGradlePluginVersion is set to BALLERINA_GRADLE_PLUGIN_VERSION.

    Returns True if the file was (or would be) modified.
    """
    props_file = module_path / "gradle.properties"
    if not props_file.exists():
        warn("gradle.properties not found — skipping plugin version patch")
        return False

    content = props_file.read_text()
    match = re.search(r"^ballerinaGradlePluginVersion\s*=\s*(.+)$", content, re.MULTILINE)
    if not match:
        warn("ballerinaGradlePluginVersion not found in gradle.properties — skipping")
        return False

    current = match.group(1).strip()
    if current == BALLERINA_GRADLE_PLUGIN_VERSION:
        info(f"ballerinaGradlePluginVersion already {BALLERINA_GRADLE_PLUGIN_VERSION}")
        return False

    info(f"Updating ballerinaGradlePluginVersion: {current} → {BALLERINA_GRADLE_PLUGIN_VERSION}")
    if dry_run:
        info(f"[DRY RUN] Would update ballerinaGradlePluginVersion in gradle.properties")
        return True

    new_content = re.sub(
        r"^(ballerinaGradlePluginVersion\s*=\s*).*$",
        rf"\g<1>{BALLERINA_GRADLE_PLUGIN_VERSION}",
        content,
        flags=re.MULTILINE,
    )
    props_file.write_text(new_content)
    return True


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
