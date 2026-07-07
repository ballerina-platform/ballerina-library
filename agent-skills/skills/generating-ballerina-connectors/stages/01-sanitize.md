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
- **Option 2**: Proceed directly to Step 1. `sanitations.md` will be regenerated from scratch at Step 5.
- **Option 3**: Print the full contents of `sanitations.md`, then re-present this 2+1 choice.

**If `sanitations.md` does not exist**, skip Step 0 entirely and proceed to Step 0b.

---

## Step 0b: Common path prefix normalization

Run on the original spec before flattening so that `bal openapi flatten` and
`bal openapi align` inherit the correct server URL and shortened paths:

```bash
python3 <skill-root>/scripts/normalize_base_url.py "<SPEC_PATH>"
```

Store the single-line stdout as `PREFIX_NORMALIZATION_RESULT`.

- If output is `Moved common prefix '<prefix>' into base URL` — store `MOVED_PREFIX = <prefix>` (`<SPEC_PATH>` updated in-place)
- If output is `No common path prefix found` — set `MOVED_PREFIX = ""`

On re-runs where `sanitations.md` already recorded this change and Step 0 replayed it,
this step will report no prefix found and is a no-op.

---

## Step 0c: Snapshot the previous aligned spec (if any)

Step 3b below overwrites `<SPEC_DIR>/aligned_ballerina_openapi.json` with this run's output, so any operationIds a previous run established must be captured first. This is deterministic — no reasoning required:

```bash
test -f "<SPEC_DIR>/aligned_ballerina_openapi.json" && cp "<SPEC_DIR>/aligned_ballerina_openapi.json" "<SPEC_DIR>/aligned_ballerina_openapi.json.prev" || echo "no previous aligned spec"
```

If the copy was made, `<SPEC_DIR>/aligned_ballerina_openapi.json.prev` holds the prior run's operationIds for use in Step 4a Pass A. If no previous aligned spec exists, that file will simply be absent — Pass A's script handles this gracefully.

---

## Step 1: Parse the spec (structured extraction)

Run:
```bash
python3 .claude/skills/generating-ballerina-connectors/scripts/parse_openapi_spec.py "<SPEC_PATH>"
```

Capture the JSON output as `SPEC_METADATA`. This is the **only** representation of the spec that should enter the LLM context — do not read or inject the raw spec file.

From `SPEC_METADATA`, note:
- `title`, `version`, `description`
- paths with missing, verbose, or path-encoded `operationId`s
- schema names that may be generic (e.g., "Object", "Response", "Item")
- operations with empty or very short `summary`/`description`

---

## Step 2: Flatten the spec

```bash
bash .claude/skills/generating-ballerina-connectors/scripts/run_bal_command.sh \
  "bal openapi flatten -i <SPEC_PATH> -o <SPEC_DIR>" \
  "<OUTPUT_DIR>"
```

Output: `<SPEC_DIR>/flattened_openapi.yaml` (or similar — capture the actual filename from stdout).

If this fails, print the error and ask the user to resolve it before continuing.

---

## Step 3: Align the spec

First, locate the flattened output (the exact filename depends on the spec title):

```bash
bash <skill-root>/scripts/find_spec_output.sh "<SPEC_DIR>"
```

Use the returned path as input to align:

```bash
bash <skill-root>/scripts/run_bal_command.sh \
  "bal openapi align -i <flattened-path> -o <SPEC_DIR>" \
  "<OUTPUT_DIR>"
```

## Step 3b: Locate and normalise the aligned spec

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

## Step 4: AI-assisted spec enhancement

Using `SPEC_METADATA` (not the raw spec), review and improve each category below. Each sub-step applies its own changes directly to `ALIGNED_SPEC` and writes the file back before moving to the next — operationId improvement, schema renaming, and description enhancement are each self-contained, matching how connector-tool treats them as separate read-modify-write passes rather than one deferred bulk write.

### 4a. OperationId improvement (two-pass)

**Pass A — restore from previous run.** This step is fully deterministic — do not reason through it manually, run the script:

```bash
python3 <skill-root>/scripts/restore_prior_operation_ids.py "<SPEC_DIR>/aligned_ballerina_openapi.json.prev" "<ALIGNED_SPEC>"
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

### 4b. Generic schema names
If schema names like `Object`, `Response`, `InlineResponse200`, `Item`, `Body` appear, propose better names based on context (the operation that returns/consumes them). Apply renames consistently, then write `ALIGNED_SPEC` back before continuing.

### 4c. Short or missing descriptions
For operations where `summary` or `description` is fewer than 10 characters (or empty), generate a concise description from the path, method, and parameter names. Apply directly to `ALIGNED_SPEC` and write back.

---

## Step 5: Record sanitations

Read `<skill-root>/templates/sanitations_template.md` as the scaffold.

Create or update `<SPEC_DIR>/sanitations.md` following that structure:
- Header with `# Sanitation for OpenAPI specification`, created/updated dates
- Numbered sections — one per change type detected (server URL, path prefix, format, nullability, type, operationId, description, schema rename)
- Each section follows the `Original / Updated / Reason` format shown in the template
- Mark auto-detected sections with `<!-- auto-generated -->` so future regenerations can identify and replace them while preserving human-authored sections
- Footer: `## OpenAPI cli command` section with the exact `bal openapi` command used to generate the client

**If `MOVED_PREFIX` is non-empty**, include these two numbered entries (following the pattern used across the HubSpot connector suite):

```
N.  **Change the `url` property of the servers object**: All API paths shared a common prefix.
    - Original: `<original-server-url>`
    - Updated:  `<original-server-url><MOVED_PREFIX>`
    - Reason: Adding the common prefix `<MOVED_PREFIX>` to the base URL simplifies endpoint paths
      and produces a more meaningful `serviceUrl` default in the generated client.

N+1. **Update the API Paths**: The common prefix `<MOVED_PREFIX>` was removed from every path key.
    - Original: Paths included the prefix (e.g. `<MOVED_PREFIX>/resource/{id}`)
    - Updated:  Prefix removed from each path (e.g. `/resource/{id}`)
    - Reason: Prefix is now represented in the base URL (see above).
```

---

## Step 6: Stage completion

Print:
```
✓ Sanitize complete
  Aligned spec: <SPEC_DIR>/aligned_ballerina_openapi.json
  Sanitations:  <SPEC_DIR>/sanitations.md
  Changes made: <N> operationIds improved (<R> restored from previous run), <M> descriptions enhanced, <K> schemas renamed
```

If `INTERACTIVE_MODE` is true, pause and ask: "Proceed to Client Generation? [Y/n/q]"
