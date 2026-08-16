#!/usr/bin/env python3
"""Validate a Central coordinate and create an isolated connector-doc run."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

CENTRAL_BASE = "https://api.central.ballerina.io/2.0/registry/packages"
COORDINATE_RE = re.compile(
    r"^(?P<org>[A-Za-z0-9][A-Za-z0-9_.-]*)/"
    r"(?P<package>[A-Za-z0-9][A-Za-z0-9_.-]*)"
    r"(?::(?P<version>[A-Za-z0-9][A-Za-z0-9_.+-]*))?$"
)

# Category slugs accepted by connector-doc-generator and used under
# en/docs/connectors/catalog/<slug>/ in docs-integrator. Names match the
# "Area/<Name>" package keyword docs-integrator connectors are tagged with
# (see connector-doc-generator/modules/category's CATALOG_CATEGORIES), so a
# package's own Central metadata is enough to derive its category slug.
DOCS_CATEGORIES = {
    "ai-ml": "AI & ML",
    "built-in": "Built-in",
    "cloud-infrastructure": "Cloud & Infrastructure",
    "communication": "Communication",
    "crm-sales": "CRM & Sales",
    "database": "Database",
    "developer-tools": "Developer Tools",
    "ecommerce": "E-Commerce",
    "erp-business": "ERP & Business",
    "finance-accounting": "Finance & Accounting",
    "healthcare": "Healthcare",
    "hrms": "HRMS",
    "marketing-social": "Marketing & Social",
    "messaging": "Messaging",
    "productivity-collaboration": "Productivity & Collaboration",
    "security-identity": "Security & Identity",
    "storage-file": "Storage & Files",
}
DOCS_CATEGORY_SLUGS = set(DOCS_CATEGORIES)
_AREA_NAME_TO_SLUG = {name.casefold(): slug for slug, name in DOCS_CATEGORIES.items()}
_AREA_KEYWORD_RE = re.compile(r"^Area/(.+)$")


def derive_category_from_keywords(metadata: dict) -> str | None:
    """Return the docs-integrator category slug implied by a package's own
    `Area/<Name>` Central keyword, or None if absent or unrecognized."""
    for keyword in metadata.get("keywords") or []:
        match = _AREA_KEYWORD_RE.match(str(keyword).strip())
        if match:
            return _AREA_NAME_TO_SLUG.get(match.group(1).strip().casefold())
    return None


def parse_coordinate(value: str) -> tuple[str, str, str]:
    match = COORDINATE_RE.fullmatch(value.strip())
    if not match:
        raise ValueError(
            "Expected a full Ballerina Central coordinate: organization/package "
            "or organization/package:version"
        )
    return match.group("org"), match.group("package"), match.group("version") or "latest"


def central_url(org: str, package: str, version: str) -> str:
    parts = [urllib.parse.quote(item, safe="") for item in (org, package, version)]
    return f"{CENTRAL_BASE}/{'/'.join(parts)}"


def safe_slug(*parts: str, separator: str = "-") -> str:
    joined = separator.join(part.lower() for part in parts)
    return re.sub(rf"[^{re.escape(separator)}a-z0-9]+", separator, joined).strip(separator)


def fetch_metadata(url: str, timeout: int = 20) -> dict:
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            if response.status != 200:
                raise RuntimeError(f"Ballerina Central returned HTTP {response.status}")
            payload = json.load(response)
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            raise RuntimeError("Package or requested version was not found in Ballerina Central") from exc
        raise RuntimeError(f"Ballerina Central returned HTTP {exc.code}") from exc
    except (urllib.error.URLError, TimeoutError) as exc:
        raise RuntimeError(f"Could not reach Ballerina Central: {exc}") from exc
    if not isinstance(payload, dict):
        raise RuntimeError("Ballerina Central returned an unexpected response")
    return payload


def prerequisite_status() -> dict[str, bool]:
    return {
        name: shutil.which(name) is not None
        for name in ("node", "npx", "python3", "code-server")
    }


def docs_site_paths(docs_repo_root: str, category: str, package: str) -> dict[str, str]:
    """Compute the docs-integrator connector directory and its overview.md.

    `package` is used verbatim as the module slug — docs-integrator directories
    are named after the exact Ballerina package name (e.g. `hubspot.events.completions`),
    matching connector-doc-generator's own convention. Everything else about where the
    example page and its screenshots land is `connector-doc-generator/scripts/
    integrate_example.py`'s own concern, computed from `--docs-repo`/`--category`/
    `--module` — this only needs enough to check whether that tool has already run.
    """
    repo_root = Path(docs_repo_root).resolve()
    connector_dir = repo_root / "en" / "docs" / "connectors" / "catalog" / category / package
    return {
        "docs_repo_root": str(repo_root),
        "category_slug": category,
        "module_slug": package,
        "docs_connector_dir": str(connector_dir),
        "docs_overview_path": str(connector_dir / "overview.md"),
    }


def build_context(
    coordinate: str,
    root: Path,
    metadata: dict,
    docs_repo_root: str | None = None,
    category: str | None = None,
    github_repo: str | None = None,
) -> dict:
    org, package, requested_version = parse_coordinate(coordinate)
    resolved_version = str(metadata.get("version") or requested_version)
    slug = safe_slug(org, package)
    image_prefix = safe_slug(org, package, separator="_")
    # No org prefix, and dots preserved: matches every existing sample directory name in
    # wso2/integration-samples (e.g. "hubspot.crm.pipelines_connector_sample",
    # "aws.s3_connector_sample") — `package` is already constrained to a safe character set
    # by COORDINATE_RE, so it needs no further sanitizing for use as a directory name.
    sample_name = f"{package}_connector_sample"
    run_dir = (root / "artifacts" / slug).resolve()
    if run_dir.exists() and any(run_dir.iterdir()):
        raise FileExistsError(
            f"Refusing to overwrite existing run directory: {run_dir}. "
            "Move it or choose a clean invocation root."
        )

    if category is not None and category not in DOCS_CATEGORY_SLUGS:
        raise ValueError(
            f"Unknown category '{category}'. Expected one of: {', '.join(sorted(DOCS_CATEGORY_SLUGS))}"
        )
    if docs_repo_root is not None and category is None:
        category = derive_category_from_keywords(metadata)

    paths = {
        "run_dir": run_dir,
        "workflow_docs_dir": run_dir / "workflow-docs",
        "screenshots_dir": run_dir / "screenshots",
        "sample_parent_dir": run_dir / "sample",
        "sample_dir": run_dir / "sample" / sample_name,
        "run_log_dir": run_dir / "run-log",
    }
    for path in paths.values():
        path.mkdir(parents=True, exist_ok=True)

    metadata_path = paths["run_log_dir"] / "central-metadata.json"
    context_path = paths["run_log_dir"] / "context.json"
    doc_path = paths["workflow_docs_dir"] / f"{image_prefix}.md"
    metadata_path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    context = {
        "requested_coordinate": coordinate.strip(),
        "organization": org,
        "package": package,
        "requested_version": requested_version,
        "resolved_version": resolved_version,
        "resolved_coordinate": f"{org}/{package}:{resolved_version}",
        "central_url": central_url(org, package, requested_version),
        "slug": slug,
        "image_prefix": image_prefix,
        "sample_name": sample_name,
        "invocation_root": str(root.resolve()),
        **{name: str(path) for name, path in paths.items()},
        "doc_path": str(doc_path),
        "metadata_path": str(metadata_path),
        "context_path": str(context_path),
        "prepared_at": datetime.now(timezone.utc).isoformat(),
        "prerequisites": prerequisite_status(),
        "code_server": {"port": 8080, "started_by_run": False, "pid": None},
        "github_repo": github_repo or f"module-{org}-{package}",
    }
    if docs_repo_root is not None and category is not None:
        context.update(docs_site_paths(docs_repo_root, category, package))
    elif docs_repo_root is not None:
        # A docs-integrator target was requested, but no category could be derived from
        # this package's own Central keywords. Preserve docs_repo_root (distinct from the
        # "no docs target at all" case below) so the caller knows to ask for --category
        # explicitly and re-run, rather than silently falling back to a scratch-only run.
        context.update({
            "docs_repo_root": str(Path(docs_repo_root).resolve()),
            "category_slug": None,
            "module_slug": package,
            "docs_connector_dir": None,
            "docs_overview_path": None,
        })
    else:
        context.update({
            "docs_repo_root": None,
            "category_slug": None,
            "module_slug": None,
            "docs_connector_dir": None,
            "docs_overview_path": None,
        })
    context_path.write_text(json.dumps(context, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return context


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("coordinate", help="organization/package or organization/package:version")
    parser.add_argument("--root", type=Path, default=Path.cwd(), help="Invocation repository root")
    parser.add_argument("--metadata-file", type=Path, help="Use saved Central JSON (tests/offline replay)")
    parser.add_argument(
        "--docs-repo-root",
        help="Local checkout of wso2/docs-integrator. When set with --category, the example "
        "page is published directly into it by connector-doc-generator's own "
        "scripts/integrate_example.py after finalization.",
    )
    parser.add_argument(
        "--category",
        choices=sorted(DOCS_CATEGORY_SLUGS),
        help="docs-integrator catalog category slug. Auto-derived from the package's own "
        "Area/... Central keyword when omitted; pass explicitly to override or to supply "
        "one when the package has no Area/... keyword.",
    )
    parser.add_argument(
        "--github-repo",
        help="Connector's GitHub repo name under github.com/ballerina-platform "
        "(default: module-<organization>-<package>).",
    )
    args = parser.parse_args()
    try:
        org, package, version = parse_coordinate(args.coordinate)
        metadata = (
            json.loads(args.metadata_file.read_text(encoding="utf-8"))
            if args.metadata_file
            else fetch_metadata(central_url(org, package, version))
        )
        if not isinstance(metadata, dict):
            raise ValueError("Ballerina Central metadata must be a JSON object")
        context = build_context(
            args.coordinate,
            args.root,
            metadata,
            docs_repo_root=args.docs_repo_root,
            category=args.category,
            github_repo=args.github_repo,
        )
    except (ValueError, RuntimeError, FileExistsError, OSError, json.JSONDecodeError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1
    print(json.dumps(context, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
