#!/usr/bin/env python3
"""
Print a newline-separated list of directories (relative to CWD) that already
contain a Ballerina.toml, found downstream from CWD. Used to recommend
BALLERINA_DIR when the connector workspace is an existing Ballerina package
nested below the repo root (e.g. ballerina-library modules keep the package
under a `ballerina/` subdirectory, separate from `docs/`, `examples/`, etc.)

Usage: find_ballerina_toml.py
"""

import os

MAX_DEPTH = 4
EXCLUDED = {".git", "target", "build", "node_modules", "build-config"}
MAX_RESULTS = 5


def main() -> None:
    cwd = os.getcwd()
    found = []
    seen = set()

    for root, dirs, files in os.walk(cwd):
        rel = os.path.relpath(root, cwd)
        depth = 0 if rel == "." else rel.count(os.sep) + 1
        if depth >= MAX_DEPTH:
            dirs[:] = []
            continue
        dirs[:] = [d for d in dirs if d not in EXCLUDED]

        if "Ballerina.toml" in files:
            display = "." if root == cwd else "./" + os.path.relpath(root, cwd).replace(os.sep, "/")
            if display not in seen:
                seen.add(display)
                found.append(display)

    for path in found[:MAX_RESULTS]:
        print(path)


if __name__ == "__main__":
    main()
