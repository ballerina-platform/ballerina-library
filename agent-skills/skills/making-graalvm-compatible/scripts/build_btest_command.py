#!/usr/bin/env python3
"""
Emit the exact, version-aware `java` command that runs the Ballerina test suite
under the GraalVM native-image tracing agent (via `org.ballerinalang.test.runtime.BTestMain`).

This is the load-bearing, version-sensitive piece of the skill. The BTestMain
argument signature CHANGED at Ballerina Update 10 (2201.10.x): from that update
onwards two leading args (`false "target/cache/tests_cache/test_suit.json"`) and
more trailing boolean flags are required. Passing the wrong signature does not
error — it silently produces incomplete/incorrect metadata. So this script is the
single source of truth for the command, echoes the branch it selected, and defaults
unknown/future updates to the >=10 signature (with a warning).

Usage:
  build_btest_command.py (--distribution 2201.10.3 | --update 10)
                         --config-output-dir <dir>
                         --classpath-file <class-path.txt>
                         [--target target]

Output (stdout): the ready-to-run command string. GRAALVM_HOME is resolved from
the current environment into a literal path (rather than emitting `$GRAALVM_HOME`
shell syntax), so the printed command runs the same under bash/zsh and under
Windows shells (cmd.exe, PowerShell) that don't expand `$VAR`.
Also prints the resolved update/branch to stderr for transparency.
"""

import argparse
import os
import re
import sys

MAIN_CLASS = "org.ballerinalang.test.runtime.BTestMain"

# Trailing argument signatures after the main class, per the Ballerina GraalVM
# compatibility guide. `{target}` is substituted with the target directory.
#   Update >= 10 (2201.10.x and higher)
ARGS_GE_10 = [
    "false",
    '"target/cache/tests_cache/test_suit.json"',
    '"{target}"',
    '""',
    "true",
    "false",
    '""',
    '""',
    '""',
    "false",
    "false",
    "false",
    "false",
]
#   Update <= 9 (2201.9.x and lower)
ARGS_LT_10 = [
    '"{target}"',
    '""',
    "true",
    "false",
    '""',
    '""',
    '""',
    "false",
    "false",
]


def parse_update(distribution: str) -> int:
    """Extract the update number from a distribution string like 2201.10.3 -> 10."""
    m = re.match(r"\s*(\d+)\.(\d+)(?:\.(\d+))?", distribution.strip())
    if not m:
        raise ValueError(f"Cannot parse update number from distribution: {distribution!r}")
    return int(m.group(2))


def build_command(update: int, config_dir: str, classpath_file: str, target: str) -> str:
    if update >= 10:
        trailing = ARGS_GE_10
    else:
        trailing = ARGS_LT_10
    trailing = [a.replace("{target}", target) for a in trailing]

    graalvm_home = os.environ.get("GRAALVM_HOME", "$GRAALVM_HOME")
    java_bin = os.path.join(graalvm_home, "bin", "java.exe" if os.name == "nt" else "java")
    parts = [
        f'"{java_bin}"',
        f'-agentlib:native-image-agent=config-output-dir="{config_dir}"',
        "-cp",
        f'"@{classpath_file}"',
        f'"{MAIN_CLASS}"',
        *trailing,
    ]
    return " ".join(parts)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    group = ap.add_mutually_exclusive_group(required=True)
    group.add_argument("--distribution", help="Ballerina distribution, e.g. 2201.10.3")
    group.add_argument("--update", type=int, help="Ballerina update number, e.g. 10")
    ap.add_argument("--config-output-dir", default="config-dir",
                    help="Directory for the tracing agent output (default: config-dir)")
    ap.add_argument("--classpath-file", default="class-path.txt",
                    help="File containing the classpath (default: class-path.txt)")
    ap.add_argument("--target", default="target",
                    help="Ballerina target directory (default: target)")
    args = ap.parse_args()

    if args.update is not None:
        update = args.update
    else:
        try:
            update = parse_update(args.distribution)
        except ValueError as e:
            print(f"ERROR: {e}", file=sys.stderr)
            sys.exit(1)

    branch = ">=10 (2201.10.x or higher)" if update >= 10 else "<10 (2201.9.x or lower)"
    print(f">>> Resolved Ballerina update: {update}  ->  BTestMain signature: {branch}",
          file=sys.stderr)
    if update > 10:
        print(">>> Note: update > 10 assumes the >=10 signature is still current. "
              "Verify against the installed distribution if the trace looks incomplete.",
              file=sys.stderr)

    command = build_command(update, args.config_output_dir, args.classpath_file, args.target)
    print(command)


if __name__ == "__main__":
    main()
