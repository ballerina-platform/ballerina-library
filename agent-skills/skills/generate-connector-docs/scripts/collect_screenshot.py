#!/usr/bin/env python3
"""Copy one Playwright MCP screenshot into its collision-safe final path."""

from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path

NAME_RE = re.compile(r"^[a-z0-9_]+_screenshot_(0[1-6])_[a-z0-9_]+\.png$")
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def collect(source: Path, destination: Path) -> Path:
    if not source.is_file():
        raise ValueError(f"Playwright screenshot does not exist: {source}")
    if not NAME_RE.fullmatch(destination.name):
        raise ValueError("Destination must use <prefix>_screenshot_01..06_<suffix>.png")
    if destination.exists():
        raise FileExistsError(f"Refusing to overwrite screenshot: {destination}")
    if source.read_bytes()[:8] != PNG_SIGNATURE:
        raise ValueError(f"Source is not a PNG file: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    return destination.resolve()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    try:
        print(collect(args.source.expanduser().resolve(), args.destination.expanduser().resolve()))
    except (ValueError, FileExistsError, OSError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
