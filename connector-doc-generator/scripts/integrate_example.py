#!/usr/bin/env python3
"""Validate and place example-generator artifacts into docs-integrator."""

from __future__ import annotations

import argparse
import json
import re
import shutil
from pathlib import Path
from typing import NoReturn


def fail(message: str) -> NoReturn:
    """Raise an integration error while preserving type narrowing."""
    raise RuntimeError(message)


def find_single_markdown(artifacts: Path) -> Path:
    """Return the single generated workflow guide."""
    files = sorted((artifacts / "workflow-docs").glob("*.md"))
    if len(files) != 1:
        fail(f"Expected exactly one workflow guide, found {len(files)}")
    return files[0]


def find_screenshots(artifacts: Path, expected: int) -> list[Path]:
    """Return generated screenshots after enforcing the expected count."""
    files = sorted((artifacts / "screenshots").glob("*_screenshot_*.png"))
    if len(files) != expected:
        fail(f"Expected {expected} screenshots, found {len(files)}")
    return files


def connector_display_name(overview_text: str, fallback: str) -> str:
    """Extract the connector's own display name from overview.md's frontmatter title.

    The title itself is "<Name> Overview" (matching WSO2's own documentation convention,
    confirmed across mi.docs.wso2.com and docs-integrator's pre-existing Twilio/HTTP pages),
    so strip that suffix back off to get the bare name for use in prose or other titles.
    """
    title_match = re.search(r'^title:\s*"([^"]+)"', overview_text, re.M)
    if not title_match:
        return fallback
    return re.sub(r"\s+Overview$", "", title_match.group(1))


def add_example_link_to_overview(overview: Path, module: str) -> bool:
    """Add an Example bullet to overview.md's Documentation section.

    Neither this script nor connector-doc-generator's own prompt templates ever add this
    link deterministically — overview.md is written before example.md exists, and nothing
    revisits it afterward. Sibling connectors that do have the link (e.g. Twilio) appear to
    have picked it up incidentally from the model noticing the file during an "update mode"
    regeneration, not from any guaranteed mechanism. Make it guaranteed instead.

    Returns True if the file was modified, False if the link was already present.
    """
    text = overview.read_text(encoding="utf-8")
    if re.search(r"\(example\.md\)", text):
        return False

    display_name = connector_display_name(text, module)
    bullet = (
        f"\n* **[Example](example.md)**: Learn how to build and configure an integration "
        f"using the **{display_name}** connector, including connection setup, operation "
        f"configuration, and execution flow.\n"
    )

    doc_heading = re.search(r"^## Documentation\s*$", text, re.M)
    if doc_heading is None:
        fail(f"'## Documentation' section not found in {overview}")
    next_heading = re.search(r"\n## ", text[doc_heading.end():])
    insertion_pos = doc_heading.end() + next_heading.start() if next_heading else len(text)
    updated = text[:insertion_pos].rstrip("\n") + "\n" + bullet + text[insertion_pos:]
    overview.write_text(updated, encoding="utf-8")
    return True


def ensure_example_frontmatter(content: str, display_name: str, module: str) -> str:
    """Prepend a frontmatter block to example.md if it doesn't already have one.

    The example-generator's own template is deliberately site-agnostic — it doesn't know at
    authoring time whether its output is headed for docs-integrator or staying as a scratch
    preview — so it never writes frontmatter itself. Add the docs-integrator-specific title
    here, at the point this content is actually placed into the site, matching the same
    "<Name> <Section>" title convention as the other three generated pages.
    """
    if content.lstrip().startswith("---"):
        return content
    frontmatter = (
        "---\n"
        "connector: true\n"
        f'connector_name: "{module}"\n'
        f'title: "{display_name} Example"\n'
        "---\n\n"
    )
    return frontmatter + content


def reconcile_example_sidebar(sidebar: Path, category: str, module: str) -> None:
    """Add the example page to an existing connector sidebar category."""
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
    trailing_indent = re.search(r"\n[ \t]*$", existing)
    insertion_pos = trailing_indent.start() if trailing_indent else len(existing)
    insertion = f"\n{indent}'{example_id}',"
    reconciled = existing[:insertion_pos] + insertion + existing[insertion_pos:]
    updated = text[:items_start] + reconciled + text[items_end:]
    sidebar.write_text(updated, encoding="utf-8")


def integrate(args: argparse.Namespace) -> dict[str, object]:
    """Validate and copy example artifacts into docs-integrator."""
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

    display_name = connector_display_name(overview.read_text(encoding="utf-8"), args.module)
    content = ensure_example_frontmatter(content, display_name, args.module)

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
    overview_updated = add_example_link_to_overview(overview, args.module)

    result: dict[str, object] = {
        "mode": args.mode,
        "page": str(target_doc.relative_to(docs_repo)),
        "screenshots": copied,
        "screenshotCount": len(copied),
        "overviewUpdated": overview_updated,
    }
    if args.result:
        result_path = Path(args.result)
        result_path.parent.mkdir(parents=True, exist_ok=True)
        result_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return result


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
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
