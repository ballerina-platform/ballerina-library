#!/usr/bin/env python3
"""
Wrapper for Ballerina CLI commands.

Usage: run_bal_command.py [--cwd <working-dir>] <command> [<argument>...]
Prints stdout/stderr to terminal and exits with the command's exit code.
On failure, also writes captured stderr to a temp file and prints its path.
"""

import os
import subprocess
import sys
import tempfile

DEFAULT_TIMEOUT_SECONDS = 1800


def main() -> None:
    arguments = sys.argv[1:]
    workdir = os.getcwd()
    if arguments[:1] == ["--cwd"]:
        if len(arguments) < 3:
            print("Usage: run_bal_command.py [--cwd <working-dir>] <command> [<argument>...]", file=sys.stderr)
            sys.exit(2)
        workdir = arguments[1]
        arguments = arguments[2:]

    if not arguments:
        print("Usage: run_bal_command.py [--cwd <working-dir>] <command> [<argument>...]", file=sys.stderr)
        sys.exit(2)

    command = arguments

    os.makedirs(workdir, exist_ok=True)

    print(f">>> Running: {subprocess.list2cmdline(command)}")
    print(f">>> Working dir: {workdir}")
    print("")
    sys.stdout.flush()

    try:
        timeout_seconds = int(os.environ.get("CONNECTOR_BAL_TIMEOUT_SECONDS", DEFAULT_TIMEOUT_SECONDS))
        if timeout_seconds <= 0:
            raise ValueError
    except ValueError:
        print("ERROR: CONNECTOR_BAL_TIMEOUT_SECONDS must be a positive integer.", file=sys.stderr)
        sys.exit(2)
    try:
        result = subprocess.run(command, shell=False, cwd=workdir, capture_output=True, text=True,
                                timeout=timeout_seconds)
    except subprocess.TimeoutExpired as exc:
        def text_output(value):
            if isinstance(value, bytes):
                return value.decode("utf-8", errors="replace")
            return value or ""

        stdout = text_output(exc.stdout)
        stderr = text_output(exc.stderr) + f"\nCommand timed out after {timeout_seconds} seconds."
        result = subprocess.CompletedProcess(command, 124, stdout, stderr)

    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)

    if result.returncode != 0:
        with tempfile.NamedTemporaryFile(
            mode="w", suffix="_bal_build_stderr.txt", delete=False, encoding="utf-8"
        ) as f:
            f.write(result.stderr or "")
            stderr_path = f.name

        print("", file=sys.stderr)
        print(f">>> Command failed with exit code {result.returncode}", file=sys.stderr)
        print(f">>> stderr saved to: {stderr_path}", file=sys.stderr)

    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
