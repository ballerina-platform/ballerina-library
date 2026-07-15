#!/usr/bin/env python3
"""
Check that the environment has the required tools for this skill.

Usage: check_environment.py
Output: status lines per check. Exits 1 if any required check fails.

Note: GraalVM itself is verified separately by check_graalvm_env.py, after the
required JDK version has been derived from the Ballerina distribution.
"""

import shutil
import subprocess
import sys

failed = False


def check(label: str, ok: bool, detail: str = "", fatal: bool = True) -> None:
    global failed
    if ok:
        print(f"  ✓ {label}" + (f"  ({detail})" if detail else ""))
    else:
        print(f"  ✗ {label}" + (f"  — {detail}" if detail else ""), file=sys.stderr)
        if fatal:
            failed = True


def main() -> None:
    print("Checking environment...")

    bal_path = shutil.which("bal")
    if bal_path:
        try:
            result = subprocess.run(
                ["bal", "version"], capture_output=True, text=True, timeout=30
            )
            bal_ver = (result.stdout or result.stderr or "unknown").splitlines()[0]
        except Exception:
            bal_ver = "unknown"
        check("Ballerina (bal)", True, bal_ver)
    else:
        check("Ballerina (bal)", False,
              "not found — install from https://ballerina.io/downloads/")

    py_ver = sys.version.split()[0]
    check("Python 3", True, f"Python {py_ver}")

    if failed:
        print("")
        print("One or more required tools are missing. Please resolve the issues "
              "above before continuing.", file=sys.stderr)
        sys.exit(1)

    print("")
    print("Environment OK.")


if __name__ == "__main__":
    main()
