# Stage 01 — Build and Test Baseline

Establish the current GraalVM-compatibility baseline and classify what (if anything) needs fixing. Always runs. Routing decisions here follow `references/workflow.md`.

> Native builds and tests are slow and memory-hungry — expect multi-minute runs.

---

## Step 1: Native build

```bash
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py "bal build --graalvm" "<BALLERINA_DIR>"
```

Set `BUILD_STATUS` = pass/fail from the exit code. On failure, note the printed `>>> output saved to: <path>` — it is the input to classification.

Classify the output (pass the saved path, or pipe the terminal output):

```bash
<PYTHON_CMD> <skill-root>/scripts/parse_graalvm_errors.py "<saved-output-path>"
```

Store `NOT_VERIFIED_WARNING` (`not_verified_warning`) and the error buckets.

---

## Step 2: Route on the build result

- **`out_of_memory: true`** → retry once with more builder memory: `bal build --graalvm --graalvm-build-options="-J-Xmx8g"`, then re-classify.
- **`class_init` non-empty (build failed)** → load `references/class-init-fix-procedure.md` and run its loop with `BUILD_DIR = <BALLERINA_DIR>`. Re-run this step after it completes.
- **Build passed** → continue to Step 3.
- **Build failed with only `other` errors** → surface them to the user; ask whether to investigate manually or continue.

---

## Step 3: Native test (only if build passed and tests exist)

If `HAS_TESTS` is false, skip to Step 4.

```bash
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py "bal test --graalvm" "<BALLERINA_DIR>"
```

Set `TEST_STATUS` = pass/fail. On failure, classify the output the same way and merge into the error buckets (test failures usually surface `missing_metadata`).

---

## Step 4: Decide the next stage

Using the merged classification (see `references/workflow.md`):

| Situation | Next |
|---|---|
| Build + test pass, no not-verified warning, no missing metadata | skip to `stages/06-mark-compatible.md` |
| `THIRD_PARTY_DEPS` non-empty (missing metadata likely from a Java dep) | `stages/02-reachability-repo.md` |
| Missing metadata, no third-party deps (or repo covered nothing) | `stages/03-trace-jar.md` (if main/service) and/or `stages/04-trace-tests.md` (if tests) |
| Not-verified warning only (build/test otherwise fine) | `stages/02-reachability-repo.md` if deps exist, else `stages/06-mark-compatible.md` |

Record `BUILD_STATUS`, `TEST_STATUS`, and the classification for the run summary.

If `INTERACTIVE_MODE`, print what was found and confirm before proceeding.
