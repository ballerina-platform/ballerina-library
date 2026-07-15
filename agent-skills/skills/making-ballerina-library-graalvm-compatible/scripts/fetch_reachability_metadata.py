#!/usr/bin/env python3
"""
Download the published native-image config files for one dependency from the
oracle/graalvm-reachability-metadata repository into a staging directory, ready
to be packed under META-INF/native-image/<groupId>/<artifactId>/ (Stage 05).

Given the metadata-version resolved by lookup_reachability_metadata.py, it reads
  metadata/<groupId>/<artifactId>/<metadata-version>/index.json
to learn which config files exist, then downloads each. If the per-version
index.json is absent or in an unexpected shape, it falls back to probing a set of
well-known config filenames (unified + legacy split).

Usage:
  fetch_reachability_metadata.py --group-id com.h2database --artifact-id h2 \
      --metadata-version 2.2.224 --out <staging-dir> [--ref master]

Output (stdout): JSON {out_dir, files:[...], error}
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

RAW_BASE = "https://raw.githubusercontent.com/oracle/graalvm-reachability-metadata/{ref}/metadata"

KNOWN_FILES = [
    "reachability-metadata.json",
    "reflect-config.json",
    "resource-config.json",
    "jni-config.json",
    "proxy-config.json",
    "serialization-config.json",
    "predefined-classes-config.json",
]


def fetch_bytes(url: str, timeout: int = 20) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "ballerina-graalvm-skill"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--group-id", required=True)
    ap.add_argument("--artifact-id", required=True)
    ap.add_argument("--metadata-version", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--ref", default="master")
    args = ap.parse_args()

    base = f"{RAW_BASE.format(ref=args.ref)}/{args.group_id}/{args.artifact_id}/{args.metadata_version}"
    os.makedirs(args.out, exist_ok=True)

    # Determine the file list from the per-version index.json when possible.
    file_names = None
    try:
        idx = json.loads(fetch_bytes(f"{base}/index.json").decode("utf-8"))
        if isinstance(idx, list):
            # list of filenames, or list of objects with "name"
            names = []
            for item in idx:
                if isinstance(item, str):
                    names.append(item)
                elif isinstance(item, dict) and "name" in item:
                    names.append(item["name"])
            if names:
                file_names = names
    except Exception:
        file_names = None

    if file_names is None:
        file_names = KNOWN_FILES  # probe well-known names

    downloaded = []
    for name in file_names:
        url = f"{base}/{name}"
        try:
            data = fetch_bytes(url)
        except urllib.error.HTTPError:
            continue
        except Exception as e:
            print(json.dumps({"out_dir": args.out, "files": downloaded,
                              "error": f"network error fetching {name}: {e}"}, indent=2))
            sys.exit(0)
        dest = os.path.join(args.out, name)
        with open(dest, "wb") as f:
            f.write(data)
        downloaded.append(name)

    error = None if downloaded else "no config files downloaded (none present or network issue)"
    print(json.dumps({"out_dir": args.out, "files": downloaded, "error": error}, indent=2))


if __name__ == "__main__":
    main()
