#!/usr/bin/env python3
# Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
#
# WSO2 LLC. licenses this file to you under the Apache License,
# Version 2.0 (the "License"); you may not use this file except
# in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied. See the License for the
# specific language governing permissions and limitations
# under the License.

"""
batch_commit_sample.py

Commits one connector's generated Ballerina sample to a shared batch branch
without creating a PR. Run this once per connector after each pipeline run;
then use batch_pr_samples.py to open a single PR covering all committed samples.

After committing, deletes the local project and closes VS Code editor tabs —
same cleanup as publish_sample.py.

If the batch branch does not yet exist on origin it is created from
upstream/{base_branch}. If it already exists the commit is appended to it.

Usage:
    python python/batch_commit_sample.py
    python python/batch_commit_sample.py --branch samples/batch-april-2026

Optional:
    --branch BRANCH         Shared batch branch name (default: samples/connector-samples)
    --samples-repo PATH     Path to local integration-samples fork (default: from .env)
    --upstream OWNER/REPO   Upstream repo (default: wso2/integration-samples)
    --base-branch BRANCH    Upstream branch to seed the batch branch from (default: main)
    --url URL               code-server URL for closing editor tabs (default: http://localhost:8080)
    --project-path PATH     Manual project path override (writes created-project.txt)
    --dry-run               Print planned actions without making any changes
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent / ".env")

sys.path.insert(0, str(Path(__file__).parent))
from publish_sample import (
    DEFAULT_BASE_BRANCH,
    DEFAULT_CODE_SERVER_PORT,
    DEFAULT_SAMPLES_REPO,
    DEFAULT_UPSTREAM_REPO,
    PROJECT_PATH_FILE,
    close_editor_tabs,
    commit_and_push,
    copy_sample,
    delete_project,
    dry,
    fail,
    find_ballerina_project,
    info,
    infer_fork,
    patch_ballerina_toml,
    read_project_path,
    run,
    warn,
    write_sample_log,
)


# ── Branch helpers ────────────────────────────────────────────────────────────

def branch_exists_on_origin(samples_repo: Path, branch: str) -> bool:
    """Return True if the branch already exists on the origin remote."""
    result = run(["git", "ls-remote", "--heads", "origin", branch], cwd=samples_repo)
    return bool(result.strip())

def checkout_or_create_batch_branch(
    samples_repo: Path,
    branch: str,
    dry_run: bool,
    upstream_slug: str = DEFAULT_UPSTREAM_REPO,
    base_branch: str = "main",
) -> None:
    """
    Check out the batch branch (creating it from upstream/{base_branch} if absent),
    then always merge upstream/{base_branch} to ensure the branch is up to date
    with the latest upstream changes before adding a new connector commit.
    """
    remotes = run(["git", "remote"], cwd=samples_repo).split()
    if "upstream" not in remotes:
        fail(
            "'upstream' remote not found in integration-samples repo.\n"
            f"Add it with: git remote add upstream https://github.com/{upstream_slug}.git"
        )

    if dry_run:
        dry(f"git fetch origin upstream  (in {samples_repo})")
        if branch_exists_on_origin(samples_repo, branch):
            dry(f"Branch '{branch}' exists on origin — git checkout -B {branch} origin/{branch}")
        else:
            dry(f"Branch '{branch}' not on origin — create from upstream/{base_branch}")
            dry(f"git checkout {base_branch} && git merge upstream/{base_branch} --ff-only")
            dry(f"git checkout -b {branch}")
        dry(f"git merge upstream/{base_branch} --no-edit  (sync latest upstream into batch branch)")
        dry(f"git push origin {branch}")
        return

    info("Fetching origin and upstream...")
    subprocess.run(["git", "fetch", "origin"], cwd=str(samples_repo), check=True)
    subprocess.run(["git", "fetch", "upstream"], cwd=str(samples_repo), check=True)

    if branch_exists_on_origin(samples_repo, branch):
        info(f"Batch branch '{branch}' already exists — checking out...")
        subprocess.run(
            ["git", "checkout", "-B", branch, f"origin/{branch}"],
            cwd=str(samples_repo),
            check=True,
        )
    else:
        info(f"Batch branch '{branch}' not found on origin — creating from upstream/{base_branch}...")
        subprocess.run(["git", "checkout", base_branch], cwd=str(samples_repo), check=True)
        try:
            subprocess.run(
                ["git", "merge", f"upstream/{base_branch}", "--ff-only"],
                cwd=str(samples_repo),
                check=True,
            )
        except subprocess.CalledProcessError:
            fail(
                f"Could not fast-forward fork's {base_branch} to upstream/{base_branch}.\n"
                "Your fork has diverged. Resolve manually before running this script."
            )
        info(f"Creating batch branch: {branch}")
        subprocess.run(["git", "checkout", "-b", branch], cwd=str(samples_repo), check=True)

    # Always merge latest upstream into the batch branch before adding a new commit
    info(f"Merging upstream/{base_branch} into '{branch}' to stay up to date...")
    try:
        subprocess.run(
            ["git", "merge", f"upstream/{base_branch}", "--no-edit"],
            cwd=str(samples_repo),
            check=True,
        )
    except subprocess.CalledProcessError:
        fail(
            f"Merge conflict when pulling upstream/{base_branch} into '{branch}'.\n"
            "Resolve conflicts manually, then re-run."
        )
    subprocess.run(["git", "push", "origin", branch], cwd=str(samples_repo), check=True)


# ── CLI ───────────────────────────────────────────────────────────────────────

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Commit one connector's generated Ballerina sample to a shared batch branch. "
            "Run once per connector; use batch_pr_samples.py to open the PR when done."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # First connector on a new batch branch:\n"
            "  python python/batch_commit_sample.py --branch samples/batch-april-2026\n"
            "\n"
            "  # Second connector — appends to the same branch:\n"
            "  python python/batch_commit_sample.py --branch samples/batch-april-2026\n"
            "\n"
            "  # Dry run:\n"
            "  python python/batch_commit_sample.py --branch samples/batch-april-2026 --dry-run\n"
        ),
    )
    parser.add_argument(
        "--branch",
        default="samples/connector-samples",
        metavar="BRANCH",
        help="Shared batch branch name (default: samples/connector-samples)",
    )
    parser.add_argument(
        "--samples-repo",
        default=str(DEFAULT_SAMPLES_REPO),
        metavar="PATH",
        help=f"Path to local integration-samples fork (default: {DEFAULT_SAMPLES_REPO})",
    )
    parser.add_argument(
        "--upstream",
        default=DEFAULT_UPSTREAM_REPO,
        metavar="OWNER/REPO",
        help=f"Upstream repo (default: {DEFAULT_UPSTREAM_REPO})",
    )
    parser.add_argument(
        "--base-branch",
        default=DEFAULT_BASE_BRANCH,
        metavar="BRANCH",
        help=f"Upstream branch to seed a new batch branch from (default: {DEFAULT_BASE_BRANCH})",
    )
    parser.add_argument(
        "--url",
        default=f"http://localhost:{DEFAULT_CODE_SERVER_PORT}",
        help=f"code-server URL for closing editor tabs (default: http://localhost:{DEFAULT_CODE_SERVER_PORT})",
    )
    parser.add_argument(
        "--project-path",
        metavar="PATH",
        help=(
            "Absolute path to the created integration project. "
            "When provided, writes it to created-project.txt before proceeding."
        ),
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print planned actions without making any changes",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    samples_repo = Path(args.samples_repo).resolve()

    if args.dry_run:
        print("=" * 79)
        print("DRY RUN — no changes will be made")
        print("=" * 79)

    # ── 0. Write project path file if supplied manually ───────────────────────
    if args.project_path:
        path_file = Path(PROJECT_PATH_FILE)
        if args.dry_run:
            info(f"[dry-run] Would write project path to {PROJECT_PATH_FILE}")
        else:
            path_file.parent.mkdir(parents=True, exist_ok=True)
            path_file.write_text(args.project_path.strip(), encoding="utf-8")
            info(f"Written project path to {PROJECT_PATH_FILE}")

    # ── 1. Read project path ──────────────────────────────────────────────────
    project = read_project_path()

    # ── 2. Validate samples repo ──────────────────────────────────────────────
    if not (samples_repo / ".git").exists():
        fail(f"{samples_repo} is not a git repository.")
    fork = infer_fork(samples_repo)

    # ── 3. Resolve actual Ballerina project + derive name ─────────────────────
    actual_project = find_ballerina_project(project)
    project_name = actual_project.name
    info(f"Fork: {fork}  |  Upstream: {args.upstream}  |  Project: {project_name}")

    # ── 4. Check out or create the batch branch ───────────────────────────────
    info(f"Batch branch: {args.branch}")
    checkout_or_create_batch_branch(
        samples_repo, args.branch, args.dry_run,
        upstream_slug=args.upstream, base_branch=args.base_branch,
    )

    # ── 5. Patch org in Ballerina.toml ────────────────────────────────────────
    patch_ballerina_toml(actual_project, args.dry_run)

    # ── 6. Copy sample ────────────────────────────────────────────────────────
    copy_sample(samples_repo, actual_project, project_name, args.dry_run)

    # ── 7. Commit and push ────────────────────────────────────────────────────
    commit_and_push(samples_repo, project_name, args.branch, args.dry_run)

    # ── 8. Write sample log ───────────────────────────────────────────────────
    write_sample_log(project_name, args.dry_run)

    print()
    print("=" * 79)
    if args.dry_run:
        print("Dry run complete. Remove --dry-run to execute.")
    else:
        print(f"Done!  '{project_name}' committed to branch: {args.branch}")
        print("Run 'make batch-pr-samples' when all connectors are committed.")
    print("=" * 79)

    # ── 9. Delete local project ───────────────────────────────────────────────
    delete_project(project, args.dry_run)

    # ── 10. Close editor tabs ─────────────────────────────────────────────────
    close_editor_tabs(args.url, args.dry_run)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:
        print(f"\n[ERROR] Unexpected error: {e}", file=sys.stderr)
        sys.exit(1)
