#!/usr/bin/env python3
"""
Wrapper for Ballerina CLI commands.

Usage: run_bal_command.py "<full command>" [<working-dir>]
Prints stdout/stderr to terminal and exits with the command's exit code.
On failure, also writes captured stderr to a temp file and prints its path.

Note: native builds (`bal build --graalvm`, `bal test --graalvm`) can take many
minutes and are memory-hungry. This wrapper does not impose a timeout; on OOM,
retry with `--graalvm-build-options="-J-Xmx8g"` (see references/troubleshooting.md).
"""

import os
import shlex
import subprocess
import sys
import tempfile


def main() -> None:
    if len(sys.argv) < 2:
        print('Usage: run_bal_command.py "<command>" [<working-dir>]', file=sys.stderr)
        sys.exit(2)

    command = sys.argv[1]
    workdir = sys.argv[2] if len(sys.argv) > 2 else os.getcwd()

    os.makedirs(workdir, exist_ok=True)

    print(f">>> Running: {command}")
    print(f">>> Working dir: {workdir}")
    print("")
    sys.stdout.flush()

    args = shlex.split(command, posix=(os.name != "nt"))

    if os.name == "nt":
        result = subprocess.run(command, shell=True, cwd=workdir, capture_output=True, text=True)
    else:
        result = subprocess.run(args, shell=False, cwd=workdir, capture_output=True, text=True)

    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)

    if result.returncode != 0:
        with tempfile.NamedTemporaryFile(
            mode="w", suffix="_bal_graalvm_stderr.txt", delete=False, encoding="utf-8"
        ) as f:
            f.write((result.stdout or "") + "\n" + (result.stderr or ""))
            stderr_path = f.name

        print("", file=sys.stderr)
        print(f">>> Command failed with exit code {result.returncode}", file=sys.stderr)
        print(f">>> output saved to: {stderr_path}", file=sys.stderr)

    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
