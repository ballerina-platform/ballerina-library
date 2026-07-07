#!/usr/bin/env python3
"""
Analyze a Ballerina client.bal file to extract function signatures and metadata.

Usage: analyze_client.py <path-to-client.bal>
Output (stdout): JSON {apiCount, numExamples, configType, methods:[{name, params:[{type,name}], returnType}]}
"""

import sys
import json
import re
import os


def number_of_examples(api_count: int) -> int:
    if api_count < 15:
        return 1
    elif api_count <= 30:
        return 2
    elif api_count <= 60:
        return 3
    else:
        return 4


def extract_config_type(content: str) -> str:
    """Extract the config type from the init() function first parameter."""
    m = re.search(
        r'public\s+isolated\s+function\s+init\s*\(([^)]+)\)',
        content,
        re.MULTILINE,
    )
    if not m:
        return ""
    params_str = m.group(1).strip()
    # First param: type varName or type varName = default
    first = params_str.split(",")[0].strip()
    # Remove default value
    first = re.sub(r'\s*=.*$', '', first).strip()
    # Extract type (everything before last word)
    parts = first.rsplit(None, 1)
    return parts[0].strip() if len(parts) == 2 else ""


def balance_parens(content: str, start: int) -> int:
    """Return the index after the closing ')' for an opening '(' at start."""
    depth = 0
    i = start
    while i < len(content):
        if content[i] == '(':
            depth += 1
        elif content[i] == ')':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return len(content)


def parse_params(params_str: str) -> list:
    """Parse comma-separated 'type name' pairs, handling nested generics."""
    params = []
    # Split on top-level commas (not inside <> or [])
    depth = 0
    current = []
    for ch in params_str:
        if ch in '<[(':
            depth += 1
        elif ch in '>])':
            depth -= 1
        if ch == ',' and depth == 0:
            params.append(''.join(current).strip())
            current = []
        else:
            current.append(ch)
    if current:
        params.append(''.join(current).strip())

    result = []
    for p in params:
        p = p.strip()
        if not p:
            continue
        # Remove default values
        p = re.sub(r'\s*=\s*\S+\s*$', '', p).strip()
        # Split type and name: last word is the name
        parts = p.rsplit(None, 1)
        if len(parts) == 2:
            result.append({"type": parts[0].strip(), "name": parts[1].strip()})
        elif len(parts) == 1:
            result.append({"type": parts[0].strip(), "name": ""})
    return result


def extract_return_type(after_params: str) -> str:
    """Extract return type from 'returns TYPE {' or end of signature."""
    m = re.search(r'returns\s+([^{;]+)', after_params)
    if m:
        return m.group(1).strip().rstrip('{').strip()
    return ""


def extract_methods(content: str) -> tuple:
    """Extract all remote and resource function signatures from client class body.

    Returns (methods, method_type) where method_type is 'remote' or 'resource'.
    """
    methods = []
    method_type = "resource"  # bal openapi --mode client default

    # Find the client class body
    class_match = re.search(r'isolated\s+client\s+class\s+Client\s*\{', content)
    if not class_match:
        return methods, method_type

    class_start = class_match.end()

    # Unified pattern for both kinds:
    #   remote: (remote) isolated function (funcName)(
    #   resource: (resource) isolated function (accessor) (path)(
    # Group 3 (optional) captures the path segment for resource functions.
    fn_pattern = re.compile(
        r'(remote|resource)\s+isolated\s+function\s+(\w+)(?:\s+([^(]+))?\s*\(',
        re.MULTILINE,
    )

    first = True
    for fn_match in fn_pattern.finditer(content, class_start):
        fn_kind = fn_match.group(1)   # "remote" or "resource"
        fn_name = fn_match.group(2)   # function name (remote) or HTTP accessor (resource)
        fn_path = fn_match.group(3)   # path for resource functions, None for remote

        if first:
            method_type = fn_kind
            first = False

        if fn_kind == "resource" and fn_path:
            name = f"{fn_name} {fn_path.strip()}"
        else:
            name = fn_name

        paren_start = fn_match.end() - 1  # position of '('
        paren_end = balance_parens(content, paren_start)
        params_str = content[paren_start + 1:paren_end - 1]
        after_params = content[paren_end:paren_end + 200]
        return_type = extract_return_type(after_params)
        methods.append({
            "name": name,
            "params": parse_params(params_str),
            "returnType": return_type,
        })

    return methods, method_type


def analyze(client_path: str) -> dict:
    if not os.path.isfile(client_path):
        print(f"ERROR: File not found: {client_path}", file=sys.stderr)
        sys.exit(1)

    content = open(client_path, "r", encoding="utf-8").read()

    methods, method_type = extract_methods(content)
    api_count = len(methods)

    return {
        "apiCount": api_count,
        "numExamples": number_of_examples(api_count),
        "configType": extract_config_type(content),
        "methodType": method_type,
        "methods": methods,
    }


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <client.bal>", file=sys.stderr)
        sys.exit(2)
    print(json.dumps(analyze(sys.argv[1]), indent=2))
