#!/usr/bin/env python3
"""
Emit the exact `java` command that runs the application uber-JAR under the GraalVM
native-image tracing agent, to collect dynamic-feature metadata.

Must use the `java` bundled with the GraalVM distribution ($GRAALVM_HOME/bin/java).

Usage:
  build_jar_trace_command.py --jar sample.jar [--config-output-dir config-dir]
                             [--jar-dir target/bin] [--app-args "..."]

Output (stdout): the ready-to-run command string.
"""

import argparse


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--jar", required=True, help="JAR file name, e.g. sample.jar")
    ap.add_argument("--jar-dir", default="target/bin", help="Directory holding the JAR (default: target/bin)")
    ap.add_argument("--config-output-dir", default="config-dir",
                    help="Tracing agent output directory (default: config-dir)")
    ap.add_argument("--app-args", default="", help="Arguments to pass to the application")
    args = ap.parse_args()

    jar_path = f"{args.jar_dir.rstrip('/')}/{args.jar}"
    parts = [
        '"$GRAALVM_HOME/bin/java"',
        f"-agentlib:native-image-agent=config-output-dir={args.config_output_dir}",
        "-jar",
        jar_path,
    ]
    command = " ".join(parts)
    if args.app_args:
        command += " " + args.app_args
    print(command)


if __name__ == "__main__":
    main()
