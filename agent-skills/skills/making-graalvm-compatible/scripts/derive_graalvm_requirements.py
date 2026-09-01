#!/usr/bin/env python3
"""
Derive the required GraalVM JDK version and the Ballerina.toml platform block
name from the Ballerina distribution (update) version.

Mapping (from the Ballerina GraalVM compatibility guide):
  - Update <= 7  (2201.7.x and lower)          -> GraalVM JDK 11 -> [platform.java11]
  - Update 8, 9, 10 (2201.8.x / .9.x / .10.x)  -> GraalVM JDK 17 -> [platform.java17]
  - Update >= 11 (2201.11.x and higher)        -> GraalVM JDK 21 -> [platform.java21]

Usage:
  derive_graalvm_requirements.py [--distribution 2201.10.3]

If --distribution is omitted, the script runs `bal version` and parses it.

Output (stdout): JSON
  {distribution, update, required_graalvm_jdk, platform_java_version, assumed}
`assumed` is true when the update is newer than the guide covers (>= 11), where
JDK 21 is a best-effort default that should be confirmed against the distribution.
"""

import argparse
import json
import re
import subprocess
import sys


def read_distribution_from_bal() -> str:
    try:
        result = subprocess.run(["bal", "version"], capture_output=True, text=True, timeout=30)
    except Exception as e:
        print(f"ERROR: could not run `bal version`: {e}", file=sys.stderr)
        sys.exit(1)
    text = result.stdout or result.stderr or ""
    # e.g. "Ballerina 2201.10.3 (Swan Lake Update 10)"
    m = re.search(r"(\d+\.\d+\.\d+)", text)
    if not m:
        print(f"ERROR: could not parse distribution from `bal version`:\n{text}", file=sys.stderr)
        sys.exit(1)
    return m.group(1)


def derive(distribution: str) -> dict:
    m = re.match(r"\s*(\d+)\.(\d+)(?:\.(\d+))?", distribution.strip())
    if not m:
        print(f"ERROR: cannot parse distribution: {distribution!r}", file=sys.stderr)
        sys.exit(1)
    update = int(m.group(2))

    assumed = False
    if update <= 7:
        jdk, platform = 11, "java11"
    elif update <= 10:
        jdk, platform = 17, "java17"
    else:
        jdk, platform = 21, "java21"
        assumed = True

    return {
        "distribution": distribution.strip(),
        "update": update,
        "required_graalvm_jdk": jdk,
        "platform_java_version": platform,
        "assumed": assumed,
    }


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--distribution", help="Ballerina distribution, e.g. 2201.10.3")
    args = ap.parse_args()

    distribution = args.distribution or read_distribution_from_bal()
    print(json.dumps(derive(distribution), indent=2))


if __name__ == "__main__":
    main()
