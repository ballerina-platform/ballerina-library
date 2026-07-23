#!/usr/bin/env python3
"""
Initialise a Ballerina package in BALLERINA_DIR using `bal new .`.
Removes the generated main.bal scaffold — the connector files (client.bal,
types.bal, utils.bal) come from `bal openapi` in the client stage.

Usage: init_ballerina_package.py <ballerina-dir>
"""

import os
import subprocess
import sys


def run_bal(args: list, cwd: str) -> subprocess.CompletedProcess:
    """Run a trusted `bal` command; callers must not pass untrusted arguments.

    Windows uses ``shell=True`` because ``bal`` is a ``.bat``/``.cmd`` shim.
    """
    if os.name == "nt":
        # list2cmdline applies Windows quoting rules (paths with spaces etc.);
        # shell=True is needed because bal is a .bat/.cmd shim on Windows
        return subprocess.run(subprocess.list2cmdline(args), shell=True, cwd=cwd)
    return subprocess.run(args, shell=False, cwd=cwd)


def main() -> None:
    if len(sys.argv) != 2:
        print("Usage: init_ballerina_package.py <ballerina-dir>", file=sys.stderr)
        sys.exit(2)

    ballerina_dir = sys.argv[1]
    os.makedirs(ballerina_dir, exist_ok=True)

    print(f">>> Running bal new . in {ballerina_dir}...")
    result = run_bal(["bal", "new", "."], cwd=ballerina_dir)
    if result.returncode != 0:
        sys.exit(result.returncode)

    main_bal = os.path.join(ballerina_dir, "main.bal")
    if os.path.isfile(main_bal):
        os.remove(main_bal)
        print(">>> Removed scaffold main.bal")

    print("✓ Ballerina package initialised")


if __name__ == "__main__":
    main()
