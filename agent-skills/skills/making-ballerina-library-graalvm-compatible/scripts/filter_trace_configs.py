#!/usr/bin/env python3
"""
Filter tracing-agent output down to the entries that belong to the library (and
its third-party dependencies), dropping JDK/GraalVM/Ballerina-runtime noise.

Handles BOTH config formats:
  - unified   reachability-metadata.json  (top-level "reflection"/"jni"/"resources"/
                                            "bundles"/"serialization" keys)
  - legacy    reflect-config.json, jni-config.json, proxy-config.json,
              serialization-config.json, resource-config.json

Class-keyed entries (reflection/jni/serialization/proxy) are filtered by
fully-qualified type name:
  - with --keep-prefixes: whitelist — keep only names starting with a listed prefix
  - without:              blacklist — drop names under known-noise prefixes
                          (java., javax., jdk., sun., com.sun., org.graalvm.,
                           io.ballerina., org.ballerinalang.)
Resource/bundle entries are NOT auto-dropped (they are glob patterns, not class
names); they pass through and are surfaced in the report for the agent to review.

Usage:
  filter_trace_configs.py --config-dir config-dir --out filtered-dir
                          [--keep-prefixes com.example.,org.foo.]

Output (stdout): JSON report {files:[...], kept, dropped, resources_passthrough, notes}
"""

import argparse
import json
import os
import sys

NOISE_PREFIXES = (
    "java.", "javax.", "jdk.", "sun.", "com.sun.", "org.graalvm.",
    "io.ballerina.", "org.ballerinalang.",
)


def name_of(entry):
    if isinstance(entry, dict):
        return entry.get("type") or entry.get("name") or ""
    return ""


def keep_name(name: str, keep_prefixes) -> bool:
    if not name:
        return False
    if keep_prefixes:
        return any(name.startswith(p) for p in keep_prefixes)
    return not any(name.startswith(p) for p in NOISE_PREFIXES)


def filter_class_list(entries, keep_prefixes, kept_counter, dropped_counter, kind):
    out = []
    for e in entries:
        # Proxy entries have no single type name — keep by interface membership.
        # Legacy proxy-config.json shape: {"interfaces": [...]}.
        # Unified reachability-metadata.json shape (nested inside "reflection"):
        #   {"type": {"proxy": [...]}}.
        ifaces = None
        if isinstance(e, dict) and "interfaces" in e:
            ifaces = e.get("interfaces", [])
        elif isinstance(e, dict) and isinstance(e.get("type"), dict) and "proxy" in e["type"]:
            ifaces = e["type"].get("proxy", [])
        if ifaces is not None:
            if any(keep_name(i, keep_prefixes) for i in ifaces):
                out.append(e)
                kept_counter[kind] = kept_counter.get(kind, 0) + 1
            else:
                dropped_counter[kind] = dropped_counter.get(kind, 0) + 1
            continue
        n = name_of(e)
        if keep_name(n, keep_prefixes):
            out.append(e)
            kept_counter[kind] = kept_counter.get(kind, 0) + 1
        else:
            dropped_counter[kind] = dropped_counter.get(kind, 0) + 1
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--config-dir", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--keep-prefixes", default="",
                    help="Comma-separated FQ name prefixes to keep (whitelist mode)")
    args = ap.parse_args()

    if not os.path.isdir(args.config_dir):
        print(f"ERROR: config dir not found: {args.config_dir}", file=sys.stderr)
        sys.exit(1)

    keep_prefixes = [p.strip() for p in args.keep_prefixes.split(",") if p.strip()]
    os.makedirs(args.out, exist_ok=True)

    kept = {}
    dropped = {}
    resources_passthrough = 0
    files_written = []
    notes = []

    for fname in sorted(os.listdir(args.config_dir)):
        if not fname.endswith(".json"):
            continue
        src = os.path.join(args.config_dir, fname)
        try:
            with open(src, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception as e:
            notes.append(f"skipped {fname}: {e}")
            continue

        if fname == "reachability-metadata.json" and isinstance(data, dict):
            out_data = {}
            for key, val in data.items():
                if key in ("reflection", "jni", "serialization") and isinstance(val, list):
                    out_data[key] = filter_class_list(val, keep_prefixes, kept, dropped, key)
                elif key in ("resources", "bundles"):
                    out_data[key] = val
                    if isinstance(val, list):
                        resources_passthrough += len(val)
                    elif isinstance(val, dict):
                        resources_passthrough += len(val.get("includes", []) or [])
                else:
                    out_data[key] = val
            result = out_data
        elif fname in ("reflect-config.json", "jni-config.json", "serialization-config.json",
                       "proxy-config.json") and isinstance(data, list):
            kind = fname.replace("-config.json", "")
            result = filter_class_list(data, keep_prefixes, kept, dropped, kind)
        elif fname == "resource-config.json":
            result = data
            if isinstance(data, dict):
                res = data.get("resources", {})
                if isinstance(res, dict):
                    resources_passthrough += len(res.get("includes", []) or [])
                elif isinstance(res, list):
                    resources_passthrough += len(res)
            notes.append("resource-config.json passed through unfiltered — review globs manually")
        else:
            result = data
            notes.append(f"{fname}: unrecognized shape, passed through unfiltered")

        dest = os.path.join(args.out, fname)
        with open(dest, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2)
        files_written.append(fname)

    report = {
        "files": files_written,
        "kept": kept,
        "dropped": dropped,
        "resources_passthrough": resources_passthrough,
        "mode": "whitelist" if keep_prefixes else "blacklist(noise-prefixes)",
        "keep_prefixes": keep_prefixes,
        "notes": notes,
    }
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
