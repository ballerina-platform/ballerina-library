#!/usr/bin/env python3
"""Register a new package in an S/4HANA area repo (module-ballerinax-sap.s4hana.<area>).

Touches every place a package has to be listed, copying the shape of an existing sibling
package so the result matches the repo:
  ballerina/<m>/Ballerina.toml      from build-config/resources/Ballerina.toml (name, version, keywords)
  ballerina/<m>/build.gradle        copy of a sibling's, renamed; description uses --name, or --api-title
                                    when the siblings' descriptions use api.sap.com titles
  settings.gradle                   include + projectDir
  gradle.properties                 <m>Version=<version>-SNAPSHOT
  ballerina/build.gradle            dependsOn(':<area>-ballerina:<m>:<task>'), the task the siblings use
  .github/workflows/*.yml           every `options:` list that names the sibling packages
  README.md                         build-table row (and the numbered list entry with --description)

Idempotent: anything already present is left alone. Prints what it changed.

Usage: register_package.py --repo <repo> --module <m> --name "Inspection Method" --api-title "Inspection Method - Read"
                           --api-id API_INSPECTIONMETHOD_SRV [--keywords "Quality Inspection" ...]
                           [--description "The service allows to ..."] [--version 1.0.0]
"""
import argparse
import re
import sys
import textwrap
from pathlib import Path

changes = []


def note(msg):
    changes.append(msg)
    print("  +", msg)


