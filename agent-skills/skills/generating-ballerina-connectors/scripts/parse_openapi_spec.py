#!/usr/bin/env python3
"""
Extract structured metadata from an OpenAPI spec without dumping the raw spec into LLM context.

Output (stdout): JSON object with:
  title, version, description, paths, schemas, tags, servers
"""

import sys
import json
import os


def load_spec(spec_path: str) -> dict:
    _, ext = os.path.splitext(spec_path.lower())
    raw = open(spec_path, "r", encoding="utf-8").read()
    if ext in (".yaml", ".yml"):
        import yaml
        return yaml.safe_load(raw)
    return json.loads(raw)


def extract(spec: dict) -> dict:
    info = spec.get("info", {})
    result = {
        "title": info.get("title", ""),
        "version": info.get("version", ""),
        "description": (info.get("description") or "")[:500],
        "openapi_version": spec.get("openapi") or spec.get("swagger", ""),
        "servers": [s.get("url", "") for s in spec.get("servers", [])[:3]],
        "tags": [t.get("name", "") for t in spec.get("tags", [])],
        "paths": [],
        "schemas": [],
    }

    for path, path_item in (spec.get("paths") or {}).items():
        if not isinstance(path_item, dict):
            continue
        for method in ("get", "post", "put", "patch", "delete", "head", "options"):
            op = path_item.get(method)
            if not isinstance(op, dict):
                continue
            params = []
            for p in op.get("parameters", []):
                if isinstance(p, dict) and "name" in p:
                    params.append({"name": p["name"], "in": p.get("in", ""), "required": p.get("required", False)})
            result["paths"].append({
                "path": path,
                "method": method.upper(),
                "operationId": op.get("operationId", ""),
                "summary": (op.get("summary") or "")[:200],
                "description": (op.get("description") or "")[:300],
                "tags": op.get("tags", []),
                "parameters": params,
                "deprecated": op.get("deprecated", False),
            })

    components = spec.get("components") or spec.get("definitions") or {}
    schemas = components.get("schemas") if isinstance(components, dict) else components
    if isinstance(schemas, dict):
        for name, schema in schemas.items():
            if not isinstance(schema, dict):
                continue
            result["schemas"].append({
                "name": name,
                "type": schema.get("type", "object"),
                "description": (schema.get("description") or "")[:200],
                "properties": list((schema.get("properties") or {}).keys())[:10],
            })

    return result


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <spec-path>", file=sys.stderr)
        sys.exit(2)
    spec = load_spec(sys.argv[1])
    print(json.dumps(extract(spec), indent=2))
