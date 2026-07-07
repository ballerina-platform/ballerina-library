# Stage 02 — Client Generation

Generate a Ballerina client project from the aligned OpenAPI spec using the `bal openapi` tool, then compile and auto-fix any errors.

Skip this stage if `client` is in `EXCLUDED_STAGES`.
If skipped, verify that `<BALLERINA_DIR>/client.bal` already exists — halt if not.

---

## Step 1: Build the `bal openapi` command

Resolve the spec input file:
- Use `ALIGNED_SPEC` if set (populated by Stage 01 Step 3b — this is the `.json` path after YAML conversion).
- If `ALIGNED_SPEC` is not set (Stage 01 was skipped), run:
  ```bash
  bash <skill-root>/scripts/find_spec_output.sh "<SPEC_DIR>"
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
bash <skill-root>/scripts/run_bal_command.sh \
  "bal openapi -i <ALIGNED_SPEC> -o <BALLERINA_DIR> --license <LICENSE_PATH> [--tags <tags>] [--operations <ops>] [--client-methods remote] --mode client" \
  "<BALLERINA_DIR>"
```

Omit `--license <LICENSE_PATH>` if `LICENSE_PATH` is not set. Omit any other optional flag that does not apply.

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
bash <skill-root>/scripts/run_bal_command.sh "bal build" "<BALLERINA_DIR>"
```

- Exit 0 → build clean, continue to completion
- Non-zero → invoke the **Fix Procedure** (`references/fix-procedure.md`) with `BUILD_DIR = <BALLERINA_DIR>`

> ⚠️ A `bal build` failure is always a generated-code issue, never a license format issue. Do NOT re-run client generation with different `--license` options or a reformatted header — go directly to the Fix Procedure.

---

## Step 4: Stage completion

Print:
```
✓ Client Generation complete
  client.bal:  <BALLERINA_DIR>/client.bal
  types.bal:   <BALLERINA_DIR>/types.bal
  utils.bal:   <BALLERINA_DIR>/utils.bal
  build:       passed (fixed in <N> iteration(s) / clean)
```

If `INTERACTIVE_MODE` is true, pause and ask: "Proceed to Tests? [Y/n/q]"
