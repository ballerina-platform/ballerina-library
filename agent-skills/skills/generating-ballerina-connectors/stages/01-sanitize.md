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

## Step 1: Parse the spec (structured extraction)

Run:
```bash
python3 .claude/skills/generating-ballerina-connectors/scripts/parse_openapi_spec.py "<SPEC_PATH>"
```

Capture the JSON output as `SPEC_METADATA`. This is the **only** representation of the spec that should enter the LLM context — do not read or inject the raw spec file.

From `SPEC_METADATA`, note:
- `title`, `version`, `description`
- paths with missing `operationId`
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

Using `SPEC_METADATA` (not the raw spec), review and improve:

### 4a. Missing operationIds
For each path entry where `operationId` is empty, generate a meaningful camelCase operationId based on the HTTP method and path segments. Example: `GET /users/{id}/orders` → `getUserOrders`.

### 4b. Generic schema names
If schema names like `Object`, `Response`, `InlineResponse200`, `Item`, `Body` appear, propose better names based on context (the operation that returns/consumes them). Apply renames consistently.

### 4c. Short or missing descriptions
For operations where `summary` or `description` is fewer than 10 characters (or empty), generate a concise description from the path, method, and parameter names.

### 4d. Apply changes to the aligned spec
Read `ALIGNED_SPEC`, apply the changes above, and write back.

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
  Changes made: <N> operationIds assigned, <M> descriptions enhanced, <K> schemas renamed
```

If `INTERACTIVE_MODE` is true, pause and ask: "Proceed to Client Generation? [Y/n/q]"
