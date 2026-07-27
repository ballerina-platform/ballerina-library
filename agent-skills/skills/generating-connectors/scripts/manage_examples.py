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


QUARANTINE_PREFIX = ".generated-examples-quarantine-"


def examples(root: Path) -> list[Path]:
    if not root.is_dir():
        return []
    return sorted([entry for entry in root.iterdir() if entry.is_dir() and
                   (entry / "main.bal").is_file() and (entry / "Ballerina.toml").is_file()], key=lambda item: item.name)


def quarantines(root: Path) -> list[Path]:
    if not root.is_dir():
        return []
    return sorted([entry for entry in root.iterdir() if entry.is_dir() and entry.name.startswith(QUARANTINE_PREFIX)],
                  key=lambda item: item.name)


def reconcile_quarantines(root: Path) -> list[str]:
    failures = []
    for quarantine in quarantines(root):
        for item in examples(quarantine):
            original = root / item.name
            if original.exists():
                failures.append(f"{item}: cannot restore; {original} already exists")
                continue
            try:
                item.rename(original)
            except OSError as exc:
                failures.append(f"{item}: restore failed: {exc}")
        try:
            quarantine.rmdir()
        except OSError as exc:
            if quarantine.exists():
                failures.append(f"{quarantine}: cleanup failed: {exc}")
    return failures


def scan(root: Path) -> None:
    failures = reconcile_quarantines(root)
    found = examples(root)
    result = {"examples": [item.name for item in found], "count": len(found)}
    if failures:
        result.update({"failures": failures, "complete": False})
    print(json.dumps(result))
    if failures:
        raise SystemExit(1)


def cleanup(root: Path) -> None:
    removed, failures = [], []
    failures.extend(reconcile_quarantines(root))
    if failures:
        print(json.dumps({"removed": removed, "failures": failures, "complete": False}))
        raise SystemExit(1)

    found = examples(root)
    if not found:
        print(json.dumps({"removed": removed, "failures": failures, "complete": True}))
        raise SystemExit(0)

    quarantine = root / f"{QUARANTINE_PREFIX}{uuid4().hex}"
    moved: list[tuple[Path, Path]] = []

    def record_removed(name: str) -> None:
        if name not in removed:
            removed.append(name)

    def restore() -> None:
        for original, quarantined in reversed(moved):
            if not quarantined.exists():
                if not original.exists():
                    record_removed(original.name)
                    failures.append(f"{quarantined}: cannot restore; package was deleted")
                continue
            try:
                quarantined.rename(original)
            except OSError as exc:
                failures.append(f"{quarantined}: restore failed: {exc}")
                if quarantined.exists() and not original.exists():
                    record_removed(original.name)
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
