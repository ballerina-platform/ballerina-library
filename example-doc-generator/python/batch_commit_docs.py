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
batch_commit_docs.py

Commits one connector's generated docs to a shared batch branch without
creating a PR. Run this once per connector after each pipeline run; then
use batch_pr_docs.py to open a single PR covering all committed connectors.

If the batch branch does not yet exist on origin it is created from
upstream/{base_branch}. If it already exists the commit is appended to it.

Usage:
    python python/batch_commit_docs.py --branch docs/batch-april-2026

Required:
    --branch BRANCH     Shared batch branch name (created from upstream if absent)

Optional:
    --docs-repo PATH        Path to local docs-integrator fork (default: from .env)
    --fork OWNER/REPO       Fork slug (default: DOCS_INTEGRATOR_FORK env var)
    --upstream OWNER/REPO   Upstream repo (default: wso2/docs-integrator)
    --base-branch BRANCH    Upstream branch to seed the batch branch from (default: main)
    --category CATEGORY     Override auto-detected connector category
    --artifacts-dir PATH    Pipeline artifacts directory (default: ./artifacts)
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
from publish_docs import (
    AVAILABLE_CATEGORIES,
    DEFAULT_BASE_BRANCH,
    DEFAULT_DOCS_REPO,
    DEFAULT_UPSTREAM,
    commit_and_push,
    detect_category,
    dry,
    extract_connector_info,
    fail,
    find_latest_doc,
    find_screenshots,
    info,
    infer_fork,
    run,
    run_claude_code_placement,
    validate_docs_repo,
    warn,
)


# ── Branch helpers ────────────────────────────────────────────────────────────

def branch_exists_on_origin(docs_repo: Path, branch: str) -> bool:
    """Return True if the branch already exists on the origin remote."""
    try:
        result = run(
            ["git", "ls-remote", "--heads", "origin", branch],
            cwd=docs_repo,
        )
        return bool(result.strip())
    except subprocess.CalledProcessError:
        return False


def checkout_or_create_batch_branch(
    docs_repo: Path,
    branch: str,
    dry_run: bool,
    upstream_slug: str = DEFAULT_UPSTREAM,
    base_branch: str = "main",
) -> None:
    """
    Check out the batch branch, creating it from upstream/{base_branch} if it
    doesn't exist yet on origin.
    """
    remotes = run(["git", "remote"], cwd=docs_repo).split()
    if "upstream" not in remotes:
        fail(
            "'upstream' remote not found in docs repo.\n"
            f"Add it with: git remote add upstream https://github.com/{upstream_slug}.git"
        )

    if dry_run:
        dry(f"git fetch origin upstream  (in {docs_repo})")
        if branch_exists_on_origin(docs_repo, branch):
            dry(f"Branch '{branch}' exists on origin — git checkout -B {branch} origin/{branch}")
        else:
            dry(f"Branch '{branch}' not found on origin — create from upstream/{base_branch}")
            dry(f"git checkout {base_branch} && git merge upstream/{base_branch} --ff-only")
            dry(f"git checkout -b {branch}")
        dry(f"git merge upstream/{base_branch} --no-edit  (sync latest upstream into batch branch)")
        dry(f"git push origin {branch}")
        return

    info("Fetching origin and upstream...")
    subprocess.run(["git", "fetch", "origin"], cwd=str(docs_repo), check=True)
    subprocess.run(["git", "fetch", "upstream"], cwd=str(docs_repo), check=True)

    if branch_exists_on_origin(docs_repo, branch):
        info(f"Batch branch '{branch}' already exists — checking out...")
        subprocess.run(
            ["git", "checkout", "-B", branch, f"origin/{branch}"],
            cwd=str(docs_repo),
            check=True,
        )
    else:
        info(f"Batch branch '{branch}' not found on origin — creating from upstream/{base_branch}...")
        subprocess.run(["git", "checkout", base_branch], cwd=str(docs_repo), check=True)
        try:
            subprocess.run(
                ["git", "merge", f"upstream/{base_branch}", "--ff-only"],
                cwd=str(docs_repo),
                check=True,
            )
        except subprocess.CalledProcessError:
            fail(
                f"Could not fast-forward fork's {base_branch} to upstream/{base_branch}.\n"
                "Your fork has diverged. Resolve manually before running this script."
            )
        info(f"Creating batch branch: {branch}")
        subprocess.run(["git", "checkout", "-b", branch], cwd=str(docs_repo), check=True)

    # Always merge latest upstream into the batch branch before adding a new commit
    info(f"Merging upstream/{base_branch} into '{branch}' to stay up to date...")
    try:
        subprocess.run(
            ["git", "merge", f"upstream/{base_branch}", "--no-edit"],
            cwd=str(docs_repo),
            check=True,
        )
    except subprocess.CalledProcessError:
        fail(
            f"Merge conflict when pulling upstream/{base_branch} into '{branch}'.\n"
            "Resolve conflicts manually, then re-run."
        )
    subprocess.run(["git", "push", "origin", branch], cwd=str(docs_repo), check=True)


