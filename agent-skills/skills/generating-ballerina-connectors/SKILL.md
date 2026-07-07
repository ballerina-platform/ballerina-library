---
name: generating-ballerina-connectors
description: Generates a complete Ballerina connector from an OpenAPI specification. Use when the user wants to create, generate, or build a Ballerina connector from an OpenAPI or Swagger spec; run the connector creation pipeline; generate a Ballerina client from an API spec; or produce connector tests, examples, and documentation.
---

# Generating Ballerina Connectors Skill

An AI-assisted pipeline for generating and maintaining Ballerina connectors from OpenAPI specifications. Mirrors the `bal connector openapi` workflow with interactive guidance, "2+1" prompting, and LLM reasoning applied only where it adds value.

---

## How This Skill Works

This skill orchestrates five pipeline stages in sequence:

```
Setup → Sanitize → Client → Tests → Examples → Docs
```

Each stage is defined in a dedicated file under `stages/`. Load only the active stage's file into context — do not preload all stages.

Compilation errors are fixed **inline within each stage** using the reusable fix procedure (`references/fix-procedure.md`). Any stage that runs `bal build` will invoke this procedure automatically on failure — no separate fix stage.

Scripts in `scripts/` handle all deterministic operations. Run them via Bash — do not reimplement their logic inline.

---

## Quick Reference

| Stage | File | Skippable? | Key output |
|-------|------|-----------|------------|
| 0. Setup | `stages/00-setup.md` | No | Configuration, validated spec |
| 1. Sanitize | `stages/01-sanitize.md` | Yes (`sanitize`) | `aligned_ballerina_openapi.yaml`, `sanitations.md` |
| 2. Client | `stages/02-client.md` | Yes (`client`) | `client.bal`, `types.bal` — build + auto-fix inline |
| 3. Tests | `stages/03-tests.md` | Yes (`tests`) | `tests/test.bal`, mock server — build + auto-fix inline |
| 4. Examples | `stages/04-examples.md` | Yes (`examples`) | per-example packages in `examples/` — build + auto-fix inline |
| 5. Docs | `stages/05-docs.md` | Yes (`docs`) | `README.md`, `Module.md` |

---

## Entry Point Instructions

When this skill is invoked:

1. Print the welcome banner:
   ```
   ╔══════════════════════════════════════════╗
   ║       Ballerina Connector Generator      ║
   ╚══════════════════════════════════════════╝

   I'll guide you through generating a Ballerina connector from your OpenAPI spec.
   This involves up to 5 stages: sanitize → client → tests → examples → docs.
   ```

2. Read and follow `stages/00-setup.md` to collect all configuration. Do this before loading any other stage file.

3. After setup, execute stages in order, respecting `EXCLUDED_STAGES`:

   ```
   for stage in [sanitize, client, tests, examples, docs]:
     if stage not in EXCLUDED_STAGES:
       Read the corresponding stage file
       Follow its instructions completely
       If INTERACTIVE_MODE: pause and confirm before next stage
   ```

4. When any stage runs `bal build` and it fails, read `references/fix-procedure.md` and invoke it immediately in that stage's context before proceeding.

---

## Shared State

These variables are set in Setup (stage 00) and used by all subsequent stages:

| Variable | Description |
|----------|-------------|
| `SPEC_PATH` | Absolute or relative path to the input OpenAPI spec |
| `BALLERINA_DIR` | Directory containing (or to contain) `Ballerina.toml` — where `client.bal`, `types.bal`, `utils.bal`, `tests/`, `README.md`, `Module.md` are generated |
| `SPEC_DIR` | User-confirmed path for aligned spec + sanitations (default: `./docs/spec`) |
| `EXAMPLE_DIR` | User-confirmed path for generated examples (default: `./examples`) — unset if the `examples` stage is excluded |
| `BAL_ORG` | Ballerina package org (read from Ballerina.toml or collected from user) |
| `BAL_PACKAGE` | Ballerina package name (read from Ballerina.toml or collected from user) |
| `LICENSE_PATH` | Path to the user-provided license file, or empty if not provided |
| `TAGS` | List of OpenAPI tags to filter (or empty for all) |
| `OPERATIONS` | List of operation IDs to filter (or empty for all) |
| `USE_REMOTE` | Boolean — generate remote vs resource methods (connector-tool default: false) |
| `INTERACTIVE_MODE` | Boolean — pause after each stage (connector-tool default: false) |
| `EXCLUDED_STAGES` | List of stage names to skip — valid values: `sanitize`, `client`, `tests`, `examples`, `docs` |
| `SPEC_METADATA` | JSON from `parse_openapi_spec.py` on the original spec (Stage 00) — the only spec representation in LLM context |
| `ALIGNED_SPEC_METADATA` | JSON from `parse_openapi_spec.py` on `ALIGNED_SPEC`, the post-flatten/align spec (Stage 01 onward) — authoritative for path keys, operationIds, and generated schema names |

