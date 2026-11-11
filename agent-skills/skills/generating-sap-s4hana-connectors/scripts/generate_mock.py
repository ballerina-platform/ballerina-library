#!/usr/bin/env python3
"""Generate ballerina/<module>/modules/mock from docs/spec/<API_ID>_MOCK.json and wire it for the tests.

After `bal openapi --mode service` (generator distribution, same reason as generate_client.py):
  * the listener becomes HTTPS on 9090 with the shared ../resources certs (IS_BAL_BUILD switch),
    exactly like every reference mock;
  * if the mock has any POST/PUT/PATCH/DELETE resource, a `head .()` resource is added that returns
    an X-CSRF-TOKEN header. sap:Client sends `HEAD /` to fetch a CSRF token before every modifying
    request; without it those calls fail with "Method not allowed".

The resource bodies are left as generated (empty). Fill them with realistic sample payloads in
the OData envelope the client expects ({"d": {...}} for V2, plain JSON / {"value": [...]} for V4).

Usage: generate_mock.py --repo <repo> --api-id <API_ID> [--module <module>] [--csrf-token <text>]
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from baldist import bal_for  # noqa: E402

LISTENER = '''boolean isBalBuild = os:getEnv("IS_BAL_BUILD") == "true";
string certPathPostFix = isBalBuild ? "../" : "/home/ballerina/ballerina/";

listener http:Listener ep0 = new (9090,
    secureSocket = {
        key: {
            certFile: certPathPostFix + "resources/public.crt",
            keyFile: certPathPostFix + "resources/private.key"
        }
    }
);'''

HEAD = '''
    resource function head .() returns http:Response {
        http:Response res = new;
        res.statusCode = 200;
        res.setHeader("X-CSRF-TOKEN", "%s");
        return res;
    }

'''


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--api-id", required=True)
    ap.add_argument("--module")
    ap.add_argument("--gen-dist", default="2201.10.3")
    ap.add_argument("--csrf-token", default="mock-csrf-token")
    ap.add_argument("--force", action="store_true", help="overwrite existing mock .bal files")
    args = ap.parse_args()

    repo = Path(args.repo).resolve()
    module = args.module or args.api_id.lower()
    docs = repo / "docs"
    mock_dir = repo / "ballerina" / module / "modules" / "mock"
    mock_dir.mkdir(parents=True, exist_ok=True)
    existing = sorted(mock_dir.glob("*.bal"))
    if existing and not args.force:
        sys.exit(f"{mock_dir} already has {[f.name for f in existing]}; they may hold hand-written sample "
                 "data. Rerun with --force to regenerate them from scratch.")
    for f in existing:
        f.unlink()
    bal = bal_for(args.gen_dist)
    cmd = [bal, "openapi", "-i", f"spec/{args.api_id}_MOCK.json", "-o", str(mock_dir), "--mode", "service"]
    if (docs / "license.txt").exists():
        cmd += ["--license", "license.txt"]
    print("$", " ".join(cmd))
    res = subprocess.run(cmd, cwd=docs, text=True, capture_output=True)
    # "ERROR: HTTP status code '4XX' is not supported" is expected: only the 4XX error responses are skipped.
    print((res.stdout + res.stderr).strip())
    if res.returncode != 0:
        return res.returncode

    services = list(mock_dir.glob("*_service.bal"))
    if len(services) != 1:
        sys.exit(f"expected one *_service.bal in {mock_dir}, found {services}")
    svc = services[0]
    text = svc.read_text(encoding="utf-8")
    text, n = re.subn(r"listener http:Listener ep0 = new \([^;]*\);", lambda _m: LISTENER, text, count=1)
    if n != 1:
        sys.exit(f"{svc.name}: no `listener http:Listener ep0 = new (...)` to replace with the TLS listener")
    if "import ballerina/os;" not in text:
        text = text.replace("import ballerina/http;", "import ballerina/http;\nimport ballerina/os;", 1)
    if re.search(r"resource function (post|put|patch|delete) ", text) and "resource function head" not in text:
        text = re.sub(r"(service [^\n]* on ep0 \{\n)", lambda m: m.group(1) + HEAD % args.csrf_token, text, count=1)
    svc.write_text(text, encoding="utf-8")
    resources = re.findall(r"resource function (\w+) ([^\(]+)\(", text)
    print(f"mock service {svc.name}: " + ", ".join(f"{m.upper()} {p.strip()}" for m, p in resources))
    return 0


if __name__ == "__main__":
    sys.exit(main())
