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
publish_docs.py

Post-pipeline script: places generated connector documentation into the
WSO2 Integrator docs-integrator fork, creates a feature branch and PR,
and adds Playwright screenshots of the rendered docs page to the PR body.

Preview screenshots are uploaded as pre-release assets on the fork repo —
they are NOT committed to the docs-integrator repository.

Usage:
    python python/publish_docs.py [options]

Optional:
    --artifacts-dir PATH    Path to pipeline artifacts directory (default: ./artifacts)
    --category CATEGORY     Connector category — required if not in the built-in map
    --no-pr                 Push the branch but skip creating a pull request
    --no-preview            Skip Playwright preview screenshots
    --dry-run               Print planned actions without making any changes

Defaults for repo paths and GitHub identifiers are read from .env (see .env.example).

Prerequisites:
    - gh CLI authenticated (gh auth login)
    - docs-integrator fork cloned locally with 'upstream' remote configured:
        git remote add upstream https://github.com/wso2/docs-integrator.git
    - Playwright installed: python -m playwright install chromium
    - For preview screenshots: node_modules installed in {docs_repo}/en/
"""

import argparse
import datetime
from collections.abc import Sequence
import os
import re
import signal
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent / ".env")

# Path to the connector name file written by the Ballerina pipeline at startup
CONNECTOR_NAME_FILE = Path("artifacts/run-log/connector-name.txt")

# ── Connector → category mapping ──────────────────────────────────────────────

CATEGORY_MAP: dict[str, str] = {
    # Database
    "mysql": "database",
    "postgresql": "database", "postgres": "database",
    "mongodb": "database", "mongo": "database",
    "mssql": "database", "sqlserver": "database",
    "redis": "database",
    "cassandra": "database",
    "oracle": "database", "oracledb": "database",
    "sqlite": "database",
    "h2": "database",
    "snowflake": "database",
    "java.jdbc": "database", "jdbc": "database",
    "cdc": "database",
    "aws.redshift": "database", "redshift": "database",
    "aws.redshiftdata": "database",
    # Messaging
    "kafka": "messaging",
    "rabbitmq": "messaging",
    "nats": "messaging",
    "activemq": "messaging",
    "ibmmq": "messaging", "ibm.ibmmq": "messaging",
    "asb": "messaging",
    "aws.sqs": "messaging", "sqs": "messaging",
    "gcloud.pubsub": "messaging", "pubsub": "messaging",
    "java.jms": "messaging", "jms": "messaging",
    "solace": "messaging",
    "confluent.cregistry": "messaging", "confluent.cavroserdes": "messaging",
    # CRM / Sales
    "salesforce": "crm-sales",
    "hubspot": "crm-sales",
    "zoho": "crm-sales",
    "pipedrive": "crm-sales",
    "dynamics": "crm-sales",
    # Communication
    "slack": "communication",
    "teams": "communication",
    "gmail": "communication", "googleapis.gmail": "communication",
    "outlook": "communication",
    "twilio": "communication",
    "sendgrid": "communication",
    "discord": "communication",
    "zoom": "communication", "zoom.meetings": "communication", "zoom.scheduler": "communication",
    "aws.sns": "communication", "sns": "communication",
    # Cloud Infrastructure
    "gcs": "cloud-infrastructure",
    "azure": "cloud-infrastructure",
    "aws.lambda": "cloud-infrastructure", "lambda": "cloud-infrastructure",
    "azure.functions": "cloud-infrastructure",
    "elastic": "cloud-infrastructure", "elastic.elasticcloud": "cloud-infrastructure",
    # AI / ML
    "openai": "ai-ml", "ai.openai": "ai-ml",
    "anthropic": "ai-ml", "ai.anthropic": "ai-ml",
    "cohere": "ai-ml",
    "gemini": "ai-ml",
    "mistral": "ai-ml",
    "ai.azure": "ai-ml",
    "ai.ollama": "ai-ml", "ollama": "ai-ml",
    "ai.deepseek": "ai-ml", "deepseek": "ai-ml",
    "ai.pinecone": "ai-ml", "pinecone": "ai-ml",
    "ai.weaviate": "ai-ml", "weaviate": "ai-ml",
    "ai.devant": "ai-ml",
    "ai.memory.mssql": "ai-ml",
    "azure.ai.search": "ai-ml",
    # E-commerce
    "shopify": "ecommerce",
    "woocommerce": "ecommerce",
    # Finance / Accounting
    "stripe": "finance-accounting",
    "paypal": "finance-accounting",
    # Developer Tools
    "github": "developer-tools",
    "gitlab": "developer-tools",
    "confluence": "developer-tools",
    "bitbucket": "developer-tools",
    # Productivity / Collaboration
    "jira": "productivity-collaboration",
    "asana": "productivity-collaboration",
    "trello": "productivity-collaboration",
    "googledrive": "productivity-collaboration", "microsoft.onedrive": "productivity-collaboration",
    "googleapis.sheets": "productivity-collaboration",
    "googleapis.calendar": "productivity-collaboration", "googleapis.gcalendar": "productivity-collaboration",
    "smartsheet": "productivity-collaboration",
    "candid": "productivity-collaboration",
    # Storage / File
    "s3": "storage-file",
    "awss3": "storage-file", "aws.s3": "storage-file",
    "onedrive": "storage-file", "alfresco": "storage-file",
    "azure_storage_service": "storage-file",
    # ERP / Business
    "sap": "erp-business",
    "netsuite": "erp-business",
    "workday": "hrms",
    # Security / Identity
    "aws.secretmanager": "security-identity", "secretmanager": "security-identity",
    "aws.secretsmanager": "security-identity", "secretsmanager": "security-identity",
    "scim": "security-identity", "scim2": "security-identity",
    # HRMS
    "hrms": "hrms",
    # Connectivity
    "sftp": "connectivity",
    "smtp": "connectivity",
    "imap": "connectivity",
    # Built-in (Ballerina standard library connectors)
    "email": "built-in",
    "ftp": "built-in",
    "graphql": "built-in",
    "grpc": "built-in",
    "http": "built-in",
    "mqtt": "built-in",
    "tcp": "built-in",
    "udp": "built-in",
    "websocket": "built-in",
    "websub": "built-in",
    # Marketing & Social
    "hubspot.marketing.campaigns": "marketing-social",
    "hubspot.marketing.emails": "marketing-social",
    "hubspot.marketing.events": "marketing-social",
    "hubspot.marketing.forms": "marketing-social",
    "hubspot.marketing.subscriptions": "marketing-social",
    "hubspot.marketing.transactional": "marketing-social",
    "mailchimp.marketing": "marketing-social",
    "mailchimp.transactional": "marketing-social",
    "salesforce.marketingcloud": "marketing-social",
    "twitter": "marketing-social",
}

AVAILABLE_CATEGORIES = sorted(set(CATEGORY_MAP.values()))

DEFAULT_UPSTREAM = os.environ.get("DOCS_INTEGRATOR_UPSTREAM", "wso2/docs-integrator")
DEFAULT_BASE_BRANCH = os.environ.get("DOCS_INTEGRATOR_BASE_BRANCH", "main")
PREVIEW_PORT = 3333
VIEWPORT_WIDTH = 1440
VIEWPORT_HEIGHT = 900

# Default docs-integrator path: env var, then sibling of this workspace
# Layout: <workspace>/connector-docs-automations/python/publish_docs.py
#         <workspace>/docs-integrator/
_WORKSPACE_ROOT = Path(__file__).resolve().parent.parent.parent
_env_docs_repo = os.environ.get("DOCS_INTEGRATOR_REPO")
DEFAULT_DOCS_REPO = (
    Path(_env_docs_repo) if _env_docs_repo
    else _WORKSPACE_ROOT / "docs-integrator"
)


# ── Logging helpers ───────────────────────────────────────────────────────────

def info(msg: str) -> None:
    print(f"[INFO]  {msg}")

def warn(msg: str) -> None:
    print(f"[WARN]  {msg}", file=sys.stderr)

def dry(msg: str) -> None:
    print(f"[DRY]   {msg}")

def fail(msg: str) -> None:
    print(f"\n[ERROR] {msg}", file=sys.stderr)
    sys.exit(1)


class PreviewError(RuntimeError):
    """Raised when optional preview screenshot generation cannot continue."""


# ── Subprocess helper ─────────────────────────────────────────────────────────

def run(cmd: list[str], cwd: Path | None = None, check: bool = True) -> str:
    """Run a command and return its stdout. Raises on non-zero exit if check=True."""
    result = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        capture_output=True,
        text=True,
        check=check,
    )
    return result.stdout.strip()


# ── Step 1: Read pipeline artifacts ───────────────────────────────────────────

def find_latest_doc(artifacts_dir: Path) -> tuple[Path, str]:
    """Return path and content of the most recently modified workflow doc."""
    docs_dir = artifacts_dir / "workflow-docs"
    if not docs_dir.exists():
        fail(f"workflow-docs/ not found in {artifacts_dir}. Run `make run` first.")
    md_files = sorted(docs_dir.glob("*.md"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not md_files:
        fail(f"No .md files found in {docs_dir}. Run `make run` first.")
    path = md_files[0]
    info(f"Using doc: {path.name}")
    return path, path.read_text(encoding="utf-8")


def extract_connector_info(content: str, artifacts_dir: Path | None = None) -> tuple[str, str, str]:
    """
    Extract connector display name, slug, and primary operation name from the doc.
    Returns (display_name, slug, operation_name).

    connector-name.txt written by the Ballerina pipeline is the authoritative source.
    When *artifacts_dir* is provided, looks for the file there instead of the
    default ``artifacts/run-log/`` path.
    """
    # connector-name.txt is required — written by the Ballerina pipeline at startup
    name_file = (artifacts_dir / "run-log" / "connector-name.txt") if artifacts_dir else CONNECTOR_NAME_FILE
    if not name_file.exists():
        fail(
            f"connector-name.txt not found in {name_file.parent}/. "
            "Run the Ballerina pipeline first."
        )
    raw = name_file.read_text(encoding="utf-8").strip()
    if not raw:
        fail("connector-name.txt is empty. Run the Ballerina pipeline first.")
    slug = re.sub(r"[^a-z0-9.]+", "-", raw.lower()).strip("-.")
    if not slug:
        fail(f"Connector name from connector-name.txt does not produce a valid slug: {raw!r}")
    display_name = raw.replace("-", " ").title()
    info(f"Connector slug from file: {slug}")

    # Last "## Configuring the X Y Operation" heading
    ops = re.findall(
        r"^##\s+Configuring the \S+\s+(\S+)\s+Operation",
        content,
        re.MULTILINE | re.IGNORECASE,
    )
    operation_name = ops[-1] if ops else "primary"

    info(f"Connector: {display_name} (slug: {slug}), Operation: {operation_name}")
    return display_name, slug, operation_name


def find_screenshots(artifacts_dir: Path) -> list[Path]:
    """Return sorted list of workflow screenshot files."""
    screenshots_dir = artifacts_dir / "screenshots"
    if not screenshots_dir.exists():
        warn("screenshots/ directory not found — no screenshots will be copied.")
        return []
    files = sorted(screenshots_dir.glob("*_screenshot_*.png"))
    if not files:
        warn("No *_screenshot_*.png files found in screenshots/.")
    else:
        info(f"Found {len(files)} screenshot(s).")
    return files


# ── Step 2: Validate docs repo ────────────────────────────────────────────────

def validate_docs_repo(docs_repo: Path) -> None:
    """Ensure docs_repo is a valid git repo with the expected structure."""
    if not (docs_repo / ".git").exists():
        fail(f"{docs_repo} is not a git repository.")
    if not (docs_repo / "en").exists():
        fail(
            f"{docs_repo}/en/ not found.\n"
            "Ensure this is the docs-integrator repository (should have an 'en/' subdirectory)."
        )


def infer_fork(docs_repo: Path) -> str:
    """Infer fork OWNER/REPO from the 'origin' remote URL."""
    try:
        url = run(["git", "remote", "get-url", "origin"], cwd=docs_repo)
        m = re.search(r"[:/]([^/:]+/[^/]+?)(?:\.git)?$", url)
        if m:
            return m.group(1)
    except subprocess.CalledProcessError:
        pass
    fail(
        "Could not infer fork slug from git remote 'origin'.\n"
        "Pass --fork OWNER/REPO explicitly."
    )


# ── Step 3: Detect category ───────────────────────────────────────────────────

def detect_category(connector_slug: str, category_arg: str | None) -> str:
    """Return connector category from explicit arg or built-in map."""
    if category_arg:
        cat = category_arg.lower()
        if cat not in AVAILABLE_CATEGORIES:
            fail(
                f"Unknown category '{cat}'.\n"
                f"Available: {', '.join(AVAILABLE_CATEGORIES)}"
            )
        return cat

    slug = connector_slug.lower()
    # Exact match
    if slug in CATEGORY_MAP:
        cat = CATEGORY_MAP[slug]
        info(f"Auto-detected category: {cat}")
        return cat
    # Substring match
    for key, cat in CATEGORY_MAP.items():
        if key in slug or slug in key:
            info(f"Auto-detected category: {cat} (matched '{key}')")
            return cat

    fail(
        f"Could not auto-detect category for connector '{connector_slug}'.\n"
        f"Available categories: {', '.join(AVAILABLE_CATEGORIES)}\n"
        "Pass --category CATEGORY to specify it."
    )


# ── Step 4: Sync dev + create branch ──────────────────────────────────────────

def sync_and_branch(
    docs_repo: Path,
    branch_name: str,
    dry_run: bool,
    upstream_slug: str = DEFAULT_UPSTREAM,
    base_branch: str = "main",
) -> None:
    """Fast-forward fork's base branch from upstream, then create the feature branch."""
    remotes = run(["git", "remote"], cwd=docs_repo).split()
    if "upstream" not in remotes:
        fail(
            "'upstream' remote not found in docs repo.\n"
            "Add it with:\n"
            f"  git remote add upstream https://github.com/{upstream_slug}.git"
        )

    if dry_run:
        dry(f"git fetch upstream  (in {docs_repo})")
        dry(f"git checkout {base_branch} && git merge upstream/{base_branch} --ff-only")
        dry(f"git checkout -b {branch_name}")
        return

    info(f"Fetching upstream/{base_branch}...")
    subprocess.run(["git", "fetch", "upstream"], cwd=str(docs_repo), check=True)
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
    info(f"Creating branch: {branch_name}")
    subprocess.run(["git", "checkout", "-b", branch_name], cwd=str(docs_repo), check=True)


