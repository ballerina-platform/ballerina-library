#!/usr/bin/env python3
"""
Scan a Ballerina package for what can be exercised under the tracing agent, which
decides whether the JAR-trace stage and/or the tests-trace stage are reachable.

Detects:
  - has_main:    a `public function main(...)` entry point
  - has_service: a service declaration or a `listener` (e.g. http:Listener)
  - has_tests:   a tests/ directory containing .bal files
  - jar_name:    best-effort uber-JAR name (<package-name>.jar), read from
                 Ballerina.toml if present next to the sources

Usage: detect_runnable_artifacts.py <BALLERINA_DIR>

Output (stdout): JSON {has_main, has_service, has_tests, jar_name, main_files, service_files}
"""

import json
import os
import re
import sys

MAIN_RE = re.compile(r"^\s*public\s+function\s+main\s*\(", re.MULTILINE)
SERVICE_RE = re.compile(r"^\s*service\b", re.MULTILINE)
LISTENER_RE = re.compile(r"\blistener\b|:\s*Listener\b|new\s+\w+:Listener", re.MULTILINE)


def read_package_name(bal_dir: str) -> str:
    toml = os.path.join(bal_dir, "Ballerina.toml")
    if os.path.isfile(toml):
        try:
            with open(toml, "r", encoding="utf-8") as f:
                content = f.read()
            m = re.search(r'^\s*name\s*=\s*"([^"]+)"', content, re.MULTILINE)
            if m:
                return m.group(1)
        except Exception:
            pass
    return os.path.basename(os.path.abspath(bal_dir))


def main() -> None:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <BALLERINA_DIR>", file=sys.stderr)
        sys.exit(2)

    bal_dir = sys.argv[1]
    if not os.path.isdir(bal_dir):
        print(f"ERROR: not a directory: {bal_dir}", file=sys.stderr)
        sys.exit(1)

    has_main = False
    has_service = False
    main_files = []
    service_files = []

    # Top-level .bal files (module root) — do not descend into tests/ for main/service.
    for entry in sorted(os.listdir(bal_dir)):
        path = os.path.join(bal_dir, entry)
        if not (os.path.isfile(path) and entry.endswith(".bal")):
            continue
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as f:
                text = f.read()
        except Exception:
            continue
        if MAIN_RE.search(text):
            has_main = True
            main_files.append(entry)
        if SERVICE_RE.search(text) or LISTENER_RE.search(text):
            has_service = True
            service_files.append(entry)

    tests_dir = os.path.join(bal_dir, "tests")
    has_tests = os.path.isdir(tests_dir) and any(
        f.endswith(".bal") for f in os.listdir(tests_dir)
    )

    pkg_name = read_package_name(bal_dir)

    result = {
        "has_main": has_main,
        "has_service": has_service,
        "has_tests": has_tests,
        "jar_name": f"{pkg_name}.jar",
        "main_files": main_files,
        "service_files": service_files,
    }
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
