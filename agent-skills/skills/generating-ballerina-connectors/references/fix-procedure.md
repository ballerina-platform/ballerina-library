# Fix Procedure — Reusable Compilation Error Fixer

This is a **reusable procedure**, not a pipeline stage. It is invoked inline by any stage that runs `bal build` and encounters compilation errors: client generation (stage 02), tests (stage 03), and examples (stage 04).

---

## When to Invoke

Invoke this procedure whenever `bal build` exits with a non-zero code, passing the directory where the build was run as `BUILD_DIR`.

---

## Procedure

### Step 1: Parse compilation errors

`<skill-root>/scripts/run_bal_command.py` (used to run the `bal build` that triggered this procedure) always captures stderr and, on non-zero exit, writes it to a cross-platform temp file and prints its path (e.g. `>>> stderr saved to: <path>`). Use that printed path:

```bash
<PYTHON_CMD> <skill-root>/scripts/parse_errors.py "<printed-stderr-path>"
```

Capture the JSON array as `COMPILE_ERRORS`.

If `COMPILE_ERRORS` is empty but the build failed anyway (unparsed error format), surface the raw stderr to the user and ask whether to continue or abort.

---

### Step 2: Fix loop — up to 3 iterations

Repeat until the build passes or 3 iterations are exhausted:

#### 2a. Build LLM context (minimal — do not load whole files)

For each error in `COMPILE_ERRORS`:
- Read only the **10 lines surrounding `error.line`** from `<BUILD_DIR>/<error.fileName>`
- Combine into: `{ file, line, col, message, code_snippet }`

#### 2b. Apply fixes

> The following compilation errors were found. Apply targeted fixes to resolve each one. Do not restructure or refactor code beyond what is strictly required to fix the errors.
>
> [structured errors with code snippets]

Use the Edit tool to apply each fix at the specific file and line.

#### 2c. Re-run build

```bash
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py "bal build" "<BUILD_DIR>"
```

- Exit 0 → build clean, exit loop, report success
- Non-zero → parse new errors, continue loop

---

### Step 3: After 3 iterations with no success

Print:
```
⚠ Fix procedure exhausted 3 iterations. Remaining errors:
<structured error list>
```

Ask:
> 1. Continue anyway (proceed to the next stage)
> 2. Stop here and fix manually

---

## Reporting

After the procedure completes (success or escalation), print:
```
  Build fix: <passed after N iteration(s) / escalated to user>
  Errors resolved: <count>
```
