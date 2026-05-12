#!/usr/bin/env python3
# Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
#
# WSO2 LLC. licenses this file to you under the Apache License,
# Version 2.0 (the "License"); you may not use this file except
# in compliance with the License.

import os
import re
import subprocess
import sys
from pathlib import Path
from typing import NoReturn

try:
    from dotenv import load_dotenv
except ModuleNotFoundError:
    def load_dotenv(*_args: object, **_kwargs: object) -> bool:
        return False

load_dotenv(Path(__file__).parent.parent / ".env")

_WORKSPACE_ROOT = Path(__file__).resolve().parent.parent.parent
_env_samples_repo = os.environ.get("INTEGRATION_SAMPLES_REPO")
DEFAULT_SAMPLES_REPO = (
    Path(_env_samples_repo) if _env_samples_repo
    else _WORKSPACE_ROOT / "integration-samples"
)
DEFAULT_UPSTREAM_REPO = os.environ.get("INTEGRATION_SAMPLES_UPSTREAM", "wso2/integration-samples")
DEFAULT_BASE_BRANCH = os.environ.get("INTEGRATION_SAMPLES_BASE_BRANCH", "main")


def info(msg: str) -> None:
    print(f"[INFO]  {msg}")


def warn(msg: str) -> None:
    print(f"[WARN]  {msg}", file=sys.stderr)


def dry(msg: str) -> None:
    print(f"[DRY]   {msg}")


def fail(msg: str) -> NoReturn:
    print(f"\n[ERROR] {msg}", file=sys.stderr)
    sys.exit(1)


def run(cmd: list[str], cwd: Path | None = None, check: bool = True) -> str:
    result = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        capture_output=True,
        text=True,
        check=check,
    )
    if result.stderr.strip():
        warn(result.stderr.strip())
    return result.stdout.strip()


def infer_fork(samples_repo: Path) -> str:
    try:
        url = run(["git", "remote", "get-url", "origin"], cwd=samples_repo).rstrip("/")
        m = re.search(r"[:/]([^/:]+/[^/]+?)(?:\.git)?$", url)
        if m:
            return m.group(1)
    except subprocess.CalledProcessError:
        pass
    fail(
        "Could not infer fork slug from git remote 'origin'.\n"
        "Pass --fork OWNER/REPO explicitly."
    )
