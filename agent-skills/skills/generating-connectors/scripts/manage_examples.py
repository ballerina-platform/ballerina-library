#!/usr/bin/env python3
"""Safely identify and clean generated example packages.

Only immediate subdirectories containing both main.bal and Ballerina.toml are
considered generated use-case examples. Other user content is untouched.
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path
from uuid import uuid4


def examples(root: Path) -> list[Path]:
    if not root.is_dir():
        return []
    return sorted([entry for entry in root.iterdir() if entry.is_dir() and
                   (entry / "main.bal").is_file() and (entry / "Ballerina.toml").is_file()], key=lambda item: item.name)


def scan(root: Path) -> None:
    found = examples(root)
    print(json.dumps({"examples": [item.name for item in found], "count": len(found)}))


def cleanup(root: Path) -> None:
    removed, failures = [], []
    found = examples(root)
    if not found:
        print(json.dumps({"removed": removed, "failures": failures, "complete": True}))
        raise SystemExit(0)

    quarantine = root / f".generated-examples-quarantine-{uuid4().hex}"
    moved: list[tuple[Path, Path]] = []

    def restore() -> None:
        for original, quarantined in reversed(moved):
            if not quarantined.exists():
                if not original.exists():
                    removed.append(original.name)
                    failures.append(f"{quarantined}: cannot restore; package was deleted")
                continue
            try:
                quarantined.rename(original)
            except OSError as exc:
                failures.append(f"{quarantined}: restore failed: {exc}")
        try:
            quarantine.rmdir()
        except OSError as exc:
            if quarantine.exists():
                failures.append(f"{quarantine}: cleanup failed: {exc}")

    try:
        quarantine.mkdir()
    except OSError as exc:
        failures.append(f"{quarantine}: {exc}")
    else:
        for item in found:
            try:
                quarantined = quarantine / item.name
                item.rename(quarantined)
                moved.append((item, quarantined))
            except OSError as exc:
                failures.append(f"{item}: {exc}")
                restore()
                break

        if not failures:
            try:
                shutil.rmtree(quarantine)
            except OSError as exc:
                failures.append(f"{quarantine}: {exc}")
                restore()
            else:
                removed = [item.name for item in found]

    print(json.dumps({"removed": removed, "failures": failures, "complete": not failures}))
    raise SystemExit(0 if not failures else 1)


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in {"scan", "cleanup"}:
        print(f"Usage: {sys.argv[0]} <scan|cleanup> <examples-dir>", file=sys.stderr)
        raise SystemExit(2)
    (scan if sys.argv[1] == "scan" else cleanup)(Path(sys.argv[2]))
