# Stage 04 — Trace the Ballerina Tests (version-sensitive)

Collect dynamic-feature metadata by running the test suite under the tracing agent.
This path is version-sensitive — the `BTestMain` argument signature changed at
Ballerina Update 10. Full procedure: `references/tracing-agent.md` (Path B).

**Skip this stage** if `HAS_TESTS` is false, or if tests already pass under
`bal test --graalvm`.

---

## Step 1: Generate the native-image args

```bash
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py "bal test --graalvm" "<BALLERINA_DIR>"
```

This writes `target/cache/tests_cache/native-config/native-image-args.txt`.
(A test failure here is expected if metadata is missing — that is why we trace.)

---

## Step 2: Extract the classpath

```bash
<PYTHON_CMD> <skill-root>/scripts/extract_test_classpath.py --out class-path.txt
```

Run from `<BALLERINA_DIR>` so the default `target/...` path resolves. Store
`CLASSPATH_FILE = class-path.txt`.

---

## Step 3: Build the version-aware BTestMain command

```bash
<PYTHON_CMD> <skill-root>/scripts/build_btest_command.py \
  --distribution "<BAL_DISTRIBUTION>" \
  --config-output-dir "<CONFIG_DIR>" \
  --classpath-file class-path.txt
```

The script prints the resolved update and signature branch to stderr. ⚠ **Show the
command and the resolved branch to the user and confirm before running it** — a
wrong signature silently produces bad metadata. If `--distribution` is unavailable,
pass `--update <BAL_UPDATE>` instead.

Run the confirmed command from `<BALLERINA_DIR>`. Configs land in `<CONFIG_DIR>`.

---

## Step 4: Validate

```bash
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py \
  "bal test --graalvm --graalvm-build-options=\"-H:ConfigurationFileDirectories=<CONFIG_DIR>\"" \
  "<BALLERINA_DIR>"
```

Tests should now pass. If some still fail, review the remaining errors
(`parse_graalvm_errors.py`) and, if needed, re-trace with more coverage or add
metadata by hand (`references/reachability-metadata.md`).

---

## Step 5: Proceed

Continue to `stages/05-filter-and-pack.md`. The raw `<CONFIG_DIR>` is filtered
there, not packed as-is.

If `INTERACTIVE_MODE`, confirm before proceeding.
