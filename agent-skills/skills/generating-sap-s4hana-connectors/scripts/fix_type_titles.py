#!/usr/bin/env python3
"""Give inline schemas titles that make valid Ballerina type names (no escaped spaces).

`bal openapi` names an inline object schema after its `title`. Two kinds of SAP title contain
spaces, and the repos' sanitations.bal leaves both alone, so every published package that has
them exposes types like `Modified\\ A_PurchasingInfoRecordType` or `Collection\\ of\\ PutawayReport`:

  PATCH body wrapper     "Modified A_XType"     -> UpdateA_XWrapper   (it wraps {"d": UpdateA_X})
  action result list     "Collection of X"      -> CollectionOfX      (the sanitizer's own list style)

Anything else with a space (none in the published specs today) is joined into one word, with
a warning. Schemas directly under components/schemas are skipped: their type name comes from
the key, not the title.

Usage: fix_type_titles.py <spec.json>     (rewrites the file, prints each rename)
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import specjson  # noqa: E402


def new_title(schema: dict, title: str) -> tuple[str, bool]:
    m = re.fullmatch(r"Modified (\w+?)(?:Type)?", title)
    if m:
        ref = ((schema.get("properties") or {}).get("d") or {}).get("$ref", "")
        inner = ref.rsplit("/", 1)[-1] if ref else f"Update{m.group(1)}"
        return f"{inner}Wrapper", True
    m = re.fullmatch(r"Collection of (\w+?)(?:Type)?", title)
    if m:
        return f"CollectionOf{m.group(1)}", True
    return "".join(w[:1].upper() + w[1:] for w in re.split(r"[^\w]+", title) if w), False


def fix(spec: dict) -> list[tuple[str, str, bool]]:
    renames = {}
    taken = set((spec.get("components") or {}).get("schemas", {}))

    def walk(node, top_level_schema: bool):
        if isinstance(node, dict):
            title = node.get("title")
            if (not top_level_schema and isinstance(title, str) and " " in title
                    and (node.get("type") == "object" or "properties" in node)):
                if title not in renames:
                    renames[title] = new_title(node, title)
                node["title"] = renames[title][0]
            for k, v in node.items():
                walk(v, False)
        elif isinstance(node, list):
            for v in node:
                walk(v, False)

    for key, value in spec.items():
        if key == "components":
            for kind, group in value.items():
                for name, schema in (group or {}).items():
                    walk(schema, kind == "schemas")
        else:
            walk(value, False)
    clashes = sorted({n for n, _ in renames.values() if n in taken})
    if clashes:
        sys.exit(f"renamed titles clash with existing schemas: {clashes}; pick names by hand")
    return [(old, new, known) for old, (new, known) in renames.items()]


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    path = Path(sys.argv[1])
    spec = specjson.load(path)
    renames = fix(spec)
    specjson.dump(spec, path)
    for old, new, known in renames:
        print(f"  {old!r} -> {new}" + ("" if known else "   (unrecognised pattern; check the name)"))
    print(f"{len(renames)} inline schema title(s) renamed" if renames else "no spaced inline titles")
    return 0


if __name__ == "__main__":
    sys.exit(main())
