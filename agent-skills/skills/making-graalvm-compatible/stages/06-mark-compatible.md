# Stage 06 — Mark the Library GraalVM Compatible

Declare the package compatible and prove it with a final verifying build/test. Always runs last. Full procedure: `references/pack-and-mark.md` (steps 6–7).

---

## Step 1: Guard — do not mark a failing build

If the most recent `bal build --graalvm` (from stage 01/03/05) did **not** pass, stop. Print why and return to the relevant stage. Never set `graalvmCompatible = true` on a package that does not build natively.

---

## Step 2: Mark compatible

```bash
<PYTHON_CMD> <skill-root>/scripts/update_ballerina_toml_graalvm.py \
  --toml "<BALLERINA_TOML>" --java-version "<PLATFORM_JAVA_VERSION>" \
  --graalvm-compatible true
```

If a **new** native config jar was created in stage 05, also wire it in:

```bash
<PYTHON_CMD> <skill-root>/scripts/update_ballerina_toml_graalvm.py \
  --toml "<BALLERINA_TOML>" --java-version "<PLATFORM_JAVA_VERSION>" \
  --add-dependency --group-id "<GROUP_ID>" --artifact-id "<ARTIFACT_ID>" \
  --dep-version "<BAL_PACKAGE version>" --path "./native/build/libs/<ARTIFACT_ID>-<version>.jar"
```

(Skip `--add-dependency` if the native jar already existed / is built by the module.)

Show the resulting `[platform.<PLATFORM_JAVA_VERSION>]` block. If `INTERACTIVE_MODE`, confirm before writing.

---

## Step 3: Final verification

```bash
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py "bal build --graalvm" "<BALLERINA_DIR>"
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py "bal test --graalvm" "<BALLERINA_DIR>"
```

Both must pass with **no** "Package is not verified with GraalVM" warning (re-check with `parse_graalvm_errors.py` if unsure). If the build now fails, revert the `graalvmCompatible` change (set it back / remove the block) and return to debugging — do not leave a false compatibility claim in place.

---

## Step 4: Run summary

Print the final summary in the format from `references/workflow.md` (Final Summary Format): package, GraalVM JDK, baseline vs final build/test status, repo-metadata hits/misses, tracing run/skip, packed config location, the Ballerina.toml change, and next steps (review packed metadata, commit, confirm the module's GraalVM Check workflow passes in CI).
