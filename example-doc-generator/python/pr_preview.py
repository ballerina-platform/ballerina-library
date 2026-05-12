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
pr_preview.py

Standalone script to take Docusaurus preview screenshots for an already-committed
docs branch and create a pull request for it.

Use this when docs have already been committed and pushed to a remote branch
(e.g. by a previous publish_docs.py run) but the preview/PR step failed or was skipped.

Usage:
    python python/pr_preview.py --branch docs/add-zoom.meetings-connector-example-documentation

Optional:
    --docs-repo PATH        Path to local docs-integrator fork (default: from .env / sibling dir)
    --fork OWNER/REPO       Fork slug (default: DOCS_INTEGRATOR_FORK env var)
    --upstream OWNER/REPO   Upstream repo for the PR (default: wso2/docs-integrator)
    --base-branch BRANCH    Target branch in upstream (default: main)
    --category CATEGORY     Override auto-detected category
    --artifacts-dir PATH    Output directory for preview screenshots (default: ./artifacts)
    --no-pr                 Take screenshots but skip PR creation
    --no-preview            Skip screenshots, create PR only
    --dry-run               Print planned actions without making any changes
"""

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent / ".env")

# Import shared helpers and functions from publish_docs
sys.path.insert(0, str(Path(__file__).parent))
from publish_docs import (
    AVAILABLE_CATEGORIES,
    DEFAULT_BASE_BRANCH,
    DEFAULT_DOCS_REPO,
    DEFAULT_UPSTREAM,
    build_pr_body,
    create_pr,
    detect_category,
    dry,
    fail,
    info,
    infer_fork,
    take_preview_screenshots,
    upload_preview_as_release,
    validate_docs_repo,
    warn,
)


# ── Helpers ───────────────────────────────────────────────────────────────────

def checkout_branch(docs_repo: Path, branch: str, dry_run: bool) -> None:
    """Fetch origin and check out the given remote branch locally."""
    if dry_run:
        dry(f"git fetch origin  (in {docs_repo})")
        dry(f"git checkout {branch}")
        return
    info("Fetching origin...")
    subprocess.run(["git", "fetch", "origin"], cwd=str(docs_repo), check=True)
    info(f"Checking out branch: {branch}")
    subprocess.run(["git", "checkout", branch], cwd=str(docs_repo), check=True)


def slug_from_branch(branch: str) -> str | None:
    """
    Extract connector slug from the branch name.
    Convention: docs/add-{slug}-connector-example-documentation
    e.g. docs/add-zoom.meetings-connector-example-documentation → zoom.meetings
    """
    m = re.match(r"(?:.+/)?add-(.+)-connector-example-documentation$", branch)
    return m.group(1) if m else None


def detect_category_from_repo(docs_repo: Path, connector_slug: str) -> str | None:
    """
    Find the category by locating example.md in the checked-out branch.
    Scans: en/docs/connectors/catalog/{category}/{connector_slug}/example.md
    """
    catalog = docs_repo / "en" / "docs" / "connectors" / "catalog"
    if not catalog.exists():
        return None
    for category_dir in catalog.iterdir():
        if (category_dir / connector_slug / "example.md").exists():
            return category_dir.name
    return None


def infer_operation(docs_repo: Path, category: str, connector_slug: str) -> str:
    """Read the primary operation name from example.md in the docs repo."""
    example_md = (
        docs_repo / "en" / "docs" / "connectors" / "catalog"
        / category / connector_slug / "example.md"
    )
    if not example_md.exists():
        return "primary"
    content = example_md.read_text(encoding="utf-8")
    ops = re.findall(
        r"^##\s+Configuring the \S+\s+(\S+)\s+Operation",
        content,
        re.MULTILINE | re.IGNORECASE,
    )
    return ops[-1] if ops else "primary"


# ── CLI ───────────────────────────────────────────────────────────────────────

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Take Docusaurus preview screenshots for an already-pushed docs branch "
            "and create a pull request."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python python/pr_preview.py \\\n"
            "    --branch docs/add-zoom.meetings-connector-example-documentation\n"
            "\n"
            "  python python/pr_preview.py \\\n"
            "    --branch docs/add-kafka-connector-example-documentation --no-preview\n"
            "\n"
            "  python python/pr_preview.py \\\n"
            "    --branch docs/add-mysql-connector-example-documentation --dry-run\n"
        ),
    )
    parser.add_argument(
        "--branch",
        required=True,
        metavar="BRANCH",
        help=(
            "Remote branch that already has the docs committed "
            "(e.g. docs/add-zoom.meetings-connector-example-documentation)"
        ),
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
        help=f"Upstream repo to target with the PR (default: {DEFAULT_UPSTREAM})",
    )
    parser.add_argument(
        "--base-branch",
        default=DEFAULT_BASE_BRANCH,
        metavar="BRANCH",
        help=f"Target branch in the upstream repo (default: {DEFAULT_BASE_BRANCH})",
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
        help="Output directory for preview screenshots (default: ./artifacts)",
    )
    parser.add_argument(
        "--no-pr",
        action="store_true",
        help="Take preview screenshots but skip PR creation",
    )
    parser.add_argument(
        "--no-preview",
        action="store_true",
        help="Skip Playwright preview screenshots, create PR only",
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
    branch = args.branch

    if args.dry_run:
        print("=" * 79)
        print("DRY RUN — no changes will be made")
        print("=" * 79)

    # ── 1. Validate docs repo and resolve fork ─────────────────────────────────
    validate_docs_repo(docs_repo)
    fork = args.fork or infer_fork(docs_repo)
    info(f"Fork: {fork}  |  Upstream: {args.upstream}  |  Base branch: {args.base_branch}")

    # ── 2. Check out the remote branch ────────────────────────────────────────
    checkout_branch(docs_repo, branch, args.dry_run)

    # ── 3. Resolve connector slug from branch name ─────────────────────────────
    connector_slug = slug_from_branch(branch)
    if not connector_slug:
        fail(
            f"Could not extract connector slug from branch: '{branch}'.\n"
            "Expected format: docs/add-{{slug}}-connector-example-documentation"
        )
    info(f"Connector slug: {connector_slug}")

    # ── 4. Detect category ─────────────────────────────────────────────────────
    if args.category:
        category = detect_category(connector_slug, args.category)
    elif not args.dry_run:
        category = detect_category_from_repo(docs_repo, connector_slug)
        if not category:
            warn("Could not find example.md in docs repo — falling back to category map.")
            category = detect_category(connector_slug, None)
    else:
        category = detect_category(connector_slug, None)
    info(f"Category: {category}")

    # ── 5. Derive connector display name and operation ─────────────────────────
    connector_name = connector_slug.replace(".", " ").title()
    operation_name = (
        infer_operation(docs_repo, category, connector_slug)
        if not args.dry_run else "primary"
    )
    info(f"Connector: {connector_name}, Operation: {operation_name}")

    # ── 6. Preview screenshots ─────────────────────────────────────────────────
    preview_urls: list[str] = []
    if not args.no_preview:
        try:
            preview_files = take_preview_screenshots(
                docs_repo, connector_slug, category, artifacts_dir, args.dry_run
            )
            if preview_files and not args.dry_run:
                preview_urls = upload_preview_as_release(
                    preview_files, connector_name, connector_slug, branch, fork
                )
        except Exception as exc:
            warn(f"Preview step failed: {exc}")

    if args.no_pr:
        print()
        print("=" * 79)
        if args.dry_run:
            print("Dry run complete. Remove --dry-run to execute.")
        else:
            print("Preview screenshots done.  (--no-pr: skipped PR creation)")
        print("=" * 79)
        return

    # ── 7. Create PR ───────────────────────────────────────────────────────────
    pr_body = build_pr_body(
        connector_name, operation_name, category, connector_slug, preview_urls
    )
    pr_url = create_pr(
        fork, args.upstream, args.base_branch,
        connector_name, branch, pr_body, args.dry_run,
    )

    print()
    print("=" * 79)
    if args.dry_run:
        print("Dry run complete. Remove --dry-run to execute.")
    else:
        print(f"Done!  PR: {pr_url}")
    print("=" * 79)


if __name__ == "__main__":
    main()
