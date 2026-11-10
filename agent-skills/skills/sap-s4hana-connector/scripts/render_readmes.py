#!/usr/bin/env python3
"""Regenerate ballerina/*/README.md from build-config/resources/README.md and each docs.json.

Same substitutions as the `updateDocumentationFiles` Gradle task in ballerina/build.gradle, so
the result is what CI would produce, without running Gradle (its Docker-based build tends to
hang on a laptop). Reads the placeholder list from the template, so it also works for repos
whose template has fewer keys.

Usage: render_readmes.py <repo> [<module> ...]
"""
import json
import re
import sys
from pathlib import Path

DEFAULT_IMAGES = {
    "scenario-search-image": "s4-3-search-scenario.png",
    "new-arrangement-image": "s4-4-new-arrangement.png",
    "arrangement-details-image": "s4-5-arrangement-details.png",
}


def render(template: str, module: str, docs: dict) -> str:
    out = template.replace("@package-name@", f"sap.s4hana.{module}").replace("@service-name@", module.upper())
    out = out.replace("@key-features@", "\n".join(f"- {k}" for k in docs.get("key-features", [])))
    for key in re.findall(r"@([a-z-]+)@", out):
        value = docs.get(key, DEFAULT_IMAGES.get(key))
        if value is None:
            raise KeyError(f"{module}/docs.json has no '{key}'")
        out = out.replace(f"@{key}@", value)
    return out


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0
    repo = Path(sys.argv[1]).resolve()
    template = (repo / "build-config/resources/README.md").read_text()
    modules = sys.argv[2:] or sorted(p.parent.name for p in (repo / "ballerina").glob("*/docs.json"))
    setup = repo / "docs" / "setup"
    for m in modules:
        docs = json.loads((repo / "ballerina" / m / "docs.json").read_text())
        text = render(template, m, docs)
        (repo / "ballerina" / m / "README.md").write_text(text)
        # Shared images live in module-ballerinax-sap; only this repo's own docs/setup files are checked.
        own = [img for r, img in re.findall(r"githubusercontent\.com/ballerina-platform/([\w.-]+)/main/docs/setup/([\w.-]+\.png)", text)
               if r != "module-ballerinax-sap"]
        missing = sorted({i for i in own if not (setup / i).exists()})
        print(f"{m}/README.md rendered" + (f"; screenshots still missing in docs/setup: {missing}" if missing else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
