# Stage 05 — Documentation

Generate README files and Ballerina Central publishing documentation.

Skip this stage if `docs` is in `EXCLUDED_STAGES`.

---

## Placeholder mapping

All templates use `{{PLACEHOLDER}}` variables. Resolve them from shared state before filling any template:

| Template placeholder | Source |
|----------------------|--------|
| `{{MODULE_NAME_PC}}` | `BAL_PACKAGE` in PascalCase — convert underscores to title case (e.g. `sharepoint_admin` → `SharepointAdmin`) |
| `{{MODULE_NAME_CC}}` | `BAL_PACKAGE` as-is (already snake_case) |
| `{{REPO_NAME}}` | `ballerina-platform/module-ballerinax-<BAL_PACKAGE with underscores replaced by dots>` (e.g. `ballerina-platform/module-ballerinax-sharepoint.admin`) |
| `{{MODULE_VERSION}}` | `TOML_META.version` (from `parse_ballerina_toml.py` output) |
| `{{BAL_VERSION}}` | `TOML_META.distribution` |

The `[//]: # (TODO: ...)` markers in each template are the sections the LLM must replace with generated content. All other structural content (badges, Build from source, Contributing, Useful links sections) must be copied verbatim from the template without modification.

---

## Step 1: Gather context

Collect the following (already in context from prior stages):
- `SPEC_METADATA`: title, version, description, paths, schemas, security schemes
- `BAL_ORG`, `BAL_PACKAGE`
- `TOML_META` (from `parse_ballerina_toml.py`) — if not already loaded, run:
  ```bash
  python3 <skill-root>/scripts/parse_ballerina_toml.py "<OUTPUT_DIR>/Ballerina.toml"
  ```
- `EXAMPLE_DIR` file list (from stage 04)
- `CLIENT_ANALYSIS.methods` (from stage 02/03)
- The exact `bal openapi` command run in Stage 02

Do **not** re-read the entire source files — use the structured metadata and file paths only.

---

## Step 2: Generate root README

Check if `<OUTPUT_DIR>/README.md` already exists:
- **Exists** → use it as the base. It may already have some or all `[//]: # (TODO: ...)` sections and `{{PLACEHOLDER}}` variables filled. Only replace what is still unfilled — do not overwrite content that is already present.
- **Absent** → read `<skill-root>/templates/readme_template.md` and proceed as below.

Replace all `{{PLACEHOLDER}}` variables using the mapping above.

Replace each `[//]: # (TODO: ...)` section with generated content:
- **Overview**: 3–5 sentences describing what the API does and what this connector enables. Derived from `SPEC_METADATA.description` and title.
- **Setup guide**: Numbered steps to obtain credentials and configure the connector. Derived from `SPEC_METADATA.securitySchemes` — list the required fields (API keys, OAuth tokens, etc.) and how to get them.
- **Quickstart**: One short Ballerina code snippet showing a single representative API call. Use a simple GET or list operation from `CLIENT_ANALYSIS.methods`. Include the `Config.toml` snippet needed.
- **Examples**: Bullet list of example names and one-line descriptions from `EXAMPLE_DIR` subdirectory names. Format: `[example-name](examples/example-name) — <one liner>`.

Copy all other sections (Build from source, Build options, Contribute, Code of conduct, Useful links) verbatim from the template.

Write to `<OUTPUT_DIR>/README.md`.

---

## Step 3: Generate Module.md (Ballerina Central)

Check if `<OUTPUT_DIR>/Module.md` already exists:
- **Exists** → use it as the base. Only replace sections that still contain unfilled `[//]: # (TODO: ...)` markers or unresolved `{{PLACEHOLDER}}` variables. Do not overwrite already-filled content.
- **Absent** → read `<skill-root>/templates/module_readme_template.md` and proceed as below.

Replace all `{{PLACEHOLDER}}` variables using the mapping above.

Replace each `[//]: # (TODO: ...)` section with generated content using the same content as Step 2 (Overview, Setup guide, Quickstart, Examples) — the module README mirrors the root README but is shorter (no build/contribute sections).

Write to `<OUTPUT_DIR>/Module.md`.

---

## Step 4: Generate sub-READMEs

### Tests README

Check if `<OUTPUT_DIR>/tests/README.md` already exists:
- **Exists** → use it as the base. Only fill in `AI_GENERATED_TESTING_APPROACH` if it still appears as the bare marker. Do not overwrite content that is already filled.
- **Absent** → read `<skill-root>/templates/tests_readme_template.md` and proceed as below.

Fill in `AI_GENERATED_TESTING_APPROACH` with a short description of what the test suite covers — derived from `CLIENT_ANALYSIS.methods` method names.

Write to `<OUTPUT_DIR>/tests/README.md`.

### Examples README

Check if `<EXAMPLE_DIR>/README.md` already exists:
- **Exists** → use it as the base. Update or add example table rows for any new examples added since the last run. Only replace `<angle-bracket>` placeholders that are still unfilled. Do not overwrite content that is already present.
- **Absent** → read `<skill-root>/templates/examples_readme_template.md` and proceed as below.

Fill in:
- `<BAL_ORG>/<BAL_PACKAGE>` → from shared state
- Example table rows — one row per subdirectory in `EXAMPLE_DIR`
- Auth field names from `SPEC_METADATA.securitySchemes`

Write to `<EXAMPLE_DIR>/README.md`.

### Per-example READMEs (generate if time permits)

For each example subdirectory that does not already have a `README.md`, read `<skill-root>/templates/example_readme_template.md` and fill in:
- `<EXAMPLE_TITLE>` → human-readable name from the directory kebab slug
- `AI_GENERATED_DESCRIPTION` → 2–3 sentences describing the use case

---

## Step 5: Generate sanitations.md

Read `<skill-root>/templates/sanitations_template.md`.

Replace `{{MODULE_NAME_PC}}` with the resolved value from the placeholder mapping.

Fill in the TODO sections:
- `_Author_` → leave blank (to be filled by the developer)
- `_Created_` → today's date in `YYYY/MM/DD` format
- `_Updated_` → today's date in `YYYY/MM/DD` format
- Numbered sanitation list → each entry from Stage 01 Step 4 (AI-assisted enhancements: operationIds improved/restored, schemas renamed, descriptions enhanced). Format each as:
  ```
  N. <Change type>
  - **Original**: <what was there before>
  - **Updated**: <what it became>
  - **Reason**: <why the change was made>
  ```
- OpenAPI CLI command → the exact `bal openapi` command used in Stage 02 (with all flags that were passed)

Write to `<SPEC_DIR>/sanitations.md`. If a `sanitations.md` already exists (from a previous run that the user chose to preserve in Stage 01 Step 0), **append** new auto-generated sections rather than overwriting human-authored ones.

---

## Step 6: Stage completion

Print:
```
✓ Documentation complete
  README.md:            <OUTPUT_DIR>/README.md
  Module.md:            <OUTPUT_DIR>/Module.md
  tests/README.md:      <OUTPUT_DIR>/tests/README.md
  examples/README.md:   <EXAMPLE_DIR>/README.md
  sanitations.md:       <SPEC_DIR>/sanitations.md
```

Then print the **Final Run Summary** from `references/workflows.md` (section: "Final Summary Format"), filled in with actual values.
