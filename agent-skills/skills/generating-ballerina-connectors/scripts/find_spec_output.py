#!/usr/bin/env python3
"""
Locate the aligned OpenAPI spec output in a spec directory.

Usage: find_spec_output.py <spec_dir>
Output (stdout): absolute path to the best available spec file
Exit 1 if nothing found.
"""

import os
import sys

# Only accept the aligned spec — flattened_openapi.* is an intermediate artifact
# that has not been through bal openapi align and must not be fed to --mode client.
CANDIDATES = [
    "aligned_ballerina_openapi.json",
    "aligned_ballerina_openapi.yaml",
    "aligned_ballerina_openapi.yml",
]


def main() -> None:
    if len(sys.argv) != 2:
        print("Usage: find_spec_output.py <spec_dir>", file=sys.stderr)
        sys.exit(2)

    spec_dir = sys.argv[1]

    for name in CANDIDATES:
        path = os.path.join(spec_dir, name)
        if os.path.isfile(path):
            print(os.path.abspath(path))
            sys.exit(0)

    print(f"ERROR: No aligned spec found in {spec_dir}", file=sys.stderr)
    print("Run Stage 01 (sanitize) first to produce aligned_ballerina_openapi.json", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
