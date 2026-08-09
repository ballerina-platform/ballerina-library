#!/usr/bin/env python3
"""Append verified examples from cached Ballerina Central metadata to a guide."""

from __future__ import annotations

import argparse
import json
import posixpath
import re
import sys
from pathlib import Path
from typing import Optional

SECTION_HEADING = "## More code examples"
# Optional quoted title per CommonMark, e.g. [label](../path.md "title").
_MD_LINK_RE = re.compile(r'(?<!!)\[([^\]]+)\]\((\S+?)(\s+"[^"]*")?\)')
_FENCE_RE = re.compile(r"^```.*?^```", re.M | re.S)


def _is_relative_link(url: str) -> bool:
    return not re.match(r"^(?:[a-zA-Z][a-zA-Z0-9+.\-]*:|#|/)", url)


def rewrite_relative_links(text: str, github_repo: str) -> str:
    """Rewrite README-relative links to absolute GitHub blob URLs.

    The extracted "Examples" section is copied verbatim from a package's README as
    cached on Ballerina Central — that README lives at `ballerina/README.md` in the
    connector's own repo, so a relative link like `../examples/x.md` only resolves
    from there. Copied verbatim into an unrelated site (e.g. docs-integrator), the
    same relative path silently 404s. Rewrite every relative link against that fixed
    known base instead of leaving it to resolve against whatever page it lands on.

    Fenced code blocks are left untouched — sample Ballerina source inside them can
    coincidentally contain bracket/paren sequences that look like Markdown links, and
    rewriting those would corrupt the sample rather than fix a link.
    """

    def _replace(match: re.Match) -> str:
        label, url, title = match.group(1), match.group(2), match.group(3) or ""
        if not _is_relative_link(url):
            return match.group(0)
        resolved = posixpath.normpath(posixpath.join("ballerina", url))
        return f"[{label}](https://github.com/ballerina-platform/{github_repo}/blob/main/{resolved}{title})"

    # split()/findall() on a group-less pattern separate fenced blocks from the prose
    # around them; only the prose parts are ever passed through the link rewrite.
    parts = _FENCE_RE.split(text)
    fences = _FENCE_RE.findall(text)
    rewritten_parts = [_MD_LINK_RE.sub(_replace, part) for part in parts]
    result = [rewritten_parts[0]]
    for fence, part in zip(fences, rewritten_parts[1:]):
        result.append(fence)
        result.append(part)
    return "".join(result)


def extract_examples(readme: str) -> Optional[str]:
    lines = readme.splitlines()
    start = None
    heading_level = 0
    for index, line in enumerate(lines):
        match = re.match(r"^(#{1,6})\s+examples?\s*$", line.strip(), re.I)
        if match:
            start = index + 1
            heading_level = len(match.group(1))
            break
    if start is None:
        return None

    body: list[str] = []
    for line in lines[start:]:
        heading = re.match(r"^(#{1,6})\s+", line)
        if heading and len(heading.group(1)) <= heading_level:
            break
        body.append(line)
    value = "\n".join(body).strip()
    return value or None


def github_repo_from_metadata(metadata: dict) -> Optional[str]:
    """Derive `module-<org>-<package>` from a package's own Central metadata.

    Uses the package's actual `organization` field rather than assuming
    `ballerinax` — stdlib packages (org `ballerina`) and any other org otherwise
    get a repository name that doesn't exist, silently pointing every rewritten
    link at the wrong GitHub repo.
    """
    package_name = metadata.get("name")
    if not package_name:
        return None
    organization = metadata.get("organization") or "ballerinax"
    return f"module-{organization}-{package_name}"


def examples_from_metadata(metadata_path: Path) -> Optional[str]:
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    readme = metadata.get("readme")
    if readme is None:
        return None
    if not isinstance(readme, str):
        raise ValueError("Ballerina Central metadata field 'readme' must be a string")
    examples = extract_examples(readme)
    if examples is None:
        return None
    github_repo = github_repo_from_metadata(metadata)
    if github_repo is None:
        return examples
    return rewrite_relative_links(examples, github_repo)


def append_central_examples(doc_path: Path, metadata_path: Path) -> tuple[bool, bool]:
    if not doc_path.is_file():
        raise FileNotFoundError(f"Missing guide: {doc_path}")
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    examples = examples_from_metadata(metadata_path)
    text = doc_path.read_text(encoding="utf-8")
    matches = list(re.finditer(r"^## More code examples\n\n(?P<body>.*?)(?=^## |\Z)", text, re.M | re.S))
    if len(matches) > 1:
        raise ValueError("Guide contains duplicate More code examples sections")
    if matches:
        if examples is None:
            raise ValueError("Guide contains More code examples but Central metadata has no examples")
        actual = matches[0].group("body").strip()
        if actual != examples:
            # A guide written by a version of this script that predates the relative-link
            # rewrite (or the standalone/no-name skip path) still has the raw README links.
            # Normalize before concluding the Central content itself has actually drifted.
            github_repo = github_repo_from_metadata(metadata)
            normalized_actual = rewrite_relative_links(actual, github_repo) if github_repo else actual
            if normalized_actual != examples:
                raise ValueError("Existing More code examples content does not match Ballerina Central")
        return True, False
    if examples is None:
        return False, False
    doc_path.write_text(f"{text.rstrip()}\n\n{SECTION_HEADING}\n\n{examples}\n", encoding="utf-8")
    return True, True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--context", required=True, type=Path)
    args = parser.parse_args()
    try:
        context = json.loads(args.context.read_text(encoding="utf-8"))
        found, added = append_central_examples(
            Path(context["doc_path"]), Path(context["metadata_path"])
        )
    except (OSError, ValueError, json.JSONDecodeError, KeyError) as exc:
        print(f"[ERROR] Could not append Central examples: {exc}", file=sys.stderr)
        return 1
    print(json.dumps({"examples_found": found, "examples_added": added}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
