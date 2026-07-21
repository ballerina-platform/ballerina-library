#!/usr/bin/env python3
"""
Print a newline-separated list of candidate OpenAPI spec files found in CWD.
Priority: openapi.yaml/yml/json first, then docs/spec/, then any *.yaml/json
(max 8 results).

Usage: find_spec_files.py
"""

import os

SPEC_EXTS = (".yaml", ".yml", ".json")
NAMED_CANDIDATES = {"openapi.yaml", "openapi.yml", "openapi.json"}
EXCLUDED_ANY = {".git", "node_modules", "target"}
MAX_RESULTS = 8


def walk(root: str, max_depth: int, excluded: set):
    if not os.path.isdir(root):
        return
    for current, dirs, files in os.walk(root):
        rel = os.path.relpath(current, root)
        depth = 0 if rel == "." else rel.count(os.sep) + 1
        if depth >= max_depth:
            dirs[:] = []
            continue
        dirs[:] = sorted(d for d in dirs if d not in excluded)
        for f in sorted(files):
            yield os.path.join(current, f)


def find_named(cwd: str):
    for path in walk(cwd, 4, {".git", "node_modules", "target"}):
        if os.path.basename(path) in NAMED_CANDIDATES:
            yield path


def find_docs_spec(cwd: str):
    docs_spec = os.path.join(cwd, "docs", "spec")
    for path in walk(docs_spec, 2, {".git"}):
        if path.endswith(SPEC_EXTS):
            yield path


def find_any(cwd: str):
    for path in walk(cwd, 3, EXCLUDED_ANY | {".claude"}):
        if path.endswith(SPEC_EXTS):
            yield path


def main() -> None:
    cwd = os.getcwd()
    seen = set()
    results = []

    for candidate in (*find_named(cwd), *find_docs_spec(cwd), *find_any(cwd)):
        if candidate not in seen:
            seen.add(candidate)
            results.append(candidate)
        if len(results) >= MAX_RESULTS:
            break

    for path in results[:MAX_RESULTS]:
        print(path)


if __name__ == "__main__":
    main()
