#!/usr/bin/env python3
"""
Look up published native-image metadata for third-party Java dependencies in the
oracle/graalvm-reachability-metadata repository. This is the PRIMARY source of
configs — prefer it over tracing, since these are maintainer-vetted.

For each dependency (groupId/artifactId/version) it fetches
  metadata/<groupId>/<artifactId>/index.json
from the repo and reports whether metadata exists, which metadata-version dir to
use (exact tested-version match if possible, else the `latest`), and whether the
requested version was actually among the tested versions.

Usage:
  # single dependency
  lookup_reachability_metadata.py --group-id com.h2database --artifact-id h2 --version 2.2.224
  # batch: a JSON file that is a list of {groupId, artifactId, version}
  lookup_reachability_metadata.py --deps-json deps.json

Options:
  --ref <git-ref>   Repo ref to query (default: master)

Output (stdout): JSON list of
  {groupId, artifactId, requested_version, has_metadata, metadata_version,
   version_tested, module_path, error}
Network failures degrade gracefully: has_metadata=false with an `error` note, exit 0.
"""

import argparse
import json
import sys
import urllib.error
import urllib.request

RAW_BASE = "https://raw.githubusercontent.com/oracle/graalvm-reachability-metadata/{ref}/metadata"


def fetch_json(url: str, timeout: int = 20):
    req = urllib.request.Request(url, headers={"User-Agent": "ballerina-graalvm-skill"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def lookup_one(group_id: str, artifact_id: str, version: str, ref: str) -> dict:
    result = {
        "groupId": group_id,
        "artifactId": artifact_id,
        "requested_version": version,
        "has_metadata": False,
        "metadata_version": None,
        "version_tested": False,
        "module_path": f"{group_id}/{artifact_id}",
        "error": None,
    }
    index_url = f"{RAW_BASE.format(ref=ref)}/{group_id}/{artifact_id}/index.json"
    try:
        entries = fetch_json(index_url)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            result["error"] = "no published metadata (404)"
        else:
            result["error"] = f"HTTP {e.code}"
        return result
    except Exception as e:
        result["error"] = f"network error: {e}"
        return result

    if not isinstance(entries, list) or not entries:
        result["error"] = "unexpected index.json format"
        return result

    # Prefer an entry whose tested-versions contains the requested version.
    chosen = None
    for entry in entries:
        tested = entry.get("tested-versions", []) or []
        if version and version in tested:
            chosen = entry
            result["version_tested"] = True
            break
    if chosen is None:
        # fall back to the entry marked latest, else the first entry
        for entry in entries:
            if entry.get("latest") is True:
                chosen = entry
                break
        if chosen is None:
            chosen = entries[0]

    result["has_metadata"] = True
    result["metadata_version"] = chosen.get("metadata-version") or chosen.get("directory")
    return result


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--deps-json", help="JSON file: list of {groupId, artifactId, version}")
    ap.add_argument("--group-id")
    ap.add_argument("--artifact-id")
    ap.add_argument("--version", default="")
    ap.add_argument("--ref", default="master")
    args = ap.parse_args()

    deps = []
    if args.deps_json:
        with open(args.deps_json, "r", encoding="utf-8") as f:
            deps = json.load(f)
    elif args.group_id and args.artifact_id:
        deps = [{"groupId": args.group_id, "artifactId": args.artifact_id, "version": args.version}]
    else:
        print("ERROR: provide --deps-json OR (--group-id and --artifact-id).", file=sys.stderr)
        sys.exit(2)

    results = []
    for dep in deps:
        gid = dep.get("groupId", "")
        aid = dep.get("artifactId", "")
        ver = str(dep.get("version", ""))
        if not gid or not aid:
            results.append({
                "groupId": gid, "artifactId": aid, "requested_version": ver,
                "has_metadata": False, "metadata_version": None, "version_tested": False,
                "module_path": f"{gid}/{aid}", "error": "missing groupId/artifactId",
            })
            continue
        results.append(lookup_one(gid, aid, ver, args.ref))

    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
