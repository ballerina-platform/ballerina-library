# Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
#
# WSO2 LLC. licenses this file to you under the Apache License,
# Version 2.0 (the "License"); you may not use this file except
# in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied. See the License for the
# specific language governing permissions and limitations
# under the License.

"""
crop_screenshots.py — Post-process pipeline screenshots by cropping UI chrome.

Default margins are tuned for a 1720x968 headless Playwright / code-server viewport.
Only the VS Code tab bar (top) and status bar (bottom) are removed — no left/right crop:
  top    = 32   (VS Code tab bar row)
  bottom = 18   (VS Code status bar)
  left   = 0
  right  = 0

Margins can be overridden via CLI flags or environment variables:
  --top / CROP_TOP, --bottom / CROP_BOTTOM, --left / CROP_LEFT, --right / CROP_RIGHT
"""

import argparse
import os
import sys
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent / ".env")

SCREENSHOTS_DIR = Path("artifacts/screenshots")

DEFAULT_TOP = 32
DEFAULT_BOTTOM = 18
DEFAULT_LEFT = 0
DEFAULT_RIGHT = 0


def _non_negative_int(value: str) -> int:
    try:
        parsed = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"Invalid integer: {value!r}") from exc
    if parsed < 0:
        raise argparse.ArgumentTypeError(f"Value must be >= 0, got: {parsed}")
    return parsed


def _env_or_default(name: str, default: int) -> int:
    raw = os.environ.get(name)
    if raw is None:
        return default
    try:
        return _non_negative_int(raw)
    except argparse.ArgumentTypeError as exc:
        raise SystemExit(f"[ERROR] Environment variable {name}: {exc}") from exc


def parse_args():
    parser = argparse.ArgumentParser(
        description="Crop UI chrome from pipeline screenshots in-place."
    )
    parser.add_argument("--top",    type=_non_negative_int, default=_env_or_default("CROP_TOP",    DEFAULT_TOP))
    parser.add_argument("--bottom", type=_non_negative_int, default=_env_or_default("CROP_BOTTOM", DEFAULT_BOTTOM))
    parser.add_argument("--left",   type=_non_negative_int, default=_env_or_default("CROP_LEFT",   DEFAULT_LEFT))
    parser.add_argument("--right",  type=_non_negative_int, default=_env_or_default("CROP_RIGHT",  DEFAULT_RIGHT))
    parser.add_argument("--dry-run", action="store_true",
                        help="Print what would happen without writing any files.")
    parser.add_argument("--backup", action="store_true",
                        help="Save originals as *.orig.png before overwriting.")
    return parser.parse_args()


def main():
    args = parse_args()

    if not SCREENSHOTS_DIR.exists():
        print(f"[INFO] {SCREENSHOTS_DIR} does not exist — no screenshots to crop.")
        sys.exit(0)

    pngs = sorted(SCREENSHOTS_DIR.glob("*.png"))
    # Exclude any backup files that may already exist
    pngs = [p for p in pngs if not p.name.endswith(".orig.png")]

    if not pngs:
        print(f"[INFO] No PNG files found in {SCREENSHOTS_DIR}.")
        sys.exit(0)

    # Import Pillow only after confirming there is work to do
    try:
        from PIL import Image
    except ImportError:
        print("[ERROR] Pillow is not installed. Run: pip install Pillow", file=sys.stderr)
        sys.exit(1)

    processed = 0
    skipped = 0
    total_pixels_before = 0
    total_pixels_after = 0

    for png in pngs:
        with Image.open(png) as img:
            width, height = img.size

            right_coord = width - args.right if args.right > 0 else width
            bottom_coord = height - args.bottom if args.bottom > 0 else height

            # Sanity check: skip if margins exceed image dimensions
            if args.left >= right_coord or args.top >= bottom_coord:
                print(f"[SKIP] {png.name} — margins exceed image size ({width}x{height}), skipping.")
                skipped += 1
                continue

            box = (args.left, args.top, right_coord, bottom_coord)
            new_width = right_coord - args.left
            new_height = bottom_coord - args.top

            total_pixels_before += width * height
            total_pixels_after += new_width * new_height

            if args.dry_run:
                print(
                    f"[DRY-RUN] {png.name}: {width}x{height} → {new_width}x{new_height} "
                    f"(crop box {box})"
                )
                processed += 1
                continue

            if args.backup:
                backup_path = png.with_suffix(".orig.png")
                import shutil
                shutil.copy2(png, backup_path)
                print(f"[BACKUP] {png.name} → {backup_path.name}")

            cropped = img.crop(box)
            # Preserve original format/mode; re-open so we can save in place
            cropped.save(png)
            print(f"[CROP] {png.name}: {width}x{height} → {new_width}x{new_height}")
            processed += 1

    # Summary
    print("")
    print("── Crop Summary ──────────────────────────────────")
    print(f"  Files processed : {processed}")
    print(f"  Files skipped   : {skipped}")
    if total_pixels_before > 0:
        reduction_pct = 100 * (1 - total_pixels_after / total_pixels_before)
        print(f"  Pixel reduction : ~{reduction_pct:.1f}%")
    if args.dry_run:
        print("  (dry-run — no files were written)")
    print("──────────────────────────────────────────────────")


if __name__ == "__main__":
    main()
