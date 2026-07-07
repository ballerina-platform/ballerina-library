#!/usr/bin/env python3
"""
Detect a common path prefix across all OpenAPI paths and move it into the server base URL.

Mirrors the manual sanitation applied to every HubSpot connector:
  - servers[0].url is updated to include the common prefix
  - The prefix is stripped from every path key in spec["paths"]

Usage: normalize_base_url.py <spec-path>
  spec-path  Path to the OpenAPI JSON spec file (modified in-place if a prefix is found)

Output (stdout):
  "Moved common prefix '/files/v3' into base URL"  — when a prefix was extracted
  "No common path prefix found"                     — when no prefix exists
"""

import sys
import json
import os


def find_common_prefix(paths: list[str]) -> str:
    """Return the longest common path prefix across all paths (e.g. '/files/v3').

    Segments are compared after splitting on '/'. The result always starts with '/'
    and ends without one. Returns '' if there is no shared non-root prefix.
    """
    if not paths:
        return ""

    # Split each path into non-empty segments
    split = [p.lstrip("/").split("/") for p in paths]

    # Find how many leading segments are identical across all paths
    common = []
    for segments in zip(*split):
        if len(set(segments)) == 1:
            common.append(segments[0])
        else:
            break

    # Require at least one segment AND the prefix must not equal the full path of any
    # single-path spec (which would leave empty strings as keys).
    if not common:
        return ""

    prefix = "/" + "/".join(common)

    # Guard: the prefix must be shorter than at least one full path, otherwise
    # stripping it would produce empty-string path keys.
    if all(p == prefix or p == prefix + "/" for p in paths):
        return ""

    return prefix


def normalize(spec_path: str) -> None:
    if not os.path.isfile(spec_path):
        print(f"ERROR: File not found: {spec_path}", file=sys.stderr)
        sys.exit(1)

    with open(spec_path, "r", encoding="utf-8") as f:
        spec = json.load(f)

    paths = list(spec.get("paths", {}).keys())
    if not paths:
        print("No common path prefix found")
        return

    servers = spec.get("servers", [])
    if not servers:
        print("No common path prefix found")
        return

    prefix = find_common_prefix(paths)
    if not prefix:
        print("No common path prefix found")
        return

    # Update server URL
    original_url = servers[0].get("url", "")
    servers[0]["url"] = original_url + prefix
    spec["servers"] = servers

    # Strip prefix from all path keys
    new_paths = {}
    for path_key, path_item in spec["paths"].items():
        if path_key.startswith(prefix):
            new_key = path_key[len(prefix):]
            if not new_key.startswith("/"):
                new_key = "/" + new_key
            new_paths[new_key] = path_item
        else:
            new_paths[path_key] = path_item
    spec["paths"] = new_paths

    with open(spec_path, "w", encoding="utf-8") as f:
        json.dump(spec, f, indent=2)

    print(f"Moved common prefix '{prefix}' into base URL")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <spec-path>", file=sys.stderr)
        sys.exit(2)
    normalize(sys.argv[1])
