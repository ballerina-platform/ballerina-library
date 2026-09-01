#!/usr/bin/env python3
"""
Extract the classpath (`-cp` value) that `bal test --graalvm` recorded, so the
Ballerina test suite can be run under the tracing agent via BTestMain.

`bal test --graalvm` writes the native-image arguments to
  target/cache/tests_cache/native-config/native-image-args.txt
This script pulls the value following `-cp` out of that file and writes it to a
classpath file (default class-path.txt), the same way the guide's `sed` one-liner does.

Usage:
  extract_test_classpath.py [--native-image-args <path>] [--out class-path.txt]

Defaults:
  --native-image-args target/cache/tests_cache/native-config/native-image-args.txt
  --out               class-path.txt

Output (stdout): JSON {classpath_file, length, found}
"""

import argparse
import json
import os
import re
import sys

DEFAULT_ARGS = os.path.join("target", "cache", "tests_cache", "native-config",
                            "native-image-args.txt")


def extract_classpath(text: str) -> str:
    # Prefer a quoted value (may contain spaces); tolerate `-cp`, `--class-path`,
    # `-classpath`. Fall back to an unquoted, whitespace-delimited value.
    m = re.search(r'(?:-cp|--class-path|-classpath)\s+"([^"]*)"', text)
    if m:
        return m.group(1)
    m = re.search(r"(?:-cp|--class-path|-classpath)\s+(\S+)", text)
    return m.group(1) if m else ""


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--native-image-args", default=DEFAULT_ARGS)
    ap.add_argument("--out", default="class-path.txt")
    args = ap.parse_args()

    if not os.path.isfile(args.native_image_args):
        print(f"ERROR: not found: {args.native_image_args}\n"
              f"Run `bal test --graalvm` first so it generates the native-image args.",
              file=sys.stderr)
        sys.exit(1)

    with open(args.native_image_args, "r", encoding="utf-8", errors="replace") as f:
        text = f.read()

    classpath = extract_classpath(text)
    if not classpath:
        print("ERROR: could not find a -cp entry in the native-image args file.",
              file=sys.stderr)
        sys.exit(1)

    with open(args.out, "w", encoding="utf-8") as f:
        f.write(classpath)

    print(json.dumps({
        "classpath_file": args.out,
        "length": len(classpath),
        "found": True,
    }, indent=2))


if __name__ == "__main__":
    main()
