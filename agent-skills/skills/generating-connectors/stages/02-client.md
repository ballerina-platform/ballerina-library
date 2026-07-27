# Stage 02 — Client Generation

Generate a Ballerina client project from the aligned OpenAPI spec using the `bal openapi` tool, then compile and auto-fix any errors.

Skip this stage if `client` is in `EXCLUDED_STAGES`.
If skipped, verify that `<BALLERINA_DIR>/client.bal` already exists — halt if not.

---

## Step 0: Capture the client baseline

Before generation, capture source snapshots without using Git:

```bash
<PYTHON_CMD> <skill-root>/scripts/client_version_summary.py capture \
  "<BALLERINA_DIR>" "<BALLERINA_DIR>/.client_version_baseline.json"
```

Keep this transient baseline until Step 4. A missing, empty, or comment-only previous `client.bal` means version analysis is skipped.

---

## Step 1: Build the `bal openapi` command

Resolve the spec input file:
- Use `ALIGNED_SPEC` if set (populated by Stage 01 Step 3b — this is the `.json` path after YAML conversion).
- If `ALIGNED_SPEC` is not set (Stage 01 was skipped), run:
  ```bash
  <PYTHON_CMD> <skill-root>/scripts/find_spec_output.py "<SPEC_DIR>"
  ```
  and set `ALIGNED_SPEC` from the result before continuing.

Base command:
```
bal openapi -i <ALIGNED_SPEC> -o <BALLERINA_DIR> --mode client
```

> **Note**: `bal openapi --mode client` outputs `client.bal`, `types.bal`, and `utils.bal` into `<BALLERINA_DIR>`. It does **not** create or modify `Ballerina.toml` — that is handled in Stage 00.

Append options based on collected configuration:
- If `TAGS` is non-empty: add `--tags <tag>` for each tag
- If `OPERATIONS` is non-empty: add `--operations <id>` for each operation ID
- If `USE_REMOTE` is true: add `--client-methods remote`
- If `LICENSE_PATH` is set and the file exists: add `--license <LICENSE_PATH>`

> The `--license` flag accepts the raw license file path — `bal openapi` reads and formats it as `//` comments automatically. Do NOT read the file contents, reformat them, or write a modified version to a temp file.

---

## Step 2: Run client generation

```bash
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py \
  --cwd "<BALLERINA_DIR>" \
  bal openapi -i "<ALIGNED_SPEC>" -o "<BALLERINA_DIR>" --mode client
```

Append each applicable option as separate arguments: `--license "<LICENSE_PATH>"`, one `--tags "<tag>"` pair per tag, one `--operations "<id>"` pair per operation ID, and `--client-methods remote` when `USE_REMOTE` is true. Omit every optional flag/value pair that does not apply.

### On success:
Verify that `<BALLERINA_DIR>/client.bal`, `<BALLERINA_DIR>/types.bal`, and `<BALLERINA_DIR>/utils.bal` were created. Print the file list.

### On failure:
`bal openapi` failures indicate spec or flag issues — do not attempt LLM fixes here. Print the error and ask:
> 1. Retry with different flags
> 2. Abort

---

## Step 3: Compile and fix

Run `bal build` in `<BALLERINA_DIR>`:

```bash
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py --cwd "<BALLERINA_DIR>" bal build
```

- Exit 0 → build clean, continue to completion
- Non-zero → invoke the **Fix Procedure** (`references/fix-procedure.md`) with `BUILD_DIR = <BALLERINA_DIR>`

> ⚠️ A `bal build` failure is always a generated-code issue, never a license format issue. Do NOT re-run client generation with different `--license` options or a reformatted header — go directly to the Fix Procedure.

---

## Step 4: Recommend a semantic-version update

Run this only if client generation itself succeeded. It compares the pre-generation snapshot with the final, fixed `client.bal` and `types.bal`; tests, examples, and docs are never included.

```bash
<PYTHON_CMD> <skill-root>/scripts/client_version_summary.py diff \
  "<BALLERINA_DIR>" "<BALLERINA_DIR>/.client_version_baseline.json"
```

- `skipped` is non-empty → print that status and continue.
- Empty `diff` → report that no version bump is required.
- Otherwise, ask AI to classify only the supplied diff as `MAJOR`, `MINOR`, or `PATCH`, with a concise rationale. Recommend `<major+1>.0.0`, `<major>.<minor+1>.0`, or `<major>.<minor>.<patch+1>` from the reported package version. Classification failure is a warning only.

Delete `.client_version_baseline.json` after reporting.

---

## Step 5: Stage completion

Print:
```
✓ Client Generation complete
  client.bal:  <BALLERINA_DIR>/client.bal
  types.bal:   <BALLERINA_DIR>/types.bal
  utils.bal:   <BALLERINA_DIR>/utils.bal
  build:       passed (fixed in <N> iteration(s) / clean)
```

If `INTERACTIVE_MODE` is true, pause and ask: "Proceed to Tests? [Y/n/q]"
