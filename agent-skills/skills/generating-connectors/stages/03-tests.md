# Stage 03 — Tests

Generate the connector test suite including a mock server and a test file.

Skip this stage if `tests` is in `EXCLUDED_STAGES`.

---

## Step 1: Analyse the client

Run before generating anything — provides method signatures without reading client.bal inline:

```bash
<PYTHON_CMD> <skill-root>/scripts/analyze_client.py "<BALLERINA_DIR>/client.bal"
```

Store the JSON output as `CLIENT_ANALYSIS`. Fields used in this stage:
- `CLIENT_ANALYSIS.apiCount` — total number of operations
- `CLIENT_ANALYSIS.methods` — list of `{name, params, returnType}` objects
- `CLIENT_ANALYSIS.methodType` — `"remote"` or `"resource"`

---

## Step 1b: Operation count threshold

Parse operationIds from the aligned spec — these are the values `bal openapi --operations` requires:

```bash
<PYTHON_CMD> <skill-root>/scripts/parse_openapi_spec.py "<ALIGNED_SPEC>"
```

Store as `ALIGNED_SPEC_METADATA`. Extract the non-empty operationIds:
```
OPERATION_IDS = [p.operationId for p in ALIGNED_SPEC_METADATA.paths if p.operationId != ""]
```

> **Why re-parse the aligned spec**: Stage 01 may rename operationIds during AI-assisted enhancement. `SPEC_METADATA` from Stage 00 reflects the original spec and may be stale. The aligned spec is what `bal openapi` reads, so its operationIds are authoritative.

Compare `len(OPERATION_IDS)` against `MAX_OPERATIONS = 30`:

**If `len(OPERATION_IDS) <= 30`**: set `SELECTED_OPERATIONS = ""`. The full spec will be used for the mock stub.

**If `len(OPERATION_IDS) > 30`**: prompt the LLM with the full operationId list:

> Your response must be **ONLY a comma-separated list of operationIds with NO spaces** — no other text, no explanations.
> Select exactly 30 from the following list.
> Criteria: core CRUD, most frequently used, variety across resource types, search/discovery, lifecycle operations.
> OperationIds: `<OPERATION_IDS joined by comma>`

Example valid response: `getFile,listFiles,uploadFile,deleteFile,createFolder,...`

**Validate the response deterministically before using it.** Split it on `,` and re-prompt (repeat the prompt above) until all of these hold:
- exactly **30** entries, all **unique** (no duplicates, no empty entries),
- every id is a member of `OPERATION_IDS`,
- no surrounding whitespace, no code fences, no extra prose.

Only once valid, join the validated ids with `,` (no spaces) and store as `SELECTED_OPERATIONS`. Pass only this validated value to Step 2a's `generate_mock_stub.py` — never an unvalidated raw response.

> `CLIENT_ANALYSIS` (from Step 1) is still used in Steps 2b and 3 for `methodType`, `configType`, and method signatures. Only the operation count and selection source changes to the spec.

---

## Step 2: Generate the mock server stub

### 2a: Generate service stub from the spec

```bash
<PYTHON_CMD> <skill-root>/scripts/generate_mock_stub.py "<ALIGNED_SPEC>" "<BALLERINA_DIR>" "<SELECTED_OPERATIONS>" "<LICENSE_PATH>"
```

Pass `SELECTED_OPERATIONS` as the 3rd argument (empty string if not filtered) and `LICENSE_PATH` as the 4th argument (empty string if not set). The script appends `--operations` and `--license` only when the respective values are non-empty.

This runs `bal openapi -i <spec> --mode service -o tests/` — generating only a service stub (no client). It renames `aligned_ballerina_openapi_service.bal` → `mock_service.bal` and removes the generated `types.bal` and `client.bal` from `tests/` since root package types are already in scope.

### 2b: Complete the stub — LLM fills in mock responses

Read this file into context:
1. `<BALLERINA_DIR>/tests/mock_service.bal` — the generated stub (correct signatures, empty bodies)

Rewrite `mock_service.bal` completing every resource function body. The following rules are **all mandatory** — violations cause compilation failures:

**Output**: Raw Ballerina source code only. No conversational text, no explanations, no ` ```ballerina ` fences. Start with the first line of code and end with the last.

**Structural rules:**
- Preserve the copyright header from the stub exactly
- Keep `http:Listener ep0 = new (9090);` exactly as generated
- **DO NOT add a `public function init()` function** — the listener auto-starts when `bal test` runs; no init is needed or allowed
- Keep all resource function signatures exactly as generated — do not rename, reorder, or change parameter types
- **Fill every resource function body** — no empty bodies, no placeholder comments, no `panic`
  - If the success return type is a **data record** (e.g. `File|AnydataDefault`, `Folder|AnydataDefault`): return a fully populated mock record — never return `http:NO_CONTENT` for these
  - If the success return type is **`http:NoContent`** (DELETE or similar returning HTTP 204): return `http:NO_CONTENT` — this is the correct and only valid value
- Preserve all doc comments (`# ...`) above resource functions

