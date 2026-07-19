#!/usr/bin/env python3
"""Capture one full-page preview for each changed connector Markdown page."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from urllib.parse import urljoin


def page_route(docs_repo: Path, page: Path) -> str:
    content = page.read_text(encoding="utf-8")
    frontmatter = re.match(r"^---\s*\n(.*?)\n---\s*\n", content, re.DOTALL)
    if frontmatter:
        slug_match = re.search(r"^slug:\s*['\"]?([^'\"\n]+)", frontmatter.group(1), re.MULTILINE)
        if slug_match:
            slug = slug_match.group(1).strip()
            return slug if slug.startswith("/") else "/" + slug

    docs_root = docs_repo / "en" / "docs"
    relative = page.relative_to(docs_root).with_suffix("")
    return "/docs/" + relative.as_posix()


def capture(args: argparse.Namespace) -> dict[str, list[object]]:
    from playwright.sync_api import sync_playwright

    docs_repo = Path(args.docs_repo).resolve()
    output = Path(args.output_dir).resolve()
    output.mkdir(parents=True, exist_ok=True)
    pages = [Path(value).resolve() for value in args.page]
    captured: list[object] = []
    failed: list[object] = []

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch()
        context = browser.new_context(viewport={"width": 1440, "height": 900})
        for page_path in pages:
            route = page_route(docs_repo, page_path)
            url = urljoin(args.base_url.rstrip("/") + "/", route.lstrip("/"))
            filename = f"{args.module}-{page_path.stem}.png".replace(".", "_")
            destination = output / filename
            page = context.new_page()
            try:
                response = page.goto(url, wait_until="networkidle", timeout=60_000)
                if response is not None and response.status >= 400:
                    raise RuntimeError(f"HTTP {response.status}")
                page.evaluate("document.fonts.ready")
                page.screenshot(path=str(destination), full_page=True)
                captured.append({"page": str(page_path), "route": route, "image": str(destination)})
            except Exception as exc:  # best-effort by contract
                failed.append({"page": str(page_path), "route": route, "error": str(exc)})
            finally:
                page.close()
        browser.close()

    result = {"captured": captured, "failed": failed}
    if args.result:
        Path(args.result).write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--docs-repo", required=True)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--module", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--page", action="append", default=[])
    parser.add_argument("--result")
    return parser.parse_args()


if __name__ == "__main__":
    print(json.dumps(capture(parse_args()), indent=2))
