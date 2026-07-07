#!/usr/bin/env python3
"""
Parse a Ballerina.toml file and extract [package] fields.

Usage: parse_ballerina_toml.py <path-to-Ballerina.toml>
Output (stdout): JSON {org, name, version, distribution}
"""

import sys
import json
import re
import os


def parse(toml_path: str) -> dict:
    if not os.path.isfile(toml_path):
        print(f"ERROR: File not found: {toml_path}", file=sys.stderr)
        sys.exit(1)

    content = open(toml_path, "r", encoding="utf-8").read()

    # Find [package] section — read until next [section] or EOF
    package_match = re.search(r"^\[package\](.*?)(?=^\[|\Z)", content, re.MULTILINE | re.DOTALL)
    if not package_match:
        print("ERROR: No [package] section found in Ballerina.toml", file=sys.stderr)
        sys.exit(1)

    section = package_match.group(1)

    def get_field(key: str) -> str:
        m = re.search(rf'^{key}\s*=\s*"([^"]*)"', section, re.MULTILINE)
        return m.group(1) if m else ""

    return {
        "org": get_field("org"),
        "name": get_field("name"),
        "version": get_field("version"),
        "distribution": get_field("distribution"),
    }


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <Ballerina.toml>", file=sys.stderr)
        sys.exit(2)
    print(json.dumps(parse(sys.argv[1]), indent=2))
