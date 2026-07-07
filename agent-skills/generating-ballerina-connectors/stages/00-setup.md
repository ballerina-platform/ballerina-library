# Stage 00 — Setup

Collect all required inputs, validate the spec, and prepare the workspace. This stage always runs.

---

## Step 0: Environment check

Before collecting any inputs, verify the environment is ready:

```bash
bash <skill-root>/scripts/check_environment.sh
```

If the script exits non-zero, show the errors and stop — do not continue until the user resolves them.

---

## Step 1: Discover spec files in the CWD

Before prompting, scan for existing OpenAPI spec files:

```bash
bash <skill-root>/scripts/find_spec_files.sh
```

Use the results to build the "2+1" prompt dynamically:

> Which OpenAPI spec file should I use?
> 1. `<first result>` (recommended) — if it's named `openapi.yaml`/`openapi.json`/`openapi.yml`, otherwise just list it
> 2. `<second result>` — omit this option if fewer than 2 files were found
> 3. Enter a custom path

If the script finds **no files at all**, skip straight to option 3 and ask the user to type a path.

Store the result as `SPEC_PATH`.

---

## Step 2: Validate the spec

```bash
python3 <skill-root>/scripts/validate_spec.py "<SPEC_PATH>"
```

- Exit code non-zero → print the error, ask the user to correct the path or fix the file, repeat from Step 1.
- Exit code 0 → continue.

Then immediately parse the spec metadata (needed for defaults in later steps):

```bash
python3 <skill-root>/scripts/parse_openapi_spec.py "<SPEC_PATH>"
```

Store the JSON output as `SPEC_METADATA`.

---

## Step 3: Output directory

Derive a slug from `SPEC_METADATA.title`: lowercase, spaces→underscores, strip special characters (e.g. "Microsoft Graph — SharePoint Admin" → `microsoft_graph_sharepoint_admin`).

"2+1" prompt — options derived at runtime:

> Where should the connector workspace be created?
> 1. `./` — current directory (connector-tool default, recommended)
> 2. `./<slug>-connector` (e.g. `./microsoft_graph_sharepoint_admin-connector`)
> 3. Enter a custom path

Store as `OUTPUT_DIR`.

---

## Step 3b: Ballerina project check

Check whether the output directory is already a Ballerina package:

```bash
test -f "<OUTPUT_DIR>/Ballerina.toml" && echo "exists" || echo "missing"
```

**If `Ballerina.toml` exists**: read it with:

```bash
python3 <skill-root>/scripts/parse_ballerina_toml.py "<OUTPUT_DIR>/Ballerina.toml"
```

Confirm with the user:
> Found existing Ballerina.toml — org: `<org>`, package: `<name>`. Use these? [Y/n]

If the user wants to change them, ask using the 2+1 prompts below. Store as `BAL_ORG` and `BAL_PACKAGE`.

**If `Ballerina.toml` is missing**: print a clear message and scaffold the package:

```
⚠ No Ballerina project found at <OUTPUT_DIR> — creating one with `bal new .`
```

```bash
bash <skill-root>/scripts/init_ballerina_package.sh "<OUTPUT_DIR>"
```

`bal new .` reads the user's Ballerina settings to pick a default org and derives the package name from the directory name. It also creates `main.bal` which the script removes immediately (not needed for a connector package).

Then read the generated `Ballerina.toml`:

```bash
python3 <skill-root>/scripts/parse_ballerina_toml.py "<OUTPUT_DIR>/Ballerina.toml"
```

Ask about **org** with a 2+1 prompt:

> What should the package org be?
> 1. `<generated-org>` — auto-generated from your Ballerina settings (recommended)
> 2. `ballerinax` — standard for Ballerina Central connectors
> 3. Enter a custom org name

Ask about **package name** with a separate 2+1 prompt. Derive two slug options from `SPEC_METADATA.title`:
- Full slug: lowercase, spaces and punctuation → underscores (e.g. `microsoft_graph_sharepoint_admin`)
- Short slug: last 1–2 meaningful words (e.g. `sharepoint_admin`)

> What should the package name be?
> 1. `<generated-name>` — auto-generated from the directory name (recommended)
> 2. `<spec-derived-slug>` — derived from the spec title (`<SPEC_METADATA.title>`)
> 3. Enter a custom package name

If org or name changed, update `<OUTPUT_DIR>/Ballerina.toml` (edit the `org` and `name` fields in the `[package]` section).

Store final values as `BAL_ORG` and `BAL_PACKAGE`.

> **Note**: `bal openapi --mode client` (Stage 02) outputs `client.bal`, `types.bal`, and `utils.bal` into `<OUTPUT_DIR>` but does **not** create or modify `Ballerina.toml`. This step is the sole owner of package initialisation.

---

## Step 4: Spec directory

"2+1" prompt (connector-tool default is `<output>/docs/spec`):

> Where should the aligned spec and sanitations.md be written?
> 1. `<OUTPUT_DIR>/docs/spec` — connector-tool default (recommended)
> 2. `<OUTPUT_DIR>/spec`
> 3. Enter a custom path

Store as `SPEC_DIR`.

---

## Step 5: Example directory

"2+1" prompt (connector-tool default is `<output>/examples`):

> Where should generated examples be written?
> 1. `<OUTPUT_DIR>/examples` — connector-tool default (recommended)
> 2. `<OUTPUT_DIR>/example`
> 3. Enter a custom path

Store as `EXAMPLE_DIR`.

---

## Step 6: License header (optional)

Ask:

> Do you have a license header file to include in generated source files? If so, provide the path (or press Enter to skip):

- Path provided → store the path as `LICENSE_PATH`. Do NOT read the file contents.
- Enter / skip → set `LICENSE_PATH` to empty. No license header will be added.

---

## Step 7: Filtering options (progressive disclosure)

> Do you want to filter by OpenAPI tags? [y/N]

If yes, list the tags from `SPEC_METADATA.tags` and ask the user to select. Store as `TAGS` (list).

> Do you want to filter by specific operation IDs? [y/N]

If yes, list `operationId` values from `SPEC_METADATA.paths` and ask the user to select. Store as `OPERATIONS` (list).

> Generate remote methods instead of the default resource methods? [y/N]

Store as `USE_REMOTE` (boolean, default false). Note: connector-tool default is resource methods.

---

## Step 8: Interactive mode

> Run in interactive mode (pause after each stage for confirmation)? [y/N]

Store as `INTERACTIVE_MODE` (boolean, default false).

---

## Step 9: Stage exclusions

> Are there any stages you want to skip? (default: run all)
> 1. Run all stages (recommended)
> 2. Skip specific stages
> 3. Run only specific stages

If skipping, list the five stages (`sanitize`, `client`, `tests`, `examples`, `docs`) and let the user select which to exclude.
Validate against the rules in `references/workflows.md` (section: "Skip validation rules").

Store as `EXCLUDED_STAGES` (list).

---

## Step 10: Confirm and proceed

Print:

```
=== Configuration Summary ===
Spec:           <SPEC_PATH>
Output dir:     <OUTPUT_DIR>
Spec dir:       <SPEC_DIR>
Example dir:    <EXAMPLE_DIR>
Bal org:        <BAL_ORG or "not set">
Bal package:    <BAL_PACKAGE or "not set">
License:        <file path or "none">
Tags:           <tags or "all">
Operations:     <operations or "all">
Remote methods: <yes/no>
Interactive:    <yes/no>
Skip stages:    <stages or "none">
```

Ask: "Proceed with this configuration? [Y/n]"

If no, restart from Step 1.
