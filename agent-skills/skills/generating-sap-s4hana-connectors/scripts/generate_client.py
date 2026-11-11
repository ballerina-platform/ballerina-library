#!/usr/bin/env python3
"""Run the S/4HANA generation pipeline for one package, the way the reference repos were built.

Stages (run them one at a time and commit between them, like the repo history does):
  sanitize   docs/: bal run sanitation/sanitations.bal, then pretty-print the spec (the repo
             keeps specs indented; the scripts write one line)
  opid       docs/: bal run sanitation/operationId.bal, pretty-print, check for duplicate IDs
  spec       sanitize + opid
  client  bal openapi --mode client with the GENERATOR distribution (default 2201.10.3,
          see below), then bal run sanitation/clientSanitations.bal, wait for the format/build
          it fires off in the background, then modernize_connection_config.py, bal format and
          bal build with the BUILD distribution (the repo's ballerinaLangVersion)
  all        spec + client

Why two distributions: from 2201.12 on, `bal openapi` rewrites operation IDs into camel case
(`listA_InspectionMethods` becomes `listAInspectionMethods`). Every published S/4HANA connector
keeps the underscore names, so new packages are generated with 2201.10.3 to match them. The
code it emits compiles fine on the newer build distribution.

Usage: generate_client.py --repo <repo> --api-id <API_ID> [--module <module>] [--stage sanitize|opid|spec|client|all]
                          [--gen-dist 2201.10.3] [--build-dist <ver>]
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

import fix_type_titles
import specjson
from baldist import bal_for

HERE = Path(__file__).resolve().parent


def run(cmd, cwd, env=None, check=True):
    print("$", " ".join(cmd), f"(in {cwd})", flush=True)
    res = subprocess.run(cmd, cwd=cwd, env=env, text=True, capture_output=True)
    tail = "\n".join((res.stdout + res.stderr).strip().splitlines()[-15:])
    if tail:
        print(tail)
    if check and res.returncode != 0:
        sys.exit(f"FAILED ({res.returncode}): {' '.join(cmd)}")
    return res


def env_with(bal: str) -> dict:
    env = dict(os.environ)
    env["PATH"] = str(Path(bal).parent) + os.pathsep + env.get("PATH", "")
    return env


def stage_spec(repo: Path, api_id: str, build_bal: str, sanitize: bool = True, opid: bool = True):
    docs = repo / "docs"
    spec = docs / "spec" / f"{api_id}.json"
    if not spec.exists():
        sys.exit(f"Missing {spec}. Copy the api.sap.com download there first.")
    env = env_with(build_bal)
    for wanted, script in ((sanitize, "sanitations.bal"), (opid, "operationId.bal")):
        if wanted:
            spelling = specjson.literals(specjson.load(spec))
            run([build_bal, "run", f"sanitation/{script}", "--", api_id], docs, env)
            data = specjson.respell(specjson.load(spec), spelling)
            if script == "sanitations.bal":
                # The repo sanitizer leaves "Modified A_XType" / "Collection of X" titles alone;
                # they would become escaped type names like `Modified\ A_XType`.
                for old, new, known in fix_type_titles.fix(data):
                    print(f"  type title {old!r} -> {new}" + ("" if known else "  (unrecognised pattern; check it)"))
            specjson.dump(data, spec)
    if not opid:
        return
    data = json.loads(spec.read_text(encoding="utf-8"))
    ids = [op.get("operationId") for item in data["paths"].values() for k, op in item.items()
           if isinstance(op, dict) and k in ("get", "post", "put", "patch", "delete")]
    dupes = sorted({i for i in ids if ids.count(i) > 1})
    print(f"spec sanitized: {len(ids)} operations" + (f", DUPLICATE operationIds: {dupes}" if dupes else ""))
    if dupes or "" in ids or None in ids:
        sys.exit("Fix the operation IDs before generating (see SKILL.md, 'Operation ID clashes').")


def wait_for_background_bal(module: str, timeout: int = 600):
    """clientSanitations.bal starts `bal format` and `bal build` without waiting for them."""
    deadline = time.time() + timeout
    pattern = f"ballerina/{module}"
    while time.time() < deadline:
        res = subprocess.run(["pgrep", "-f", pattern], text=True, capture_output=True)
        pids = [p for p in res.stdout.split() if p and int(p) != os.getpid()]
        if not pids:
            return
        time.sleep(2)
    sys.exit(f"Background bal processes for {pattern} still running after {timeout}s")


def stage_client(repo: Path, api_id: str, module: str, gen_bal: str, build_bal: str):
    docs = repo / "docs"
    pkg = repo / "ballerina" / module
    pkg.mkdir(parents=True, exist_ok=True)
    for name in ("client.bal", "types.bal", "utils.bal", "main.bal"):
        (pkg / name).unlink(missing_ok=True)
    spec = json.loads((docs / "spec" / f"{api_id}.json").read_text(encoding="utf-8"))
    server = spec["servers"][0]["url"]
    m = re.search(r"\{port\}/(.*)$", server)
    if not m:
        sys.exit(f"Cannot derive the API postfix from servers[0].url = {server}")
    postfix = m.group(1)

    license_args = ["--license", "license.txt"] if (docs / "license.txt").exists() else []
    run([gen_bal, "openapi", "-i", f"spec/{api_id}.json", "-o", f"../ballerina/{module}", "--mode", "client", "--client-methods", "remote", *license_args],
        docs, env_with(gen_bal))
    env = env_with(build_bal)
    run([build_bal, "run", "sanitation/clientSanitations.bal", "--", module, postfix], docs, env)
    time.sleep(2)
    wait_for_background_bal(module)
    run([sys.executable, str(HERE / "modernize_connection_config.py"), str(pkg)], repo)
    run([build_bal, "format", "."], pkg, env)
    run([build_bal, "build"], pkg, env)
    client = (pkg / "client.bal").read_text(encoding="utf-8")
    n = len(re.findall(r"remote isolated function ", client))
    if re.search(r"resource isolated function ", client):
        sys.exit("client.bal has resource methods; S/4HANA connectors use remote methods (--client-methods remote)")
    expected = sum(1 for item in spec["paths"].values() for k in item if k in ("get", "post", "put", "patch", "delete"))
    print(f"client generated: {n} remote functions for {expected} spec operations" +
          ("" if n == expected else "  <-- MISMATCH: bal openapi skipped some operations; check its output above"))
    types = (pkg / "types.bal").read_text(encoding="utf-8")
    escaped = sorted(set(re.findall(r"^public type (\w+(?:\\ \w+)+)", types, re.M)))
    if escaped:
        sys.exit(f"ESCAPED TYPE NAMES in types.bal: {escaped}. A spaced schema title got through; extend "
                 "scripts/fix_type_titles.py (or fix the title in the spec) and rerun from --stage sanitize.")
    hits = len(re.findall(r"public type Wrapper\b", types))
    if hits:
        print(f"WARNING: {hits} bare Wrapper types in types.bal")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--api-id", required=True)
    ap.add_argument("--module")
    ap.add_argument("--stage", default="all", choices=["sanitize", "opid", "spec", "client", "all"])
    ap.add_argument("--gen-dist", default="2201.10.3")
    ap.add_argument("--build-dist")
    args = ap.parse_args()

    repo = Path(args.repo).resolve()
    module = args.module or args.api_id.lower()
    build_dist = args.build_dist
    if not build_dist:
        props = (repo / "gradle.properties").read_text(encoding="utf-8")
        m = re.search(r"^ballerinaLangVersion=(\S+)", props, re.M)
        build_dist = m.group(1) if m else "2201.13.0"
    build_bal = bal_for(build_dist)
    if args.stage in ("sanitize", "opid", "spec", "all"):
        stage_spec(repo, args.api_id, build_bal, sanitize=args.stage != "opid", opid=args.stage != "sanitize")
    if args.stage in ("client", "all"):
        stage_client(repo, args.api_id, module, bal_for(args.gen_dist), build_bal)
    return 0


if __name__ == "__main__":
    sys.exit(main())
