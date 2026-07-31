# Stage 04 — Examples

Generate standalone Ballerina usage examples, each as its own runnable package.

Skip this stage if `examples` is in `EXCLUDED_STAGES`.

---

## Step 0: Safely replace or retain examples

If this stage is running, clean only recognized generated use-case packages before creating replacements:

```bash
<PYTHON_CMD> <skill-root>/scripts/manage_examples.py cleanup "<EXAMPLE_DIR>"
```

The script recognizes only immediate child directories containing both `main.bal` and `Ballerina.toml`; it does not remove hand-authored files or directories. If cleanup reports any failure, **skip example generation entirely** and report the failures to avoid a mixed old/new set.

If `examples` is in `EXCLUDED_STAGES`, do not generate anything. Instead run `manage_examples.py scan "<EXAMPLE_DIR>"`, pack and push the current connector once, and run `bal build` plus the normal compilation fix procedure for each retained package. Report every retained package's result; unresolved packages are warnings, not a pipeline failure.

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
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py --cwd "<BALLERINA_DIR>" bal pack
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py --cwd "<BALLERINA_DIR>" bal push --repository=local
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

From `USE_CASE`, suggest a snake_case directory name:
- Exactly 3–4 words, lowercase with underscores
- Scenario-focused — no "example", "demo", "test", or raw operation names

Good: `sharepoint_tenant_configuration`, `admin_settings_update`
Bad: `get_sharepoint_example`, `getSharepoint_demo`

Store the raw suggestion as `SUGGESTED_EXAMPLE_NAME`, then normalize it and resolve collisions deterministically. Invoke the helper with an argument array so every value is passed as a separate argv element:

```text
[
  <PYTHON_CMD>,
  <skill-root>/scripts/example_names.py,
  resolve,
  <EXAMPLE_DIR>,
  SUGGESTED_EXAMPLE_NAME,
  example_<iteration-number>
]
```

Never interpolate `SUGGESTED_EXAMPLE_NAME` into shell source, including inside ordinary double quotes; shell metacharacters in an AI-generated suggestion must remain literal argument data. Parse the returned JSON and store `name` as `EXAMPLE_NAME`. Use this exact value for the directory, Ballerina package name, named documentation file, and aggregate documentation links. The helper converts arbitrary suggestions to snake_case and appends `_2`, `_3`, and so on when any existing filesystem entry already uses the name.

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
name = "<EXAMPLE_NAME>"
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
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py --cwd "<EXAMPLE_DIR>/<EXAMPLE_NAME>" bal build
```

- Exit 0 → clean
- Non-zero → invoke the **Fix Procedure** (`references/fix-procedure.md`) with `BUILD_DIR = <EXAMPLE_DIR>/<EXAMPLE_NAME>`

Compilation errors in examples are **non-fatal if fix fails** — warn the user and continue to the next example.

---

## Step 4: Stage completion

Print:
```
✓ Examples complete
  <NUM_EXAMPLES> example(s) generated:
    <EXAMPLE_DIR>/<name-1>/   (build: passed / needs manual review)
    <EXAMPLE_DIR>/<name-2>/   ...
```

If `INTERACTIVE_MODE` is true, pause and ask: "Proceed to Documentation? [Y/n/q]"
