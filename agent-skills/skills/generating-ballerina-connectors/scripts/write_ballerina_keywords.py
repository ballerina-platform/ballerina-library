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


def write_keywords(toml_path: str, keywords: list) -> None:
    if not os.path.isfile(toml_path):
        print(f"ERROR: File not found: {toml_path}", file=sys.stderr)
        sys.exit(1)

    with open(toml_path, "r", encoding="utf-8") as f:
        lines = f.read().split("\n")

    keywords_line = "keywords = [" + ", ".join(f'"{k}"' for k in keywords) + "]"

    has_keywords_line = any(line.strip().startswith("keywords") for line in lines)

    new_lines = []
    if has_keywords_line:
        for line in lines:
            if line.strip().startswith("keywords"):
                new_lines.append(keywords_line)
            else:
                new_lines.append(line)
    else:
        for line in lines:
            new_lines.append(line)
            if line.strip().startswith("version"):
                new_lines.append(keywords_line)

    with open(toml_path, "w", encoding="utf-8") as f:
        f.write("\n".join(new_lines))


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <Ballerina.toml> <keyword1> [keyword2 ...]", file=sys.stderr)
        sys.exit(2)
    write_keywords(sys.argv[1], sys.argv[2:])
    print(f"✓ keywords written: {sys.argv[2:]}")
