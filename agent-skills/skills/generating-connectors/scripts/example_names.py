#!/usr/bin/env python3
"""Normalize and resolve unique generated-example directory names."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


def normalize(value: str) -> str:
    return re.sub(r"^_+|_+$", "", re.sub(r"[^a-z0-9]+", "_", value.strip().lower()))


def resolve(examples_dir: str, suggested: str, fallback: str) -> dict[str, str]:
    base = normalize(suggested) or normalize(fallback) or "example"
    root = Path(examples_dir)
    candidate = base
    suffix = 2
    while (root / candidate).exists():
        candidate = f"{base}_{suffix}"
        suffix += 1
    return {"name": candidate, "base_name": base}


if __name__ == "__main__":
    if len(sys.argv) != 5 or sys.argv[1] != "resolve":
        print(f"Usage: {sys.argv[0]} resolve <examples-dir> <suggested-name> <fallback-name>", file=sys.stderr)
        raise SystemExit(2)
    print(json.dumps(resolve(*sys.argv[2:])))