def insert_after_last(text: str, pattern: str, new_line: str) -> str:
    matches = list(re.finditer(pattern, text, re.M))
    if not matches:
        raise ValueError(f"no line matches {pattern!r}")
    end = text.index("\n", matches[-1].end()) + 1 if "\n" in text[matches[-1].end():] else len(text)
    return text[:end] + new_line + "\n" + text[end:]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--module", required=True)
    ap.add_argument("--name", required=True, help="display name after 'SAP S/4HANA', e.g. 'Inspection Method'")
    ap.add_argument("--api-title", required=True, help="api.sap.com title, e.g. 'Inspection Method - Read'")
    ap.add_argument("--api-id", required=True)
    ap.add_argument("--keywords", nargs="*", default=[])
    ap.add_argument("--description", help="sentence starting 'The service allows to ...' for the root README list")
    ap.add_argument("--version", default="1.0.0")
    ap.add_argument("--gradle-title", help="override the label in build.gradle's description")
    args = ap.parse_args()

    repo = Path(args.repo).resolve()
    m = args.module
    settings = (repo / "settings.gradle").read_text()
    area_match = re.search(r"include ':([\w.-]+)-ballerina'", settings)
    if not area_match:
        sys.exit("settings.gradle has no `include ':<area>-ballerina'`; is this an S/4HANA area repo?")
    area = area_match.group(1)
    siblings = [s for s in re.findall(rf"include ':{area}-ballerina:(\w+)'", settings) if s != m]
    if not siblings:
        sys.exit("No sibling package to copy from. For a brand-new repo, see references/new-repo.md.")
    sib = siblings[0]
    pkg = repo / "ballerina" / m
    pkg.mkdir(parents=True, exist_ok=True)
    print(f"area={area}, copying the shape of sibling {sib}")

    # Ballerina.toml
    toml = pkg / "Ballerina.toml"
    if not toml.exists():
        tpl = (repo / "build-config/resources/Ballerina.toml").read_text()
        tpl_kw = re.search(r"^keywords = \[(.*)\]$", tpl, re.M)
        area_kw = re.findall(r'"([^"]+)"', tpl_kw.group(1)) if tpl_kw else []
        base = [f"Name/SAP S/4HANA {args.name}", "Type/Connector", "Vendor/SAP", "Area/ERP & Business Operations",
                "Business Management/ERP", "Cost/Paid", "S/4HANA"]
        kws = base + [k for k in area_kw + args.keywords if k not in base and "/" not in k]
        text = tpl.replace("@package.name@", f"sap.s4hana.{m}").replace("@toml.version@", args.version)
        text = re.sub(r"^keywords = \[.*\]$", "keywords = [" + ", ".join(f'"{k}"' for k in kws) + "]", text, flags=re.M)
        toml.write_text(text)
        note(f"ballerina/{m}/Ballerina.toml")

    # build.gradle
    bg = pkg / "build.gradle"
    if not bg.exists():
        text = (repo / "ballerina" / sib / "build.gradle").read_text()
        # Repos differ: delivery uses the short name ("Inbound Delivery"), qm/sales the api.sap.com
        # title ("Inspection Method - Read"). Follow the siblings: title only if one of them uses it.
        descs = [re.search(r"^description = '(.*)'$", (repo / "ballerina" / s / "build.gradle").read_text(), re.M)
                 for s in siblings if (repo / "ballerina" / s / "build.gradle").exists()]
        uses_title = any(d and " - " in d.group(1).removeprefix("Ballerina - ") for d in descs)
        label = args.gradle_title or (args.api_title if uses_title else args.name)
        text = re.sub(r"^description = '.*'$", f"description = 'Ballerina - SAP S/4HANA {label} API'", text, flags=re.M)
        text = text.replace(sib, m)
        bg.write_text(text)
        note(f"ballerina/{m}/build.gradle")

    # settings.gradle
    if f"include ':{area}-ballerina:{m}'" not in settings:
        settings = insert_after_last(settings, rf"^include ':{area}-ballerina:\w+'", f"include ':{area}-ballerina:{m}'")
        settings = insert_after_last(settings, rf"^project\(':{area}-ballerina:\w+'\)\.projectDir.*$",
                                     f"project(':{area}-ballerina:{m}').projectDir = file(\"ballerina/{m}\")")
        (repo / "settings.gradle").write_text(settings)
        note("settings.gradle")

    # gradle.properties
    props_path = repo / "gradle.properties"
    props = props_path.read_text()
    if not re.search(rf"^{m}Version=", props, re.M):
        alt = "|".join(re.escape(s) for s in siblings)
        props = insert_after_last(props, rf"^({alt})Version=.*$", f"{m}Version={args.version}-SNAPSHOT")
        props_path.write_text(props)
        note("gradle.properties")

    # ballerina/build.gradle
    bb_path = repo / "ballerina" / "build.gradle"
    bb = bb_path.read_text()
    # Most repos depend on each package's commitTomlFiles task; sales uses :build. Copy the siblings.
    task = re.search(rf"dependsOn\(':{area}-ballerina:\w+:(\w+)'\)", bb)
    dep = f"dependsOn(':{area}-ballerina:{m}:{task.group(1) if task else 'commitTomlFiles'}')"
    if task and f"':{area}-ballerina:{m}:" not in bb:
        bb = insert_after_last(bb, rf"^\s*dependsOn\(':{area}-ballerina:\w+:{task.group(1)}'\)", "    " + dep)
        bb_path.write_text(bb)
        note("ballerina/build.gradle")

    # workflow option lists
    for wf in sorted((repo / ".github" / "workflows").glob("*.yml")):
        text = wf.read_text()
        # [ \t] rather than \s: \s would also match the newline and the blank line that ends the list
        pat = rf"^([ \t]*)- ({'|'.join(re.escape(s) for s in siblings)})[ \t]*$"
        hits = list(re.finditer(pat, text, re.M))
        if hits and not re.search(rf"^[ \t]*- {m}[ \t]*$", text, re.M):
            indent = hits[-1].group(1)
            text = insert_after_last(text, pat, f"{indent}- {m}")
            wf.write_text(text)
            note(f".github/workflows/{wf.name}")

    # README build table + optional list entry
    readme_path = repo / "README.md"
    readme = readme_path.read_text()
    if f"| {m} " not in readme and f"|{m}|" not in readme.replace(" ", ""):
        row_pat = rf"^([ \t]*)\|[ \t]*({'|'.join(re.escape(s) for s in siblings)})[ \t]*\|.*$"
        rows = list(re.finditer(row_pat, readme, re.M))
        if rows:
            last = rows[-1].group(0)
            cells = last.split("|")
            w1, w2 = len(cells[1]), len(cells[2])
            row = f"{rows[-1].group(1)}| {m:<{w1 - 2}} | {'ballerinax/sap.s4hana.' + m:<{w2 - 2}} |"
            readme = insert_after_last(readme, row_pat, row)
            note("README.md build table row")
    if args.description and f"(ballerina/{m})" not in readme:
        items = list(re.finditer(r"^(\d+)\. \[SAP S/4HANA .*?\]\(ballerina/\w+\).*?(?=\n\n)", readme, re.M | re.S))
        if items:
            n = int(items[-1].group(1)) + 1
            body = textwrap.fill(args.description, width=120, initial_indent="   ", subsequent_indent="   ")
            entry = (f"\n\n{n}. [SAP S/4HANA {args.name}](ballerina/{m}) provides a way to interact with the\n"
                     f"   [{args.api_title} API](https://api.sap.com/api/{args.api_id}/overview).\n"
                     f"{body}")
            readme = readme[:items[-1].end()] + entry + readme[items[-1].end():]
            note("README.md package list entry")
        # Older repos (sales) write: N. The `ballerinax/sap.s4hana.<m>` package provides APIs that ...
        old = list(re.finditer(r"^(\d+)\. The `ballerinax/sap\.s4hana\.\w+` package.*?(?=\n\n|\Z)", readme, re.M | re.S))
        if not items and old and f"sap.s4hana.{m}`" not in readme:
            n = int(old[-1].group(1)) + 1
            text = (f"{n}. The `ballerinax/sap.s4hana.{m}` package provides APIs that enable seamless integration with "
                    f"the [{args.api_title} API v1.0.0](https://api.sap.com/api/{args.api_id}/overview). {args.description}")
            entry = "\n\n" + textwrap.fill(text, width=120, subsequent_indent=" " * (len(str(n)) + 2),
                                           break_long_words=False, break_on_hyphens=False)
            readme = readme[:old[-1].end()] + entry + readme[old[-1].end():]
            note("README.md package list entry (older 'The `ballerinax/...` package' style)")
        if not items and not old:
            print("  ! README package list not recognised; add the entry by hand in the siblings' style")
    readme_path.write_text(readme)

    cl = repo / "changelog.md"
    if cl.exists() and re.search(rf"\b{re.escape(m)}\b", cl.read_text()) and args.version == "1.0.0":
        print(f"  ! changelog.md already lists {m}: it was released before. Rerun with --version set to the"
              " siblings' version (gradle.properties) unless it really starts over at 1.0.0.")
    if not changes:
        print("nothing to change; already registered")
    return 0


if __name__ == "__main__":
    sys.exit(main())
