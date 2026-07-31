#!/usr/bin/env python3
"""
Deterministically scan an aligned OpenAPI spec for duplicate operationIds.
Non-fatal — client generation will also surface any remaining conflicts.

Usage: check_duplicate_operation_ids.py <aligned-spec-path>

Output (stdout):
  "No duplicate operationIds found"                                    — when unique
  "WARNING: duplicate operationId '<id>' at: METHOD /path, METHOD /path" — per duplicate
"""

import sys
import json
import os

HTTP_METHODS = ("get", "post", "put", "patch", "delete", "head", "options", "trace")


def find_duplicates(spec: dict) -> dict:
    seen = {}
    for path, path_item in (spec.get("paths") or {}).items():
        if not isinstance(path_item, dict):
            continue
        for method in HTTP_METHODS:
            op = path_item.get(method)
            if not isinstance(op, dict):
                continue
            op_id = op.get("operationId")
            if op_id:
                seen.setdefault(op_id, []).append(f"{method.upper()} {path}")
    return {op_id: locs for op_id, locs in seen.items() if len(locs) > 1}


def check(spec_path: str) -> None:
    if not os.path.isfile(spec_path):
        print(f"ERROR: File not found: {spec_path}", file=sys.stderr)
        sys.exit(1)

    with open(spec_path, "r", encoding="utf-8") as f:
        spec = json.load(f)

    duplicates = find_duplicates(spec)
    if not duplicates:
        print("No duplicate operationIds found")
        return

    for op_id, locations in duplicates.items():
        print(f"WARNING: duplicate operationId '{op_id}' at: {', '.join(locations)}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <aligned-spec-path>", file=sys.stderr)
        sys.exit(2)
    check(sys.argv[1])
