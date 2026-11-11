#!/usr/bin/env python3
"""Compile a package's README quickstart (import + client init + api-invocation from docs.json).

Pushes the package to the local Ballerina repository, builds a throwaway project that uses it
exactly as the README shows, then removes the local push again. Catches the usual docs.json
mistakes: a misspelled method, a return type that is not the generated one, a missing
`\\$` escape on OData query names, or a wrong module alias.

Usage: check_quickstart.py <repo> <module> [--dist 2201.13.0]
"""
import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from baldist import bal_for  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("repo")
    ap.add_argument("module")
    ap.add_argument("--dist")
    args = ap.parse_args()
    repo = Path(args.repo).resolve()
    pkg = repo / "ballerina" / args.module
    dist = args.dist
    if not dist:
        m = re.search(r"^ballerinaLangVersion=(\S+)", (repo / "gradle.properties").read_text(encoding="utf-8"), re.M)
        dist = m.group(1) if m else "2201.13.0"
    bal = bal_for(dist)
    toml = (pkg / "Ballerina.toml").read_text(encoding="utf-8")
    name_m = re.search(r'^name = "(.*)"', toml, re.M)
    version_m = re.search(r'^version = "(.*)"', toml, re.M)
    if not name_m or not version_m:
        sys.exit(f"{pkg / 'Ballerina.toml'} has no `name = \"...\"` and `version = \"...\"` lines")
    name, version = name_m.group(1), version_m.group(1)
    docs = json.loads((pkg / "docs.json").read_text(encoding="utf-8"))

    local = Path.home() / ".ballerina/repositories/local/bala/ballerinax" / name
    # An earlier local push of the same package may be in use elsewhere: keep a copy and put it back.
    backup = Path(tempfile.mkdtemp(prefix="qs-backup-")) / name
    existed = local.exists()
    if existed:
        shutil.copytree(local, backup)
    try:
        for cmd in (["pack"], ["push", "--repository=local"]):
            try:
                res = subprocess.run([bal, *cmd], cwd=pkg, text=True, capture_output=True, timeout=600)
            except subprocess.TimeoutExpired:
                print(f"bal {cmd[0]} timed out after 600 s")
                return 1
            if res.returncode != 0:
                print(res.stdout + res.stderr)
                return 1
        var = docs["api-invocation"].split("=")[0].split()[-1]
        main_bal = f"""{docs['import-statement']}

configurable string hostname = ?;
configurable string username = ?;
configurable string password = ?;

public function main() returns error? {{
    {docs['client-init']}
        {{
          auth: {{
            username,
            password
          }}
        }},
        hostname
    );
    {docs['api-invocation']}
    _ = {var};
}}
"""
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "Ballerina.toml").write_text(
                f'[package]\norg = "qs"\nname = "quickstart"\nversion = "0.1.0"\n\n'
                f'[[dependency]]\norg = "ballerinax"\nname = "{name}"\nversion = "{version}"\nrepository = "local"\n', encoding="utf-8")
            Path(tmp, "main.bal").write_text(main_bal, encoding="utf-8")
            # --offline: everything is local; online, the build can wait on Central for an hour.
            try:
                res = subprocess.run([bal, "build", "--offline"], cwd=tmp, text=True, capture_output=True, timeout=600)
            except subprocess.TimeoutExpired:
                print("quickstart build timed out after 600 s")
                return 1
            errors = [l for l in (res.stdout + res.stderr).splitlines() if "ERROR" in l]
            if res.returncode != 0 or errors:
                print("QUICKSTART DOES NOT COMPILE:\n" + "\n".join(errors or [res.stdout + res.stderr]))
                print("--- main.bal ---\n" + main_bal)
                return 1
        print(f"quickstart for {name} compiles")
        return 0
    finally:
        shutil.rmtree(local, ignore_errors=True)
        if existed:
            shutil.copytree(backup, local)
        shutil.rmtree(backup.parent, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
