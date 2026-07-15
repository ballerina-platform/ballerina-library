---
name: making-ballerina-library-graalvm-compatible
description: Makes a Ballerina library GraalVM-compatible by running the native build/test workflow, sourcing reachability metadata, and marking the package compatible. Use when the user wants to make a Ballerina library or package GraalVM compatible; build or test a Ballerina package with `bal build --graalvm` / `bal test --graalvm`; fix GraalVM native-image class-initialization or reflection/JNI/resource errors in a Ballerina project; run the GraalVM tracing agent for Ballerina tests or a service; pack native-image reachability metadata into META-INF for a Ballerina module; resolve the "Package is not verified with GraalVM" warning; or set graalvmCompatible = true in Ballerina.toml.
---

# Making a Ballerina Library GraalVM Compatible

An AI-assisted workflow for taking a Ballerina library to a verified, warning-free
`bal build --graalvm` / `bal test --graalvm`. It builds and tests natively,
resolves build-time class-initialization errors, sources native-image metadata
(preferring the vetted `oracle/graalvm-reachability-metadata` repo over the tracing
agent), packs the required config under `META-INF/native-image/`, and marks the
package compatible in `Ballerina.toml`.

Based on `docs/graalvm-compatibility-in-ballerina-libraries.md`, with GraalVM
reference material adapted from the Oracle GraalVM community skills.

---

## How This Skill Works

Unlike a linear pipeline, this is a **decision tree with loops** driven by what the
baseline build/test reveals:

```
Setup → Build & Test ─┬─ (build-time class-init errors) → fix loop → re-build
                      ├─ (all green) ──────────────────────────────► Mark
                      └─ (runtime/metadata gaps) → Reachability repo
                                                 → Trace JAR / Trace tests
                                                 → Filter & pack → Mark
```

Each stage is a file under `stages/`. **Load only the active stage's file** into
context — do not preload all stages. Routing between stages follows
`references/workflow.md`.

Scripts in `scripts/` handle all deterministic operations (version derivation,
classpath extraction, the version-sensitive `BTestMain` command, config
filtering/packing, `Ballerina.toml` edits). Run them via Bash — do not reimplement
their logic inline. LLM reasoning is reserved for judgment: class-init strategy,
exercising a running service, choosing which configs to keep, dependency upgrades.

---

## Quick Reference

| Stage | File | Skip when | Key output |
|-------|------|-----------|------------|
| 0. Setup | `stages/00-setup.md` | never | Shared State, GraalVM/JDK check |
| 1. Build & Test | `stages/01-build-and-test.md` | never | baseline status + class-init fix loop |
| 2. Reachability repo | `stages/02-reachability-repo.md` | no third-party Java deps | repo-sourced metadata (preferred) |
| 3. Trace JAR | `stages/03-trace-jar.md` | no main/service, or repo covered all | traced configs (service exercised) |
| 4. Trace tests | `stages/04-trace-tests.md` | no tests, or tests pass | traced configs (version-aware BTestMain) |
| 5. Filter & pack | `stages/05-filter-and-pack.md` | nothing to pack | `META-INF/native-image/<g>/<a>/` |
| 6. Mark compatible | `stages/06-mark-compatible.md` | never | `graalvmCompatible = true` + final verify |

---

## Entry Point Instructions

When this skill is invoked:

1. Print the welcome banner:
   ```
   ╔════════════════════════════════════════════════════╗
   ║   Ballerina Library — GraalVM Compatibility Helper   ║
   ╚════════════════════════════════════════════════════╝

   I'll take your Ballerina library to a verified `bal build --graalvm`
   and `bal test --graalvm`: build/test → resolve errors → source metadata
   → pack it → mark the package compatible.
   ```

2. Read and follow `stages/00-setup.md` to establish all Shared State. Do this
   before loading any other stage file.

3. Run `stages/01-build-and-test.md`, then route to the remaining stages per the
   classification in `references/workflow.md`. Skip stages per the table above.

4. When any native build fails at build time with a class-initialization error,
   read `references/class-init-fix-procedure.md` and invoke it inline before
   proceeding.

5. If `INTERACTIVE_MODE`, pause and confirm after each stage.

---

## Shared State

Set in Setup (stage 00) and used by later stages:

| Variable | Description |
|----------|-------------|
| `PYTHON_CMD` | Resolved Python 3 command (`python3`/`python`/`py`) |
| `BALLERINA_DIR` | Directory containing `Ballerina.toml` |
| `BALLERINA_TOML` | Absolute path to that `Ballerina.toml` |
| `BAL_ORG` / `BAL_PACKAGE` | Package org / name |
| `BAL_DISTRIBUTION` | e.g. `2201.10.3` |
| `BAL_UPDATE` | Update number (drives the `BTestMain` signature) |
| `REQUIRED_GRAALVM_JDK` | `11` / `17` / `21` |
| `PLATFORM_JAVA_VERSION` | `java11` / `java17` / `java21` — the Ballerina.toml platform block |
| `GRAALVM_HOME` / `GRAALVM_JDK_ACTUAL` / `GRAALVM_OK` | GraalVM install + detected JDK + match |
| `IS_ARM64_MAC` | Apple Silicon flag (experimental native-image warning) |
| `GROUP_ID` / `ARTIFACT_ID` | Native-image metadata coordinates |
| `HAS_NATIVE_MODULE` / `NATIVE_DIR` / `META_INF_DIR` | Native module presence + paths |
| `HAS_MAIN` / `HAS_SERVICE` / `HAS_TESTS` / `JAR_NAME` | Routing flags for tracing |
| `THIRD_PARTY_DEPS` | `[[platform.javaXX.dependency]]` entries `{groupId,artifactId,version,path}` |
| `REACHABILITY_REPO_HITS` | Deps with published metadata + their staging dirs |
| `CONFIG_DIR` | Tracing-agent output directory (default `config-dir`) |
| `CLASSPATH_FILE` | `class-path.txt` produced in Stage 04 |
| `KEEP_PACKAGE_PREFIXES` | Prefixes kept during filtering (Stage 05) |
| `BUILD_STATUS` / `TEST_STATUS` / `NOT_VERIFIED_WARNING` | Baseline results (Stage 01) |
| `GRAALVM_COMPATIBLE_ALREADY` | Whether the toml already declares it |
| `INTERACTIVE_MODE` | Pause after each stage |

