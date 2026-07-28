#!/usr/bin/env python3
"""Capture and compare the generated client API without relying on Git.

Usage:
  client_version_summary.py capture <ballerina-dir> <baseline.json>
  client_version_summary.py diff <ballerina-dir> <baseline.json>
"""

from __future__ import annotations

import difflib
import json
import os
import re
import sys
import tempfile
from pathlib import Path


def atomic_write(path: str, data: dict) -> None:
    directory = os.path.dirname(os.path.abspath(path))
    os.makedirs(directory, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".connector-client-", suffix=".json", dir=directory)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as file:
            json.dump(data, file, indent=2)
            file.write("\n")
            file.flush()
            os.fsync(file.fileno())
        os.replace(temporary, path)
    except OSError:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def read_snapshot(path: Path) -> dict:
    if not path.is_file():
        return {"exists": False, "content": ""}
    return {"exists": True, "content": path.read_text(encoding="utf-8")}


def meaningful(content: str) -> bool:
    content = re.sub(r"/\*.*?\*/", "", content, flags=re.DOTALL)
    content = re.sub(r"(?m)^\s*(?://|#).*?$", "", content)
    return bool(content.strip())


def capture(directory: str, output: str) -> None:
    root = Path(directory)
    client = read_snapshot(root / "client.bal")
    atomic_write(output, {
        "client": client,
        "types": read_snapshot(root / "types.bal"),
        "has_meaningful_client": client["exists"] and meaningful(client["content"]),
    })
    print(json.dumps({"baseline_path": output, "has_meaningful_client": client["exists"] and meaningful(client["content"])}))


def package_version(directory: Path) -> str:
    toml = directory / "Ballerina.toml"
    if not toml.is_file():
        return ""
    package = re.search(r"^\[package\](.*?)(?=^\[|\Z)", toml.read_text(encoding="utf-8"), re.MULTILINE | re.DOTALL)
    match = re.search(r'^version\s*=\s*"([^"]+)"', package.group(1), re.MULTILINE) if package else None
    return match.group(1) if match else ""


def diff(directory: str, baseline_path: str) -> None:
    baseline = json.loads(Path(baseline_path).read_text(encoding="utf-8"))
    root = Path(directory)
    if not baseline.get("has_meaningful_client"):
        print(json.dumps({"skipped": "no meaningful previous client.bal", "diff": "", "version": package_version(root)}))
        return
    chunks = []
    for name, key in (("client.bal", "client"), ("types.bal", "types")):
        before = (baseline.get(key) or {}).get("content", "").replace("\r\n", "\n").replace("\r", "\n")
        after = read_snapshot(root / name)["content"].replace("\r\n", "\n").replace("\r", "\n")
        if before != after:
            chunks.append("Changes in " + name + ":\n" + "\n".join(difflib.unified_diff(
                before.splitlines(), after.splitlines(), fromfile="previous/" + name, tofile="current/" + name,
                lineterm="")))
    print(json.dumps({"skipped": "" if chunks else "no client/types changes", "diff": "\n\n".join(chunks), "version": package_version(root)}))


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "capture":
        capture(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 4 and sys.argv[1] == "diff":
        diff(sys.argv[2], sys.argv[3])
    else:
        print(f"Usage: {sys.argv[0]} capture <ballerina-dir> <baseline.json>", file=sys.stderr)
        print(f"       {sys.argv[0]} diff <ballerina-dir> <baseline.json>", file=sys.stderr)
        raise SystemExit(2)
