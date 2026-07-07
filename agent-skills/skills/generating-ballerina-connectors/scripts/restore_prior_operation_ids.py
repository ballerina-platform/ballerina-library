#!/usr/bin/env python3
"""
Deterministically restore operationIds established in a previous run into the
current aligned spec, keyed by path+method, and compute the reserved-name list
for Pass B AI improvement. Mirrors connector-tool's buildOperationIdMap +
collectExistingOperationIds (spec_analyzer.bal / batch_processor.bal): Pass-A
restoration plus reserved-id collection are both deterministic — no AI call.

Usage: restore_prior_operation_ids.py <prior-aligned-spec-path> <current-aligned-spec-path>
  prior-aligned-spec-path    Path to the aligned spec JSON from a previous run (may not exist)
  current-aligned-spec-path Path to the current aligned spec JSON (modified in-place)

Output (stdout): a single JSON object:
  {
    "prior_spec_found": bool,
    "restored_count": int,
    "reserved_operation_ids": [str, ...]
  }

reserved_operation_ids mirrors collectExistingOperationIds's two branches:
  - No prior spec, or a prior spec with no operationIds at all: every current
    operationId is reserved (there's nothing Pass-A-settled to protect
    exclusively yet, but Pass B must still avoid clashing with what's there).
  - A non-empty prior map: only ids belonging to path+methods actually
    restored in Pass A are reserved — a Pass-B candidate's own current id is
    never self-reserved, so the AI can keep it unchanged if it's already good.
"""

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
    for path, path_item in (spec.get("paths") or {}).items():
        if not isinstance(path_item, dict):
            continue
        for method in HTTP_METHODS:
            op = path_item.get(method)
            if isinstance(op, dict):
                op_id = op.get("operationId")
                if op_id:
                    ids.append(op_id)
    return ids


def restore(prior_spec_path: str, current_spec_path: str) -> dict:
    with open(current_spec_path, "r", encoding="utf-8") as f:
        current_spec = json.load(f)

    prior_spec_found = os.path.isfile(prior_spec_path)
    prior_map: dict[str, dict[str, str]] = {}
    if prior_spec_found:
        with open(prior_spec_path, "r", encoding="utf-8") as f:
            prior_spec = json.load(f)
        prior_map = build_prior_operation_id_map(prior_spec)

    if not prior_map:
        # Either no prior spec, or one with no operationIds — nothing to restore.
        # Mirror collectExistingOperationIds's "no prior" branch: reserve every
        # current operationId rather than leaving Pass B with no guard rails.
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
        "prior_spec_found": True,
        "restored_count": restored,
        "reserved_operation_ids": reserved_ids,
    }


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <prior-aligned-spec-path> <current-aligned-spec-path>", file=sys.stderr)
        sys.exit(2)
    print(json.dumps(restore(sys.argv[1], sys.argv[2])))
