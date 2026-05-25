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
publish_all.py

Convenience wrapper: runs publish_docs.py then publish_sample.py in sequence,
streams each script's output live, and prints both PR links at the end.

Usage:
    python python/publish_all.py [options]

Optional:
    --no-pr             Push both branches but skip PR creation
    --dry-run           Print planned actions without making any changes
    --open              Open both PR links in the browser after creation

Docs options (forwarded to publish_docs.py):
    --artifacts-dir PATH
    --docs-repo PATH
    --docs-fork OWNER/REPO
    --docs-upstream OWNER/REPO
    --docs-base-branch BRANCH
    --category CATEGORY
    --no-preview

Samples options (forwarded to publish_sample.py):
    --url URL
    --samples-repo PATH
    --project-path PATH
    --samples-upstream OWNER/REPO
    --samples-base-branch BRANCH
    --no-publish

Examples:
    python python/publish_all.py
    python python/publish_all.py --dry-run
    python python/publish_all.py --no-preview --open
    python python/publish_all.py --no-pr
"""

import argparse
import os
import re
import subprocess
import sys
import webbrowser
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent / ".env")

SCRIPTS_DIR = Path(__file__).parent


# ── Logging helpers ───────────────────────────────────────────────────────────

def info(msg: str) -> None:
    print(f"[INFO]  {msg}")

def dry(msg: str) -> None:
    print(f"[DRY]   {msg}")


# ── Script runner ─────────────────────────────────────────────────────────────

def run_script(label: str, cmd: list[str]) -> str | None:
    """
    Run a publish script, stream its stdout live with a label prefix,
    and return the GitHub PR URL found in the output (or None).
    """
    print()
    print("=" * 79)
    print(f"[{label}] Starting ...")
    print("=" * 79)

    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    pr_url: str | None = None
    for line in proc.stdout:
        stripped = line.rstrip()
        print(f"[{label}] {stripped}")
        m = re.search(r"https://github\.com/\S+/pull/\d+", stripped)
        if m:
            pr_url = m.group(0)

    # Read stderr only after stdout is drained (avoids pipe deadlock)
    stderr_output = proc.stderr.read()
    proc.wait()

    if proc.returncode != 0:
        print(f"\n[ERROR] {label} failed (exit {proc.returncode}).", file=sys.stderr)
        if stderr_output.strip():
            print(stderr_output.strip(), file=sys.stderr)

    return pr_url


# ── Command builders ──────────────────────────────────────────────────────────

def build_docs_cmd(args: argparse.Namespace) -> list[str]:
    cmd = [sys.executable, "-u", str(SCRIPTS_DIR / "publish_docs.py")]
    cmd += ["--artifacts-dir", args.artifacts_dir]
    if args.docs_repo:
        cmd += ["--docs-repo", args.docs_repo]
    if args.docs_fork:
        cmd += ["--fork", args.docs_fork]
    cmd += ["--upstream", args.docs_upstream]
    cmd += ["--base-branch", args.docs_base_branch]
    if args.category:
        cmd += ["--category", args.category]
    if args.no_preview:
        cmd.append("--no-preview")
    if args.no_pr:
        cmd.append("--no-pr")
    if args.dry_run:
        cmd.append("--dry-run")
    return cmd


def build_samples_cmd(args: argparse.Namespace) -> list[str]:
    cmd = [sys.executable, "-u", str(SCRIPTS_DIR / "publish_sample.py")]
    cmd += ["--url", args.url]
    if args.samples_repo:
        cmd += ["--samples-repo", args.samples_repo]
    if args.project_path:
        cmd += ["--project-path", args.project_path]
    cmd += ["--upstream", args.samples_upstream]
    cmd += ["--base-branch", args.samples_base_branch]
    if args.no_publish:
        cmd.append("--no-publish")
    if args.no_pr:
        cmd.append("--no-pr")
    if args.dry_run:
        cmd.append("--dry-run")
    return cmd


# ── CLI ───────────────────────────────────────────────────────────────────────

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run publish_docs.py then publish_sample.py and display both PR links."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python python/publish_all.py\n"
            "  python python/publish_all.py --dry-run\n"
            "  python python/publish_all.py --no-preview --open\n"
            "  python python/publish_all.py --no-pr\n"
        ),
    )

    # ── Shared ────────────────────────────────────────────────────────────────
    parser.add_argument(
        "--no-pr",
        action="store_true",
        help="Push both branches but skip PR creation",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print planned actions without making any changes",
    )
    parser.add_argument(
        "--open",
        action="store_true",
        help="Open both PR links in the browser after creation",
    )

    # ── publish_docs.py ───────────────────────────────────────────────────────
    docs = parser.add_argument_group("publish_docs.py options")
    docs.add_argument(
        "--artifacts-dir",
        default="./artifacts",
        metavar="PATH",
        help="Path to pipeline artifacts directory (default: ./artifacts)",
    )
    docs.add_argument(
        "--docs-repo",
        default=None,
        metavar="PATH",
        help="Path to local docs-integrator fork (default: from .env or sibling directory)",
    )
    docs.add_argument(
        "--docs-fork",
        default=os.environ.get("DOCS_INTEGRATOR_FORK"),
        metavar="OWNER/REPO",
        help="Docs fork slug (default: DOCS_INTEGRATOR_FORK env var)",
    )
    docs.add_argument(
        "--docs-upstream",
        default=os.environ.get("DOCS_INTEGRATOR_UPSTREAM", "wso2/docs-integrator"),
        metavar="OWNER/REPO",
        help="Upstream docs repo for the PR (default: wso2/docs-integrator)",
    )
    docs.add_argument(
        "--docs-base-branch",
        default=os.environ.get("DOCS_INTEGRATOR_BASE_BRANCH", "main"),
        metavar="BRANCH",
        help="Target branch in the docs upstream repo (default: main)",
    )
    docs.add_argument(
        "--category",
        metavar="CATEGORY",
        help="Connector category — skip auto-detection",
    )
    docs.add_argument(
        "--no-preview",
        action="store_true",
        help="Skip Playwright preview screenshots",
    )

    # ── publish_sample.py ─────────────────────────────────────────────────────
    samples = parser.add_argument_group("publish_sample.py options")
    samples.add_argument(
        "--url",
        default=f"http://localhost:{os.environ.get('CODE_SERVER_PORT', '8080')}",
        help="code-server URL (default: http://localhost:8080)",
    )
    samples.add_argument(
        "--samples-repo",
        default=None,
        metavar="PATH",
        help="Path to local integration-samples fork (default: from .env or sibling directory)",
    )
    samples.add_argument(
        "--project-path",
        metavar="PATH",
        help="Absolute path to the created integration project",
    )
    samples.add_argument(
        "--samples-upstream",
        default=os.environ.get("INTEGRATION_SAMPLES_UPSTREAM", "wso2/integration-samples"),
        metavar="OWNER/REPO",
        help="Upstream integration-samples repo for the PR (default: wso2/integration-samples)",
    )
    samples.add_argument(
        "--samples-base-branch",
        default=os.environ.get("INTEGRATION_SAMPLES_BASE_BRANCH", "main"),
        metavar="BRANCH",
        help="Target branch in the integration-samples upstream repo (default: main)",
    )
    samples.add_argument(
        "--no-publish",
        action="store_true",
        help="Skip sample publishing — just delete project and close editor tabs",
    )

    return parser.parse_args()


def main() -> None:
    args = parse_args()

    docs_cmd = build_docs_cmd(args)
    samples_cmd = build_samples_cmd(args)

    if args.dry_run:
        print("=" * 79)
        print("DRY RUN — no changes will be made")
        print("=" * 79)
        dry(f"publish_docs:   {' '.join(docs_cmd)}")
        dry(f"publish_sample: {' '.join(samples_cmd)}")
        print()
        print("=" * 79)
        print("Dry run complete. Remove --dry-run to execute.")
        print("=" * 79)
        return

    docs_pr = run_script("DOCS", docs_cmd)
    samples_pr = run_script("SAMPLES", samples_cmd)

    # ── Summary ───────────────────────────────────────────────────────────────
    print()
    print("=" * 79)
    print("ALL DONE")
    print("=" * 79)
    print(f"  Docs PR    : {docs_pr or '(not created)'}")
    print(f"  Samples PR : {samples_pr or '(not created)'}")
    print()
    print("Open in browser:")
    if docs_pr:
        print(f"  open \"{docs_pr}\"")
    if samples_pr:
        print(f"  open \"{samples_pr}\"")
    print("=" * 79)

    if args.open:
        if docs_pr:
            info(f"Opening docs PR ...")
            webbrowser.open(docs_pr)
        if samples_pr:
            info(f"Opening samples PR ...")
            webbrowser.open(samples_pr)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:
        print(f"\n[ERROR] Unexpected error: {e}", file=sys.stderr)
        sys.exit(1)
