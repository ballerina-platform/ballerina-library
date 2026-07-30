# Stage 01 — Sanitize

Flatten, align, and AI-enhance the OpenAPI specification. Records all changes to `sanitations.md` for reproducibility.

Skip this stage if `sanitize` is in `EXCLUDED_STAGES`.
If skipped, run `<PYTHON_CMD> <skill-root>/scripts/find_spec_output.py "<SPEC_DIR>"` to verify an aligned spec exists — halt if it exits non-zero.

---

## Step 0: Check for existing sanitations

Before running any new processing, check whether `<SPEC_DIR>/sanitations.md` already exists. If it does, read it and check whether it still contains the literal substring `TODO` (case-insensitive) — every unfilled marker the template ships with (`<!-- TODO: Add author name -->`, `<!-- TODO: Add date -->`, `(TODO: Add source link)`, `[//]: # (TODO: Add sanitation details)`, `# TODO: Add OpenAPI CLI command used to generate the client`) contains that substring, so its presence means the file is still an unfilled scaffold from `templates/sanitations_template.md` rather than real recorded content.

**If the file doesn't exist**, skip Step 0 entirely and proceed to Step 1.

**If it exists with no `TODO` markers (real recorded content)**, offer the following 2+1 choice:

> A `sanitations.md` was found at `<SPEC_DIR>/sanitations.md`. Apply the recorded sanitations to the spec before processing?
> 1. Yes — apply pre-existing sanitations first (recommended — preserves prior human edits)
> 2. No — skip, start fresh from the original spec
> 3. View `sanitations.md` before deciding

- **Option 1**: Read `sanitations.md`. For each numbered section, extract the `Updated:` value and patch the corresponding field in `<SPEC_PATH>` in-place. Then proceed to Step 1.
- **Option 2**: Proceed directly to Step 1. `sanitations.md`'s auto-detected sections are refreshed at Step 4 (any human-authored sections are preserved via the merge).
- **Option 3**: Print the full contents of `sanitations.md`, then re-present this 2+1 choice.

**If it exists but still contains `TODO` markers (unfilled template)**, offer the same choice with the recommendation flipped instead:

> A `sanitations.md` was found at `<SPEC_DIR>/sanitations.md`, but it still contains unfilled `TODO` placeholders — it looks like an empty template rather than a completed record of prior sanitations.
> 1. No — ignore it, start fresh from the original spec (recommended — file appears to be an unfilled template)
> 2. Yes — apply it anyway (only if you believe it has real content despite the markers)
> 3. View `sanitations.md` before deciding

