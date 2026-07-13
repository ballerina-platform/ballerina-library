#!/usr/bin/env python3
"""
Parse a Ballerina.toml file and extract [package] fields.

Usage: parse_ballerina_toml.py <path-to-Ballerina.toml>
Output (stdout): JSON {org, name, version, distribution, keywords, description}
"""

import sys
import json
import re
import os


def parse(toml_path: str) -> dict:
    if not os.path.isfile(toml_path):
        print(f"ERROR: File not found: {toml_path}", file=sys.stderr)
        sys.exit(1)

    with open(toml_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Find [package] section — read until next [section] or EOF
    package_match = re.search(r"^\[package\](.*?)(?=^\[|\Z)", content, re.MULTILINE | re.DOTALL)
    if not package_match:
        print("ERROR: No [package] section found in Ballerina.toml", file=sys.stderr)
        sys.exit(1)

    section = package_match.group(1)

    def get_field(key: str) -> str:
        m = re.search(rf'^{key}\s*=\s*"([^"]*)"', section, re.MULTILINE)
        return m.group(1) if m else ""

    def get_keywords() -> list:
        m = re.search(r'^keywords\s*=\s*\[([^\]]*)\]', section, re.MULTILINE)
        if not m:
            return []
        tokens = m.group(1).split(",")
        return [t.strip().strip('"') for t in tokens if t.strip().strip('"')]

    return {
        "org": get_field("org"),
        "name": get_field("name"),
        "version": get_field("version"),
        "distribution": get_field("distribution"),
        "keywords": get_keywords(),
        "description": get_field("description"),
    }


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <Ballerina.toml>", file=sys.stderr)
        sys.exit(2)
    print(json.dumps(parse(sys.argv[1]), indent=2))