# ── Steps 5–8: Place docs and update sidebar via Claude Code ──────────────────

def run_claude_code_placement(
    docs_repo: Path,
    category: str,
    connector_slug: str,
    connector_name: str,
    source_doc_path: Path,
    screenshot_files: list[Path],
    dry_run: bool,
) -> None:
    """
    Use the Claude Code CLI (claude --print) to:
      1. Read the generated doc and rewrite ../screenshots/ paths to static img paths
      2. Write example.md to the correct catalog location
      3. Copy screenshots to the static img directory
      4. Intelligently edit sidebars.ts to add the example entry to the right
         connector block (identified by link.id containing the connector slug)
    """
    example_md_target = (
        docs_repo / "en" / "docs" / "connectors" / "catalog"
        / category / connector_slug / "example.md"
    )
    screenshot_target_dir = (
        docs_repo / "en" / "static" / "img" / "connectors" / "catalog"
        / category / connector_slug
    )
    sidebars_path = docs_repo / "en" / "sidebars.ts"
    static_img_prefix = f"/img/connectors/catalog/{category}/{connector_slug}/"

    screenshot_list = "\n".join(f"  - {f}" for f in screenshot_files) or "  (none)"

    prompt = f"""\
You are a documentation placement assistant for the WSO2 Integrator docs project.
Perform each step precisely in order, using the Read, Write, Edit, and Bash tools.

## Context
- Connector name : {connector_name}
- Connector slug : {connector_slug}
- Category       : {category}

## Step 1 — Rewrite screenshot paths in the doc
Read the file at: {source_doc_path}
Replace EVERY occurrence of the string `../screenshots/` with `{static_img_prefix}`
Keep the rest of the file content exactly as-is.

## Step 2 — Write example.md
First run: mkdir -p "{example_md_target.parent}"
Then write the rewritten content (from Step 1) to: {example_md_target}
Use the Write tool for this — do NOT use Bash echo/cat.

## Step 3 — Copy screenshots
Run: mkdir -p "{screenshot_target_dir}"
Then copy each of the following files into {screenshot_target_dir}/:
{screenshot_list}
Use individual `cp` commands for each file.

## Step 4 — Update sidebars.ts
Read the file: {sidebars_path}
Find the connector's sidebar entry: the TypeScript object whose `link` property
has an `id` field that contains the string '{connector_slug}'
(e.g. `id: 'connectors/catalog/{category}/{connector_slug}/overview'`).
That object has an `items` array. Append the string
  'connectors/catalog/{category}/{connector_slug}/example'
as the last element of that `items` array, matching the trailing-comma style of
the surrounding entries. Use the Edit tool to make this precise change.

Confirm each step as you complete it. If a step fails, report the error clearly.
"""

    if dry_run:
        dry("Claude Code doc placement prompt (steps 5-8):")
        for line in prompt.splitlines():
            dry(f"  {line}")
        return

    info("Running Claude Code to place docs and update sidebars...")
    cmd = [
        "claude", "--print",
        "--permission-mode", "bypassPermissions",
        "--allowedTools", "Read,Write,Edit,Bash(mkdir:*),Bash(cp:*)",
        "--model", "claude-sonnet-4-6",
        "-p", prompt,
    ]
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    # Stream stdout in real-time so progress is visible while Claude works
    for line in proc.stdout:
        info(f"  [claude] {line.rstrip()}")

    # Read stderr only after stdout is exhausted (avoids pipe deadlock)
    stderr_output = proc.stderr.read()
    proc.wait()

    if proc.returncode != 0:
        fail(
            f"Claude Code doc placement failed (exit {proc.returncode}).\n"
            f"{stderr_output.strip()}"
        )
    info("Claude Code placement complete.")


