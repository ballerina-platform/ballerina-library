#!/usr/bin/env python3
"""Request source CODEOWNERS on a docs-integrator PR, best effort."""

from __future__ import annotations

import argparse
import json
import re
import subprocess


OWNER_RE = re.compile(r"(?<!\S)@([A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)?)")


def parse_owners(content: str) -> list[str]:
    owners: set[str] = set()
    for raw_line in content.splitlines():
        line = raw_line.split("#", 1)[0]
        owners.update(OWNER_RE.findall(line))
    return sorted(owners, key=str.lower)


def gh(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["gh", *args], text=True, capture_output=True, check=check)


def load_codeowners(source_repo: str) -> str:
    for path in (".github/CODEOWNERS", "CODEOWNERS", "docs/CODEOWNERS"):
        result = gh("api", f"repos/{source_repo}/contents/{path}", "--jq", ".content", check=False)
        if result.returncode == 0:
            import base64
            return base64.b64decode(result.stdout.strip()).decode("utf-8")
    return ""


def request(args: argparse.Namespace) -> dict[str, list[str]]:
    owners = parse_owners(load_codeowners(args.source_repo))
    requested: list[str] = []
    skipped: list[str] = []
    target_org = args.target_repo.split("/", 1)[0]
    endpoint = f"repos/{args.target_repo}/pulls/{args.pr_number}/requested_reviewers"

    for owner in owners:
        if "/" in owner:
            org, team = owner.split("/", 1)
            if org.lower() != target_org.lower():
                skipped.append(f"@{owner} (cross-organization team)")
                continue
            payload = f'team_reviewers[]={team}'
        else:
            payload = f'reviewers[]={owner}'
        result = gh("api", "--method", "POST", endpoint, "-f", payload, check=False)
        if result.returncode == 0:
            requested.append(f"@{owner}")
        else:
            skipped.append(f"@{owner} ({result.stderr.strip() or 'not eligible'})")
    return {"requested": requested, "skipped": skipped}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-repo", required=True)
    parser.add_argument("--target-repo", default="wso2/docs-integrator")
    parser.add_argument("--pr-number", required=True)
    return parser.parse_args()


if __name__ == "__main__":
    print(json.dumps(request(parse_args()), indent=2))
