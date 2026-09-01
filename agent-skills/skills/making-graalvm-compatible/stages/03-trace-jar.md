# Stage 03 — Trace the Application JAR

Collect dynamic-feature metadata for a runnable `main` or service via the GraalVM tracing agent on the uber JAR. Full procedure: `references/tracing-agent.md` (Path A).

**Skip this stage** if both `HAS_MAIN` and `HAS_SERVICE` are false, or if stage 02 already covered all missing metadata.

---

## Step 1: Build the JAR

```bash
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py "bal build" "<BALLERINA_DIR>"
```

---

## Step 2: Run under the tracing agent

```bash
<PYTHON_CMD> <skill-root>/scripts/build_jar_trace_command.py \
  --jar "<JAR_NAME>" --config-output-dir "<CONFIG_DIR>"
```

Run the printed command from `<BALLERINA_DIR>` (it uses `$GRAALVM_HOME/bin/java`).

- **Service** — this is load-bearing. Prompt the user:
> The service is running under the tracing agent. Please exercise it now — hit every representative endpoint / code path (the collected metadata is only as complete as the traffic you drive). Tell me when you're done and I'll stop it.

Wait for the user, then terminate the process.
- **Main** — ensure the invocation covered representative arguments/paths (pass `--app-args` to `build_jar_trace_command.py` if needed).

Configs are written to `<CONFIG_DIR>`.

---

## Step 3: Validate the collected config

```bash
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py \
  "bal build --graalvm --graalvm-build-options=\"-H:ConfigurationFileDirectories=<CONFIG_DIR>\"" \
  "<BALLERINA_DIR>"
```

Run `./target/bin/<executable>` and verify functionality. If runtime errors remain, re-trace with broader exercise coverage.

---

## Step 4: Proceed

Continue to `stages/04-trace-tests.md` if `HAS_TESTS` and test failures remain, otherwise to `stages/05-filter-and-pack.md`. The raw `<CONFIG_DIR>` is **not** packed as-is — it is filtered in stage 05.

If `INTERACTIVE_MODE`, confirm before proceeding.
