#!/usr/bin/env python3
"""Reject generated changes outside the connector documentation allowlist."""

from __future__ import annotations

import argparse
import re
import subprocess


def changed_paths() -> list[str]:
    """Return every path reported by porcelain status, including rename sources."""
    output = subprocess.check_output(
        ["git", "status", "--porcelain=v1", "-z", "--untracked-files=all"]
    )
    records = output.split(b"\0")
    paths: list[str] = []
    index = 0
    while index < len(records) and records[index]:
        record = records[index].decode("utf-8", errors="surrogateescape")
        status = record[:2]
        paths.append(record[3:])
        index += 1
        if "R" in status or "C" in status:
            if index >= len(records) or not records[index]:
                raise RuntimeError("Malformed porcelain output for rename or copy")
            paths.append(records[index].decode("utf-8", errors="surrogateescape"))
            index += 1
    return paths


def validate(category: str, module: str) -> None:
    """Fail when any changed path is outside the generated-docs allowlist."""
    category_pattern = re.escape(category)
    module_pattern = re.escape(module)
    allowed = re.compile(
        rf"^(?:en/sidebars\.ts|en/docs/connectors/catalog/index\.mdx|"
        rf"en/docs/connectors/catalog/{category_pattern}/{module_pattern}(?:/.*)?|"
        rf"en/static/img/connectors/catalog/{category_pattern}/{module_pattern}(?:/.*)?)$"
    )
    unexpected = [path for path in changed_paths() if not allowed.fullmatch(path)]
    if unexpected:
        formatted = "\n".join(f"- {path}" for path in unexpected)
        raise RuntimeError(f"Unexpected generated paths:\n{formatted}")


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--category", required=True)
    parser.add_argument("--module", required=True)
    return parser.parse_args()


if __name__ == "__main__":
    arguments = parse_args()
    validate(arguments.category, arguments.module)
