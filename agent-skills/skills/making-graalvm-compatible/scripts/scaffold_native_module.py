#!/usr/bin/env python3
"""
Create a minimal `native/` module resource layout when the library has no native
module yet, so tracing/repo-sourced config files have somewhere to live and can be
packed into a resources-only jar.

Creates:
  <native-dir>/src/main/resources/META-INF/native-image/<groupId>/<artifactId>/

This is a resources-only layout (no Java sources, no Gradle/Maven build), so
build_native_config_jar.py can zip it without requiring a Java toolchain.

Usage:
  scaffold_native_module.py --native-dir <path> --group-id <g> --artifact-id <a>

Output (stdout): JSON {native_dir, meta_inf_dir, created}
"""

import argparse
import json
import os


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--native-dir", required=True)
    ap.add_argument("--group-id", required=True)
    ap.add_argument("--artifact-id", required=True)
    args = ap.parse_args()

    meta_inf_dir = os.path.join(
        args.native_dir, "src", "main", "resources", "META-INF", "native-image",
        args.group_id, args.artifact_id,
    )
    created = not os.path.isdir(meta_inf_dir)
    os.makedirs(meta_inf_dir, exist_ok=True)

    print(json.dumps({
        "native_dir": args.native_dir,
        "meta_inf_dir": meta_inf_dir,
        "created": created,
    }, indent=2))


if __name__ == "__main__":
    main()
