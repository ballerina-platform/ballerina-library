# Stage 01 — Sanitize

Flatten, align, and AI-enhance the OpenAPI specification. Records all changes to `sanitations.md` for reproducibility.

Skip this stage if `sanitize` is in `EXCLUDED_STAGES`.
If skipped, run `bash <skill-root>/scripts/find_spec_output.sh "<SPEC_DIR>"` to verify an aligned spec exists — halt if it exits non-zero.

---

## Step 0: Check for existing sanitations

Before running any new processing, check whether a `sanitations.md` already exists from a previous run:

```bash
test -f "<SPEC_DIR>/sanitations.md" && echo "exists" || echo "missing"
```

**If `sanitations.md` exists**, offer the following 2+1 choice:

> A `sanitations.md` was found at `<SPEC_DIR>/sanitations.md`. Apply the recorded sanitations to the spec before processing?
> 1. Yes — apply pre-existing sanitations first (recommended — preserves prior human edits)
> 2. No — skip, start fresh from the original spec
> 3. View `sanitations.md` before deciding

- **Option 1**: Read `sanitations.md`. For each numbered section, extract the `Updated:` value and patch the corresponding field in `<SPEC_PATH>` in-place. Then proceed to Step 1.
- **Option 2**: Proceed directly to Step 1. `sanitations.md` will be regenerated from scratch at Step 4.
- **Option 3**: Print the full contents of `sanitations.md`, then re-present this 2+1 choice.

**If `sanitations.md` does not exist**, skip Step 0 entirely and proceed to Step 0b.

---

## Step 0b: Build the prior operationId map (if any)

Step 2 below overwrites `<SPEC_DIR>/aligned_ballerina_openapi.json` with this run's output, so any operationIds a previous run established must be captured first. This is deterministic — no reasoning required, and no need to check existence first:

```bash
python3 <skill-root>/scripts/restore_prior_operation_ids.py build "<SPEC_DIR>/aligned_ballerina_openapi.json" > "<SPEC_DIR>/.prior_operation_ids.json"
```

This extracts just the `path -> {method: operationId}` map (not a full spec copy) into a small scratch file, used by Step 3a Pass A after alignment. If no previous aligned spec exists, the script prints `{"prior_spec_found": false, "operation_id_map": {}}` — no error.

---

## Step 1: Flatten the spec

```bash
bash .claude/skills/generating-ballerina-connectors/scripts/run_bal_command.sh \
  "bal openapi flatten -i <SPEC_PATH> -o <SPEC_DIR>" \
  "<BALLERINA_DIR>"
```

Output: `<SPEC_DIR>/flattened_openapi.yaml` (or similar — capture the actual filename from stdout).

If this fails, print the error and ask the user to resolve it before continuing.

---

## Step 2: Align the spec

First, locate the flattened output (the exact filename depends on the spec title):

```bash
bash <skill-root>/scripts/find_spec_output.sh "<SPEC_DIR>"
```

Use the returned path as input to align:

```bash
bash <skill-root>/scripts/run_bal_command.sh \
  "bal openapi align -i <flattened-path> -o <SPEC_DIR>" \
  "<BALLERINA_DIR>"
```

If this fails, print the error and ask the user to resolve it before continuing.

## Step 2b: Locate and normalise the aligned spec

Find the aligned output file:

```bash
bash <skill-root>/scripts/find_spec_output.sh "<SPEC_DIR>"
```

Store the returned path as `ALIGNED_SPEC`.

If `ALIGNED_SPEC` ends in `.yaml` or `.yml`, convert it to JSON:

```bash
python3 <skill-root>/scripts/convert_yaml_to_json.py "<ALIGNED_SPEC>"
```

The script prints the JSON output path — update `ALIGNED_SPEC` to that path.

---

## Step 2c: Parse the aligned spec (structured extraction)

Run:
```bash
python3 <skill-root>/scripts/parse_openapi_spec.py "<ALIGNED_SPEC>"
```

Capture the JSON output as `ALIGNED_SPEC_METADATA`. This reflects the spec *after* flatten and align — parsing it here (rather than the original spec) keeps path keys, operationIds, and generic schema names (e.g. `InlineResponse200`, introduced by flatten) accurate for Step 3 below, which edits `ALIGNED_SPEC` directly.

From `ALIGNED_SPEC_METADATA`, note:
- `title`, `version`, `description`
- paths with missing, verbose, or path-encoded `operationId`s
- schema names that may be generic (e.g., "Object", "Response", "Item")
- operations with empty or very short `summary`/`description`

---

## Step 3: AI-assisted spec enhancement

