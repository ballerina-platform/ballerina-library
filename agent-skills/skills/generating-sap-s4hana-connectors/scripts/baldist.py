"""Locate installed Ballerina distributions without touching the global `bal`.

The skill needs two versions side by side (an older one for `bal openapi`, the repo's
`ballerinaLangVersion` for building), so it addresses distributions directly instead of
relying on whatever `bal` is on PATH. Set BALLERINA_DIST_ROOT if yours live elsewhere.
"""
import os
import platform
import sys
from pathlib import Path

DEFAULTS = {
    "Darwin": "/Library/Ballerina/distributions",
    "Linux": "/usr/lib/ballerina/distributions",
    "Windows": r"C:\Program Files\Ballerina\distributions",
}


def dist_root() -> Path:
    return Path(os.environ.get("BALLERINA_DIST_ROOT") or DEFAULTS.get(platform.system(), DEFAULTS["Linux"]))


def bal_for(version: str) -> str:
    """Path to the `bal` launcher of one distribution, e.g. bal_for("2201.10.3")."""
    exe = "bal.bat" if platform.system() == "Windows" else "bal"
    candidate = dist_root() / f"ballerina-{version}" / "bin" / exe
    if not candidate.exists():
        installed = sorted(p.name[len("ballerina-"):] for p in dist_root().glob("ballerina-*"))
        sys.exit(f"Ballerina {version} is not installed under {dist_root()} (found: {installed or 'none'}). "
                 "Install it with `bal dist pull " + version + "`, or point BALLERINA_DIST_ROOT at your distributions.")
    return str(candidate)
