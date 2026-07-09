#!/usr/bin/env python3
"""
Generate a Ballerina service stub from an OpenAPI spec into tests/mock_service.bal.

Usage: generate_mock_stub.py <spec-path> <ballerina-dir> [operations] [license-path]
  operations    Optional comma-separated operationIds (used when spec has >30 operations)
  license-path  Optional path to a license header file passed to --license

The stub is written to <ballerina-dir>/tests/mock_service.bal
"""

import os
import subprocess
import sys


def run_bal(args: list, cwd: str) -> subprocess.CompletedProcess:
    if os.name == "nt":
        return subprocess.run(" ".join(args), shell=True, cwd=cwd)
    return subprocess.run(args, shell=False, cwd=cwd)


def main() -> None:
    if len(sys.argv) < 3:
        print(
            "Usage: generate_mock_stub.py <spec-path> <ballerina-dir> [operations] [license-path]",
            file=sys.stderr,
        )
        sys.exit(2)

    spec_path = sys.argv[1]
    ballerina_dir = sys.argv[2]
    operations = sys.argv[3] if len(sys.argv) > 3 else ""
    license_path = sys.argv[4] if len(sys.argv) > 4 else ""

    tests_dir = os.path.join(ballerina_dir, "tests")
    os.makedirs(tests_dir, exist_ok=True)

    # --mode service generates only the service stub, not a client
    args = ["bal", "openapi", "-i", spec_path, "--mode", "service", "-o", tests_dir]
    if operations:
        print(f">>> Filtering to operations: {operations}")
        args += ["--operations", operations]
    if license_path:
        args += ["--license", license_path]

    print(">>> Running bal openapi to generate service stub...")
    result = run_bal(args, cwd=os.getcwd())
    if result.returncode != 0:
        sys.exit(result.returncode)

    service_file = os.path.join(tests_dir, "aligned_ballerina_openapi_service.bal")
    mock_file = os.path.join(tests_dir, "mock_service.bal")

    if not os.path.isfile(service_file):
        print(f"ERROR: Expected {service_file} but it was not generated.", file=sys.stderr)
        sys.exit(1)

    os.replace(service_file, mock_file)
    print(">>> Renamed aligned_ballerina_openapi_service.bal → mock_service.bal")

    # Remove generated types.bal and client.bal — root package types.bal is already in scope
    for name in ("types.bal", "client.bal", "utils.bal"):
        path = os.path.join(tests_dir, name)
        if os.path.isfile(path):
            os.remove(path)

    print(f"✓ Stub written: {mock_file}")


if __name__ == "__main__":
    main()
