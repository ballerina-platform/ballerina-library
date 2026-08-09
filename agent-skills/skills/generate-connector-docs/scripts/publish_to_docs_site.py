#!/usr/bin/env python3
"""Publish a validated connector example page into a local docs-integrator checkout.

Rewrites the authored guide's relative `../screenshots/...` image links to the
site's absolute `/img/connectors/catalog/<category>/<module>/...` convention,
copies the six screenshots into the site's static image tree, writes the guide
to `en/docs/connectors/catalog/<category>/<module>/example.md`, and patches
`en/sidebars.ts` so the connector's category block lists the example page.

Requires `--docs-repo-root` and `--category` to have been supplied to
prepare_run.py — run this only after finalize_run.py has already validated the
guide. Never commits, pushes, or opens a PR; all changes are left as
uncommitted working-tree edits in the docs-integrator checkout.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

SCREENSHOT_LINK_RE = re.compile(r"(!\[[^\]]+\]\()\.\./screenshots/([^)]+\.png)(\))")


def rewrite_image_links(text: str, image_base_url: str) -> tuple[str, int]:
    """Rewrite every `../screenshots/x.png` link to `<image_base_url>/x.png`."""
    count = 0

    def _replace(match: re.Match) -> str:
        nonlocal count
        count += 1
        return f"{match.group(1)}{image_base_url}/{match.group(2)}{match.group(3)}"

    return SCREENSHOT_LINK_RE.sub(_replace, text), count


def copy_screenshots(screenshots_dir: Path, static_img_dir: Path) -> list[str]:
    pngs = sorted(screenshots_dir.glob("*.png"))
    if len(pngs) != 6:
        raise ValueError(f"Expected 6 screenshots in {screenshots_dir}, found {len(pngs)}")
    static_img_dir.mkdir(parents=True, exist_ok=True)
    copied = []
    for png in pngs:
        destination = static_img_dir / png.name
        shutil.copy2(png, destination)
        copied.append(str(destination))
    return copied


def find_closing_bracket(text: str, start: int) -> int:
    """Return the index of the `]` matching the `[` implied to be just before `start`."""
    depth = 1
    pos = start
    while pos < len(text) and depth > 0:
        char = text[pos]
        if char == "[":
            depth += 1
        elif char == "]":
            depth -= 1
        pos += 1
    return pos - 1 if depth == 0 else -1


def find_items_block(text: str, after: int) -> tuple[int, int]:
    """Return (items_start, items_end) for the first `items: [` at/after `after`."""
    items_pos = text.find("items: [", after)
    if items_pos < 0:
        raise ValueError("Could not find an 'items: [' array")
    items_start = items_pos + len("items: [")
    items_end = find_closing_bracket(text, items_start)
    if items_end < 0:
        raise ValueError("Could not find the closing ']' for an items array")
    return items_start, items_end


def patch_sidebar_example(sidebars_path: Path, category: str, module: str, display_name: str) -> bool:
    """Ensure `sidebars.ts` lists the example page for this connector.

    Returns True if the file was modified, False if the entry already existed.
    """
    text = sidebars_path.read_text(encoding="utf-8")
    base_path = f"connectors/catalog/{category}/{module}"
    example_id = f"{base_path}/example"

    for quote in ("'", '"'):
        overview_marker = f"id: {quote}{base_path}/overview{quote}"
        overview_pos = text.find(overview_marker)
        if overview_pos < 0:
            continue
        items_start, items_end = find_items_block(text, overview_pos)
        items_text = text[items_start:items_end]
        if example_id in items_text:
            return False
        # Insert right after the last item's own trailing comma, not blindly before the
        # closing bracket — the array's existing trailing whitespace/indentation before
        # `]` must be preserved as-is rather than duplicated or left dangling mid-line.
        trimmed_len = len(items_text.rstrip())
        insert_at = items_start + trimmed_len
        new_text = (
            text[:insert_at]
            + f"\n            '{example_id}',"
            + "\n          "
            + text[items_end:]
        )
        sidebars_path.write_text(new_text, encoding="utf-8")
        return True

    # Fallback: the connector has no existing sidebar entry at all (connector-doc-generator
    # has not run yet, or was skipped). Add a standalone category block under
    # "Connector Catalog", pointing its own link at the example page.
    for quote in ("'", '"'):
        label_marker = f"label: {quote}Connector Catalog{quote}"
        label_pos = text.find(label_marker)
        if label_pos < 0:
            continue
        items_start, items_end = find_items_block(text, label_pos)
        items_text = text[items_start:items_end]
        if example_id in items_text:
            return False
        block = (
            "\n        {\n"
            "          type: 'category',\n"
            f"          label: '{display_name}',\n"
            f"          link: {{ type: 'doc', id: '{example_id}' }},\n"
            "          items: [\n"
            f"            '{example_id}',\n"
            "          ],\n"
            "        },"
        )
        new_text = text[:items_end] + block + text[items_end:]
        sidebars_path.write_text(new_text, encoding="utf-8")
        return True

    raise ValueError(f"Could not find 'Connector Catalog' or an existing '{base_path}/overview' entry in {sidebars_path}")


def default_display_name(module: str) -> str:
    """Best-effort title-cased display name from a dotted module slug.

    Only used for the standalone fallback insert; prefer running
    connector-doc-generator first so the real, correctly-cased connector name
    from Ballerina.toml is used instead.
    """
    return " ".join(part.capitalize() for part in module.split("."))


def publish(context: dict) -> dict:
    docs_repo_root = context.get("docs_repo_root")
    category = context.get("category_slug")
    module = context.get("module_slug")
    if not docs_repo_root or not category or not module:
        raise ValueError(
            "context.json has no docs-integrator target. Re-run prepare_run.py with "
            "--docs-repo-root and --category before publishing."
        )

    doc_path = Path(context["doc_path"])
    screenshots_dir = Path(context["screenshots_dir"])
    docs_example_path = Path(context["docs_example_path"])
    docs_static_img_dir = Path(context["docs_static_img_dir"])
    sidebars_path = Path(context["docs_sidebars_path"])
    image_base_url = context["docs_image_base_url"]

    if not doc_path.is_file():
        raise ValueError(f"Guide not found — run finalize_run.py first: {doc_path}")

    text = doc_path.read_text(encoding="utf-8")
    rewritten_text, rewritten_count = rewrite_image_links(text, image_base_url)
    if rewritten_count != 6:
        raise ValueError(f"Expected 6 screenshot links to rewrite, rewrote {rewritten_count}")

    copied = copy_screenshots(screenshots_dir, docs_static_img_dir)

    docs_example_path.parent.mkdir(parents=True, exist_ok=True)
    docs_example_path.write_text(rewritten_text, encoding="utf-8")

    display_name = default_display_name(module)
    sidebar_patched = False
    if sidebars_path.is_file():
        sidebar_patched = patch_sidebar_example(sidebars_path, category, module, display_name)

    return {
        "docs_example_path": str(docs_example_path),
        "screenshots_copied": copied,
        "sidebar_patched": sidebar_patched,
        "sidebars_path": str(sidebars_path),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--context", required=True, type=Path)
    args = parser.parse_args()
    try:
        context = json.loads(args.context.read_text(encoding="utf-8"))
        result = publish(context)
    except (OSError, ValueError, json.JSONDecodeError, KeyError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
