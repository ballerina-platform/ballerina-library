#!/usr/bin/env python3
"""
Convert a YAML spec file to JSON with a fallback chain.

Mirrors sanitizor/execute.bal:convertAlignedYamlToJson logic.

Usage: convert_yaml_to_json.py <path-to-yaml-file>
Output: Writes <same-path-but-.json>, prints the JSON output path to stdout.
"""

import sys
import json
import os
import subprocess
import re


def yaml_path_to_json_path(yaml_path: str) -> str:
    base = re.sub(r'\.(yaml|yml)$', '', yaml_path, flags=re.IGNORECASE)
    return base + ".json"


def try_python_yaml(yaml_path: str) -> dict | None:
    try:
        import yaml
        with open(yaml_path, "r", encoding="utf-8") as f:
            content = f.read()
        # Mirror the Ballerina workaround: replace backtick (U+0060) chars
        content = content.replace("`", "_")
        return yaml.safe_load(content)
    except ImportError:
        return None
    except Exception as e:
        print(f"  python yaml failed: {e}", file=sys.stderr)
        return None


def try_yq(yaml_path: str) -> dict | None:
    try:
        result = subprocess.run(
            ["yq", "-o=json", ".", yaml_path],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode == 0:
            return json.loads(result.stdout)
    except (FileNotFoundError, subprocess.TimeoutExpired, json.JSONDecodeError) as e:
        print(f"  yq fallback failed: {e}", file=sys.stderr)
    return None


def try_python_yaml_raw(yaml_path: str) -> dict | None:
    # 3rd fallback: PyYAML without backtick replacement — in case the replacement itself corrupted the parse
    try:
        import yaml
        with open(yaml_path, "r", encoding="utf-8") as f:
            return yaml.safe_load(f)
    except ImportError:
        return None
    except Exception as e:
        print(f"  python yaml (raw) fallback failed: {e}", file=sys.stderr)
        return None


def convert(yaml_path: str) -> str:
    if not os.path.isfile(yaml_path):
        print(f"ERROR: File not found: {yaml_path}", file=sys.stderr)
        sys.exit(1)

    ext = os.path.splitext(yaml_path)[1].lower()
    if ext == ".json":
        print(yaml_path)
        return yaml_path

    data = try_python_yaml(yaml_path)
    if data is None:
        data = try_yq(yaml_path)
    if data is None:
        data = try_python_yaml_raw(yaml_path)
    if data is None:
        print(
            "ERROR: Could not convert YAML to JSON. Tried:\n"
            "  1. PyYAML with backtick replacement\n"
            "  2. yq (install: https://github.com/mikefarah/yq)\n"
            "  3. PyYAML without backtick replacement\n"
            "Install PyYAML with `pip install pyyaml` or yq to resolve this.",
            file=sys.stderr,
        )
        sys.exit(1)

    json_path = yaml_path_to_json_path(yaml_path)
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)

    return json_path


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <spec.yaml>", file=sys.stderr)
        sys.exit(2)
    out = convert(sys.argv[1])
    print(out)
