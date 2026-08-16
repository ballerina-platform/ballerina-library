#!/usr/bin/env python3
"""Validate a generated connector guide, screenshots, and sample project."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Optional

from append_central_examples import examples_from_metadata
from inject_try_it_yourself import build_section, build_urls

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
BANNED = {
    "code-server": re.compile(r"code-server", re.I),
    "localhost": re.compile(r"localhost|127\.0\.0\.1", re.I),
    "MCP/browser internals": re.compile(
        r"\b(?:playwright|mcp|browser_(?:snapshot|click|type|navigate|evaluate|take_screenshot))\b", re.I
    ),
    "local filesystem paths": re.compile(r"(?:/Users/|/home/|/workspace/|~/|artifacts/|[A-Za-z]:\\)"),
    ".bal references": re.compile(r"\b[^\s`]+\.bal\b", re.I),
    "publishing/PR content": re.compile(r"\b(?:pull request|create a pr)\b", re.I),
    "WSO2 Integrator BI": re.compile(r"WSO2 Integrator BI", re.I),
    "wordy phrasing": re.compile(
        r"\b(?:in order to|utili[sz]e|make use of|at this point in time|please note that)\b", re.I
    ),
    "nonpreferred UI terminology": re.compile(
        r"\b(?:click|clicked|choose|chosen|press|fill in|uncheck)\b|"
        r"(?<!data )\btype\s+(?=(?:a|an|the|your|this|that)\b|[`\"'{0-9])|"
        r"(?<!operation )\binput\s+(?=(?:a|an|the|your|this|that)\b|[`\"'{0-9])",
        re.I,
    ),
    "nondescriptive link text": re.compile(r"\[(?:click here|here|this page|this guide|learn more)\]", re.I),
}

GENERIC_HEADING_WORDS = {
    "Actual", "Add", "Adding", "And", "Configure", "Configuring", "Connection", "Connector",
    "Entry", "Expand", "Flow", "For", "Integration", "Operation", "Parameters", "Result", "Save",
    "Set", "The", "To", "Values", "Your",
}


def h2_kind(heading: str) -> Optional[str]:
    if heading == "What you'll build":
        return "what"
    if heading == "Architecture":
        return "architecture"
    if heading == "Prerequisites":
        return "prerequisites"
    if re.fullmatch(r"Setting up the .+ integration", heading):
        return "setup"
    if re.fullmatch(r"Adding the .+ connector", heading):
        return "adding"
    if re.fullmatch(r"Configuring the .+ connection", heading):
        return "connection"
    if re.fullmatch(r"Configuring the .+ .+ operation", heading):
        return "operation"
    if heading == "Try it yourself":
        return "try"
    if heading == "More code examples":
        return "examples"
    return None


def validate(context: dict) -> list[str]:
    errors: list[str] = []
    doc_path = Path(context["doc_path"])
    screenshots_dir = Path(context["screenshots_dir"])
    sample_dir = Path(context["sample_dir"])
    if not doc_path.is_file():
        return [f"Missing guide: {doc_path}"]
    text = doc_path.read_text(encoding="utf-8")
    authored_text = re.split(r"^## Try it yourself\s*$", text, maxsplit=1, flags=re.M)[0]
    if not text.startswith("# Example\n"):
        errors.append("The guide must start at byte zero with '# Example'.")
    if re.search(r"\{\{[A-Z0-9_]+\}\}|<!--", authored_text):
        errors.append("Guide contains unresolved template placeholders or template comments.")

    all_headings = re.findall(r"^(#{1,3}) (.+)$", authored_text, re.M)
    punctuated = [heading for _, heading in all_headings if heading.endswith(".")]
    if punctuated:
        errors.append(f"Headings must not end with periods: {', '.join(punctuated)}")
    bad_case: list[str] = []
    for _, heading in all_headings:
        title = re.sub(r"^Step \d+:\s*", "", heading)
        words = re.findall(r"[A-Za-z]+", title)
        if any(word in GENERIC_HEADING_WORDS for word in words[1:]):
            bad_case.append(heading)
    if bad_case:
        errors.append(f"Headings must use sentence case: {', '.join(bad_case)}")

    headings = re.findall(r"^## (.+)$", text, re.M)
    kinds = [h2_kind(heading) for heading in headings]
    if any(kind is None for kind in kinds):
        unknown = [heading for heading, kind in zip(headings, kinds) if kind is None]
        errors.append(f"Unexpected H2 section(s): {', '.join(unknown)}")
    required = ["what", "architecture", "setup", "adding", "connection", "operation"]
    filtered = [kind for kind in kinds if kind not in ("prerequisites", "try", "examples", None)]
    if filtered != required:
        errors.append(f"Required H2 order is invalid: {filtered}")
    if kinds.count("prerequisites") > 1 or kinds.count("try") != 1 or kinds.count("examples") > 1:
        errors.append("Prerequisites and examples may appear at most once; Try it yourself must appear exactly once.")
    if "prerequisites" in kinds and kinds.index("prerequisites") != 2:
        errors.append("Prerequisites must follow Architecture.")
    if "try" in kinds:
        try_index = kinds.index("try")
        operation_index = kinds.index("operation") if "operation" in kinds else -1
        if try_index != operation_index + 1:
            errors.append("Try it yourself must immediately follow the operation section.")
    if "examples" in kinds:
        follows_try = "try" in kinds and kinds.index("examples") == kinds.index("try") + 1
        if kinds[-1] != "examples" or not follows_try:
            errors.append("More code examples must immediately follow Try it yourself as the final H2 section.")

    expected_examples = examples_from_metadata(Path(context["metadata_path"]))
    examples_match = re.search(r"^## More code examples\n\n(?P<body>.*)\Z", text, re.M | re.S)
    if expected_examples is None and examples_match:
        errors.append("Guide contains More code examples but Central metadata has no examples.")
    elif expected_examples is not None:
        if not examples_match or examples_match.group("body").strip() != expected_examples:
            errors.append("More code examples must exactly match the cached Ballerina Central metadata.")

    try_match = re.search(r"^## Try it yourself\n\n(?P<body>.*?)(?=^## |\Z)", text, re.M | re.S)
    try:
        expected_try = build_section(context["sample_name"])
        build_urls(context["sample_name"])
    except ValueError as exc:
        expected_try = ""
        errors.append(str(exc))
    actual_try = "## Try it yourself\n\n" + try_match.group("body").strip() if try_match else ""
    if actual_try != expected_try:
        errors.append("Try it yourself section or its deterministic links are invalid.")
    if sample_dir.name != context["sample_name"]:
        errors.append("Sample directory name must exactly match context sample_name.")

    setup_match = re.search(
        r"^## Setting up the .+ integration\n\n(?P<body>.*?)(?=^## )", text, re.M | re.S
    )
    expected_setup = (
        "> **New to WSO2 Integrator?** Follow the [Create a New Integration]"
        "(../../../../develop/create-integrations/create-a-new-integration.md) guide to set up "
        "your integration first, then return here to add the connector."
    )
    if not setup_match or setup_match.group("body").strip() != expected_setup:
        errors.append("The fixed Setting up blockquote is missing or changed.")

    fences = re.findall(r"^```([^\n]*)$", authored_text, re.M)
    if fences != ["mermaid", ""]:
        errors.append("The only fenced block must be one Mermaid architecture block.")
    architecture_match = re.search(r"^## Architecture\n\n(.*?)(?=^## )", text, re.M | re.S)
    if not architecture_match or not re.fullmatch(
        r"```mermaid\nflowchart LR\n.+?\n```\s*", architecture_match.group(1), re.S
    ):
        errors.append("Architecture must contain only one Mermaid flowchart LR block.")
    elif architecture_match:
        diagram = architecture_match.group(1)
        node_ids = set(re.findall(r"\b([A-Za-z][A-Za-z0-9_]*)\s*(?=\[|\(|\{)", diagram))
        if len(node_ids) < 4:
            errors.append("Architecture must contain at least four nodes.")
        if not re.search(r"\bA\(\(User\)\)\s*-->", diagram):
            errors.append("Architecture must begin with A((User)).")
        if not re.search(r"\bC\[[^\]\n]+ Connector\]", diagram, re.I):
            errors.append("Architecture must use the third node for the connector.")
        if r"\n" in diagram:
            errors.append("Architecture node labels must not contain literal \\n sequences.")

    steps = [int(value) for value in re.findall(r"^### Step (\d+): .+$", authored_text, re.M)]
    if not steps or steps != list(range(1, len(steps) + 1)):
        errors.append(f"Step headings must be sequential from 1; found {steps}.")

    connection_match = re.search(
        r"^## Configuring the .+ connection\n\n(?P<body>.*?)(?=^## )", authored_text, re.M | re.S
    )
    if not connection_match or not re.search(
        r"^### Step \d+: Set actual values for your configurables$", connection_match.group("body"), re.M
    ):
        errors.append("Connection section must include 'Set actual values for your configurables'.")
    elif "**Configurations**" not in connection_match.group("body") or "**Data Mappers**" not in connection_match.group("body"):
        errors.append("Configurations step must direct readers to Configurations under Data Mappers.")

    for line in re.findall(r"^- \*\*[^\n]+$", authored_text, re.M):
        if not re.match(r"^- \*\*[^*]+\*\*(?: \(`[^`]+`\))? : \S", line):
            errors.append(f"Invalid parameter/configurable bullet format: {line}")

    for label, pattern in BANNED.items():
        if pattern.search(authored_text):
            errors.append(f"Guide contains forbidden {label} content.")
    if re.search(r"^\|.+\|\s*$", authored_text, re.M):
        errors.append("Markdown tables are not allowed in the guide.")

    image_refs = re.findall(r"!\[[^\]]+\]\(([^)]+)\)", authored_text)
    screenshot_refs = [ref for ref in image_refs if ref.startswith("../screenshots/")]
    expected_numbers = [f"{number:02d}" for number in range(1, 7)]
    actual_numbers = []
    for ref in screenshot_refs:
        match = re.search(r"_screenshot_(\d{2})_", ref)
        if match:
            actual_numbers.append(match.group(1))
        resolved = (doc_path.parent / ref).resolve()
        if resolved.parent != screenshots_dir.resolve() or not resolved.is_file():
            errors.append(f"Broken or unsafe screenshot reference: {ref}")
    if actual_numbers != expected_numbers or len(screenshot_refs) != 6:
        errors.append(f"Guide must reference screenshots 01-06 exactly once; found {actual_numbers}.")

    pngs = sorted(screenshots_dir.glob("*.png"))
    file_numbers = []
    for png in pngs:
        match = re.search(r"_screenshot_(\d{2})_", png.name)
        if match:
            file_numbers.append(match.group(1))
        if png.read_bytes()[:8] != PNG_SIGNATURE:
            errors.append(f"Unreadable PNG signature: {png.name}")
    if file_numbers != expected_numbers or len(pngs) != 6:
        errors.append(f"Screenshot directory must contain only 01-06; found {file_numbers}.")

    if not (sample_dir / "Ballerina.toml").is_file():
        errors.append("Sample project is missing Ballerina.toml.")
    if not list(sample_dir.rglob("*.bal")):
        errors.append("Sample project contains no Ballerina source files.")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--context", required=True, type=Path)
    args = parser.parse_args()
    try:
        context = json.loads(args.context.read_text(encoding="utf-8"))
        errors = validate(context)
    except (OSError, json.JSONDecodeError, KeyError) as exc:
        print(f"[ERROR] Could not validate output: {exc}", file=sys.stderr)
        return 1
    if errors:
        for error in errors:
            print(f"[ERROR] {error}", file=sys.stderr)
        return 1
    print("Output validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
