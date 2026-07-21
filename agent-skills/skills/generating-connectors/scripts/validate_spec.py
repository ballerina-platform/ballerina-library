#!/usr/bin/env python3
"""Validate that an OpenAPI spec file is valid YAML/JSON and has required top-level fields."""

import sys
import json
import os


def validate(spec_path: str) -> None:
    if not os.path.isfile(spec_path):
        print(f"ERROR: File not found: {spec_path}", file=sys.stderr)
        sys.exit(1)

    _, ext = os.path.splitext(spec_path.lower())
    raw = open(spec_path, "r", encoding="utf-8").read()

    if ext in (".yaml", ".yml"):
        try:
            import yaml
            spec = yaml.safe_load(raw)
        except Exception as e:
            print(f"ERROR: Invalid YAML — {e}", file=sys.stderr)
            sys.exit(1)
    elif ext == ".json":
        try:
            spec = json.loads(raw)
        except json.JSONDecodeError as e:
            print(f"ERROR: Invalid JSON — {e}", file=sys.stderr)
            sys.exit(1)
    else:
        # Try YAML first, then JSON
        try:
            import yaml
            spec = yaml.safe_load(raw)
        except Exception:
            try:
                spec = json.loads(raw)
            except Exception:
                print("ERROR: File is neither valid YAML nor JSON.", file=sys.stderr)
                sys.exit(1)

    if not isinstance(spec, dict):
        print("ERROR: Spec root must be a mapping object.", file=sys.stderr)
        sys.exit(1)

    missing = [f for f in ("info", "paths") if f not in spec]
    if missing:
        print(f"ERROR: Missing required OpenAPI fields: {', '.join(missing)}", file=sys.stderr)
        sys.exit(1)

    version_hint = spec.get("openapi") or spec.get("swagger") or "unknown"
    info = spec.get("info")
    title = info.get("title", "untitled") if isinstance(info, dict) else "untitled"
    path_count = len(spec.get("paths", {}))
    print(f"OK: '{title}' (OpenAPI {version_hint}) — {path_count} path(s) found.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <spec-path>", file=sys.stderr)
        sys.exit(2)
    validate(sys.argv[1])