---

## Core Principles

**Context hygiene**: Never inject the raw OpenAPI spec into the LLM context. Always use the structured JSON output from `scripts/parse_openapi_spec.py`. When fixing code errors, read only the specific lines indicated by `scripts/parse_errors.py`.

**Deterministic first**: Use scripts for everything that doesn't require reasoning. Only use the LLM for: spec enhancement (naming, descriptions), code error repair, and content generation (examples, docs).

**"2+1" prompting**: For every required input, always offer exactly two contextual defaults plus a "custom value" option. See `stages/00-setup.md` for the pattern.

**Transparency**: Print a clear status line before each sub-step. Use `✓` for success, `⚠` for warnings, `✗` for failures.

---

## Reference Files

- `references/workflows.md` — Stage sequencing rules, error handling, final summary format
- `references/fix-procedure.md` — Reusable compilation error fixer (invoked inline by client, tests, examples stages)
- `templates/readme_template.md` — Connector README scaffold for stage 05

---

## Scripts Reference

All scripts are in `<skill-root>/scripts/`.

```bash
# Check environment (bal, python3, ANTHROPIC_API_KEY) — run first in setup
bash scripts/check_environment.sh

# Find OpenAPI spec candidates in CWD — use before prompting for spec path
bash scripts/find_spec_files.sh

# Find an existing Ballerina.toml nested below CWD — use before prompting for output dir
bash scripts/find_ballerina_toml.sh

# Initialise a Ballerina package in the output dir (bal new . + remove main.bal)
bash scripts/init_ballerina_package.sh "<output-dir>"

# Validate spec file (YAML/JSON validity + required fields)
python3 scripts/validate_spec.py "<spec-path>"

# Extract structured spec metadata — the only spec representation in LLM context
python3 scripts/parse_openapi_spec.py "<spec-path>"

# Convert YAML spec to JSON — writes <same-name>.json, prints output path
python3 scripts/convert_yaml_to_json.py "<spec.yaml>"

# Locate aligned/flattened spec output in a spec directory
bash scripts/find_spec_output.sh "<spec-dir>"

# Read Ballerina.toml package fields → JSON {org, name, version, distribution}
python3 scripts/parse_ballerina_toml.py "<Ballerina.toml>"

# Analyse client.bal → JSON {apiCount, numExamples, configType, methods:[...]}
python3 scripts/analyze_client.py "<client.bal>"

# Generate service stub from spec → tests/mock_service.bal
bash scripts/generate_mock_stub.sh "<aligned-spec>" "<output-dir>"

# Run any bal command in a working directory
bash scripts/run_bal_command.sh "<command>" "<working-dir>"

# Parse compilation errors from bal build stderr → JSON error array
python3 scripts/parse_errors.py "<stderr-file-or-stdin>"

# Extract the prior run's operationId map (run before flatten/align overwrites it)
python3 scripts/restore_prior_operation_ids.py build "<existing-aligned-spec>" > "<map-file>"

# Apply that map into the newly aligned spec, restoring matching operationIds
python3 scripts/restore_prior_operation_ids.py apply "<map-file>" "<current-aligned-spec>"

# Scan an aligned spec for duplicate operationIds — non-fatal warnings
python3 scripts/check_duplicate_operation_ids.py "<aligned-spec>"
```
