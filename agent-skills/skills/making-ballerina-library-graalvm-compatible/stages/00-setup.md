# Stage 00 — Setup

Verify the environment, locate the library package, derive GraalVM requirements
from the Ballerina distribution, and establish all Shared State. This stage always
runs and cannot be skipped.

---

## Step 0: Python command

Determine which Python 3 command works — try each in order via Bash (plain
commands, cross-platform):

```
python3 --version
python --version
py --version
```

Use the first whose output starts with `Python 3`. Store as `<PYTHON_CMD>`; use it
for every script invocation here and in later stages.

Then check the base environment:

```bash
<PYTHON_CMD> <skill-root>/scripts/check_environment.py
```

If it exits non-zero, show the errors and stop.

---

## Step 1: Locate the Ballerina package

Search downstream from CWD for `Ballerina.toml` (ballerina-library modules keep
the package under a `ballerina/` subdirectory):

```bash
<PYTHON_CMD> <skill-root>/scripts/find_ballerina_toml.py
```

"2+1" prompt from the results:
- Exactly one directory found → offer it (recommended), `./`, or a custom path.
- None found → ask the user for the package path (this skill operates on an
  existing library; it does not scaffold one).
- More than one → list up to two as options plus a custom path.

Store as `BALLERINA_DIR`, and `BALLERINA_TOML = <BALLERINA_DIR>/Ballerina.toml`.

---

## Step 2: Read package coordinates

```bash
<PYTHON_CMD> <skill-root>/scripts/detect_package_coordinates.py "<BALLERINA_TOML>"
```

From the JSON, store: `BAL_ORG`, `BAL_PACKAGE` (org/name), `BAL_DISTRIBUTION`
(the `distribution` field), `GROUP_ID`, `ARTIFACT_ID`, `HAS_NATIVE_MODULE`
(`has_native_dir`), `NATIVE_DIR`, `META_INF_DIR`, `THIRD_PARTY_DEPS`
(`java_dependencies`), and `GRAALVM_COMPATIBLE_ALREADY` (whether any platform
block already sets `graalvmCompatible = true`).

---

## Step 3: Derive GraalVM requirements

```bash
<PYTHON_CMD> <skill-root>/scripts/derive_graalvm_requirements.py --distribution "<BAL_DISTRIBUTION>"
```

If `BAL_DISTRIBUTION` is empty, omit `--distribution` so the script reads
`bal version`. Store `BAL_UPDATE` (`update`), `REQUIRED_GRAALVM_JDK`, and
`PLATFORM_JAVA_VERSION`. If `assumed` is true (update newer than the guide covers),
note that JDK 21 is a best-effort default to confirm.

---

## Step 4: Verify the GraalVM installation

```bash
<PYTHON_CMD> <skill-root>/scripts/check_graalvm_env.py --required-jdk <REQUIRED_GRAALVM_JDK>
```

Store `GRAALVM_HOME`, `GRAALVM_JDK_ACTUAL`, `GRAALVM_OK` (`ok`), and `IS_ARM64_MAC`.
Print each warning from the `warnings` array. In particular:
- If GRAALVM_HOME/java/native-image are missing (`ok: false`) → stop; the user must
  install GraalVM and set `GRAALVM_HOME` (see the guide's "Configure GraalVM locally").
- JDK mismatch → warn but continue.
- `IS_ARM64_MAC` → surface the experimental-native-image caveat so later failures
  aren't mistaken for library bugs.

---

## Step 5: Detect runnable artifacts

```bash
<PYTHON_CMD> <skill-root>/scripts/detect_runnable_artifacts.py "<BALLERINA_DIR>"
```

Store `HAS_MAIN`, `HAS_SERVICE`, `HAS_TESTS`, `JAR_NAME`. These decide which
tracing stages are reachable (03 needs main/service; 04 needs tests).

---

## Step 6: Tracing config directory and interactive mode

Ask (2+1, default `config-dir`):
> Where should the tracing agent write collected configs? (default: `config-dir`)

Store as `CONFIG_DIR`.

> Run in interactive mode (pause after each stage)? [y/N]

Store as `INTERACTIVE_MODE` (default false).

---

## Step 7: Confirm and proceed

Print:

```
=== Configuration Summary ===
Package:        <BAL_ORG>/<BAL_PACKAGE>
Ballerina dir:  <BALLERINA_DIR>
Distribution:   <BAL_DISTRIBUTION>  (Update <BAL_UPDATE>)
Required JDK:   GraalVM JDK <REQUIRED_GRAALVM_JDK>  → [platform.<PLATFORM_JAVA_VERSION>]
GraalVM:        <GRAALVM_HOME>  (JDK <GRAALVM_JDK_ACTUAL>, <ok/mismatch>)
Coordinates:    <GROUP_ID>/<ARTIFACT_ID>   native module: <yes/no>
Java deps:      <count>
Runnable:       main <yes/no>  service <yes/no>  tests <yes/no>
Config dir:     <CONFIG_DIR>
ARM64 macOS:    <yes (experimental) / no>
Already marked: <yes/no>
Interactive:    <yes/no>
```

Ask: "Proceed? [Y/n]" — if no, adjust the answers above.

Then continue to `stages/01-build-and-test.md`.