# ── CLI ───────────────────────────────────────────────────────────────────────

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Commit one connector's generated docs to a shared batch branch. "
            "Run once per connector; use batch_pr_docs.py to open the PR when done."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # First connector on a new batch branch:\n"
            "  python python/batch_commit_docs.py --branch docs/batch-april-2026\n"
            "\n"
            "  # Second connector — appends to the same branch:\n"
            "  python python/batch_commit_docs.py --branch docs/batch-april-2026\n"
            "\n"
            "  # Dry run:\n"
            "  python python/batch_commit_docs.py --branch docs/batch-april-2026 --dry-run\n"
        ),
    )
    parser.add_argument(
        "--branch",
        default="docs/connector-docs",
        metavar="BRANCH",
        help="Shared batch branch name (default: docs/connector-docs)",
    )
    parser.add_argument(
        "--docs-repo",
        default=str(DEFAULT_DOCS_REPO),
        metavar="PATH",
        help=f"Path to local clone of the docs-integrator fork (default: {DEFAULT_DOCS_REPO})",
    )
    parser.add_argument(
        "--fork",
        default=os.environ.get("DOCS_INTEGRATOR_FORK"),
        metavar="OWNER/REPO",
        help="Fork repo slug (default: DOCS_INTEGRATOR_FORK env var or inferred from git remote 'origin')",
    )
    parser.add_argument(
        "--upstream",
        default=DEFAULT_UPSTREAM,
        metavar="OWNER/REPO",
        help=f"Upstream repo (default: {DEFAULT_UPSTREAM})",
    )
    parser.add_argument(
        "--base-branch",
        default=DEFAULT_BASE_BRANCH,
        metavar="BRANCH",
        help=f"Upstream branch to seed a new batch branch from (default: {DEFAULT_BASE_BRANCH})",
    )
    parser.add_argument(
        "--category",
        metavar="CATEGORY",
        help=f"Override auto-detected category. Choices: {', '.join(AVAILABLE_CATEGORIES)}",
    )
    parser.add_argument(
        "--artifacts-dir",
        default="./artifacts",
        metavar="PATH",
        help="Pipeline artifacts directory (default: ./artifacts)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print planned actions without making any changes",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    docs_repo = Path(args.docs_repo).resolve()
    artifacts_dir = Path(args.artifacts_dir).resolve()

    if args.dry_run:
        print("=" * 79)
        print("DRY RUN — no changes will be made")
        print("=" * 79)

    # ── 1. Read artifacts ─────────────────────────────────────────────────────
    source_doc_path, doc_content = find_latest_doc(artifacts_dir)
    connector_name, connector_slug, _ = extract_connector_info(doc_content, artifacts_dir)
    screenshot_files = find_screenshots(artifacts_dir)

    # ── 2. Validate docs repo ─────────────────────────────────────────────────
    validate_docs_repo(docs_repo)
    fork = args.fork or infer_fork(docs_repo)
    info(f"Fork: {fork}  |  Upstream: {args.upstream}  |  Base branch: {args.base_branch}")

    # ── 3. Detect category ────────────────────────────────────────────────────
    category = detect_category(connector_slug, args.category)

    # ── 4. Check out or create the batch branch ───────────────────────────────
    info(f"Batch branch: {args.branch}")
    checkout_or_create_batch_branch(
        docs_repo, args.branch, args.dry_run,
        upstream_slug=args.upstream, base_branch=args.base_branch,
    )

    # ── 5–8. Place example.md, copy screenshots, update sidebar ───────────────
    run_claude_code_placement(
        docs_repo, category, connector_slug, connector_name,
        source_doc_path, screenshot_files, args.dry_run,
    )

    # ── 9. Commit and push ────────────────────────────────────────────────────
    generated_paths = [
        docs_repo / "en" / "docs" / "connectors" / "catalog" / category / connector_slug / "example.md",
        docs_repo / "en" / "static" / "img" / "connectors" / "catalog" / category / connector_slug,
        docs_repo / "en" / "sidebars.ts",
    ]
    commit_and_push(docs_repo, connector_name, args.branch, args.dry_run, generated_paths)

    print()
    print("=" * 79)
    if args.dry_run:
        print("Dry run complete. Remove --dry-run to execute.")
    else:
        print(f"Done!  '{connector_name}' committed to branch: {args.branch}")
        print("Run 'make batch-pr-docs' when all connectors are committed.")
    print("=" * 79)


if __name__ == "__main__":
    main()