**Import rules:**
- **Types are already in scope**: the mock service lives in `tests/` which shares the root package namespace with `types.bal` — all root types are directly available with no import
- The only allowed imports are `ballerina/http` and `ballerina/log` (and only if actually used)
- Do NOT add any other import statements

**Data rules:**
- Return realistic, believable mock data (not empty strings, not zeros, not `""`)
- Use Ballerina mapping constructor expressions: `{fieldName: value}` — NOT JSON-style string keys
- **`@jsondata:Name` annotations**: when a record field has `@jsondata:Name {value: "json_name"}`, use the **Ballerina identifier** (the line below the annotation), NOT the annotation string value
  - Wrong: `{"tweet_count": 42}` — will NOT compile
  - Correct: `{tweetCount: 42}` — uses the Ballerina field name
- **`Type|record {}` union fields (BCE2523)**: any field whose declared type contains `|record {}` requires an explicit type cast on any mapping constructor assigned to it
  - Wrong: `idleSessionSignOut: {isEnabled: true}` — BCE2523, ambiguous type
  - Correct: `idleSessionSignOut: <MicrosoftGraphIdleSessionSignOut>{isEnabled: true}`
  - This rule applies at every nesting level

---

## Step 3: Generate test suite

Write `<BALLERINA_DIR>/tests/test.bal`. Provide the LLM with:
- `BAL_ORG`, `BAL_PACKAGE`
- Full content of `tests/mock_service.bal` (the completed mock)
- The client's `init` method signature (from `CLIENT_ANALYSIS`)
- Referenced type definitions used in the init method
- Full `client.bal` content
- Full `types.bal` content
- `CLIENT_ANALYSIS.methodType` (`remote` or `resource`)

The following rules are **all mandatory**:

**Output**: Raw Ballerina source code only. No code fences. Start with the copyright header.

**Imports** (required):
```ballerina
import ballerina/os;
import ballerina/test;
```
The mock service lives in the same `tests/` package scope and auto-starts when `bal test` runs — no side-effect import is needed. Do NOT add `import ... mock.server as _;` or any import referencing the mock service.

**Environment setup**:
```ballerina
final boolean isLiveServer = os:getEnv("IS_LIVE_SERVER") == "true";
final string serviceUrl = isLiveServer ? "<real-api-base-url>" : "http://localhost:9090";
// Credentials as final vars from os:getEnv
final string token = isLiveServer ? os:getEnv("<CRED_ENV_VAR>") : "test_token";
```

**Client initialisation**: use the exact `init` method signature from `CLIENT_ANALYSIS`. Do not use a generic template — derive from the actual connector.

**Test functions**:
- One `@test:Config { groups: ["live_tests", "mock_tests"] }` function per endpoint in the mock server
- Method syntax:
  - Resource: `check client->/path/to/resource()`
  - Remote: `check client->methodName(param1, param2)`
- **Assertions**:
  - Single record response: `test:assertTrue(response?.data !is ());`
  - Array response: `test:assertTrue(response.data.length() > 0);`
  - Errors field: `test:assertTrue(response?.errors is ());`
  - No-body success (HTTP 202 etc.): declare result as `error?`, assert `test:assertTrue(response is ());`
- **`Type|record {}` union fields (BCE2523)**: same rule as mock server — any mapping constructor for a `Type|record {}` field must use an explicit type cast

---

## Step 4: Compile and fix

```bash
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py "bal build" "<BALLERINA_DIR>"
```

- Exit 0 → clean, continue
- Non-zero → invoke the **Fix Procedure** (`references/fix-procedure.md`) with `BUILD_DIR = <BALLERINA_DIR>`

---

## Step 5: Run tests

```bash
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py "bal test" "<BALLERINA_DIR>"
```

Test failures are **non-fatal** — record the result and continue. Print the test summary.

---

## Step 6: Stage completion

Print:
```
✓ Tests complete
  mock server: <BALLERINA_DIR>/tests/mock_service.bal
  test suite:  <BALLERINA_DIR>/tests/test.bal
  build:       passed (fixed in <N> iteration(s) / clean)
  test run:    <N passing, M failing / skipped>
```

If `INTERACTIVE_MODE` is true, pause and ask: "Proceed to Examples? [Y/n/q]"
