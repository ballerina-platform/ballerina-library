#!/usr/bin/env python3
"""
Classify the output of a failed (or warning-emitting) `bal build --graalvm` /
`bal test --graalvm` run into actionable categories.

Reads from a file path argument or stdin (the path is printed by
run_bal_command.py as ">>> output saved to: <path>").

Output (stdout): JSON
  {
    "not_verified_warning": bool,        # "Package is not verified with GraalVM"
    "class_init": [ "<class>", ... ],    # class-initialization errors -> class-init fix loop
    "missing_metadata": [ {"kind": "reflection|jni|resource|proxy|serialization",
                            "symbol": "<detail>"}, ... ],   # runtime -> tracing agent / repo
    "out_of_memory": bool,               # builder OOM -> raise -J-Xmx
    "other": [ "<line>", ... ]           # unclassified error lines, for the agent to read
  }

Category routing mirrors references/troubleshooting.md and
references/reachability-metadata.md.
"""

import json
import re
import sys

NOT_VERIFIED_RE = re.compile(r"Package is not verified with GraalVM", re.IGNORECASE)

# Class initialization: names appear in a few shapes across GraalVM versions, e.g.
#   "Classes that should be initialized at run time got initialized during image building:"
#   "com.example.Foo the class was requested to be initialized at build time"
#   "--initialize-at-run-time=..."
CLASS_INIT_LINE_RE = re.compile(
    r"class initialization"
    r"|initializ\w*\s+(?:at\s+(?:run|build)\s+time|during image building)"
    r"|requested to be initialized"
    r"|--initialize-at-",
    re.IGNORECASE,
)
CLASS_NAME_RE = re.compile(r"\b([a-zA-Z_][\w]*(?:\.[a-zA-Z_][\w]*)*\.[A-Z]\w+)\b")

OOM_RE = re.compile(r"OutOfMemoryError|Java heap space|GC overhead limit", re.IGNORECASE)

MISSING_PATTERNS = [
    ("reflection", re.compile(r"MissingReflectionRegistrationError|No instances of .* are allowed|"
                              r"ClassNotFoundException|NoSuchMethodException|NoSuchFieldException|"
                              r"reflectively", re.IGNORECASE)),
    ("jni", re.compile(r"MissingJNIRegistrationError|JNI", re.IGNORECASE)),
    ("resource", re.compile(r"MissingResourceException|resource.*not.*found|"
                            r"getResourceAsStream returned null", re.IGNORECASE)),
    ("proxy", re.compile(r"proxy|Proxy class", re.IGNORECASE)),
    ("serialization", re.compile(r"NotSerializableException|serialization|SerializationError",
                                 re.IGNORECASE)),
]

ERROR_LINE_RE = re.compile(r"error|exception|fatal|caused by", re.IGNORECASE)


def classify(text: str) -> dict:
    lines = text.splitlines()

    not_verified = bool(NOT_VERIFIED_RE.search(text))
    out_of_memory = bool(OOM_RE.search(text))

    class_init = []
    missing = []
    other = []
    seen_missing = set()

    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue

        matched = False

        if CLASS_INIT_LINE_RE.search(stripped):
            # Skip generic SVM/JDK exception types; keep app/library class names.
            for cls in CLASS_NAME_RE.findall(stripped):
                if cls.startswith(("com.oracle.svm.", "java.", "jdk.")):
                    continue
                if cls not in class_init:
                    class_init.append(cls)
            matched = True

        for kind, pat in MISSING_PATTERNS:
            if pat.search(stripped):
                # The accessed type is usually the LAST fully-qualified name on the
                # line (e.g. "tried to reflectively access <type>"); the first is
                # often the exception class. Fall back to the whole line.
                names = CLASS_NAME_RE.findall(stripped)
                symbol = names[-1] if names else stripped[:200]
                key = (kind, symbol)
                if key not in seen_missing:
                    seen_missing.add(key)
                    missing.append({"kind": kind, "symbol": symbol})
                matched = True
                break

        if not matched and ERROR_LINE_RE.search(stripped) and not NOT_VERIFIED_RE.search(stripped):
            other.append(stripped[:300])

    # Dedup + cap `other` so it stays readable.
    deduped_other = []
    for o in other:
        if o not in deduped_other:
            deduped_other.append(o)

    return {
        "not_verified_warning": not_verified,
        "class_init": class_init,
        "missing_metadata": missing,
        "out_of_memory": out_of_memory,
        "other": deduped_other[:40],
    }


if __name__ == "__main__":
    if len(sys.argv) == 2:
        with open(sys.argv[1], "r", encoding="utf-8", errors="replace") as f:
            text = f.read()
    else:
        text = sys.stdin.read()
    print(json.dumps(classify(text), indent=2))
