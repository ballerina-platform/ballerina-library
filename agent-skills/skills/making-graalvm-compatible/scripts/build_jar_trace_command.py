#!/usr/bin/env python3
"""
Emit the exact `java` command that runs the application uber-JAR under the GraalVM
native-image tracing agent, to collect dynamic-feature metadata.

Must use the `java` bundled with the GraalVM distribution ($GRAALVM_HOME/bin/java).
Resolves GRAALVM_HOME from the current environment into a literal path (rather
than emitting `$GRAALVM_HOME` shell syntax), so the printed command runs the
same under bash/zsh and under Windows shells (cmd.exe, PowerShell) that don't
expand `$VAR`.

Usage:
  build_jar_trace_command.py --jar sample.jar [--config-output-dir config-dir]
                             [--jar-dir target/bin] [--app-args "..."]

Output (stdout): the ready-to-run command string.
"""

import argparse
import os


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--jar", required=True, help="JAR file name, e.g. sample.jar")
    ap.add_argument("--jar-dir", default="target/bin", help="Directory holding the JAR (default: target/bin)")
    ap.add_argument("--config-output-dir", default="config-dir",
                    help="Tracing agent output directory (default: config-dir)")
    ap.add_argument("--app-args", default="", help="Arguments to pass to the application")
    args = ap.parse_args()

    graalvm_home = os.environ.get("GRAALVM_HOME", "$GRAALVM_HOME")
    java_bin = os.path.join(graalvm_home, "bin", "java.exe" if os.name == "nt" else "java")
    jar_path = os.path.join(args.jar_dir, args.jar)
    parts = [
        f'"{java_bin}"',
        f'-agentlib:native-image-agent=config-output-dir="{args.config_output_dir}"',
        "-jar",
        f'"{jar_path}"',
    ]
    command = " ".join(parts)
    if args.app_args:
        command += " " + args.app_args
    print(command)


if __name__ == "__main__":
    main()
