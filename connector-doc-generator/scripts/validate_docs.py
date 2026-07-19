#!/usr/bin/env python3
"""Hard validation for the combined connector documentation result."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


def validate(args: argparse.Namespace) -> dict[str, object]:
    repo = Path(args.docs_repo).resolve()
    doc_dir = repo / "en/docs/connectors/catalog" / args.category / args.module
    errors: list[str] = []

    required = ["overview.md"]
    if args.reference:
        required.append("action-reference.md")
    if args.examples:
        required.append("example.md")
    for filename in required:
        path = doc_dir / filename
        if not path.exists() or not path.read_text(encoding="utf-8").strip():
            errors.append(f"Required page is missing or empty: {path}")

    local_path = re.compile(r"\.\./screenshots/|(?:^|[\s(])/(?:home|Users|private|tmp)/")
    image_pattern = re.compile(
        rf"/img/connectors/catalog/{re.escape(args.category)}/{re.escape(args.module)}/([^\s)\"']+)"
    )
    pages = sorted(doc_dir.glob("*.md")) if doc_dir.exists() else []
    for page in pages:
        content = page.read_text(encoding="utf-8")
        if local_path.search(content):
            errors.append(f"Unresolved local path in {page}")
        for filename in image_pattern.findall(content):
            image = repo / "en/static/img/connectors/catalog" / args.category / args.module / filename
            if not image.exists():
                errors.append(f"Referenced image does not exist: {image}")

    sidebar = repo / "en/sidebars.ts"
    sidebar_text = sidebar.read_text(encoding="utf-8")
    base = f"connectors/catalog/{args.category}/{args.module}/"
    ids = set(re.findall(rf"['\"]({re.escape(base)}[^'\"]+)['\"]", sidebar_text))
    if f"{base}overview" not in ids:
        errors.append(f"Sidebar overview anchor is missing: {base}overview")
    for doc_id in ids:
        page = repo / "en/docs" / f"{doc_id}.md"
        if not page.exists():
            errors.append(f"Sidebar target does not exist: {page}")

    result: dict[str, object] = {
        "valid": not errors,
        "errors": errors,
        "pages": [str(page.relative_to(repo)) for page in pages],
    }
    if errors:
        raise RuntimeError("\n".join(errors))
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--docs-repo", required=True)
    parser.add_argument("--category", required=True)
    parser.add_argument("--module", required=True)
    parser.add_argument("--reference", action="store_true")
    parser.add_argument("--examples", action="store_true")
    return parser.parse_args()


if __name__ == "__main__":
    print(json.dumps(validate(parse_args()), indent=2))
