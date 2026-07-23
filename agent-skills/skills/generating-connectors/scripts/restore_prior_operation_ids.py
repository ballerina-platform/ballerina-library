#!/usr/bin/env python3
"""
Restore operationIds from a previous run into the current aligned spec, keyed
by path+method, and compute the reserved-name list for AI-driven improvement
of the rest.

Two subcommands, run at different points because `bal openapi align`
overwrites the aligned spec file in between:

  build <existing-aligned-spec-path>
    Run BEFORE flatten/align. Extracts the path -> {method: operationId} map
    and prints it as JSON — write this to a small temp file.
    Output: {"prior_spec_found": bool, "operation_id_map": {...}}

  apply <map-file-path> <current-aligned-spec-path>
    Run AFTER align. Reads the map file from `build`, writes matching
    operationIds into the current aligned spec (modified in-place), and
    returns the reserved-name list (ids not eligible for renaming).
    Output: {"prior_spec_found": bool, "restored_count": int, "reserved_operation_ids": [str, ...]}

The map file passed to `apply` is a transient scratch artifact — delete it
once `apply` has run.
"""

from __future__ import annotations

import sys
import json
import os

HTTP_METHODS = ("get", "post", "put", "patch", "delete", "head", "options", "trace")


def build_prior_operation_id_map(spec: dict) -> dict[str, dict[str, str]]:
    result: dict[str, dict[str, str]] = {}
    for path, path_item in (spec.get("paths") or {}).items():
        if not isinstance(path_item, dict):
            continue
        methods: dict[str, str] = {}
        for method in HTTP_METHODS:
            op = path_item.get(method)
            if isinstance(op, dict):
                op_id = op.get("operationId")
                if op_id:
                    methods[method] = op_id
        if methods:
            result[path] = methods
    return result


def collect_all_operation_ids(spec: dict) -> list[str]:
    ids: list[str] = []
    for _path, path_item in (spec.get("paths") or {}).items():
        if not isinstance(path_item, dict):
            continue
        for method in HTTP_METHODS:
            op = path_item.get(method)
            if isinstance(op, dict):
                op_id = op.get("operationId")
                if op_id:
                    ids.append(op_id)
    return ids


def cmd_build(existing_aligned_spec_path: str) -> dict:
    if not os.path.isfile(existing_aligned_spec_path):
        return {"prior_spec_found": False, "operation_id_map": {}}

    with open(existing_aligned_spec_path, "r", encoding="utf-8") as f:
        spec = json.load(f)

    return {"prior_spec_found": True, "operation_id_map": build_prior_operation_id_map(spec)}


def cmd_apply(map_file_path: str, current_spec_path: str) -> dict:
    with open(map_file_path, "r", encoding="utf-8") as f:
        build_result = json.load(f)
    prior_spec_found = bool(build_result.get("prior_spec_found", False))
    prior_map: dict[str, dict[str, str]] = build_result.get("operation_id_map") or {}

    with open(current_spec_path, "r", encoding="utf-8") as f:
        current_spec = json.load(f)

    if not prior_map:
        # Either no prior spec, or one with no operationIds — nothing to restore.
        # Reserve every current operationId so AI improvement still has guard rails.
        return {
            "prior_spec_found": prior_spec_found,
            "restored_count": 0,
            "reserved_operation_ids": collect_all_operation_ids(current_spec),
        }

    restored = 0
    reserved_ids: list[str] = []
    for path, methods in prior_map.items():
        path_item = current_spec.get("paths", {}).get(path)
        if not isinstance(path_item, dict):
            continue
        for method, operation_id in methods.items():
            op = path_item.get(method)
            if isinstance(op, dict):
                op["operationId"] = operation_id
                restored += 1
                reserved_ids.append(operation_id)

    if restored:
        with open(current_spec_path, "w", encoding="utf-8") as f:
            json.dump(current_spec, f, indent=2)

    return {
        "prior_spec_found": prior_spec_found,
        "restored_count": restored,
        "reserved_operation_ids": reserved_ids,
    }


def usage() -> None:
    print(f"Usage: {sys.argv[0]} build <existing-aligned-spec-path>", file=sys.stderr)
    print(f"       {sys.argv[0]} apply <map-file-path> <current-aligned-spec-path>", file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        usage()

    subcommand = sys.argv[1]
    if subcommand == "build" and len(sys.argv) == 3:
        print(json.dumps(cmd_build(sys.argv[2])))
    elif subcommand == "apply" and len(sys.argv) == 4:
        print(json.dumps(cmd_apply(sys.argv[2], sys.argv[3])))
    else:
        usage()
