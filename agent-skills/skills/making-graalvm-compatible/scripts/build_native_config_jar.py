#!/usr/bin/env python3
"""
Zip a resources tree (containing META-INF/native-image/...) into a jar file. A jar
is just a zip, so this uses Python's stdlib zipfile — no Java toolchain required.

The resources root passed in should be the directory whose immediate child is
`META-INF/` (i.e. <native-dir>/src/main/resources), so the archive entries are
`META-INF/native-image/<group>/<artifact>/<config>.json`.

Usage:
  build_native_config_jar.py --resources-dir <native-dir>/src/main/resources \
                             --out <native-dir>/build/libs/<artifact>-<version>.jar

Output (stdout): JSON {jar, entries:[...]}
"""

import argparse
import json
import os
import sys
import zipfile


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--resources-dir", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    if not os.path.isdir(args.resources_dir):
        print(f"ERROR: resources dir not found: {args.resources_dir}", file=sys.stderr)
        sys.exit(1)

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)

    entries = []
    with zipfile.ZipFile(args.out, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, _dirs, files in os.walk(args.resources_dir):
            for fname in sorted(files):
                abs_path = os.path.join(root, fname)
                arcname = os.path.relpath(abs_path, args.resources_dir).replace(os.sep, "/")
                zf.write(abs_path, arcname)
                entries.append(arcname)

    if not entries:
        print("ERROR: no files found under the resources dir — nothing to jar.",
              file=sys.stderr)
        sys.exit(1)

    print(json.dumps({"jar": args.out, "entries": entries}, indent=2))


if __name__ == "__main__":
    main()
