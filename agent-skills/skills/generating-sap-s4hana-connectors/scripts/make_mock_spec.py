#!/usr/bin/env python3
"""Write docs/spec/<API_ID>_MOCK.json: the sanitized spec cut down to the paths the tests call.

The reference repos generate their mock service from a reduced copy of the spec (no keyed or
parameterized paths, usually one list path plus one create or action path), so the generated
service stays small. Components the kept paths do not reach are pruned transitively.

Usage: make_mock_spec.py <sanitized-spec.json> <out_MOCK.json> <path> [<path> ...]
       Paths are spec keys such as /A_InspectionLot or /$batch. Each keeps all its methods,
       unless written as /A_InspectionLot:get,post.
"""
import re
import sys
from pathlib import Path

import specjson


def refs(node, found):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "$ref" and isinstance(v, str):
                found.add(v)
            else:
                refs(v, found)
    elif isinstance(node, list):
        for v in node:
            refs(v, found)


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    spec = specjson.load(sys.argv[1])
    out = Path(sys.argv[2])
    keep = {}
    for arg in sys.argv[3:]:
        p, _, methods = arg.partition(":")
        if p not in spec["paths"]:
            sys.exit(f"{p} is not a path in the spec")
        item = spec["paths"][p]
        if methods:
            wanted = [x.strip().lower() for x in methods.split(",") if x.strip()]
            unknown = [x for x in wanted if x not in item]
            if unknown:
                sys.exit(f"{p} has no {unknown} operation (it has {[k for k in item if k != 'parameters']})")
            item = {k: v for k, v in item.items() if k in wanted or k == "parameters"}
        if re.search(r"[({]", p):
            print(f"WARNING: {p} has key parameters; the reference mocks avoid parameterized paths")
        keep[p] = item
    spec["paths"] = keep

    # Keep only components reachable from the kept paths (schemas, parameters, responses, ...).
    comps = spec.get("components") or {}
    seen, frontier = set(), set()
    refs({k: v for k, v in spec.items() if k != "components"}, frontier)
    while frontier:
        r = frontier.pop()
        parts = r.split("/")
        if len(parts) != 4 or parts[:2] != ["#", "components"] or r in seen:
            continue
        node = comps.get(parts[2], {}).get(parts[3])
        if node is None:
            continue
        seen.add(r)
        found = set()
        refs(node, found)
        frontier |= found - seen
    for kind in ("schemas", "parameters", "responses", "requestBodies"):
        if kind in comps:
            comps[kind] = {k: v for k, v in comps[kind].items() if f"#/components/{kind}/{k}" in seen}
    specjson.dump(spec, out)
    print(f"wrote {out}: {len(keep)} paths, {len(comps.get('schemas', {}))} schemas")
    return 0


if __name__ == "__main__":
    sys.exit(main())
