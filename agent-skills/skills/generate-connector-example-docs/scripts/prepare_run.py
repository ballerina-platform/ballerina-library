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


def build_context(coordinate: str, root: Path, metadata: dict) -> dict:
    org, package, requested_version = parse_coordinate(coordinate)
    resolved_version = str(metadata.get("version") or requested_version)
    slug = safe_slug(org, package)
    image_prefix = safe_slug(org, package, separator="_")
    sample_name = f"{safe_slug(org, package, separator='_')}_connector_sample"
    run_dir = (root / "artifacts" / slug).resolve()
    if run_dir.exists() and any(run_dir.iterdir()):
        raise FileExistsError(
            f"Refusing to overwrite existing run directory: {run_dir}. "
            "Move it or choose a clean invocation root."
        )

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
    }
    context_path.write_text(json.dumps(context, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return context


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("coordinate", help="organization/package or organization/package:version")
    parser.add_argument("--root", type=Path, default=Path.cwd(), help="Invocation repository root")
    parser.add_argument("--metadata-file", type=Path, help="Use saved Central JSON (tests/offline replay)")
    args = parser.parse_args()
    try:
        org, package, version = parse_coordinate(args.coordinate)
        metadata = (
            json.loads(args.metadata_file.read_text(encoding="utf-8"))
            if args.metadata_file
            else fetch_metadata(central_url(org, package, version))
        )
        context = build_context(args.coordinate, args.root, metadata)
    except (ValueError, RuntimeError, FileExistsError, OSError, json.JSONDecodeError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1
    print(json.dumps(context, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
