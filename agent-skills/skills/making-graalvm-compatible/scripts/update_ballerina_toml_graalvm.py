#!/usr/bin/env python3
"""
Update Ballerina.toml for GraalVM compatibility, preserving existing formatting
and comments (targeted text edits — never a blind rewrite / full re-serialization).

Two independent operations (either or both):
  1. Set `graalvmCompatible = <bool>` in the [platform.<javaXX>] section
     (creating the section if absent).
  2. --add-dependency: append a [[platform.<javaXX>.dependency]] table for a
     native config jar.

Usage:
  update_ballerina_toml_graalvm.py --toml <path> --java-version java21
      [--graalvm-compatible true]
      [--add-dependency --group-id <g> --artifact-id <a> --dep-version <v> --path <jar>]

Output (stdout): JSON {toml, changes:[...]}
"""

import argparse
import json
import os
import re
import sys


def set_graalvm_compatible(text: str, java_version: str, value: bool, changes: list) -> str:
    header = f"[platform.{java_version}]"
    val_str = "true" if value else "false"

    header_re = re.compile(rf"^\[platform\.{re.escape(java_version)}\]\s*$", re.MULTILINE)
    m = header_re.search(text)
    if not m:
        block = f"{header}\ngraalvmCompatible = {val_str}\n"
        # Prefer to place the table block BEFORE the first platform.<jv> header
        # (e.g. an existing [[platform.<jv>.dependency]] array) — the canonical,
        # unambiguous ordering (define the table, then its array-of-tables).
        first_platform = re.search(rf"^\[+platform\.{re.escape(java_version)}\b",
                                   text, re.MULTILINE)
        if first_platform:
            idx = first_platform.start()
            changes.append(f"added {header} with graalvmCompatible = {val_str} "
                           f"(before existing platform.{java_version} entries)")
            return text[:idx] + block + "\n" + text[idx:]
        # Otherwise append at EOF.
        sep = "" if text.endswith("\n") or text == "" else "\n"
        changes.append(f"added {header} with graalvmCompatible = {val_str}")
        return text + f"{sep}\n{block}"

    # Section exists — find its extent (until next top-level [ or EOF).
    sec_start = m.end()
    next_sec = re.search(r"^\[", text[sec_start:], re.MULTILINE)
    sec_end = sec_start + next_sec.start() if next_sec else len(text)
    section = text[sec_start:sec_end]

    gc_re = re.compile(r"^(\s*graalvmCompatible\s*=\s*)(true|false)\s*$", re.MULTILINE)
    gm = gc_re.search(section)
    if gm:
        new_section = gc_re.sub(rf"\g<1>{val_str}", section, count=1)
        changes.append(f"set graalvmCompatible = {val_str} in {header}")
    else:
        # `section` begins with the header line's own line-ending newline
        # (since sec_start = m.end(), which sits right before it). Preserve
        # exactly that one newline so the header keeps its own line, then
        # insert the key, then keep the remainder — including any blank-line
        # spacing already present — untouched.
        rest = section[1:] if section.startswith("\n") else section
        new_section = f"\ngraalvmCompatible = {val_str}\n" + rest
        changes.append(f"inserted graalvmCompatible = {val_str} into {header}")

    return text[:sec_start] + new_section + text[sec_end:]


def add_dependency(text: str, java_version: str, group_id: str, artifact_id: str,
                   version: str, path: str, changes: list) -> str:
    block = (
        f"\n[[platform.{java_version}.dependency]]\n"
        f'groupId = "{group_id}"\n'
        f'artifactId = "{artifact_id}"\n'
        f'version = "{version}"\n'
        f'path = "{path}"\n'
    )
    sep = "" if text.endswith("\n") else "\n"
    changes.append(f"added [[platform.{java_version}.dependency]] for {group_id}:{artifact_id}")
    return text + sep + block


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--toml", required=True)
    ap.add_argument("--java-version", required=True, help="e.g. java21")
    ap.add_argument("--graalvm-compatible", choices=["true", "false"])
    ap.add_argument("--add-dependency", action="store_true")
    ap.add_argument("--group-id")
    ap.add_argument("--artifact-id")
    ap.add_argument("--dep-version")
    ap.add_argument("--path")
    args = ap.parse_args()

    if not os.path.isfile(args.toml):
        print(f"ERROR: file not found: {args.toml}", file=sys.stderr)
        sys.exit(1)

    with open(args.toml, "r", encoding="utf-8") as f:
        text = f.read()

    changes = []

    if args.graalvm_compatible is not None:
        text = set_graalvm_compatible(text, args.java_version,
                                      args.graalvm_compatible == "true", changes)

    if args.add_dependency:
        missing = [k for k in ("group_id", "artifact_id", "dep_version", "path")
                   if getattr(args, k) is None]
        if missing:
            print(f"ERROR: --add-dependency requires --group-id --artifact-id "
                  f"--dep-version --path (missing: {missing})", file=sys.stderr)
            sys.exit(2)
        text = add_dependency(text, args.java_version, args.group_id, args.artifact_id,
                              args.dep_version, args.path, changes)

    if not changes:
        print("ERROR: nothing to do — pass --graalvm-compatible and/or --add-dependency.",
              file=sys.stderr)
        sys.exit(2)

    with open(args.toml, "w", encoding="utf-8") as f:
        f.write(text)

    print(json.dumps({"toml": args.toml, "changes": changes}, indent=2))


if __name__ == "__main__":
    main()
