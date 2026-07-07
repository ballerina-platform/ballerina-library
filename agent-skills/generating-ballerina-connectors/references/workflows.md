# Connector Creator — Internal Agent Workflow Guide

This document is for the agent's internal use. It describes sequencing rules, error-handling decisions, and behavioural contracts for each stage.

---

## Stage Sequencing

Stages run in this fixed order. Each stage may be skipped if the user excluded it.

```
0. setup      → always runs (cannot be skipped)
1. sanitize   → skippable; requires aligned spec to exist if skipped
2. client     → skippable; requires client.bal to exist if skipped; runs fix procedure inline on build failure
3. tests      → skippable; runs fix procedure inline on build failure
4. examples   → skippable; runs fix procedure inline per example on build failure (non-fatal if fix fails)
5. docs       → skippable
```

Skip validation rules (mirror the connector-tool's `OpenApiStageValidationUtils`):
- If `sanitize` is skipped: `<SPEC_DIR>/aligned_ballerina_openapi.yaml` must exist — fail with a clear message if not.
- If `client` is skipped: `<OUTPUT_DIR>/client.bal` must exist — fail with a clear message if not.
- If all stages are skipped: reject immediately.

---

## Fix Procedure

Compilation errors are resolved **inline within the stage that generated the failing code** — there is no separate fix stage. When any stage's `bal build` call fails, read `references/fix-procedure.md` and invoke it before proceeding.

The fix procedure takes `BUILD_DIR` as its context (the directory where `bal build` was run):
- **Client stage**: `BUILD_DIR = OUTPUT_DIR`
- **Tests stage**: `BUILD_DIR = OUTPUT_DIR`
- **Examples stage**: `BUILD_DIR = EXAMPLE_DIR/<example-name>` (per example, non-fatal if fix exhausted)

---

## "2+1" Prompting Contract

For every required user input, always present exactly:
1. **Option A** — the most common/recommended default (mark as "(recommended)")
2. **Option B** — a plausible alternative
3. **Option C** — "Enter a custom value"

Never present more than three options unless the input is a multi-select (e.g., tags).
Always confirm the collected values before proceeding to stage execution.

---

## Interactive Mode

When `--interactive` is enabled:
- After each stage completes, print a summary of what was produced (files created/modified).
- Ask: "Proceed to the next stage? [Y/n/q]"
  - `Y` or Enter → continue
  - `n` → skip this stage's follow-up (continue to stage after next)
  - `q` → stop the pipeline and summarize what was completed

---

## Error Handling Decision Tree

### Script failure (validate_spec.py, parse_openapi_spec.py)
→ Print the error, ask the user to fix the input, re-run the script. Do not continue.

### `bal openapi` failure (client stage)
→ Print the raw error. Ask the user to retry with different flags or abort. Do NOT invoke fix procedure.

### `bal build` failure (client or tests stage)
→ Invoke fix procedure with `BUILD_DIR`. Up to 3 iterations. If exhausted, ask user to continue or abort.

### `bal build` failure (examples stage, per example)
→ Invoke fix procedure with `BUILD_DIR = EXAMPLE_DIR/<example-name>`. If exhausted, warn and continue to the next example — non-fatal.

### `bal test` failure
→ Non-fatal. Record and continue. Note failure in the final summary.

---

## Context Hygiene

- **Never** inject raw OpenAPI spec content into the LLM context.
- **Always** use `parse_openapi_spec.py` output (structured JSON) as the spec representation.
- For code fixes: read only the specific file + line range indicated by `parse_errors.py`, not whole files.
- Stage files are loaded **one at a time** when that stage becomes active. Do not preload all stages.

---

## Final Summary Format

At the end of the pipeline (or when aborted), print:

```
=== Connector Creator — Run Summary ===
Spec:         <input spec path>
Output:       <output dir>
Stages run:   sanitize ✓  client ✓  tests ✓  examples ✓  docs ✓
Stages skipped: (none)

Generated files:
  docs/spec/aligned_ballerina_openapi.yaml
  docs/spec/sanitations.md
  client.bal
  types.bal
  tests/mock_service.bal
  tests/test.bal
  examples/<example-name>/main.bal
  examples/<example-name>/Ballerina.toml
  examples/README.md
  README.md
  Module.md

Next steps:
  1. Review docs/spec/sanitations.md for AI-made spec changes.
  2. Run `bal test` to verify the generated tests.
  3. cd examples/<example-name> && bal run  to try an example.
  4. Publish to Ballerina Central when ready.
```
