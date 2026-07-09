# Stage 00 — Setup

Collect all required inputs, validate the spec, and prepare the workspace. This stage always runs.

---

## Step 0: Environment check

Before anything else, determine which Python 3 command works on this machine — try each in order using the Bash tool directly (plain commands, no shell-specific syntax, so this works identically on macOS/Linux/Windows):

```
python3 --version
python --version
py --version
```

Use the first one whose output starts with `Python 3`. Store it as `<PYTHON_CMD>` — every script invocation below and in later stages uses this instead of a hardcoded `python3`.

Then verify the rest of the environment is ready:

```bash
<PYTHON_CMD> <skill-root>/scripts/check_environment.py
```

If the script exits non-zero, show the errors and stop — do not continue until the user resolves them.

---

## Step 1: Discover spec files in the CWD

Before prompting, scan for existing OpenAPI spec files:

```bash
<PYTHON_CMD> <skill-root>/scripts/find_spec_files.py
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
<PYTHON_CMD> <skill-root>/scripts/validate_spec.py "<SPEC_PATH>"
```

- Exit code non-zero → print the error, ask the user to correct the path or fix the file, repeat from Step 1.
- Exit code 0 → continue.

Then immediately parse the spec metadata (needed for defaults in later steps):

```bash
<PYTHON_CMD> <skill-root>/scripts/parse_openapi_spec.py "<SPEC_PATH>"
```

Store the JSON output as `SPEC_METADATA`.

---

## Step 3: Ballerina package directory

Before prompting, search downstream from the CWD for an existing Ballerina package — some repos (e.g. ballerina-library modules) keep `Ballerina.toml` nested below the root rather than at `./`:

```bash
<PYTHON_CMD> <skill-root>/scripts/find_ballerina_toml.py
```

Derive a slug from `SPEC_METADATA.title`: lowercase, spaces→underscores, strip special characters (e.g. "Microsoft Graph — SharePoint Admin" → `microsoft_graph_sharepoint_admin`).

"2+1" prompt — options derived at runtime:

