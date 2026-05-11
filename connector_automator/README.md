# Connector Automator

A comprehensive Ballerina-based CLI tool for automating the creation, enhancement, and documentation of Ballerina API connectors. This tool leverages AI (powered by Anthropic's Claude) to generate high-quality Ballerina client code, examples, tests, and documentation from either **OpenAPI specifications** or **Java SDK JARs**.

## Overview

The Connector Automator supports two distinct automation workflows:

| Workflow | Input | Use Case |
|----------|-------|----------|
| **OpenAPI** | OpenAPI specification (`.yaml` / `.json`) | Generate a Ballerina connector from an existing REST API spec |
| **SDK** | Java SDK JAR + optional Javadoc JAR (or Maven coordinates) | Generate a Ballerina connector wrapping a Java SDK |

Both workflows produce production-ready Ballerina connectors with typed clients, usage examples, test suites, and documentation.

### Key Features

- **OpenAPI Sanitization**: Flatten, align, and enhance OpenAPI specifications with AI-generated metadata
- **Ballerina Client Generation**: Create typed Ballerina clients from OpenAPI specs with proper conventions
- **Java SDK Analysis**: Parse Java SDK JARs and extract method/type metadata via Javadoc + bytecode analysis
- **IR Generation**: Convert Java SDK metadata into a structured Intermediate Representation (IR) for connector code generation
- **Connector Generation**: Generate Ballerina client + native Java adaptor from IR and API spec
- **Code Fixing**: AI-powered automatic resolution of compilation errors (Java native + Ballerina)
- **Example Generation**: AI-powered generation of realistic usage examples
- **Test Generation**: Comprehensive test suites — mock server tests (OpenAPI) or live integration tests (SDK)
- **Documentation Generation**: Complete README files for all components
- **Full Pipeline**: Execute the complete automation workflow end-to-end with a single command

## Prerequisites

- **Ballerina**: Version 2201.13.0 or later
- **Java**: JDK 17 or later (required for SDK workflow native compilation)
- **Gradle**: For building native Java adaptors (SDK workflow)
- **Anthropic API Key**: Required for all AI-powered features:
  ```bash
  export ANTHROPIC_API_KEY="your-api-key"
  ```

## Installation

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd connector-automator
   ```

2. Build the `sdkanalyzer` native package (requires `BALLERINA_HOME` or `BAL_HOME` to be set):
   ```bash
   cd modules/sdkanalyzer/native
   ./gradlew build
   cd ../../..
   ```

3. Build the package:
   ```bash
   bal build
   ```

## Usage

Run without arguments to see the top-level help:

```bash
bal run -- help
```

All commands follow the pattern:

```bash
bal run -- <workflow> <command> [arguments] [options]
```

Where `<workflow>` is either `sdk` or `openapi`.

---

## SDK Workflow

The SDK workflow converts a Java SDK into a Ballerina connector. It analyzes the SDK JAR to extract methods, types, and connection configuration, then generates Ballerina client code backed by a native Java adaptor.

### SDK Pipeline (End-to-End)

Run the complete SDK automation pipeline with a single command:

```bash
bal run -- sdk pipeline <dataset-key> <output-dir> [options]
```

**Arguments:**
- `<dataset-key>` — Identifies the SDK; must match JAR files in `test-jars/`:
  - `test-jars/<dataset-key>.jar` — SDK JAR
  - `test-jars/<dataset-key>-javadoc.jar` — Javadoc JAR
- `<output-dir>` — Root directory where all generated artifacts are written

**Options:**

| Option | Description |
|--------|-------------|
| `yes` | Auto-confirm continuation prompts |
| `quiet` | Minimal logging output |
| `--fix-code` | Run full code fixer phase (default: enabled) |
| `--fix-report-only` | Run fixer in diagnostics mode only |
| `--skip-fix` | Skip code fixing phase |
| `--skip-tests` | Skip test generation phase |
| `--skip-examples` | Skip example generation phase |
| `--skip-docs` | Skip documentation generation phase |
| `--fix-iterations=<n>` | Maximum fixer iterations (default: 3) |

**Example:**
```bash
bal run -- sdk pipeline s3-2.31.66 /home/user/connectors
bal run -- sdk pipeline s3-2.31.66 /home/user/connectors yes quiet --skip-tests
```

**Pipeline Steps:**
1. Analyze Java SDK → metadata JSON
2. Generate API Specification + IR JSON from metadata
3. Generate Ballerina connector (client, types, native adaptor)
4. Fix compilation errors (Java native + Ballerina)
5. Generate usage examples
6. Generate live integration tests
7. Generate documentation

### SDK Step-by-Step Commands

Run individual pipeline stages independently for finer control.

#### 1. Analyze Java SDK

Parse the SDK JAR and extract method/type metadata:

```bash
bal run -- sdk analyze <dataset-key> <output-dir> [options]
```

Accepts either a local dataset key (resolves to `test-jars/`) or a Maven coordinate:

```bash
# Local JAR (test-jars/s3-2.31.66.jar must exist)
bal run -- sdk analyze s3-2.31.66 /home/user/connectors

# Maven coordinate (downloads from Maven Central)
bal run -- sdk analyze software.amazon.awssdk:s3:2.31.66 /home/user/connectors
```

**Options:**

| Option | Description |
|--------|-------------|
| `quiet` | Minimal logging output |
| `--sources=<path>` | Path to sources JAR for enhanced analysis |
| `include-deprecated` | Include deprecated methods |
| `include-internal` | Include internal (non-public) methods |
| `include-non-public` | Include non-public classes |
| `exclude-packages=<pkg1,pkg2>` | Exclude specific Java packages |
| `include-packages=<pkg1,pkg2>` | Restrict analysis to specific packages |
| `max-depth=<n>` | Maximum dependency traversal depth |
| `methods-to-list=<n>` | Maximum number of methods to extract |

**Output:** `<output-dir>/docs/spec/<dataset-key>-metadata.json`

#### 2. Generate API Specification + IR

Convert analyzer metadata into an Intermediate Representation (IR) and Ballerina API spec:

```bash
bal run -- sdk generate <output-dir> [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `quiet` | Minimal logging output |
| `no-thinking` | Disable LLM extended thinking mode |

**Output:**
- `<output-dir>/docs/spec/<dataset-key>-ir.json`
- `<output-dir>/docs/spec/<dataset-key>_spec.bal`

#### 3. Generate Connector Artifacts

Generate the Ballerina client and native Java adaptor from IR + spec:

```bash
bal run -- sdk connector <output-dir> [options]
```

**Output:**
- `<output-dir>/ballerina/client.bal`
- `<output-dir>/ballerina/types.bal`
- `<output-dir>/native/` — Native Java adaptor with `build.gradle`

#### 4. Fix Code Errors

Run AI-powered code fixing on both the Java native adaptor and the Ballerina client:

```bash
bal run -- sdk fix-code <output-dir> [options]
bal run -- sdk fix-report-only <output-dir> [options]   # diagnostics only
```

**Options:**

| Option | Description |
|--------|-------------|
| `quiet` | Minimal logging output |
| `--fix-iterations=<n>` | Maximum fixer iterations (default: 3) |

#### 5. Generate Examples

Create AI-powered usage examples for the connector:

```bash
bal run -- sdk generate-examples <output-dir> [options]
```

**Output:** `<output-dir>/examples/`

#### 6. Generate Tests

Generate live integration tests for the connector:

```bash
bal run -- sdk generate-tests <output-dir> [options]
```

SDK tests use `@test:Config { enable: testsEnabled }` where `testsEnabled` gates on the presence of runtime credentials. There are no mock server tests for the SDK workflow — only live API tests.

**Output:** `<output-dir>/ballerina/tests/test.bal`

**Running tests:**
```bash
cd <output-dir>/ballerina && bal test
```

Set credentials before running live tests:
```bash
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
```

#### 7. Generate Documentation

Generate all README files for the connector:

```bash
bal run -- sdk generate-docs <output-dir> [options]
bal run -- sdk generate-all <output-dir> [options]    # shortcut for generate-all
```

### SDK Output Structure

```
<output-dir>/
├── docs/
│   └── spec/
│       ├── <dataset-key>-metadata.json    # Analyzer output
│       ├── <dataset-key>-ir.json          # Intermediate Representation
│       └── <dataset-key>_spec.bal         # API specification
├── ballerina/
│   ├── Ballerina.toml
│   ├── client.bal                         # Generated Ballerina client
│   ├── types.bal                          # Generated types
│   ├── README.md
│   └── tests/
│       ├── test.bal                       # Live integration tests
│       └── README.md
├── native/
│   ├── build.gradle                       # Native adaptor build file
│   └── src/main/java/...                  # Java native adaptor source
├── examples/
│   ├── README.md
│   ├── example-1/
│   │   ├── main.bal
│   │   ├── Ballerina.toml
│   │   └── README.md
│   └── example-2/
│       └── ...
└── README.md
```

---

## OpenAPI Workflow

The OpenAPI workflow generates a Ballerina connector from an OpenAPI specification. It sanitizes the spec, generates a typed Ballerina client, creates mock-server-backed tests, examples, and documentation.

### OpenAPI Pipeline (End-to-End)

Run the complete OpenAPI automation pipeline:

```bash
bal run -- openapi pipeline <spec> <output-dir> [options]
```

**Arguments:**
- `<spec>` — Path to the OpenAPI specification (`.yaml` or `.json`)
- `<output-dir>` — Root directory for generated artifacts

**Options:**

| Option | Description |
|--------|-------------|
| `yes` | Auto-confirm all prompts |
| `quiet` | Minimal logging output |

**Example:**
```bash
bal run -- openapi pipeline ./openapi.yaml ./my-connector yes
bal run -- openapi pipeline ./openapi.yaml ./my-connector yes quiet
```

**Pipeline Steps:**
1. Sanitize OpenAPI specification
2. Generate Ballerina client
3. Build and validate client
4. Generate usage examples
5. Generate mock server + live tests
6. Generate documentation

### OpenAPI Step-by-Step Commands

#### 1. Sanitize OpenAPI Specification

Flatten, align, and enhance an OpenAPI specification with AI-generated metadata:

```bash
bal run -- openapi sanitize <spec> <output-dir> [options]
```

**What it does:**
- Flattens nested `$ref` references
- Aligns with Ballerina naming conventions
- Generates missing `operationId` values using AI
- Renames generic `InlineResponse` schemas to meaningful names
- Adds missing field descriptions

**Output:**
- `<output-dir>/docs/spec/flattened_openapi.json`
- `<output-dir>/docs/spec/aligned_ballerina_openapi.json`

#### 2. Generate Ballerina Client

Create a Ballerina client from a (sanitized) OpenAPI specification:

```bash
bal run -- openapi generate-client <spec> <output-dir> [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `yes` | Auto-confirm all prompts |
| `quiet` | Minimal logging output |
| `remote-methods` | Use remote methods |
| `resource-methods` | Use resource methods (default) |
| `license=<path>` | License file path for copyright header |
| `tags=<tag1,tag2>` | Filter operations by tags |
| `operations=<op1,op2>` | Generate specific operations only |

**Example:**
```bash
bal run -- openapi generate-client ./aligned_openapi.json ./client resource-methods
```

#### 3. Fix Code Errors

AI-powered resolution of compilation errors in the generated Ballerina client:

```bash
bal run -- openapi fix-code <connector-path> [options]
```

#### 4. Generate Tests

Generate a mock server module and comprehensive test suite:

```bash
bal run -- openapi generate-tests <connector-path> <spec-path> [options]
```

OpenAPI tests include both mock-server tests and live server tests using `@test:Config { groups: ["live_tests", "mock_tests"] }`. Use `IS_LIVE_SERVER=true` to run against the real API.

**Output:**
- `<connector-path>/ballerina/modules/mock.server/mock_server.bal`
- `<connector-path>/ballerina/modules/mock.server/types.bal`
- `<connector-path>/ballerina/tests/test.bal`

**Running tests:**
```bash
cd <connector-path>/ballerina && bal test                           # mock tests
IS_LIVE_SERVER=true bal test --groups live_tests                    # live tests
```

#### 5. Generate Examples

Create usage examples for the connector:

```bash
bal run -- openapi generate-examples <connector-path> [options]
```

**Output:** `<connector-path>/examples/`

#### 6. Generate Documentation

Create README files for all components:

```bash
bal run -- openapi generate-docs <doc-command> <connector-path> [options]
```

**Doc commands:**

| Command | Description |
|---------|-------------|
| `generate-all` | Generate all READMEs |
| `generate-ballerina` | Generate module README |
| `generate-tests` | Generate tests README |
| `generate-examples` | Generate examples README |
| `generate-individual-examples` | Generate README for each example |
| `generate-main` | Generate root README |

**Example:**
```bash
bal run -- openapi generate-docs generate-all ./my-connector yes
```

### OpenAPI Output Structure

```
<output-dir>/
├── README.md
├── docs/
│   └── spec/
│       ├── flattened_openapi.json
│       └── aligned_ballerina_openapi.json
├── ballerina/
│   ├── Ballerina.toml
│   ├── client.bal
│   ├── types.bal
│   ├── utils.bal
│   ├── README.md
│   ├── tests/
│   │   ├── test.bal
│   │   └── README.md
│   └── modules/
│       └── mock.server/
│           ├── mock_server.bal
│           └── types.bal
└── examples/
    ├── README.md
    ├── example-1/
    │   ├── main.bal
    │   ├── Ballerina.toml
    │   └── README.md
    └── example-2/
        └── ...
```

---

## Legacy / Low-Level Commands

The following commands operate directly on dataset keys and the internal directory layout. They are preserved for compatibility and fine-grained control. Prefer `sdk <command>` for new workflows.

| Command | Description |
|---------|-------------|
| `bal run -- analyze <dataset-key> <output-dir>` | Analyze SDK JAR (same as `sdk analyze`) |
| `bal run -- generate <output-dir>` | Generate IR + spec (same as `sdk generate`) |
| `bal run -- connector <dataset-key> <output-dir>` | Generate connector (same as `sdk connector`) |
| `bal run -- fix-code <dataset-key> <output-dir>` | Fix code errors (same as `sdk fix-code`) |
| `bal run -- fix-report-only <dataset-key> <output-dir>` | Fix report only (same as `sdk fix-report-only`) |
| `bal run -- pipeline <dataset-key> <output-dir>` | Full pipeline (same as `sdk pipeline`) |
| `bal run -- generate-tests <dataset-key> <output-dir>` | Generate tests (same as `sdk generate-tests`) |
| `bal run -- generate-examples <dataset-key> <output-dir>` | Generate examples (same as `sdk generate-examples`) |
| `bal run -- generate-docs <doc-command> <dataset-key> <output-dir>` | Generate docs (same as `sdk generate-docs`) |

---

## Module Architecture

| Module | Description |
|--------|-------------|
| `sdkanalyzer` | Java SDK JAR parsing, Javadoc extraction, Maven resolution, metadata output |
| `api_specification_generator` | Converts SDK metadata → IR JSON → Ballerina API spec |
| `connector_generator` | Generates Ballerina client + native Java adaptor from IR and spec |
| `sanitizor` | OpenAPI specification processing and AI enhancement |
| `client_generator` | Ballerina client generation from OpenAPI specs |
| `code_fixer` | AI-powered Java native + Ballerina compilation error resolution |
| `example_generator` | AI-powered usage example creation |
| `test_generator` | Test suite generation — mock server (OpenAPI) or live integration (SDK) |
| `document_generator` | README and documentation generation |
| `utils` | Shared utilities, AI service, token usage tracking, command execution |

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `ANTHROPIC_API_KEY` | **Required** for all AI-powered features |
| `IS_LIVE_SERVER` | Set to `true` to run live API tests (OpenAPI workflow) |

---

## Global Options

Both `sdk` and `openapi` workflows support these options on all commands:

| Option | Description |
|--------|-------------|
| `yes` | Auto-confirm all prompts (CI/CD friendly) |
| `quiet` | Minimal logging output |

---

## Troubleshooting

**API Key not configured**
```
✗ ANTHROPIC_API_KEY not configured
```
Set the `ANTHROPIC_API_KEY` environment variable before running.

**Build failures after generation**
```bash
bal run -- sdk fix-code <output-dir>
# or for OpenAPI:
bal run -- openapi fix-code <connector-path>/ballerina
```

**Large specs / SDKs take too long**
- Operations are automatically filtered to the most useful subset when the operation count exceeds the configured threshold.
- Use `--skip-tests`, `--skip-examples`, or `--skip-docs` to limit what the pipeline generates.
- Use `tags=` or `operations=` options (OpenAPI) to restrict client generation scope.

**SDK JAR not found**
Ensure both files exist before running `analyze` or `pipeline`:
```
test-jars/<dataset-key>.jar
test-jars/<dataset-key>-javadoc.jar
```
Or pass a Maven coordinate directly: `software.amazon.awssdk:s3:2.31.66`

---

## License

This project is licensed under the Apache License 2.0. See the [LICENSE](../LICENSE) file for details.
