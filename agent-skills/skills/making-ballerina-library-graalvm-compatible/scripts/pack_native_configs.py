#!/usr/bin/env python3
"""
Copy filtered/vetted native-image config files into the module's resource tree so
they ship with the library:
  <native-dir>/src/main/resources/META-INF/native-image/<groupId>/<artifactId>/

Sources may come from tracing (filter_trace_configs.py output) and/or from the
reachability-metadata repo (fetch_reachability_metadata.py output). Pass --merge
to combine same-named JSON files instead of overwriting (unified reachability
metadata and legacy list-based configs are merged structurally).

Usage:
  pack_native_configs.py --filtered-dir <dir> --native-dir <native-root>
                         --group-id <g> --artifact-id <a> [--merge]

Output (stdout): JSON {dest_dir, files:[...], merged:[...]}
"""

import argparse
import json
import os
import shutil
import sys


def merge_json(existing, incoming):
    """Best-effort structural merge for native-image config files."""
    if isinstance(existing, list) and isinstance(incoming, list):
        out = list(existing)
        # de-dup by JSON serialization
        seen = {json.dumps(x, sort_keys=True) for x in existing}
        for item in incoming:
            key = json.dumps(item, sort_keys=True)
            if key not in seen:
                seen.add(key)
                out.append(item)
        return out
    if isinstance(existing, dict) and isinstance(incoming, dict):
        out = dict(existing)
        for k, v in incoming.items():
            if k in out:
                out[k] = merge_json(out[k], v)
            else:
                out[k] = v
        return out
    return incoming


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--filtered-dir", required=True)
    ap.add_argument("--native-dir", required=True)
    ap.add_argument("--group-id", required=True)
    ap.add_argument("--artifact-id", required=True)
    ap.add_argument("--merge", action="store_true")
    args = ap.parse_args()

    if not os.path.isdir(args.filtered_dir):
        print(f"ERROR: source dir not found: {args.filtered_dir}", file=sys.stderr)
        sys.exit(1)

    dest_dir = os.path.join(
        args.native_dir, "src", "main", "resources", "META-INF", "native-image",
        args.group_id, args.artifact_id,
    )
    os.makedirs(dest_dir, exist_ok=True)

    copied = []
    merged = []
    for fname in sorted(os.listdir(args.filtered_dir)):
        src = os.path.join(args.filtered_dir, fname)
        if not os.path.isfile(src):
            continue
        dest = os.path.join(dest_dir, fname)

        if args.merge and fname.endswith(".json") and os.path.isfile(dest):
            try:
                with open(dest, "r", encoding="utf-8") as f:
                    existing = json.load(f)
                with open(src, "r", encoding="utf-8") as f:
                    incoming = json.load(f)
                combined = merge_json(existing, incoming)
                with open(dest, "w", encoding="utf-8") as f:
                    json.dump(combined, f, indent=2)
                merged.append(fname)
                continue
            except Exception:
                pass  # fall through to overwrite

        shutil.copy2(src, dest)
        copied.append(fname)

    print(json.dumps({"dest_dir": dest_dir, "files": copied, "merged": merged}, indent=2))


if __name__ == "__main__":
    main()
