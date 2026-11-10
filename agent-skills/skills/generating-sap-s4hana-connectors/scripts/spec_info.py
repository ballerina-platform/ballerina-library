#!/usr/bin/env python3
"""Summarize an SAP S/4HANA OpenAPI spec (as downloaded from api.sap.com) as JSON.

Everything the later steps need comes from here, so the raw spec never has to be
read into context:
  api_id            API ID on api.sap.com (file stem, e.g. API_INSPECTIONMETHOD_SRV)
  module            Ballerina package suffix (lower-case API ID, e.g. api_inspectionmethod_srv)
  api_postfix       service path after host:port (argument for clientSanitations.bal)
  odata_version     ODATA (V2) or ODATAV4
  title, short_text, business_objects
  scenarios         [{name, id}] from "Communication Scenario" (SAP_COM_xxxx)
  operations        count per HTTP method
  list_paths        GET collection paths without keys (good mock/test targets)
  create_paths      POST paths on entity sets (create operations)
  action_paths      function imports / bound actions (lower or mixed case paths without keys)

Usage: spec_info.py <spec.json> [--api-id ID]
"""
import argparse
import json
import re
import sys
from pathlib import Path

METHODS = ("get", "post", "put", "patch", "delete")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("spec")
    ap.add_argument("--api-id", help="override the API ID (defaults to the file stem without _MOCK)")
    args = ap.parse_args()

    path = Path(args.spec)
    spec = json.loads(path.read_text(encoding="utf-8"))
    api_id = args.api_id or re.sub(r"_MOCK$", "", path.stem)

    server = (spec.get("servers") or [{}])[0].get("url", "")
    m = re.search(r"\{port\}/(.*)$", server) or re.search(r"https?://[^/]+/(.*)$", server)
    api_postfix = m.group(1) if m else ""

    scenarios, business_objects = [], []
    for item in spec.get("x-sap-ext-overview", []) or []:
        for v in item.get("values", []):
            text = v.get("text", "")
            if item.get("name") == "Communication Scenario":
                sm = re.match(r"\s*(.*?)\s*\((SAP_COM_\d{4})\)\s*$", text)
                scenarios.append({"name": sm.group(1), "id": sm.group(2)} if sm else {"name": text, "id": None})
            elif item.get("name") == "Business Object":
                business_objects.append(text)
    if not scenarios:
        ids = sorted(set(re.findall(r"SAP_COM_\d{4}", json.dumps(spec))))
        scenarios = [{"name": None, "id": i} for i in ids]

    counts = {k: 0 for k in METHODS}
    list_paths, create_paths, action_paths = [], [], []
    for p, item in spec.get("paths", {}).items():
        for meth in METHODS:
            if meth in item:
                counts[meth] += 1
        keyed = "(" in p or "{" in p
        segment = p.strip("/").split("/")[0]
        if p == "/$batch":
            continue
        if not keyed and "/" not in p.strip("/"):
            # An entity set's POST body is the entity (`...A_SalesOrderSimulationType-create`); a
            # function import's POST has no body or a different one, and its name may be lower case.
            is_action = segment[:1].islower() or ("get" not in item and "post" in item and not any(
                segment in s.get("$ref", "") for s in [_body_schema(item["post"])]))
            if "get" in item and not is_action:
                desc = json.dumps(item["get"].get("responses", {}).get("200", {}))
                if "Retrieved entities" in desc or "Collection" in desc:
                    list_paths.append(p)
            if "post" in item:
                (action_paths if is_action else create_paths).append(p)
            elif is_action and "get" in item:
                action_paths.append(p)

    out = {
        "api_id": api_id,
        "module": api_id.lower(),
        "package": "sap.s4hana." + api_id.lower(),
        "api_postfix": api_postfix,
        "odata_version": spec.get("x-sap-api-type"),
        "openapi": spec.get("openapi") or spec.get("swagger"),
        "title": spec.get("info", {}).get("title"),
        "short_text": spec.get("x-sap-shortText"),
        "business_objects": business_objects,
        "scenarios": scenarios,
        "operations": {**{k: v for k, v in counts.items() if v}, "total": sum(counts.values())},
        "list_paths": list_paths,
        "create_paths": create_paths,
        "action_paths": action_paths,
        "api_sap_com_url": f"https://api.sap.com/api/{api_id}/overview",
    }
    print(json.dumps(out, indent=2))
    return 0


def _body_schema(op: dict) -> dict:
    body = op.get("requestBody", {}).get("content", {}).get("application/json", {}).get("schema", {})
    if not body:
        for prm in op.get("parameters", []) or []:
            if prm.get("in") == "body":
                body = prm.get("schema", {})
    return body or {}


if __name__ == "__main__":
    sys.exit(main())