# ── Step 9: Docusaurus preview screenshots ────────────────────────────────────

def take_preview_screenshots(
    docs_repo: Path,
    connector_slug: str,
    category: str,
    artifacts_dir: Path,
    dry_run: bool,
) -> list[Path]:
    """
    Start Docusaurus dev server, take scroll-based desktop screenshots
    of the connector example page covering all content.
    Returns list of screenshot paths saved to artifacts/preview-screenshots/.
    """
    if dry_run:
        dry("Start Docusaurus server and take full-page desktop preview screenshots")
        return []

    en_dir = docs_repo / "en"
    if not (en_dir / "node_modules").exists():
        raise PreviewError(
            f"node_modules not found in {en_dir}.\n"
            f"Run: cd {en_dir} && npm install"
        )

    preview_dir = artifacts_dir / "preview-screenshots"
    preview_dir.mkdir(parents=True, exist_ok=True)

    page_url = (
        f"http://localhost:{PREVIEW_PORT}/docs/connectors/catalog"
        f"/{category}/{connector_slug}/example"
    )

    info("Starting Docusaurus dev server...")
    server_proc = subprocess.Popen(
        ["npm", "run", "start", "--", f"--port={PREVIEW_PORT}", "--no-open"],
        cwd=str(en_dir),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    # Poll until server is ready (max 90s)
    ready = False
    for _ in range(90):
        try:
            urllib.request.urlopen(f"http://localhost:{PREVIEW_PORT}", timeout=1)
            ready = True
            break
        except Exception:
            time.sleep(1)

    if not ready:
        server_proc.kill()
        raise PreviewError(f"Docusaurus server did not start within 90s on port {PREVIEW_PORT}.")

    info(f"Server ready. Navigating to: {page_url}")

    screenshot_files: list[Path] = []
    try:
        from playwright.sync_api import sync_playwright  # type: ignore

        with sync_playwright() as p:
            browser = p.chromium.launch()
            page = browser.new_page(
                viewport={"width": VIEWPORT_WIDTH, "height": VIEWPORT_HEIGHT}
            )
            page.goto(page_url)
            page.wait_for_load_state("networkidle")
            page.wait_for_timeout(1000)  # let any animations/fonts settle

            page_height: int = page.evaluate("document.body.scrollHeight")
            info(f"Page height: {page_height}px — taking scroll screenshots at {VIEWPORT_HEIGHT}px steps")

            # Build scroll positions: 0, 900, 1800, … + final bottom position
            positions = list(range(0, page_height, VIEWPORT_HEIGHT))
            # Ensure the very bottom of the page is always captured
            bottom = max(0, page_height - VIEWPORT_HEIGHT)
            if not positions or positions[-1] < bottom:
                positions.append(bottom)

            for i, scroll_y in enumerate(positions, start=1):
                page.evaluate(f"window.scrollTo(0, {scroll_y})")
                page.wait_for_timeout(400)  # let lazy-loaded images render
                out = preview_dir / f"{connector_slug.replace('.', '_')}_preview_{i:02d}.png"
                page.screenshot(path=str(out))
                screenshot_files.append(out)
                info(f"  [{i:02d}] scroll={scroll_y}px → {out.name}")

            browser.close()
    finally:
        server_proc.send_signal(signal.SIGTERM)
        try:
            server_proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            server_proc.kill()
        info("Docusaurus server stopped.")

    info(f"Captured {len(screenshot_files)} preview screenshot(s).")
    return screenshot_files


def upload_preview_as_release(
    screenshot_files: list[Path],
    connector_name: str,
    connector_slug: str,
    branch_name: str,
    fork: str,
) -> list[str]:
    """
    Upload preview screenshots as assets on a pre-release tag of the fork.
    Returns list of GitHub release asset download URLs for embedding in markdown.

    The release is marked as pre-release and can be deleted after PR review.
    Images are NOT committed to the docs-integrator repository.
    """
    if not screenshot_files:
        return []

    timestamp = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
    tag = f"docs-preview-{connector_slug.replace('.', '_')}-{timestamp}"
    title = f"Doc preview: {connector_name} connector example"
    notes = (
        f"Preview screenshots of the rendered docs page for branch `{branch_name}`.\n\n"
        "> This pre-release exists only for PR review purposes and can be deleted after the PR is merged."
    )

    info(f"Uploading {len(screenshot_files)} preview screenshot(s) as release assets on {fork}...")
    cmd = [
        "gh", "release", "create", tag,
        "--repo", fork,
        "--title", title,
        "--notes", notes,
        "--prerelease",
    ] + [str(f) for f in screenshot_files]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        release_url = result.stdout.strip()
        info(f"Pre-release created: {release_url}")
    except subprocess.CalledProcessError as e:
        warn(
            f"Failed to create GitHub release: {e.stderr.strip()}\n"
            "Preview screenshots will not be included in the PR body."
        )
        return []

    fork_owner, fork_repo = fork.split("/")
    return [
        f"https://github.com/{fork_owner}/{fork_repo}/releases/download/{tag}/{f.name}"
        for f in screenshot_files
    ]


# ── Step 10: Commit and push ──────────────────────────────────────────────────

def commit_and_push(
    docs_repo: Path,
    connector_name: str,
    branch_name: str,
    dry_run: bool,
    generated_paths: Sequence[Path],
) -> None:
    """Stage only the generated files, commit, and push the feature branch to origin."""
    paths_str = " ".join(map(str, generated_paths))
    if dry_run:
        dry(f"git add -- {paths_str}")
        dry(f"git commit -m 'docs: add {connector_name} connector example guide'")
        dry(f"git push origin {branch_name}")
        return
    info("Committing changes...")
    subprocess.run(["git", "add", "--", *map(str, generated_paths)], cwd=str(docs_repo), check=True)
    subprocess.run(
        ["git", "commit", "-m", f"docs: add {connector_name} connector example guide"],
        cwd=str(docs_repo),
        check=True,
    )
    info(f"Pushing branch '{branch_name}' to origin...")
    subprocess.run(["git", "push", "origin", branch_name], cwd=str(docs_repo), check=True)


# ── Step 11: Create PR ────────────────────────────────────────────────────────

def build_pr_body(
    connector_name: str,
    operation_name: str,
    category: str,
    connector_slug: str,
    preview_urls: list[str],
) -> str:
    """Build the WSO2 PR template body with docs-relevant sections only."""
    preview_section = ""
    if preview_urls:
        images = "\n\n".join(
            f"![Desktop preview {i + 1:02d}]({url})"
            for i, url in enumerate(preview_urls)
        )
        preview_section = (
            "\n\n## Doc page preview (desktop)\n\n"
            "> Playwright screenshots of the rendered example page taken locally.\n\n"
            f"{images}"
        )

    return f"""\
## Purpose

Adds a step-by-step example guide for the {connector_name} connector, covering \
connection setup and the {operation_name} operation with embedded screenshots.

## Goals

- Provide a complete walkthrough for configuring the {connector_name} connector \
in the WSO2 Integrator low-code canvas
- Include annotated screenshots at each key configuration step

## Approach

Content generated by the connector-docs-automations pipeline. \
Example page preview screenshots are included at the bottom of this description.

## Release note

Added {connector_name} connector example guide showing how to configure the \
{operation_name} operation using the WSO2 Integrator low-code canvas.

## Documentation

- `en/docs/connectors/catalog/{category}/{connector_slug}/example.md` (added)
- `en/static/img/connectors/catalog/{category}/{connector_slug}/` (screenshots added)
- `en/sidebars.ts` (sidebar entry added)

## Security checks

- Followed secure coding standards: N/A (documentation only)
- Ran FindSecurityBugs plugin: N/A (documentation only)
{preview_section}
"""


def create_pr(
    fork: str,
    upstream: str,
    base_branch: str,
    connector_name: str,
    branch_name: str,
    pr_body: str,
    dry_run: bool,
) -> str:
    """Create the GitHub PR from fork branch to upstream base branch."""
    fork_owner = fork.split("/")[0]
    title = f"docs: add {connector_name} connector example guide"
    head = f"{fork_owner}:{branch_name}"

    if dry_run:
        dry(f"gh pr create --repo {upstream} --head {head} --base {base_branch}")
        dry(f"  Title: {title}")
        return "(dry run — no PR created)"

    info(f"Creating PR: {upstream} ← {head}")
    try:
        result = subprocess.run(
            [
                "gh", "pr", "create",
                "--repo", upstream,
                "--head", head,
                "--base", base_branch,
                "--title", title,
                "--body", pr_body,
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        fail(f"Failed to create PR:\n{e.stderr.strip()}")


# ── CLI ───────────────────────────────────────────────────────────────────────

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Publish connector docs to the WSO2 Integrator docs-integrator fork "
            "and create a PR with Playwright preview screenshots."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python python/publish_docs.py\n"
            "  python python/publish_docs.py --dry-run\n"
            "  python python/publish_docs.py --category messaging --no-preview\n"
            "  python python/publish_docs.py --docs-repo ~/repos/docs-integrator\n"
        ),
    )
    parser.add_argument(
        "--docs-repo",
        default=str(DEFAULT_DOCS_REPO),
        metavar="PATH",
        help=(
            f"Path to local clone of the docs-integrator fork "
            f"(default: {DEFAULT_DOCS_REPO})"
        ),
    )
    parser.add_argument(
        "--artifacts-dir",
        default="./artifacts",
        metavar="PATH",
        help="Path to pipeline artifacts directory (default: ./artifacts)",
    )
    parser.add_argument(
        "--fork",
        default=os.environ.get("DOCS_INTEGRATOR_FORK"),
        metavar="OWNER/REPO",
        help=(
            "Fork repo slug, e.g. your-org/docs-integrator "
            "(default: DOCS_INTEGRATOR_FORK env var; inferred from git remote 'origin' if unset)"
        ),
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
        help=(
            f"Connector category — skip auto-detection. "
            f"Choices: {', '.join(AVAILABLE_CATEGORIES)}"
        ),
    )
    parser.add_argument(
        "--no-pr",
        action="store_true",
        help="Push the branch but skip creating a pull request",
    )
    parser.add_argument(
        "--no-preview",
        action="store_true",
        help="Skip Playwright preview screenshots",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print planned actions without making any changes",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    artifacts_dir = Path(args.artifacts_dir).resolve()
    docs_repo = Path(args.docs_repo).resolve()

    upstream = args.upstream
    fork = None  # resolved below after docs_repo is validated
    if args.dry_run:
        print("=" * 79)
        print("DRY RUN — no changes will be made")
        print("=" * 79)

    # ── 1. Read artifacts ─────────────────────────────────────────────────────
    source_doc_path, doc_content = find_latest_doc(artifacts_dir)
    connector_name, connector_slug, operation_name = extract_connector_info(doc_content, artifacts_dir)
    screenshot_files = find_screenshots(artifacts_dir)

    # ── 2. Validate docs repo ─────────────────────────────────────────────────
    validate_docs_repo(docs_repo)
    fork = args.fork or infer_fork(docs_repo)
    info(f"Fork: {fork}  |  Upstream: {upstream}  |  Base branch: {args.base_branch}")

    # ── 3. Detect category ────────────────────────────────────────────────────
    category = detect_category(connector_slug, args.category)

    # ── 4. Sync dev + create branch ───────────────────────────────────────────
    branch_name = f"docs/add-{connector_slug}-connector-example-documentation"
    info(f"Branch: {branch_name}")
    sync_and_branch(docs_repo, branch_name, args.dry_run,
                    upstream_slug=upstream, base_branch=args.base_branch)

    # ── 5-8. Place example.md, copy screenshots, update sidebar ───────────────
    run_claude_code_placement(
        docs_repo, category, connector_slug, connector_name,
        source_doc_path, screenshot_files, args.dry_run,
    )

    # ── 9. Commit + push ──────────────────────────────────────────────────────
    generated_paths: list[Path] = [
        docs_repo / "en" / "docs" / "connectors" / "catalog" / category / connector_slug / "example.md",
        docs_repo / "en" / "static" / "img" / "connectors" / "catalog" / category / connector_slug,
        docs_repo / "en" / "sidebars.ts",
    ]
    commit_and_push(docs_repo, connector_name, branch_name, args.dry_run, generated_paths)

    if args.no_pr:
        print()
        print("=" * 79)
        if args.dry_run:
            print("Dry run complete. Remove --dry-run to execute.")
        else:
            print(f"Branch pushed: {branch_name}  (--no-pr: skipped PR creation)")
        print("=" * 79)
        return

    # ── 10. Preview screenshots (not committed to docs repo) ──────────────────
    preview_urls: list[str] = []
    if not args.no_preview:
        try:
            preview_files = take_preview_screenshots(
                docs_repo, connector_slug, category, artifacts_dir, args.dry_run
            )
            if preview_files and not args.dry_run:
                preview_urls = upload_preview_as_release(
                    preview_files, connector_name, connector_slug, branch_name, fork
                )
        except Exception as exc:
            warn(f"Preview step failed (branch already pushed — continuing to PR creation): {exc}")

    # ── 11. Create PR ─────────────────────────────────────────────────────────
    pr_body = build_pr_body(
        connector_name, operation_name, category, connector_slug, preview_urls
    )
    pr_url = create_pr(
        fork, upstream, args.base_branch,
        connector_name, branch_name, pr_body, args.dry_run,
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
