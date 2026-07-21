#!/usr/bin/env python3
"""
Generate (or merge into) sanitations.md by diffing the original OpenAPI spec
against the aligned spec, recording only the structural changes that
`bal openapi flatten`/`align` produce.

This is a faithful port of connector-tool's sanitations_handler.bal
(generateSanitationsDoc / buildAutoDetectedSections / mergeWithExistingSanitations).
It records ONLY five structural categories — server URL, path-prefix removal,
date-time->datetime format, nullability, and type changes. The operationId,
schema-rename, description, and summary enhancements are applied to the spec
elsewhere but are deliberately NOT recorded here.

Usage:
  generate_sanitations.py <original-spec> <aligned-spec> <output-sanitations.md>
    --template <sanitations_template.md> --module-name <MODULE_NAME_PC>
    --cli-command "<bal openapi ... --mode client ...>" [--source-link <url>]

Prints a one-line per-category summary to stdout.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone

MARKER = "<!-- auto-generated -->"


# --------------------------------------------------------------------------- #
# Spec loading (JSON or YAML)
# --------------------------------------------------------------------------- #

def load_spec(path: str) -> dict:
    if not os.path.isfile(path):
        print(f"ERROR: spec not found: {path}", file=sys.stderr)
        sys.exit(1)
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        try:
            import yaml
        except ImportError:
            print(f"ERROR: {path} is not JSON and PyYAML is unavailable to parse YAML.", file=sys.stderr)
            sys.exit(1)
        data = yaml.safe_load(text)
        if not isinstance(data, dict):
            print(f"ERROR: {path} did not parse to a mapping.", file=sys.stderr)
            sys.exit(1)
        return data


# --------------------------------------------------------------------------- #
# Detectors (ported verbatim from sanitations_handler.bal)
# --------------------------------------------------------------------------- #

def extract_server_url(spec: dict) -> str:
    servers = spec.get("servers") if isinstance(spec, dict) else None
    if isinstance(servers, list) and servers:
        first = servers[0]
        if isinstance(first, dict):
            url = first.get("url")
            if isinstance(url, str):
                return url
    return ""


def extract_path_keys(spec: dict) -> list:
    if isinstance(spec, dict):
        paths = spec.get("paths")
        if isinstance(paths, dict):
            return list(paths.keys())
    return []


def detect_removed_path_prefix(original: dict, aligned: dict) -> str:
    original_paths = extract_path_keys(original)
    aligned_paths = extract_path_keys(aligned)
    if not original_paths or not aligned_paths:
        return ""
    # Quirk preserved from connector-tool: compares only the FIRST path key.
    first_original = original_paths[0]
    first_aligned = aligned_paths[0]
    if len(first_original) > len(first_aligned):
        suffix_start = len(first_original) - len(first_aligned)
        if first_original[suffix_start:] == first_aligned:
            return first_original[:suffix_start]
    return ""


def spec_contains_format(node, format_value: str) -> bool:
    if isinstance(node, dict):
        for key, val in node.items():
            if key == "format" and isinstance(val, str) and val == format_value:
                return True
            if spec_contains_format(val, format_value):
                return True
    elif isinstance(node, list):
        for item in node:
            if spec_contains_format(item, format_value):
                return True
    return False


def detect_format_changes(original: dict, aligned: dict) -> list:
    # Hardcoded to date-time -> datetime, matching connector-tool.
    if spec_contains_format(original, "date-time") and spec_contains_format(aligned, "datetime"):
        return [{
            "originalFormat": "date-time",
            "updatedFormat": "datetime",
            "reason": "The `date-time` format is not compatible with the openAPI generation tool. Updated to `datetime` for Ballerina compatibility.",
        }]
    return []


def extract_schemas(spec: dict) -> dict:
    if isinstance(spec, dict):
        components = spec.get("components")
        if isinstance(components, dict):
            schemas = components.get("schemas")
            if isinstance(schemas, dict):
                return schemas
    return {}


def detect_nullability_changes(original: dict, aligned: dict) -> list:
    changes = []
    original_schemas = extract_schemas(original)
    aligned_schemas = extract_schemas(aligned)
    for schema_name, aligned_schema in aligned_schemas.items():
        if not isinstance(aligned_schema, dict):
            continue
        original_schema = original_schemas.get(schema_name)
        original_schema = original_schema if isinstance(original_schema, dict) else {}
        a_props = aligned_schema.get("properties")
        if not isinstance(a_props, dict):
            continue
        o_props = original_schema.get("properties")
        o_props = o_props if isinstance(o_props, dict) else {}
        for field_name, a_field in a_props.items():
            if not isinstance(a_field, dict):
                continue
            nullable_in_aligned = a_field.get("nullable") is True
            o_field = o_props.get(field_name)
            nullable_in_original = isinstance(o_field, dict) and o_field.get("nullable") is True
            if nullable_in_aligned and not nullable_in_original:
                changes.append({
                    "schemaName": schema_name,
                    "fieldName": field_name,
                    "nullable": True,
                    "reason": "The API can return a null value for this field.",
                })
    return changes


def detect_type_changes(original: dict, aligned: dict) -> list:
    changes = []
    original_schemas = extract_schemas(original)
    aligned_schemas = extract_schemas(aligned)
    for schema_name, aligned_schema in aligned_schemas.items():
        original_schema = original_schemas.get(schema_name)
        if not (isinstance(aligned_schema, dict) and isinstance(original_schema, dict)):
            continue
        a_props = aligned_schema.get("properties")
        o_props = original_schema.get("properties")
        if not (isinstance(a_props, dict) and isinstance(o_props, dict)):
            continue
        for field_name, a_field in a_props.items():
            o_field = o_props.get(field_name)
            if not (isinstance(a_field, dict) and isinstance(o_field, dict)):
                continue
            # Fields using $ref / oneOf / anyOf have no "type" key — skip them.
            if "type" not in a_field or "type" not in o_field:
                continue
            a_type = a_field.get("type")
            o_type = o_field.get("type")
            if isinstance(a_type, str) and isinstance(o_type, str) and a_type != o_type:
                changes.append({
                    "schemaName": schema_name,
                    "fieldName": field_name,
                    "originalType": o_type,
                    "updatedType": a_type,
                    "reason": f"The API returns {field_name} as {a_type}; updated for accurate representation.",
                })
    return changes


# --------------------------------------------------------------------------- #
# Section building (buildAutoDetectedSections)
# --------------------------------------------------------------------------- #

def build_auto_detected_sections(original: dict, aligned: dict, start_index: int = 1):
    """Return (blocks, counts). Blocks carry the auto-generated marker."""
    blocks = []
    counts = {"server-url": 0, "path-prefix": 0, "format": 0, "nullability": 0, "type": 0}
    idx = start_index

    orig_server = extract_server_url(original)
    new_server = extract_server_url(aligned)
    if orig_server and new_server and orig_server != new_server:
        blocks.append(
            f"{idx}. Change the `url` property of the servers object\n"
            f"- **Original**: `{orig_server}`\n"
            f"- **Updated**: `{new_server}`\n"
            f"- **Reason**: Common prefix added to base URL to simplify endpoint paths."
        )
        counts["server-url"] += 1
        idx += 1

    prefix = detect_removed_path_prefix(original, aligned)
    if prefix:
        blocks.append(
            f"{idx}. Update the API Paths\n"
            f"- **Original**: Paths included common prefix `{prefix}` in each endpoint.\n"
            f"- **Updated**: Common prefix removed from endpoints as it is now in the base URL.\n"
            f"- **Reason**: Simplifies API paths and avoids duplication."
        )
        counts["path-prefix"] += 1
        idx += 1

    for fc in detect_format_changes(original, aligned):
        blocks.append(
            f"{idx}. Update `{fc['originalFormat']}` to `{fc['updatedFormat']}`\n"
            f"- **Original**: `\"format\":\"{fc['originalFormat']}\"`\n"
            f"- **Updated**: `\"format\":\"{fc['updatedFormat']}\"`\n"
            f"- **Reason**: {fc['reason']}"
        )
        counts["format"] += 1
        idx += 1

    for nc in detect_nullability_changes(original, aligned):
        now_str = "nullable" if nc["nullable"] else "not nullable"
        was_str = "not nullable" if nc["nullable"] else "nullable"
        blocks.append(
            f"{idx}. Change `{nc['schemaName']} {nc['fieldName']}` to {now_str}\n"
            f"- **Original**: The `{nc['fieldName']}` field in `{nc['schemaName']}` was `{was_str}`.\n"
            f"- **Updated**: The `{nc['fieldName']}` field has been updated to be `{now_str}`.\n"
            f"- **Reason**: {nc['reason']}"
        )
        counts["nullability"] += 1
        idx += 1

    for tc in detect_type_changes(original, aligned):
        field_identifier = f"{tc['schemaName']}.{tc['fieldName']}" if tc["schemaName"] else tc["fieldName"]
        blocks.append(
            f"{idx}. Change `{field_identifier}` from `{tc['originalType']}` to `{tc['updatedType']}`\n"
            f"- **Original**: The `{tc['fieldName']}` field was defined as a `{tc['originalType']}`.\n"
            f"- **Updated**: The `{tc['fieldName']}` field has been changed to `{tc['updatedType']}`.\n"
            f"- **Reason**: {tc['reason']}"
        )
        counts["type"] += 1
        idx += 1

    marked = [block + "\n" + MARKER for block in blocks]
    return marked, counts


# --------------------------------------------------------------------------- #
# Merge with existing file (mergeWithExistingSanitations & helpers)
# --------------------------------------------------------------------------- #

NUMBERED_RE = re.compile(r"^[0-9]+\..*")


def extract_file_header(content: str) -> str:
    lines = content.split("\n")
    first_section = len(lines)
    for i, line in enumerate(lines):
        if NUMBERED_RE.match(line.strip()):
            first_section = i
            break
    if first_section == 0:
        return ""
    header_lines = lines[:first_section]
    last = len(header_lines) - 1
    while last > 0 and header_lines[last].strip() == "":
        last -= 1
    return "\n".join(header_lines[:last + 1])


def extract_numbered_sections(content: str) -> list:
    sections = []
    lines = content.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if line.startswith("## "):
            break
        if NUMBERED_RE.match(line):
            block = [lines[i]]
            j = i + 1
            while j < len(lines):
                nxt = lines[j].strip()
                if NUMBERED_RE.match(nxt) or nxt.startswith("## "):
                    break
                block.append(lines[j])
                j += 1
            last = len(block) - 1
            while last > 0 and block[last].strip() == "":
                last -= 1
            sections.append("\n".join(block[:last + 1]))
            i = j
            continue
        i += 1
    return sections


def extract_file_footer(content: str, default_footer: str) -> str:
    lines = content.split("\n")
    for i, line in enumerate(lines):
        if line.strip().startswith("## "):
            return "\n".join(lines[i:])
    return default_footer


def renumber_sections(sections: list) -> list:
    result = []
    for i, s in enumerate(sections):
        dot = s.find(".")
        if dot != -1:
            result.append(f"{i + 1}." + s[dot + 1:])
        else:
            result.append(s)
    return result


def update_date_in_header(header: str, date_str: str) -> str:
    header = re.sub(r"_Updated_:.*", f"_Updated_: {date_str} \\\\", header)
    # Fill _Created_ only if it's still a TODO placeholder (real dates left untouched).
    header = re.sub(r"_Created_:[ \t]*<!--.*?-->[ \t]*\\?", f"_Created_: {date_str} \\\\", header)
    return header


def is_empty_section(section: str) -> bool:
    dot = section.find(".")
    if dot != -1:
        return section[dot + 1:].strip() == ""
    return True


def remove_template_todo_lines(header: str) -> str:
    return "\n".join(l for l in header.split("\n") if not l.strip().startswith("[//]: #"))


def is_section_already_covered(new_section: str, existing_lower: str) -> bool:
    section_lower = new_section.lower()
    if "servers object" in section_lower or ("url" in section_lower and "server" in section_lower):
        return "servers object" in existing_lower or ("url" in existing_lower and "server" in existing_lower)
    if "api paths" in section_lower or "path prefix" in section_lower or "common prefix" in section_lower:
        return ("api paths" in existing_lower or "path prefix" in existing_lower
                or "common prefix" in existing_lower)
    if "format" in section_lower:
        marker = '"format":"'
        q = new_section.find(marker)
        if q != -1:
            after = new_section[q + len(marker):]
            end = after.find('"')
            if end != -1:
                return after[:end].lower() in existing_lower
        return "date-time" in existing_lower or "datetime" in existing_lower
    if "nullable" in section_lower:
        bt1 = new_section.find("`")
        if bt1 != -1:
            bt2 = new_section.find("`", bt1 + 1)
            if bt2 != -1:
                token = new_section[bt1 + 1:bt2].lower()
                return token in existing_lower and "nullable" in existing_lower
        return "nullable" in existing_lower
    if "from" in section_lower and ("string" in section_lower or "integer" in section_lower):
        bt1 = new_section.find("`")
        if bt1 != -1:
            bt2 = new_section.find("`", bt1 + 1)
            if bt2 != -1:
                field_name = new_section[bt1 + 1:bt2].lower()
                if field_name:
                    return field_name in existing_lower
    return False


def merge_with_existing(existing: str, original: dict, aligned: dict,
                        built_footer: str, date_str: str):
    header = extract_file_header(existing)
    existing_sections = extract_numbered_sections(existing)
    updated_header = update_date_in_header(header, date_str)
    updated_header = remove_template_todo_lines(updated_header)

    # Preserve human-authored sections (no marker), but drop empty placeholders.
    human_sections = [s for s in existing_sections if MARKER not in s and not is_empty_section(s)]

    fresh_sections, counts = build_auto_detected_sections(original, aligned, 1)

    human_text = "\n".join(human_sections).lower()
    filtered_fresh = [s for s in fresh_sections if not is_section_already_covered(s, human_text)]

    all_sections = human_sections + filtered_fresh
    renumbered = renumber_sections(all_sections)

    parts = [updated_header, ""]
    for s in renumbered:
        parts.append(s)
        parts.append("")
    parts.append(built_footer)
    return "\n".join(parts), counts


# --------------------------------------------------------------------------- #
# Fresh-file assembly from the template
# --------------------------------------------------------------------------- #

def build_fresh(template: str, module_name: str, cli_command: str,
                source_link: str, sections: list, date_str: str) -> str:
    content = template.replace("{{MODULE_NAME_PC}}", module_name)

    # Dates: fill Created/Updated (leave _Author_ blank for the developer).
    content = re.sub(r"(_Created_:)\s*<!-- TODO: Add date -->", rf"\1 {date_str}", content)
    content = re.sub(r"(_Updated_:)\s*<!-- TODO: Add date -->", rf"\1 {date_str}", content)
    content = re.sub(r"(_Author_:)\s*<!-- TODO: Add author name -->", r"\1", content)

    if source_link:
        content = content.replace("(TODO: Add source link)", source_link)

    # Replace the sanitation-details placeholder block:
    #   [//]: # (TODO: Add sanitation details)\n1. \n2. \n3.
    sections_text = "\n\n".join(sections) if sections else "_No structural sanitations were detected._"
    content = re.sub(
        r"\[//\]: # \(TODO: Add sanitation details\)\n(?:\d+\.[ \t]*\n)+",
        lambda _match: sections_text + "\n",
        content,
    )

    # Footer CLI command.
    content = content.replace("# TODO: Add OpenAPI CLI command used to generate the client", cli_command)
    return content


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #

def main() -> None:
    parser = argparse.ArgumentParser(description="Generate or merge sanitations.md from a spec diff.")
    parser.add_argument("original_spec")
    parser.add_argument("aligned_spec")
    parser.add_argument("output")
    parser.add_argument("--template", required=True)
    parser.add_argument("--module-name", required=True)
    parser.add_argument("--cli-command", required=True)
    parser.add_argument("--source-link", default="")
    args = parser.parse_args()

    original = load_spec(args.original_spec)
    aligned = load_spec(args.aligned_spec)
    date_str = datetime.now(timezone.utc).strftime("%Y/%m/%d")

    if not os.path.isfile(args.template):
        print(f"ERROR: template not found: {args.template}", file=sys.stderr)
        sys.exit(1)
    with open(args.template, "r", encoding="utf-8") as f:
        template = f.read()
    # Footer is always freshly built from the template + the real command — on a
    # merge the existing file's footer is never preserved (matches connector-tool).
    built_footer = extract_file_footer(template, "").replace(
        "# TODO: Add OpenAPI CLI command used to generate the client", args.cli_command)

    if os.path.isfile(args.output):
        with open(args.output, "r", encoding="utf-8") as f:
            existing = f.read()
        content, counts = merge_with_existing(existing, original, aligned, built_footer, date_str)
    else:
        sections, counts = build_auto_detected_sections(original, aligned, 1)
        content = build_fresh(template, args.module_name, args.cli_command,
                              args.source_link, sections, date_str)

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        f.write(content)

    summary = " ".join(f"{k}:{v}" for k, v in counts.items())
    print(f"✓ sanitations.md written: {args.output}")
    print(summary)


if __name__ == "__main__":
    main()
