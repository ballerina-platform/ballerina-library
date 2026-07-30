#!/usr/bin/env python3
"""Collect and apply request-body and API-key descriptions.

Usage:
  spec_descriptions.py prepare <aligned-spec.json> <requests.json>
  spec_descriptions.py apply <aligned-spec.json> <requests.json> <decisions.json>
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
from typing import Any

HTTP_METHODS = ("get", "post", "put", "delete", "patch", "head", "options", "trace")
PLACEHOLDERS = {
    "-", "tbd", "todo", "n/a", "na", "none", "null", "not available",
    "not applicable", "description", "add description", "no description",
}


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key '{key}'")
        result[key] = value
    return result


def read_json(path: str, reject_duplicates: bool = False) -> Any:
    try:
        with open(path, encoding="utf-8") as file:
            return json.load(file, object_pairs_hook=reject_duplicate_keys if reject_duplicates else None)
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        fail(f"could not read JSON file {path}: {exc}")


def atomic_write_json(path: str, value: Any) -> None:
    directory = os.path.dirname(os.path.abspath(path))
    fd, temporary = tempfile.mkstemp(prefix=".connector-descriptions-", suffix=".json", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as file:
            json.dump(value, file, indent=2, ensure_ascii=False)
            file.write("\n")
            file.flush()
            os.fsync(file.fileno())
        os.replace(temporary, path)
    except OSError as exc:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        fail(f"could not atomically write {path}: {exc}")


def invalid_description(value: Any) -> bool:
    if not isinstance(value, str) or not value.strip():
        return True
    normalized = " ".join(value.strip().lower().rstrip(".").split())
    return normalized in PLACEHOLDERS


def schema_context(schema: Any) -> dict[str, Any]:
    if not isinstance(schema, dict):
        return {}
    reference = schema.get("$ref")
    if isinstance(reference, str):
        return {"reference": reference.rsplit("/", 1)[-1]}
    result: dict[str, Any] = {}
    if isinstance(schema.get("type"), str):
        result["type"] = schema["type"]
    properties = schema.get("properties")
    if isinstance(properties, dict):
        result["properties"] = list(properties)[:20]
    if isinstance(schema.get("items"), dict):
        result["items"] = schema_context(schema["items"])
    return result


def collect(spec: dict[str, Any]) -> list[dict[str, Any]]:
    info = spec.get("info") if isinstance(spec.get("info"), dict) else {}
    api = {
        "title": info.get("title", ""),
        "description": (info.get("description") or "")[:500],
    }
    requests: list[dict[str, Any]] = []
    paths = spec.get("paths")
    if isinstance(paths, dict):
        for path, path_item in paths.items():
            if not isinstance(path_item, dict):
                continue
            for method in HTTP_METHODS:
                operation = path_item.get(method)
                if not isinstance(operation, dict):
                    continue
                body = operation.get("requestBody")
                if not isinstance(body, dict) or "$ref" in body or not invalid_description(body.get("description")):
                    continue
                content_context = []
                content = body.get("content")
                if isinstance(content, dict):
                    for media_type, media in content.items():
                        media = media if isinstance(media, dict) else {}
                        content_context.append({
                            "media_type": media_type,
                            "schema": schema_context(media.get("schema")),
                        })
                requests.append({
                    "id": f"requestBody:{len(requests)}",
                    "type": "requestBody",
                    "location": {"path": path, "method": method},
                    "context": {
                        **api,
                        "operation_id": operation.get("operationId", ""),
                        "summary": (operation.get("summary") or "")[:200],
                        "operation_description": (operation.get("description") or "")[:300],
                        "path": path,
                        "method": method,
                        "required": bool(body.get("required", False)),
                        "content": content_context,
                    },
                    "instruction": "Describe the complete submitted payload and its purpose in under 100 characters.",
                })

    components = spec.get("components")
    schemes = components.get("securitySchemes") if isinstance(components, dict) else None
    if isinstance(schemes, dict):
        for name, scheme in schemes.items():
            if (not isinstance(scheme, dict) or scheme.get("type") != "apiKey" or
                    not invalid_description(scheme.get("description"))):
                continue
            requests.append({
                "id": f"securityScheme:{len(requests)}",
                "type": "securityScheme",
                "location": {"scheme_name": name},
                "context": {
                    **api,
                    "scheme_name": name,
                    "wire_name": scheme.get("name", name),
                    "in": scheme.get("in", ""),
                    "x_ballerina_name": scheme.get("x-ballerina-name", ""),
                },
                "instruction": "Describe the credential and where or how it is supplied in under 100 characters.",
            })
    return requests


def prepare(spec_path: str, requests_path: str) -> None:
    spec = read_json(spec_path)
    if not isinstance(spec, dict):
        fail("aligned specification must contain a JSON object")
    requests = collect(spec)
    atomic_write_json(requests_path, {"requests": requests})
    print(json.dumps({
        "request_count": len(requests),
        "request_body_count": sum(item["type"] == "requestBody" for item in requests),
        "security_scheme_count": sum(item["type"] == "securityScheme" for item in requests),
        "requests": requests,
    }))


def parse_decisions(value: Any) -> dict[str, str]:
    if not isinstance(value, dict):
        fail("description decisions must be a JSON object")
    decisions: dict[str, str] = {}
    for request_id, description in value.items():
        if not isinstance(request_id, str) or not isinstance(description, str):
            fail("description decisions must map request IDs to non-placeholder descriptions")
        normalized = description.strip().rstrip(".")
        if invalid_description(normalized):
            fail("description decisions must map request IDs to non-placeholder descriptions")
        decisions[request_id] = normalized
    return decisions


def apply(spec_path: str, requests_path: str, decisions_path: str) -> None:
    spec = read_json(spec_path)
    request_document = read_json(requests_path)
    decisions = parse_decisions(read_json(decisions_path, reject_duplicates=True))
    if not isinstance(spec, dict) or not isinstance(request_document, dict):
        fail("spec and request document must be JSON objects")
    request_items = request_document.get("requests")
    if not isinstance(request_items, list):
        fail("request document must contain a requests array")
    requests = {
        item.get("id"): item for item in request_items
        if isinstance(item, dict) and isinstance(item.get("id"), str)
    }
    unknown = sorted(set(decisions) - set(requests))
    if unknown:
        fail("unknown description decision IDs: " + ", ".join(unknown))

    body_updates = scheme_updates = skipped = 0
    for request_id, description in decisions.items():
        request = requests[request_id]
        location = request.get("location")
        if not isinstance(location, dict):
            fail(f"invalid location for request '{request_id}'")
        target: Any = None
        if request.get("type") == "requestBody":
            path_item = (spec.get("paths") or {}).get(location.get("path"))
            operation = path_item.get(location.get("method")) if isinstance(path_item, dict) else None
            target = operation.get("requestBody") if isinstance(operation, dict) else None
            if not isinstance(target, dict) or "$ref" in target:
                fail(f"request body no longer exists for '{request_id}'")
            if invalid_description(target.get("description")):
                target["description"] = description
                body_updates += 1
            else:
                skipped += 1
        elif request.get("type") == "securityScheme":
            components = spec.get("components")
            schemes = components.get("securitySchemes") if isinstance(components, dict) else None
            target = schemes.get(location.get("scheme_name")) if isinstance(schemes, dict) else None
            if not isinstance(target, dict):
                fail(f"security scheme no longer exists for '{request_id}'")
            if target.get("type") == "apiKey" and invalid_description(target.get("description")):
                target["description"] = description
                scheme_updates += 1
            else:
                skipped += 1
        else:
            fail(f"unsupported description request type for '{request_id}'")

    atomic_write_json(spec_path, spec)
    print(json.dumps({
        "request_bodies_updated": body_updates,
        "security_schemes_updated": scheme_updates,
        "pending_count": len(requests) - len(decisions),
        "skipped_documented_count": skipped,
    }))


def usage() -> None:
    print(f"Usage: {sys.argv[0]} prepare <aligned-spec.json> <requests.json>", file=sys.stderr)
    print(f"       {sys.argv[0]} apply <aligned-spec.json> <requests.json> <decisions.json>", file=sys.stderr)
    raise SystemExit(2)


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "prepare":
        prepare(*sys.argv[2:])
    elif len(sys.argv) == 5 and sys.argv[1] == "apply":
        apply(*sys.argv[2:])
    else:
        usage()
