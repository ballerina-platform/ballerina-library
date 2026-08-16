#!/usr/bin/env python3
"""Prepare a WSO2 Integrator sample project for publishing to wso2/integration-samples.

Copies only the files every existing sample in that repo actually commits — never the
editor config, build output, or local secrets a WSO2 Integrator project also generates
locally — and sets the package org to "wso2", matching every sibling sample. Never runs
git commands or touches the target repo's remote; the caller commits, pushes, and opens
the pull request itself, the same boundary this skill already holds for docs-integrator.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# Every existing sample under wso2/integration-samples/integrator-default-profile/connectors/
# commits exactly this set — no .vscode/, target/, Dependencies.toml, or Config.toml.
INCLUDED_NAMES = {".gitignore", "Ballerina.toml"}


def copy_sample_files(sample_dir: Path, target_dir: Path) -> list[str]:
    """Copy only the files an integration-samples entry actually commits.

    Returns the list of copied filenames. Raises ValueError if `sample_dir` doesn't look
    like a WSO2 Integrator project (no Ballerina.toml at its root).
    """
    if not (sample_dir / "Ballerina.toml").is_file():
        raise ValueError(f"Not a Ballerina project (no Ballerina.toml): {sample_dir}")

    target_dir.mkdir(parents=True, exist_ok=True)
    copied: list[str] = []
    for source in sorted(sample_dir.iterdir()):
        if not source.is_file():
            continue
        if source.name not in INCLUDED_NAMES and source.suffix != ".bal":
            continue
        destination = target_dir / source.name
        destination.write_bytes(source.read_bytes())
        copied.append(source.name)
    return copied


def set_package_org(ballerina_toml: Path, org: str = "wso2") -> bool:
    """Set [package] org in a copied Ballerina.toml. Returns True if the file changed.

    WSO2 Integrator projects are created locally under whatever Ballerina org the
    developer's own environment is configured with — never the placeholder every
    published sample actually uses.
    """
    text = ballerina_toml.read_text(encoding="utf-8")
    updated, count = re.subn(r'(?m)^org\s*=\s*"[^"]*"', f'org = "{org}"', text, count=1)
    if count == 0:
        raise ValueError(f"No [package] org field found in {ballerina_toml}")
    if updated == text:
        return False
    ballerina_toml.write_text(updated, encoding="utf-8")
    return True


def prepare(sample_dir: Path, target_dir: Path, org: str) -> dict[str, object]:
    copied = copy_sample_files(sample_dir, target_dir)
    org_updated = set_package_org(target_dir / "Ballerina.toml", org)
    return {"target_dir": str(target_dir), "files_copied": copied, "org_updated": org_updated}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample-dir", required=True, type=Path)
    parser.add_argument("--target-dir", required=True, type=Path)
    parser.add_argument("--org", default="wso2")
    args = parser.parse_args()
    try:
        result = prepare(args.sample_dir.resolve(), args.target_dir.resolve(), args.org)
    except (OSError, ValueError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