- **If the search found exactly one directory** (and it isn't `.`):
  > Where does the Ballerina package live?
  > 1. `<found-dir>` — existing Ballerina.toml found here (recommended)
  > 2. `./` — current directory
  > 3. Enter a custom path
- **If the search found nothing, or only `.`**:
  > Where should the Ballerina package be created?
  > 1. `./` — current directory (connector-tool default, recommended)
  > 2. `./<slug>-connector` (e.g. `./microsoft_graph_sharepoint_admin-connector`)
  > 3. Enter a custom path
- **If the search found more than one directory**: list up to two of them as options 1 and 2 (no "recommended" marker — ambiguous), plus option 3 for a custom path.

Store as `BALLERINA_DIR`. This is the directory containing (or that will contain) `Ballerina.toml`, `client.bal`, `types.bal`, `utils.bal`, `tests/`, `README.md`, and `Module.md`.

---

## Step 3b: Ballerina project check

Check whether `<BALLERINA_DIR>/Ballerina.toml` exists.

**If it exists**: read it with:

```bash
<PYTHON_CMD> <skill-root>/scripts/parse_ballerina_toml.py "<BALLERINA_DIR>/Ballerina.toml"
```

Confirm with the user:
> Found existing Ballerina.toml — org: `<org>`, package: `<name>`. Use these? [Y/n]

If the user wants to change them, ask using the 2+1 prompts below. Store as `BAL_ORG` and `BAL_PACKAGE`.

**If it's missing**: print a clear message and scaffold the package:

```
⚠ No Ballerina project found at <BALLERINA_DIR> — creating one with `bal new .`
```

```bash
<PYTHON_CMD> <skill-root>/scripts/init_ballerina_package.py "<BALLERINA_DIR>"
```

`bal new .` reads the user's Ballerina settings to pick a default org and derives the package name from the directory name. It also creates `main.bal` which the script removes immediately (not needed for a connector package).

Then read the generated `Ballerina.toml`:

```bash
<PYTHON_CMD> <skill-root>/scripts/parse_ballerina_toml.py "<BALLERINA_DIR>/Ballerina.toml"
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

If org or name changed, update `<BALLERINA_DIR>/Ballerina.toml` (edit the `org` and `name` fields in the `[package]` section).

Store final values as `BAL_ORG` and `BAL_PACKAGE`.

> **Note**: `bal openapi --mode client` (Stage 02) outputs `client.bal`, `types.bal`, and `utils.bal` into `<BALLERINA_DIR>` but does **not** create or modify `Ballerina.toml`. This step is the sole owner of package initialisation.

---

## Step 4: Stage exclusions

Ask this before any stage-specific questions below, so those can be skipped when their stage won't run:

> Are there any stages you want to skip? (default: run all)
> 1. Run all stages (recommended)
> 2. Skip specific stages
> 3. Run only specific stages

If skipping (or selecting which to run only), collect the stage list across **two** multi-select questions in the same prompt — `AskUserQuestion` caps options at 4 per question, so all 5 stages cannot be offered in one:
- Question A — options: `sanitize`, `client`
- Question B — options: `tests`, `examples`, `docs`

Union the selections from both questions into a single list. Validate against the rules in `references/workflows.md` (section: "Skip validation rules").

Store as `EXCLUDED_STAGES` (list).

---

## Step 5: Spec directory

"2+1" prompt (connector-tool default is `./docs/spec`):

> Where should the aligned spec and sanitations.md be written?
> 1. `./docs/spec` — connector-tool default (recommended)
> 2. `./spec`
> 3. Enter a custom path

Store as `SPEC_DIR`.

---

## Step 6: Example directory

Skip this step entirely if `examples` is in `EXCLUDED_STAGES` — leave `EXAMPLE_DIR` unset.

"2+1" prompt (connector-tool default is `./examples`):

> Where should generated examples be written?
> 1. `./examples` — connector-tool default (recommended)
> 2. `./example`
> 3. Enter a custom path

Store as `EXAMPLE_DIR`.

---

## Step 7: License header (optional)

Skip this step entirely if **both** `client` and `tests` are in `EXCLUDED_STAGES` — those are the only stages that consume `LICENSE_PATH`. Leave `LICENSE_PATH` empty.

Otherwise, ask:

> Do you have a license header file to include in generated source files? If so, provide the path (or press Enter to skip):

- Path provided → store the path as `LICENSE_PATH`. Do NOT read the file contents.
- Enter / skip → set `LICENSE_PATH` to empty. No license header will be added.

---

## Step 8: Filtering options (progressive disclosure)

Skip this step entirely if `client` is in `EXCLUDED_STAGES` — `TAGS`, `OPERATIONS`, and `USE_REMOTE` are only consumed by Stage 02 (client generation). Leave `TAGS`/`OPERATIONS` empty and `USE_REMOTE` false.

Otherwise:

> Do you want to filter by OpenAPI tags? [y/N]

If yes, list the tags from `SPEC_METADATA.tags` and ask the user to select. Store as `TAGS` (list).

> Do you want to filter by specific operation IDs? [y/N]

If yes, list `operationId` values from `SPEC_METADATA.paths` and ask the user to select. Store as `OPERATIONS` (list).

> Generate remote methods instead of the default resource methods? [y/N]

Store as `USE_REMOTE` (boolean, default false). Note: connector-tool default is resource methods.

---

## Step 9: Interactive mode

> Run in interactive mode (pause after each stage for confirmation)? [y/N]

Store as `INTERACTIVE_MODE` (boolean, default false).

---

## Step 10: Confirm and proceed

Print:

```
=== Configuration Summary ===
Spec:           <SPEC_PATH>
Ballerina dir:  <BALLERINA_DIR>
Spec dir:       <SPEC_DIR>
Example dir:    <EXAMPLE_DIR or "N/A (examples stage skipped)">
Bal org:        <BAL_ORG or "not set">
Bal package:    <BAL_PACKAGE or "not set">
License:        <file path, "none", or "N/A (client and tests skipped)">
Tags:           <tags, "all", or "N/A (client stage skipped)">
Operations:     <operations, "all", or "N/A (client stage skipped)">
Remote methods: <yes/no, or "N/A (client stage skipped)">
Interactive:    <yes/no>
Skip stages:    <stages or "none">
```

Ask: "Proceed with this configuration? [Y/n]"

If no, restart from Step 1.
