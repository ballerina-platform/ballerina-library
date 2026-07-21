# Stage 04 — Examples

Generate standalone Ballerina usage examples, each as its own runnable package.

Skip this stage if `examples` is in `EXCLUDED_STAGES`.

---

## Step 1: Analyse the client and connector metadata

Run both scripts upfront — this replaces all inline file reading for this stage:

```bash
<PYTHON_CMD> <skill-root>/scripts/analyze_client.py "<BALLERINA_DIR>/client.bal"
```

Store as `CLIENT_ANALYSIS`. Take `NUM_EXAMPLES` from `CLIENT_ANALYSIS.numExamples` (formula already applied). Initialise `USED_FUNCTIONS = []`.

```bash
<PYTHON_CMD> <skill-root>/scripts/parse_ballerina_toml.py "<BALLERINA_DIR>/Ballerina.toml"
```

Store as `TOML_META`. Use `TOML_META.distribution` and `TOML_META.version` when writing per-example `Ballerina.toml` files.

---

## Step 2: Pack connector to local repository

Before generating any examples, publish the connector so that each example's `import <BAL_ORG>/<BAL_PACKAGE>` can resolve at build time:

```bash
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py "bal pack" "<BALLERINA_DIR>"
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py "bal push --repository=local" "<BALLERINA_DIR>"
```

`bal pack` creates the `.bala` archive in `target/`; `bal push --repository=local` publishes it to `~/.ballerina/repositories/local/bala/` so examples can resolve the import at build time.

If either command fails, print the error and **halt** — examples cannot build without a packaged and published connector.

---

## Step 3: For each example (repeat `NUM_EXAMPLES` times)

### 3a: Select a use case

Pick a **distinct, realistic, multi-step use case** from `CLIENT_ANALYSIS.methods`:
- Combines 2–4 operations in a logical workflow
- Avoids functions already in `USED_FUNCTIONS`
- Solves a real-world scenario a developer would recognise
- Is meaningfully different from previous examples

Determine `USE_CASE` (1-2 sentence description) and `REQUIRED_FUNCTIONS` (list of method names from `CLIENT_ANALYSIS.methods`).
Add `REQUIRED_FUNCTIONS` to `USED_FUNCTIONS`.

### 3b: Derive a use-case name

From `USE_CASE`, produce a kebab-case directory name:
- Exactly 3–4 words, lowercase with hyphens
- Scenario-focused — no "example", "demo", "test", or raw operation names

Good: `sharepoint-tenant-configuration`, `admin-settings-update`
Bad: `get-sharepoint-example`, `getSharepoint-demo`

Store as `EXAMPLE_NAME`.

### 3c: Extract targeted code context

Filter `CLIENT_ANALYSIS.methods` to only the entries whose `name` is in `REQUIRED_FUNCTIONS`. Use those `{name, params, returnType}` objects as the code context — do not read `client.bal` again.

### 3d: Write `<EXAMPLE_DIR>/<EXAMPLE_NAME>/main.bal`

```ballerina
// <USE_CASE description>

import ballerina/io;
import <BAL_ORG>/<BAL_PACKAGE>;

// Configuration — create a Config.toml with these values before running
configurable string <auth_field_1> = ?;
configurable string <auth_field_2> = ?;

public function main() returns error? {
    <BAL_PACKAGE>:Client baseClient = check new ({
        auth: { <fields from spec security schemes> }
    });

    // Step 1: <first operation description>
    <return_type> result1 = check baseClient-><fn1>(<params>);
    io:println("Result: ", result1);

    // Step 2: ...
}
```

Rules:
- Use exact function names and parameter types from the extracted context
- Prefix all connector types with `<BAL_PACKAGE>:`
- Import only `ballerina/io` and `<BAL_ORG>/<BAL_PACKAGE>`
- Entry point is always `public function main() returns error?`

### 3e: Write `<EXAMPLE_DIR>/<EXAMPLE_NAME>/Ballerina.toml`

```toml
[package]
org = "<BAL_ORG>"
name = "<EXAMPLE_NAME with hyphens replaced by underscores>"
version = "0.1.0"
distribution = "<TOML_META.distribution>"

[build-options]
observabilityIncluded = true

[[dependency]]
org = "<BAL_ORG>"
name = "<BAL_PACKAGE>"
version = "<TOML_META.version>"
repository = "local"
```

The `[[dependency]]` block with `repository = "local"` lets the example resolve `import <BAL_ORG>/<BAL_PACKAGE>` from the locally published connector.

### 3f: Compile and fix

```bash
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py "bal build" "<EXAMPLE_DIR>/<EXAMPLE_NAME>"
```

- Exit 0 → clean
- Non-zero → invoke the **Fix Procedure** (`references/fix-procedure.md`) with `BUILD_DIR = <EXAMPLE_DIR>/<EXAMPLE_NAME>`

Compilation errors in examples are **non-fatal if fix fails** — warn the user and continue to the next example.

---

## Step 4: Write `<EXAMPLE_DIR>/README.md`

Read `<skill-root>/templates/examples_readme_template.md`.

Fill in:
- `<BAL_ORG>/<BAL_PACKAGE>` → from shared state
- Example table rows — one row per example generated in Step 3 (`<example-name>` and USE_CASE one-liner)
- `<BALLERINA_DIR>` → the connector output directory path
- Auth field names (`<auth_field_1>`, `<auth_field_2>`) → from `SPEC_METADATA.securitySchemes`

Write the filled content to `<EXAMPLE_DIR>/README.md`.

---

## Stage completion

Print:
```
✓ Examples complete
  <NUM_EXAMPLES> example(s) generated:
    <EXAMPLE_DIR>/<name-1>/   (build: passed / needs manual review)
    <EXAMPLE_DIR>/<name-2>/   ...
```

If `INTERACTIVE_MODE` is true, pause and ask: "Proceed to Documentation? [Y/n/q]"
