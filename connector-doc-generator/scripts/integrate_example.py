#!/usr/bin/env python3
"""Validate and place example-generator artifacts into docs-integrator."""

from __future__ import annotations

import argparse
import json
import re
import shutil
from pathlib import Path


def fail(message: str) -> None:
    raise RuntimeError(message)


def find_single_markdown(artifacts: Path) -> Path:
    files = sorted((artifacts / "workflow-docs").glob("*.md"))
    if len(files) != 1:
        fail(f"Expected exactly one workflow guide, found {len(files)}")
    return files[0]


def find_screenshots(artifacts: Path, expected: int) -> list[Path]:
    files = sorted((artifacts / "screenshots").glob("*_screenshot_*.png"))
    if len(files) != expected:
        fail(f"Expected {expected} screenshots, found {len(files)}")
    return files


def reconcile_example_sidebar(sidebar: Path, category: str, module: str) -> None:
    text = sidebar.read_text(encoding="utf-8")
    base = f"connectors/catalog/{category}/{module}"
    overview = f"{base}/overview"
    overview_pos = text.find(overview)
    if overview_pos < 0:
        fail(f"Existing sidebar overview anchor not found: {overview}")

    items_marker = text.find("items: [", overview_pos)
    if items_marker < 0:
        fail(f"Sidebar items array not found for {module}")
    items_start = items_marker + len("items: [")

    depth = 1
    cursor = items_start
    while cursor < len(text) and depth:
        if text[cursor] == "[":
            depth += 1
        elif text[cursor] == "]":
            depth -= 1
        cursor += 1
    if depth:
        fail(f"Unclosed sidebar items array for {module}")

    items_end = cursor - 1
    existing = text[items_start:items_end]
    example_id = f"{base}/example"
    if example_id in existing:
        return

    indent_match = re.search(r"\n([ \t]+)'[^']+',", existing)
    indent = indent_match.group(1) if indent_match else "            "
    insertion = f"\n{indent}'{example_id}',"
    updated = text[:items_end] + insertion + text[items_end:]
    sidebar.write_text(updated, encoding="utf-8")


def integrate(args: argparse.Namespace) -> dict[str, object]:
    docs_repo = Path(args.docs_repo).resolve()
    artifacts = Path(args.artifacts_dir).resolve()
    target_dir = (
        docs_repo / "en" / "docs" / "connectors" / "catalog"
        / args.category / args.module
    )
    overview = target_dir / "overview.md"
    if not overview.exists():
        fail(f"Existing connector overview is required before example placement: {overview}")

    source_doc = find_single_markdown(artifacts)
    expected = 7 if args.mode == "trigger" else 6
    screenshots = find_screenshots(artifacts, expected)
    content = source_doc.read_text(encoding="utf-8")
    if re.search(r"(?:^|[\s(])/(?:home|Users|private|tmp)/", content):
        fail("Generated guide contains an unresolved local absolute path")

    static_prefix = f"/img/connectors/catalog/{args.category}/{args.module}/"
    content = content.replace("../screenshots/", static_prefix)
    if "../screenshots/" in content:
        fail("Generated guide contains unresolved screenshot paths")

    target_dir.mkdir(parents=True, exist_ok=True)
    target_doc = target_dir / "example.md"
    target_doc.write_text(content, encoding="utf-8")

    image_dir = (
        docs_repo / "en" / "static" / "img" / "connectors" / "catalog"
        / args.category / args.module
    )
    image_dir.mkdir(parents=True, exist_ok=True)
    copied: list[str] = []
    for screenshot in screenshots:
        destination = image_dir / screenshot.name
        shutil.copy2(screenshot, destination)
        copied.append(str(destination.relative_to(docs_repo)))

    sidebar = docs_repo / "en" / "sidebars.ts"
    reconcile_example_sidebar(sidebar, args.category, args.module)

    result: dict[str, object] = {
        "mode": args.mode,
        "page": str(target_doc.relative_to(docs_repo)),
        "screenshots": copied,
        "screenshotCount": len(copied),
    }
    if args.result:
        result_path = Path(args.result)
        result_path.parent.mkdir(parents=True, exist_ok=True)
        result_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--docs-repo", required=True)
    parser.add_argument("--artifacts-dir", required=True)
    parser.add_argument("--category", required=True)
    parser.add_argument("--module", required=True)
    parser.add_argument("--mode", choices=("connector", "trigger"), required=True)
    parser.add_argument("--result")
    return parser.parse_args()


if __name__ == "__main__":
    print(json.dumps(integrate(parse_args()), indent=2))
