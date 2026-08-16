#!/usr/bin/env python3
"""Append Central examples, crop screenshots once, validate, and write run.json."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

from append_central_examples import append_central_examples
from crop_screenshots import crop_directory
from inject_try_it_yourself import build_urls, inject_try_it_yourself
from validate_output import validate


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--context", required=True, type=Path)
    parser.add_argument("--skip-crop", action="store_true", help="Keep original screenshots")
    args = parser.parse_args()
    try:
        context = json.loads(args.context.read_text(encoding="utf-8"))
        doc_path = Path(context["doc_path"])
        run_json_path = Path(context["run_log_dir"]) / "run.json"
        previous = json.loads(run_json_path.read_text(encoding="utf-8")) if run_json_path.exists() else {}
        try_it_yourself_added = inject_try_it_yourself(
            doc_path, Path(context["sample_dir"]), context["sample_name"]
        )
        devant_url, github_url = build_urls(context["sample_name"])
        central_examples_found, examples_added = append_central_examples(
            doc_path, Path(context["metadata_path"])
        )
        already_cropped = bool(previous.get("screenshots_cropped"))
        if not args.skip_crop and not already_cropped:
            crop_directory(Path(context["screenshots_dir"]))
        errors = validate(context)
        result = {
            **context,
            "completed_at": datetime.now(timezone.utc).isoformat(),
            "examples_added": bool(previous.get("examples_added")) or examples_added,
            "central_examples_found": central_examples_found,
            "try_it_yourself_added": bool(previous.get("try_it_yourself_added")) or try_it_yourself_added,
            "devant_url": devant_url,
            "github_url": github_url,
            "screenshots_cropped": already_cropped or not args.skip_crop,
            "validation": {"status": "passed" if not errors else "failed", "errors": errors},
        }
        run_json_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError, KeyError) as exc:
        print(f"[ERROR] Finalization failed: {exc}", file=sys.stderr)
        return 1
    if errors:
        for error in errors:
            print(f"[ERROR] {error}", file=sys.stderr)
        return 1
    print(f"Finalized and validated: {context['run_dir']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
