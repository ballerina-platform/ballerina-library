#!/usr/bin/env python3
"""
Verify the local GraalVM setup for a native-image build.

Checks:
  - GRAALVM_HOME is set and points at a directory
  - $GRAALVM_HOME/bin/java exists and reports a JDK major version
  - $GRAALVM_HOME/bin/native-image exists
  - the reported JDK major matches the required version (from
    derive_graalvm_requirements.py)
  - flags darwin-aarch64 (Apple Silicon), where native-image is experimental

Usage:
  check_graalvm_env.py --required-jdk 17

Output (stdout): JSON
  {graalvm_home, java_found, native_image_found, graalvm_jdk_actual,
   required_jdk, jdk_matches, is_arm64_mac, ok, warnings:[...]}
Exits 1 only when GRAALVM_HOME/java/native-image are missing (hard errors);
a JDK-version mismatch is reported as a warning, not a hard failure.
"""

import argparse
import json
import os
import platform
import re
import subprocess
import sys


def java_major(java_bin: str):
    try:
        result = subprocess.run([java_bin, "-version"], capture_output=True, text=True, timeout=30)
    except Exception:
        return None
    text = result.stderr or result.stdout or ""
    # e.g. 'openjdk version "17.0.9" 2023-10-17' or '"21.0.4"' or older '"11.0.20"'
    m = re.search(r'version "(\d+)(?:\.(\d+))?', text)
    if not m:
        return None
    major = int(m.group(1))
    # Legacy "1.8" style (not expected for GraalVM 11+, but be safe)
    if major == 1 and m.group(2):
        return int(m.group(2))
    return major


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--required-jdk", type=int, required=True)
    args = ap.parse_args()

    warnings = []
    hard_fail = False

    graalvm_home = os.environ.get("GRAALVM_HOME", "")
    home_ok = bool(graalvm_home) and os.path.isdir(graalvm_home)
    if not graalvm_home:
        warnings.append("GRAALVM_HOME is not set. Install GraalVM and set GRAALVM_HOME "
                        "(if using SDKMAN!, it can equal JAVA_HOME).")
        hard_fail = True
    elif not home_ok:
        warnings.append(f"GRAALVM_HOME points at a missing directory: {graalvm_home}")
        hard_fail = True

    exe = ".exe" if os.name == "nt" else ""
    java_bin = os.path.join(graalvm_home, "bin", f"java{exe}") if graalvm_home else ""
    ni_bin = os.path.join(graalvm_home, "bin", f"native-image{exe}") if graalvm_home else ""

    java_found = bool(java_bin) and os.path.isfile(java_bin)
    native_image_found = bool(ni_bin) and os.path.isfile(ni_bin)

    if home_ok and not java_found:
        warnings.append(f"java not found at {java_bin}")
        hard_fail = True
    if home_ok and not native_image_found:
        warnings.append("native-image not found in GRAALVM_HOME/bin. Install it with "
                        "`gu install native-image` (older distros) or use a distribution "
                        "that bundles it (e.g. graalce via SDKMAN!).")
        hard_fail = True

    actual = java_major(java_bin) if java_found else None
    jdk_matches = actual == args.required_jdk
    if actual is not None and not jdk_matches:
        warnings.append(f"GraalVM JDK {actual} does not match the JDK {args.required_jdk} "
                        f"required by this Ballerina distribution. Builds may fail or behave "
                        f"unexpectedly; install the matching GraalVM JDK.")

    is_arm64_mac = platform.system() == "Darwin" and platform.machine() in ("arm64", "aarch64")
    if is_arm64_mac:
        warnings.append("Running on macOS ARM64 (darwin-aarch64): GraalVM native-image support "
                        "is experimental here. Native build/test failures may reflect the "
                        "platform rather than the library.")

    result = {
        "graalvm_home": graalvm_home,
        "java_found": java_found,
        "native_image_found": native_image_found,
        "graalvm_jdk_actual": actual,
        "required_jdk": args.required_jdk,
        "jdk_matches": jdk_matches,
        "is_arm64_mac": is_arm64_mac,
        "ok": not hard_fail,
        "warnings": warnings,
    }
    print(json.dumps(result, indent=2))
    sys.exit(0 if not hard_fail else 1)


if __name__ == "__main__":
    main()
