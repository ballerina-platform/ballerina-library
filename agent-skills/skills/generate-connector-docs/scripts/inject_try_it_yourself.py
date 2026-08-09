#!/usr/bin/env python3
"""Inject the deterministic Try it yourself section into a connector guide."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

BUTTON_IMAGE_URL = "https://openindevant.choreoapps.dev/images/DeployDevant-White.svg"
SAMPLE_REPOSITORY_PATH = "wso2/integration-samples/tree/main/integrator-default-profile/connectors"
SAMPLE_NAME_RE = re.compile(r"^[a-z0-9]+(?:_[a-z0-9]+)*_connector_sample$")


def build_urls(sample_name: str) -> tuple[str, str]:
    if not SAMPLE_NAME_RE.fullmatch(sample_name):
        raise ValueError(f"Invalid connector sample name: {sample_name}")
    suffix = f"{SAMPLE_REPOSITORY_PATH}/{sample_name}"
    return f"https://console.devant.dev/new?gh={suffix}", f"https://github.com/{suffix}"


def build_section(sample_name: str) -> str:
    devant_url, github_url = build_urls(sample_name)
    return (
        "## Try it yourself\n\n"
        "Try this sample in WSO2 Integration Platform.\n\n"
        f"[![Deploy to Devant]({BUTTON_IMAGE_URL})]({devant_url})\n\n"
        f"[View source on GitHub]({github_url})"
    )


def inject_try_it_yourself(doc_path: Path, sample_dir: Path, sample_name: str) -> bool:
    if sample_dir.name != sample_name:
        raise ValueError(
            f"Sample directory name '{sample_dir.name}' does not match context sample name '{sample_name}'"
        )
    if not doc_path.is_file():
        raise FileNotFoundError(f"Missing guide: {doc_path}")

    text = doc_path.read_text(encoding="utf-8")
    section = build_section(sample_name)
    existing = re.search(r"^## Try it yourself\n\n(?P<body>.*?)(?=^## |\Z)", text, re.M | re.S)
    if existing:
        actual = "## Try it yourself\n\n" + existing.group("body").strip()
        if actual != section:
            raise ValueError("Existing Try it yourself section does not match the deterministic template")
        return False

    examples = re.search(r"^## More code examples\s*$", text, re.M)
    if examples:
        before = text[: examples.start()].rstrip()
        after = text[examples.start() :].lstrip()
        updated = f"{before}\n\n{section}\n\n{after.rstrip()}\n"
    else:
        updated = f"{text.rstrip()}\n\n{section}\n"
    doc_path.write_text(updated, encoding="utf-8")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--context", required=True, type=Path)
    args = parser.parse_args()
    try:
        context = json.loads(args.context.read_text(encoding="utf-8"))
        added = inject_try_it_yourself(
            Path(context["doc_path"]), Path(context["sample_dir"]), context["sample_name"]
        )
        devant_url, github_url = build_urls(context["sample_name"])
    except (OSError, ValueError, json.JSONDecodeError, KeyError) as exc:
        print(f"[ERROR] Could not inject Try it yourself section: {exc}", file=sys.stderr)
        return 1
    print(json.dumps({"added": added, "devant_url": devant_url, "github_url": github_url}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
