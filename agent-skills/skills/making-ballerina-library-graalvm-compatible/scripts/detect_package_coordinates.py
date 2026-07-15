#!/usr/bin/env python3
"""
Read a Ballerina.toml and extract everything the GraalVM workflow needs:
package identity, declared platform blocks, the graalvmCompatible flag, and the
third-party Java dependencies (from [[platform.<javaXX>.dependency]] tables).

The first Java dependency's groupId/artifactId are surfaced as GROUP_ID /
ARTIFACT_ID (the coordinates under which native-image config is packed:
META-INF/native-image/<groupId>/<artifactId>/). When there is no Java dependency,
they fall back to the package org / name so the stages still have a coordinate.

Usage: detect_package_coordinates.py <path-to-Ballerina.toml>

Output (stdout): JSON
  {org, name, version, distribution, platform_blocks:[...],
   graalvm_compatible: {java11: bool, ...}, java_dependencies:[{platform, groupId,
   artifactId, version, path}], group_id, artifact_id, has_native_dir, native_dir,
   meta_inf_dir}

Prefers the stdlib `tomllib` (Python 3.11+) or `tomli`; falls back to a regex
parser for the fields this skill relies on.
"""

import json
import os
import re
import sys

try:
    import tomllib as _toml  # Python 3.11+
    _HAS_TOML = True
except ImportError:
    try:
        import tomli as _toml  # backport
        _HAS_TOML = True
    except ImportError:
        _HAS_TOML = False


def _parse_with_toml(content: bytes) -> dict:
    data = _toml.loads(content.decode("utf-8"))
    package = data.get("package", {})
    platform = data.get("platform", {}) or {}

    platform_blocks = []
    graalvm_compatible = {}
    java_dependencies = []
    for key, block in platform.items():
        if not isinstance(block, dict):
            continue
        platform_blocks.append(key)
        if "graalvmCompatible" in block:
            graalvm_compatible[key] = bool(block.get("graalvmCompatible"))
        for dep in block.get("dependency", []) or []:
            java_dependencies.append({
                "platform": key,
                "groupId": dep.get("groupId", ""),
                "artifactId": dep.get("artifactId", ""),
                "version": str(dep.get("version", "")),
                "path": dep.get("path", ""),
            })
    return {
        "org": package.get("org", ""),
        "name": package.get("name", ""),
        "version": str(package.get("version", "")),
        "distribution": package.get("distribution", ""),
        "platform_blocks": platform_blocks,
        "graalvm_compatible": graalvm_compatible,
        "java_dependencies": java_dependencies,
    }


def _parse_with_regex(text: str) -> dict:
    def package_field(key: str) -> str:
        m = re.search(r"^\[package\](.*?)(?=^\[|\Z)", text, re.MULTILINE | re.DOTALL)
        section = m.group(1) if m else ""
        fm = re.search(rf'^{key}\s*=\s*"([^"]*)"', section, re.MULTILINE)
        return fm.group(1) if fm else ""

    platform_blocks = sorted(set(re.findall(r"^\[+platform\.([A-Za-z0-9_]+)", text, re.MULTILINE)))

    graalvm_compatible = {}
    for pk in platform_blocks:
        m = re.search(rf"^\[platform\.{pk}\](.*?)(?=^\[|\Z)", text, re.MULTILINE | re.DOTALL)
        section = m.group(1) if m else ""
        gm = re.search(r"^graalvmCompatible\s*=\s*(true|false)", section, re.MULTILINE)
        if gm:
            graalvm_compatible[pk] = gm.group(1) == "true"

    java_dependencies = []
    for m in re.finditer(r"^\[\[platform\.([A-Za-z0-9_]+)\.dependency\]\](.*?)(?=^\[|\Z)",
                         text, re.MULTILINE | re.DOTALL):
        pk, section = m.group(1), m.group(2)

        def field(key: str) -> str:
            fm = re.search(rf'^{key}\s*=\s*"?([^"\n]*)"?', section, re.MULTILINE)
            return fm.group(1).strip().strip('"') if fm else ""

        java_dependencies.append({
            "platform": pk,
            "groupId": field("groupId"),
            "artifactId": field("artifactId"),
            "version": field("version"),
            "path": field("path"),
        })

    return {
        "org": package_field("org"),
        "name": package_field("name"),
        "version": package_field("version"),
        "distribution": package_field("distribution"),
        "platform_blocks": platform_blocks,
        "graalvm_compatible": graalvm_compatible,
        "java_dependencies": java_dependencies,
    }


def main() -> None:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <Ballerina.toml>", file=sys.stderr)
        sys.exit(2)

    toml_path = sys.argv[1]
    if not os.path.isfile(toml_path):
        print(f"ERROR: File not found: {toml_path}", file=sys.stderr)
        sys.exit(1)

    with open(toml_path, "rb") as f:
        raw = f.read()

    if _HAS_TOML:
        try:
            result = _parse_with_toml(raw)
        except Exception:
            result = _parse_with_regex(raw.decode("utf-8", errors="replace"))
    else:
        result = _parse_with_regex(raw.decode("utf-8", errors="replace"))

    # Derive coordinates for META-INF packing.
    if result["java_dependencies"]:
        first = result["java_dependencies"][0]
        group_id = first["groupId"] or result["org"]
        artifact_id = first["artifactId"] or result["name"]
    else:
        group_id = result["org"]
        artifact_id = result["name"]
    result["group_id"] = group_id
    result["artifact_id"] = artifact_id

    pkg_dir = os.path.dirname(os.path.abspath(toml_path))
    native_dir = os.path.join(pkg_dir, "native")
    result["has_native_dir"] = os.path.isdir(native_dir)
    result["native_dir"] = native_dir
    result["meta_inf_dir"] = os.path.join(
        native_dir, "src", "main", "resources", "META-INF", "native-image",
        group_id, artifact_id,
    )

    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
