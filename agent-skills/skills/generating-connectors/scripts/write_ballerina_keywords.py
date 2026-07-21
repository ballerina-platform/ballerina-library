#!/usr/bin/env python3
"""
Write (or replace) the `keywords` array in a Ballerina.toml's [package] section.

Usage: write_ballerina_keywords.py <path-to-Ballerina.toml> <keyword1> [keyword2 ...]

If a `keywords = [...]` line already exists, it is replaced in place.
Otherwise, a new `keywords = [...]` line is inserted directly after the
line starting with `version`. Every other line is left untouched.
"""

import sys
import os


def _is_key(line: str, key: str) -> bool:
    """True if `line` is a TOML assignment for `key` (i.e. `key` followed by
    optional whitespace and `=`), not a different key that merely shares the
    prefix (e.g. `keywords_old`, `version_info`)."""
    stripped = line.strip()
    if not stripped.startswith(key):
        return False
    return stripped[len(key):].lstrip().startswith("=")


def write_keywords(toml_path: str, keywords: list) -> None:
    if not os.path.isfile(toml_path):
        print(f"ERROR: File not found: {toml_path}", file=sys.stderr)
        sys.exit(1)

    with open(toml_path, "r", encoding="utf-8") as f:
        lines = f.read().split("\n")

    keywords_line = "keywords = [" + ", ".join(f'"{k}"' for k in keywords) + "]"

    has_keywords_line = any(_is_key(line, "keywords") for line in lines)

    new_lines = []
    if has_keywords_line:
        for line in lines:
            new_lines.append(keywords_line if _is_key(line, "keywords") else line)
    else:
        inserted = False
        for line in lines:
            new_lines.append(line)
            if not inserted and _is_key(line, "version"):
                new_lines.append(keywords_line)
                inserted = True
        if not inserted:
            # No `version` key to anchor to — append to the end of the
            # [package] section instead (before the next table header / EOF).
            new_lines = []
            in_package = False
            for line in lines:
                stripped = line.strip()
                if in_package and not inserted and stripped.startswith("[") and stripped != "[package]":
                    new_lines.append(keywords_line)
                    inserted = True
                    in_package = False
                new_lines.append(line)
                if stripped == "[package]":
                    in_package = True
            if in_package and not inserted:
                new_lines.append(keywords_line)
                inserted = True
        if not inserted:
            print("ERROR: No [package] section found in Ballerina.toml — cannot write keywords.", file=sys.stderr)
            sys.exit(1)

    with open(toml_path, "w", encoding="utf-8") as f:
        f.write("\n".join(new_lines))


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <Ballerina.toml> <keyword1> [keyword2 ...]", file=sys.stderr)
        sys.exit(2)
    write_keywords(sys.argv[1], sys.argv[2:])
    print(f"✓ keywords written: {sys.argv[2:]}")