Using `ALIGNED_SPEC_METADATA` (not the raw spec), review and improve each category below. Each sub-step applies its own changes directly to `ALIGNED_SPEC` and writes the file back before moving to the next — operationId improvement, schema renaming, description enhancement, and summary improvement are each self-contained, matching how connector-tool treats them as separate read-modify-write passes rather than one deferred bulk write.

### 3a. OperationId improvement (two-pass)

**Pass A — restore from previous run.** This step is fully deterministic — do not reason through it manually, run the script:

```bash
python3 <skill-root>/scripts/restore_prior_operation_ids.py apply "<SPEC_DIR>/.prior_operation_ids.json" "<ALIGNED_SPEC>"
```

The script writes any restored operationIds directly into `ALIGNED_SPEC` — no AI call — and prints a single JSON object to stdout:

```json
{"prior_spec_found": bool, "restored_count": int, "reserved_operation_ids": [str, ...]}
```

Parse it and print the status line matching the case:
- `prior_spec_found` is `false` → `No previous aligned spec found — all operationIds eligible for AI improvement`
- `prior_spec_found` is `true` and `restored_count` is `0` → `Previous aligned spec found but contains no operationIds — all operationIds will be AI-improved`
- otherwise → `Restored <restored_count> operationIds from previous run`

Store `restored_count` as `RESTORED_COUNT` and `reserved_operation_ids` as `RESERVED_OPERATION_IDS` for use below.

The map file has now been fully consumed — delete it:

```bash
rm -f "<SPEC_DIR>/.prior_operation_ids.json"
```

**Pass B — AI improvement.** For every operation whose path+method is *not* covered by Pass A (new endpoints, or ones with no prior recorded id):
- If the current operationId (if any) is path-encoded or verbose/non-intuitive, replace it with a concise, intent-revealing camelCase name based on the HTTP method and path segments. Example: `postFilesV3FilesUpload` → `uploadFile`, `GET /users/{id}/orders` → `getUserOrders`.
- If it's already concise and intent-revealing, leave it unchanged.
- Hard limit: 37 characters for the camelCase operationId — if a candidate exceeds it, simplify (drop qualifiers, use a shorter verb/object) rather than truncating mechanically.
- Treat every id in `RESERVED_OPERATION_IDS` as a hard "must not conflict" name. A Pass-B operation's own current id is never in that list (only Pass-A-restored ids are), so it's always free to keep its own id unchanged.
- Once all Pass B decisions are made, apply them directly to `ALIGNED_SPEC` and write the file back now.

**Duplicate check.** Also fully deterministic — run immediately after Pass B writes back, before continuing to schema renaming:

```bash
python3 <skill-root>/scripts/check_duplicate_operation_ids.py "<ALIGNED_SPEC>"
```

Print any `WARNING: duplicate operationId ...` lines verbatim. Non-fatal — record the warning and continue (client generation will also surface any remaining conflicts).

### 3b. Generic schema names
If schema names like `Object`, `Response`, `InlineResponse200`, `Item`, `Body` appear, propose better names based on context (the operation that returns/consumes them). Apply renames consistently, then write `ALIGNED_SPEC` back before continuing.

### 3c. Short or missing descriptions
For schema fields, parameters, and operations where `description` is fewer than 10 characters (or empty), generate a concise description from context (field/parameter name, or the operation's path, method, and parameters). Apply directly to `ALIGNED_SPEC` and write back.

### 3d. Operation summary improvement
For operations where `summary` is fewer than 10 characters (or empty), generate a concise summary from the path, method, and parameter names — this becomes the doc comment on the generated client's resource/remote function. Apply directly to `ALIGNED_SPEC` and write back.

---

## Step 4: Record sanitations

Read `<skill-root>/templates/sanitations_template.md` as the scaffold.

Create or update `<SPEC_DIR>/sanitations.md` following that structure:
- Header with `# Sanitation for OpenAPI specification`, created/updated dates
- Numbered sections — one per change type detected (format, nullability, type, operationId, description, schema rename)
- Each section follows the `Original / Updated / Reason` format shown in the template
- Mark auto-detected sections with `<!-- auto-generated -->` so future regenerations can identify and replace them while preserving human-authored sections
- Footer: `## OpenAPI cli command` section with the exact `bal openapi` command used to generate the client

---

## Step 5: Stage completion

Print:
```
✓ Sanitize complete
  Aligned spec: <SPEC_DIR>/aligned_ballerina_openapi.json
  Sanitations:  <SPEC_DIR>/sanitations.md
  Changes made: <N> operationIds improved (<R> restored from previous run), <K> schemas renamed, <M> descriptions enhanced, <S> summaries improved
```

If `INTERACTIVE_MODE` is true, pause and ask: "Proceed to Client Generation? [Y/n/q]"