Option semantics are unchanged from above (option 1 = proceed to Step 1, sanitations refreshed at Step 4; option 2 = read and patch from it same as the "real content" case's option 1; option 3 = print contents then re-present this same flipped prompt) — only the wording and the recommended default differ.

---

## Step 1: Flatten the spec

```bash
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py \
  --cwd "<BALLERINA_DIR>" \
  bal openapi flatten -i "<SPEC_PATH>" -o "<SPEC_DIR>"
```

Output: `<SPEC_DIR>/flattened_openapi.yaml` (or similar — capture the actual filename from stdout).

If this fails, print the error and ask the user to resolve it before continuing.

---

## Step 2: Align the spec

Use the flattened file path captured from Step 1's stdout as input to align. Do **not** use `find_spec_output.py` here — that script only matches `aligned_ballerina_openapi.*` (deliberately, so intermediates are never fed to client generation), so it cannot find the flattened file, and on a re-run it would return the *previous* run's stale aligned spec instead.

```bash
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py \
  --cwd "<BALLERINA_DIR>" \
  bal openapi align -i "<flattened-path>" -o "<SPEC_DIR>"
```

If this fails, print the error and ask the user to resolve it before continuing.

## Step 2b: Locate and normalise the aligned spec

Find the aligned output file:

```bash
<PYTHON_CMD> <skill-root>/scripts/find_spec_output.py "<SPEC_DIR>"
```

Store the returned path as `ALIGNED_SPEC`.

If `ALIGNED_SPEC` ends in `.yaml` or `.yml`, convert it to JSON:

```bash
<PYTHON_CMD> <skill-root>/scripts/convert_yaml_to_json.py "<ALIGNED_SPEC>"
```

The script prints the JSON output path — update `ALIGNED_SPEC` to that path.

---

## Step 2c: Parse the aligned spec (structured extraction)

Run:
```bash
<PYTHON_CMD> <skill-root>/scripts/parse_openapi_spec.py "<ALIGNED_SPEC>"
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

When a category has enough items to require multiple AI requests, process deterministic batches. If every batch fails, stop sanitation without claiming success. If only some batches fail, preserve successful changes, print the failed batch identifiers, and continue with a partial-failure warning.

### 3a. Short or missing descriptions

For schema fields, parameters, and operations where `description` is fewer than 10 characters, empty, or an obvious placeholder (`TBD`, `TODO`, `N/A`, `Not available`), generate a concise description from the structured aligned metadata and apply it directly to `ALIGNED_SPEC`. Preserve every valid existing description.

Request bodies and API-key security schemes use deterministic collection and application. Prepare their structured requests:

```bash
<PYTHON_CMD> <skill-root>/scripts/spec_descriptions.py prepare \
  "<ALIGNED_SPEC>" "<SPEC_DIR>/.description_requests.json"
```

Batch only the returned `requests`. Classify `requestBody` before the generic operation category:

- `requestBody` — describe the complete submitted payload and its purpose in under 100 characters.
- `securityScheme` — describe the credential and where or how it is supplied in under 100 characters.

Return one non-empty description per request ID with no prose or code fences. Merge successful batches into a single JSON object at `<SPEC_DIR>/.description_decisions.json`:

```json
{
  "requestBody:0": "File content, destination, and upload options",
  "securityScheme:1": "Private app token supplied in the request header"
}
```

Apply successful decisions:

```bash
<PYTHON_CMD> <skill-root>/scripts/spec_descriptions.py apply \
  "<ALIGNED_SPEC>" "<SPEC_DIR>/.description_requests.json" \
  "<SPEC_DIR>/.description_decisions.json"
```

The helper processes inline request bodies only, preserves exact paths and security-scheme names, skips `$ref`-only request bodies, and ignores non-API-key schemes. Delete both transient description files after a successful apply. If no requests were returned, skip the AI call and apply command, then delete the empty request file.

### 3b. Operation summary improvement

For operations where `summary` is fewer than 10 characters (or empty), generate a concise summary from the path, method, and parameter names. Apply it directly to `ALIGNED_SPEC` before improving operationIds.

### 3c. Stable operationId improvement

Operation-ID decisions are persisted in `<SPEC_DIR>/ai-mappings.json`, keyed by exact aligned path and lowercase HTTP method. Do not restore IDs from an earlier aligned spec and do not edit the mapping file manually.

Prepare the current run and apply reusable decisions:

```bash
<PYTHON_CMD> <skill-root>/scripts/operation_id_mappings.py prepare \
  "<ALIGNED_SPEC>" "<SPEC_DIR>/ai-mappings.json" \
  "<SPEC_DIR>/.operation_id_mappings_candidate.json"
```

Store `OPERATION_ID_REUSED_COUNT`, `OPERATION_ID_PRUNED_COUNT`, `UNSEEN_OPERATIONS`, and `RESERVED_OPERATION_IDS` from the result. Every operation in `UNSEEN_OPERATIONS` requires one decision, including operations whose existing ID is already good; preserve those as explicit identity decisions.

Process `UNSEEN_OPERATIONS` in deterministic batches. For each operation:
- Replace a path-encoded or verbose/non-intuitive ID with a concise, intent-revealing camelCase name based on method, path, summary, description, and parameters. Example: `postFilesV3FilesUpload` → `uploadFile`, `GET /users/{id}/orders` → `getUserOrders`.
- Preserve an already concise ID unchanged.
- Hard limit: 37 characters for the camelCase operationId — if a candidate exceeds it, simplify (drop qualifiers, use a shorter verb/object) rather than truncating mechanically.
- Treat every ID in `RESERVED_OPERATION_IDS` as belonging to another persisted operation.
- Require each successful batch response to cover exactly its requested path+method entries.

Merge successful responses into `<SPEC_DIR>/.operation_id_decisions.json` using nested path/method objects:

```json
{
  "/users": {
    "get": "listUsers",
    "post": "createUser"
  }
}
```

If every batch fails, stop sanitization without applying or persisting operation-ID changes. Partial successful batches may be applied; missing decisions remain pending and will be reviewed on the next run.

If `UNSEEN_OPERATIONS` is empty, write `{}` to the decisions file and continue to `apply` without an AI call. Applying the empty decision object finalizes pruning and the normalized mapping document.

Apply the decisions:

```bash
<PYTHON_CMD> <skill-root>/scripts/operation_id_mappings.py apply \
  "<ALIGNED_SPEC>" "<SPEC_DIR>/.operation_id_mappings_candidate.json" \
  "<SPEC_DIR>/.operation_id_decisions.json" "<SPEC_DIR>/ai-mappings.json"
```

Store `OPERATION_ID_APPLIED_COUNT`, `OPERATION_ID_CHANGED_COUNT`, and `OPERATION_ID_PENDING_COUNT` from the result. The script resolves remaining collisions deterministically with numeric suffixes and atomically persists both files. Delete the transient candidate and decisions files after successful application.

**Duplicate check.** Also fully deterministic — run immediately after operation-ID decisions are applied, before continuing to schema renaming:

```bash
<PYTHON_CMD> <skill-root>/scripts/check_duplicate_operation_ids.py "<ALIGNED_SPEC>"
```

Print any `WARNING: duplicate operationId ...` lines verbatim. Non-fatal — record the warning and continue (client generation will also surface any remaining conflicts).

### 3d. Stable schema names

Schema-name decisions are persisted in `<SPEC_DIR>/ai-mappings.json`; it is a regeneration artifact and may contain unrelated top-level sections that must be preserved. Do not hand-edit the aligned JSON or mapping file.

First prepare the current run and apply reusable decisions:

```bash
<PYTHON_CMD> <skill-root>/scripts/schema_mappings.py prepare \
  "<ALIGNED_SPEC>" "<SPEC_DIR>/ai-mappings.json" "<SPEC_DIR>/.schema_mappings_candidate.json"
```

Parse the returned JSON and store `UNSEEN_SCHEMAS` from `unseen_schemas`, `REUSED_SCHEMA_COUNT` from `reused_count`, and `PRUNED_SCHEMA_COUNT` from `pruned_count`. On the first run `UNSEEN_SCHEMAS` contains every schema. On later runs it contains only newly introduced schemas; prior decisions have already been applied, including every local `#/components/schemas/...` reference. Only `UNSEEN_SCHEMAS` is input to schema decisions.

If `UNSEEN_SCHEMAS` is empty, set `SCHEMA_DECISION_COUNT = 0` and `IDENTITY_SCHEMA_COUNT = 0`, skip the AI decision and apply commands, then delete the transient candidate file. `prepare` has already finalized `ai-mappings.json`, including pruning stale schema mappings. This also covers specifications with no `components.schemas`.

For every schema in `UNSEEN_SCHEMAS`, ask AI for one concise, unique public schema name based on its structured metadata. Require a JSON object mapping every source name to its target name. Preserve an already good name as an identity mapping. Never include prose or code fences.

Validate the response by writing it to `<SPEC_DIR>/.schema_name_decisions.json` and apply it:

```bash
<PYTHON_CMD> <skill-root>/scripts/schema_mappings.py apply \
  "<ALIGNED_SPEC>" "<SPEC_DIR>/.schema_mappings_candidate.json" \
  "<SPEC_DIR>/.schema_name_decisions.json" "<SPEC_DIR>/ai-mappings.json"
```

Parse the successful `apply` result and store `SCHEMA_DECISION_COUNT` from `applied_count` and `IDENTITY_SCHEMA_COUNT` from `identity_count`. If validation rejects malformed, incomplete, or colliding names, retry the AI response up to the normal bounded retry limit. For any remaining schema, use an identity mapping (`"OriginalName": "OriginalName"`) and re-run `apply`; print a warning. The script atomically persists the spec and mappings, prunes mappings for removed schemas, and preserves unknown top-level mapping data. Delete the two transient dot-files after a successful apply.

---

## Step 4: Record sanitations

`sanitations.md` records only the **structural** spec changes that flatten/align produced — server URL change, path-prefix removal, `date-time`→`datetime` format, nullability changes, and type changes. It is a deterministic diff of the original spec against the aligned spec. The Step 3 AI enhancements (operationIds, schema renames, descriptions, summaries) are applied to the spec but deliberately **not** recorded here, matching connector-tool.

Run the generator (fully deterministic — do not hand-write the file):

```bash
<PYTHON_CMD> <skill-root>/scripts/generate_sanitations.py \
  "<SPEC_PATH>" "<ALIGNED_SPEC>" "<SPEC_DIR>/sanitations.md" \
  --template "<skill-root>/templates/sanitations_template.md" \
  --module-name "<MODULE_NAME_PC>" \
  --cli-command "<the exact bal openapi ... --mode client command Stage 02 will run>"
```

- `<MODULE_NAME_PC>` = `BAL_PACKAGE` in PascalCase (e.g. `sharepoint_admin` → `SharepointAdmin`) — same derivation as the Stage 05 placeholder mapping.
- `--cli-command` = the `bal openapi -i <ALIGNED_SPEC> -o <BALLERINA_DIR> --mode client` command that Stage 02 will run, with the same flags built from the collected config (`--license`/`--tags`/`--operations`/`--client-methods remote` as applicable). This goes into the doc's footer.
- Optional `--source-link "<url>"` if the spec's upstream source URL is known from context; otherwise the template's `(TODO: Add source link)` placeholder is left for the developer.

The script prints a one-line per-category count (`server-url:N path-prefix:N format:N nullability:N type:N`). If `sanitations.md` already exists, the script **merges** — preserving human-authored numbered sections (those without the `<!-- auto-generated -->` marker), refreshing its own auto-detected sections, and renumbering. No need to check for existence first.

Capture the printed counts as `SANITATION_COUNTS` for the completion print below.

---

## Step 5: Stage completion

Print:
```
✓ Sanitize complete
  Aligned spec: <SPEC_DIR>/aligned_ballerina_openapi.json
  Sanitations:  <SPEC_DIR>/sanitations.md (structural spec changes: <SANITATION_COUNTS>)
  AI enhancements applied: <M> descriptions enhanced, <S> summaries improved, <OPERATION_ID_CHANGED_COUNT> operationIds changed (<OPERATION_ID_REUSED_COUNT> reused, <OPERATION_ID_PENDING_COUNT> pending, <OPERATION_ID_PRUNED_COUNT> pruned), <SCHEMA_DECISION_COUNT> schema decisions (<REUSED_SCHEMA_COUNT> reused, <IDENTITY_SCHEMA_COUNT> identity fallbacks, <PRUNED_SCHEMA_COUNT> pruned)
```

The AI enhancements line reports the Step 3 work applied to the spec — those are intentionally not part of `sanitations.md`, which holds only the structural diff.

If `INTERACTIVE_MODE` is true, pause and ask: "Proceed to Client Generation? [Y/n/q]"
