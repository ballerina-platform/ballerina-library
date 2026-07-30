#!/usr/bin/env python3
"""Crop code-server tab and status bars from connector screenshots."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def non_negative(value: str) -> int:
    parsed = int(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("crop margins must be non-negative")
    return parsed


def crop_directory(directory: Path, top: int = 32, bottom: int = 18, left: int = 0, right: int = 0) -> int:
    try:
        from PIL import Image
    except ImportError as exc:
        raise RuntimeError("Pillow is required; install scripts/requirements.txt") from exc
    images = sorted(directory.glob("*.png"))
    for path in images:
        with Image.open(path) as image:
            width, height = image.size
            box = (left, top, width - right, height - bottom)
            if box[0] >= box[2] or box[1] >= box[3]:
                raise ValueError(f"Crop margins exceed dimensions for {path.name}")
            cropped = image.crop(box)
            cropped.save(path, format="PNG")
    return len(images)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("screenshots_dir", type=Path)
    parser.add_argument("--top", type=non_negative, default=32)
    parser.add_argument("--bottom", type=non_negative, default=18)
    parser.add_argument("--left", type=non_negative, default=0)
    parser.add_argument("--right", type=non_negative, default=0)
    args = parser.parse_args()
    try:
        count = crop_directory(args.screenshots_dir, args.top, args.bottom, args.left, args.right)
    except (RuntimeError, ValueError, OSError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1
    print(f"Cropped {count} screenshot(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
