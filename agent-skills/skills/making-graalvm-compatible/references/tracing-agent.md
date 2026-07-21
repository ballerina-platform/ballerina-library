# The GraalVM Tracing Agent (Ballerina)

The tracing agent runs the application (or tests) on a regular JVM and records all uses of dynamic features (reflection, JNI, resources, proxies, serialization) into config files. Use it to discover metadata the reachability-metadata repo does not already provide (`reachability-metadata-repo.md`).

**Always use the `java` bundled with the GraalVM distribution** (`$GRAALVM_HOME/bin/java`).

There are two paths. The JAR path is straightforward; the tests path is version-sensitive.

---

## Path A — Tracing the application JAR (main / service)

Use when `HAS_MAIN` or `HAS_SERVICE` is true and runtime errors remain after the repo lookup.

### 1. Build the JAR

```bash
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py "bal build" "<BALLERINA_DIR>"
```

### 2. Run under the tracing agent

Generate the exact command (uses `$GRAALVM_HOME`):

```bash
<PYTHON_CMD> <skill-root>/scripts/build_jar_trace_command.py \
  --jar "<JAR_NAME>" --config-output-dir "<CONFIG_DIR>"
```

Run the printed command. Then:

- **Service**: this is load-bearing — **prompt the user to exercise the running service**, hitting every representative endpoint/code path (the collected metadata is only as complete as the traffic driven). Confirm before terminating.
- **Main**: ensure the invocation covers representative arguments/paths.

Configs land in `<CONFIG_DIR>`.

### 3. Validate by rebuilding with the collected config

```bash
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py \
  "bal build --graalvm --graalvm-build-options=\"-H:ConfigurationFileDirectories=<CONFIG_DIR>\"" \
  "<BALLERINA_DIR>"
```

Run `./target/bin/<executable>` and verify functionality before packing.

---

## Path B — Tracing the Ballerina tests (version-sensitive)

Ballerina tests are not a single uber JAR, so the agent must be attached to the test runner (`org.ballerinalang.test.runtime.BTestMain`) with the right classpath, main class, and **version-specific arguments**.

### 1. Generate the native-image args (also produces the classpath source)

```bash
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py "bal test --graalvm" "<BALLERINA_DIR>"
```

This writes `target/cache/tests_cache/native-config/native-image-args.txt`.

### 2. Extract the classpath

```bash
<PYTHON_CMD> <skill-root>/scripts/extract_test_classpath.py --out class-path.txt
```

Stores the classpath in `class-path.txt` (equivalent to the guide's `sed` one-liner).

### 3. Build the version-aware BTestMain command

⚠ **The `BTestMain` argument signature changed at Ballerina Update 10 (2201.10.x).** Passing the wrong signature does **not** error — it silently produces bad metadata. `build_btest_command.py` is the single source of truth:

```bash
<PYTHON_CMD> <skill-root>/scripts/build_btest_command.py \
  --distribution "<BAL_DISTRIBUTION>" \
  --config-output-dir "<CONFIG_DIR>" \
  --classpath-file class-path.txt
```

The script prints the resolved update and branch to stderr (e.g. `>=10 (2201.10.x or higher)`). **Show the command and the resolved branch to the user and confirm** before running it.

- **Update ≥ 10** signature: `... "org.ballerinalang.test.runtime.BTestMain" false "target/cache/tests_cache/test_suit.json" "target" "" true false "" "" "" false false false false`
- **Update ≤ 9** signature: `... "org.ballerinalang.test.runtime.BTestMain" "target" "" true false "" "" "" false false`

Run the printed command. Configs land in `<CONFIG_DIR>`.

### 4. Validate by re-running tests with the collected config

```bash
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py \
  "bal test --graalvm --graalvm-build-options=\"-H:ConfigurationFileDirectories=<CONFIG_DIR>\"" \
  "<BALLERINA_DIR>"
```

---

## After collection

The raw `<CONFIG_DIR>` contains a large amount of JDK/Ballerina-runtime metadata. Do **not** pack it wholesale — filter it first (`filter_trace_configs.py`) and pack only the library's entries. See `workflow.md` (filtering contract) and `pack-and-mark.md`.

## Sources

- Ballerina GraalVM compatibility guide: `docs/graalvm-compatibility-in-ballerina-libraries.md`
- https://www.graalvm.org/jdk21/reference-manual/native-image/metadata/AutomaticMetadataCollection/