---

## Core Principles

**Repo before tracing**: prefer `oracle/graalvm-reachability-metadata` (vetted,
deterministic) over the tracing agent; trace only for the gaps it doesn't cover.

**Version sensitivity is load-bearing**: the `BTestMain` argument signature changes
at Ballerina Update 10. `scripts/build_btest_command.py` is the single source of
truth — show its resolved branch and confirm before running.

**Deterministic first**: use scripts for anything mechanical. Use the LLM only for
judgment — class-init strategy, exercising services, choosing configs, upgrades.

**Never claim false compatibility**: do not set `graalvmCompatible = true` unless
the final native build and tests pass with no not-verified warning.

**Transparency**: print a status line before each sub-step. Use `✓`/`⚠`/`✗`.

---

## Reference Files

- `references/workflow.md` — decision tree, stage routing, guardrails, run summary
- `references/class-init-fix-procedure.md` — reusable build-time class-init fix loop
- `references/tracing-agent.md` — both tracing paths (JAR + version-sensitive tests)
- `references/reachability-metadata-repo.md` — using the oracle/graalvm-reachability-metadata repo
- `references/reachability-metadata.md` — native-image metadata JSON schema (adapted from Oracle)
- `references/troubleshooting.md` — build/runtime failure routing (adapted from Oracle)
- `references/native-image-options.md` — raw flags for `--graalvm-build-options` (adapted from Oracle)
- `references/pack-and-mark.md` — filtering, packing into META-INF, and marking compatible
- `templates/` — Ballerina.toml platform block, metadata skeleton, native module layout

---

## Scripts Reference

All scripts are in `<skill-root>/scripts/` and are pure Python (`.py`) — no shell
scripts, so they run identically on macOS/Linux/Windows. Invoke with `<PYTHON_CMD>`
(resolved in Setup Step 0), not a hardcoded `python3`.

```bash
# Environment + package discovery (Stage 00)
<PYTHON_CMD> scripts/check_environment.py
<PYTHON_CMD> scripts/find_ballerina_toml.py
<PYTHON_CMD> scripts/detect_package_coordinates.py "<Ballerina.toml>"
<PYTHON_CMD> scripts/detect_runnable_artifacts.py "<BALLERINA_DIR>"

# GraalVM version derivation + verification (Stage 00)
<PYTHON_CMD> scripts/derive_graalvm_requirements.py [--distribution 2201.10.3]
<PYTHON_CMD> scripts/check_graalvm_env.py --required-jdk 17

# Build/test + error classification (Stage 01)
<PYTHON_CMD> scripts/run_bal_command.py "<bal command>" "<working-dir>"
<PYTHON_CMD> scripts/parse_graalvm_errors.py "<stderr-or-output-file>"

# Reachability-metadata repo (Stage 02)
<PYTHON_CMD> scripts/lookup_reachability_metadata.py --deps-json "<deps.json>"
<PYTHON_CMD> scripts/fetch_reachability_metadata.py --group-id <g> --artifact-id <a> --metadata-version <v> --out <dir>

# Tracing agent (Stages 03/04)
<PYTHON_CMD> scripts/build_jar_trace_command.py --jar "<JAR_NAME>" --config-output-dir "<CONFIG_DIR>"
<PYTHON_CMD> scripts/extract_test_classpath.py --out class-path.txt
<PYTHON_CMD> scripts/build_btest_command.py --distribution "<BAL_DISTRIBUTION>" --config-output-dir "<CONFIG_DIR>" --classpath-file class-path.txt

# Filter + pack + mark (Stages 05/06)
<PYTHON_CMD> scripts/filter_trace_configs.py --config-dir "<CONFIG_DIR>" --out "<filtered-dir>" --keep-prefixes "<prefixes>"
<PYTHON_CMD> scripts/scaffold_native_module.py --native-dir "<NATIVE_DIR>" --group-id "<g>" --artifact-id "<a>"
<PYTHON_CMD> scripts/pack_native_configs.py --filtered-dir "<dir>" --native-dir "<NATIVE_DIR>" --group-id "<g>" --artifact-id "<a>" --merge
<PYTHON_CMD> scripts/build_native_config_jar.py --resources-dir "<NATIVE_DIR>/src/main/resources" --out "<jar>"
<PYTHON_CMD> scripts/update_ballerina_toml_graalvm.py --toml "<Ballerina.toml>" --java-version java21 --graalvm-compatible true
```
