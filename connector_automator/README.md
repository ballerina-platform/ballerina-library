# Connector Automator

A comprehensive Ballerina-based CLI tool for automating the creation, enhancement, and documentation of Ballerina API connectors. This tool leverages AI (powered by Anthropic's Claude) to generate high-quality Ballerina client code, examples, tests, and documentation from OpenAPI specifications.

## Overview

The Connector Automator provides an end-to-end pipeline for generating production-ready Ballerina connectors from OpenAPI specifications. It supports both interactive and command-line modes, making it suitable for both manual development workflows and CI/CD automation.

### Key Features

- **OpenAPI Sanitization**: Flatten, align, and enhance OpenAPI specifications with AI-generated metadata
- **Ballerina Client Generation**: Create typed Ballerina clients from OpenAPI specs with proper conventions
- **Example Generation**: AI-powered generation of realistic usage examples
- **Test Generation**: Comprehensive test suites with mock servers
- **Documentation Generation**: Complete README files for all components
- **Code Fixing**: AI-powered automatic resolution of compilation errors
- **Full Pipeline**: Execute the complete automation workflow with a single command

## Prerequisites

- **Ballerina**: Version 2201.13.0 or later
- **Anthropic API Key**: Required for AI-powered features. Set the environment variable:
  ```bash
  export ANTHROPIC_API_KEY="your-api-key"
  ```

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/ballerina-platform/ballerina-library.git
   cd ballerina-library/connector_automator
   ```

2. Build the package:
   ```bash
   bal build
   ```

## Usage

### Interactive Mode

Run without arguments to enter interactive mode:

```bash
bal run
```

This presents a menu-driven interface with options for each automation step.

### Command-Line Mode

Execute specific commands directly:

```bash
bal run -- <command> [arguments] [options]
```

### Available Commands

#### 1. Sanitize OpenAPI Specification

Flatten, align, and enhance an OpenAPI specification with AI-generated metadata:

```bash
bal run -- sanitize <spec> <output-dir> [yes] [quiet]
```

**Example:**
```bash
bal run -- sanitize ./openapi.yaml ./output yes
```

**What it does:**
- Flattens nested OpenAPI references
- Aligns with Ballerina conventions
- Generates missing operationIds using AI
- Renames generic InlineResponse schemas to meaningful names
- Adds missing field descriptions

#### 2. Generate Ballerina Client

Create a Ballerina client from an OpenAPI specification:

```bash
bal run -- generate-client <spec> <output-dir> [options]
```

**Options:**
- `yes` - Auto-confirm all prompts
- `quiet` - Minimal logging output
- `remote-methods` - Use remote methods (default: resource methods)
- `resource-methods` - Use resource methods (default)
- `license=<path>` - License file path for copyright header
- `tags=<tag1,tag2>` - Filter operations by tags
- `operations=<op1,op2>` - Generate specific operations only

**Example:**
```bash
bal run -- generate-client ./spec.json ./client resource-methods license=./license.txt
```

#### 3. Generate Examples

Create usage examples for a connector:

```bash
bal run -- generate-examples <connector-path> [yes] [quiet]
```

**Example:**
```bash
bal run -- generate-examples ./connector yes
```

**What it does:**
- Analyzes connector APIs
- Generates AI-powered use cases
- Creates complete Ballerina example projects
- Automatically fixes compilation errors

#### 4. Generate Tests

Generate comprehensive tests with mock servers:

```bash
bal run -- generate-tests <connector-path> <spec> [yes] [quiet]
```

**Example:**
```bash
bal run -- generate-tests ./connector ./spec.yaml yes
```

**What it does:**
- Creates a mock server module
- Generates AI-powered mock responses
- Creates comprehensive test cases
- Supports both live and mock test modes

#### 5. Generate Documentation

Create README files for all components:

```bash
bal run -- generate-docs <command> <connector-path> [yes] [quiet]
```

**Commands:**
- `generate-all` - Generate all READMEs
- `generate-ballerina` - Generate module README
- `generate-tests` - Generate tests README
- `generate-examples` - Generate examples README
- `generate-individual-examples` - Generate README for each example
- `generate-main` - Generate root README

**Example:**
```bash
bal run -- generate-docs generate-all ./connector yes
```

#### 6. Fix Code Errors

AI-powered resolution of compilation errors:

```bash
bal run -- fix-code <project-path> [yes] [quiet]
```

**Example:**
```bash
bal run -- fix-code ./ballerina-project yes
```

**What it does:**
- Analyzes compilation errors
- Generates AI-powered fixes
- Applies fixes with confirmation
- Iterates until resolved

#### 7. Full Pipeline

Execute the complete automation workflow:

```bash
bal run -- pipeline <spec> <output-dir> [yes] [quiet]
```

**Example:**
```bash
bal run -- pipeline ./openapi.yaml ./output yes quiet
```

**Pipeline Steps:**
1. Sanitize OpenAPI specification
2. Generate Ballerina client
3. Build and validate client
4. Generate examples
5. Generate tests
6. Generate documentation

### Global Options

- `yes` - Auto-confirm all prompts (CI/CD friendly)
- `quiet` - Minimal logging output

## Module Architecture

The package is organized into the following modules:

| Module | Description |
|--------|-------------|
| `sanitizor` | OpenAPI specification processing and AI enhancement |
| `client_generator` | Ballerina client code generation |
| `example_generator` | AI-powered usage example creation |
| `test_generator` | Test suite and mock server generation |
| `doc_generator` | README and documentation generation |
| `code_fixer` | AI-powered compilation error resolution |
| `utils` | Shared utilities, AI service, and command execution |

## Configuration

### Config.toml

Create a `Config.toml` file for default configuration:

```toml
# AI Service Configuration
[connector_automator.utils]
apiKey = "your-anthropic-api-key"

# Code Fixer Configuration
[connector_automator.code_fixer]
maxIterations = 5

# Client Generator Options
[connector_automator.client_generator.options]
license = "docs/license.txt"
clientMethod = "resource"

# Retry Configuration for Sanitizer
[connector_automator.sanitizor]
maxRetries = 3
initialDelaySeconds = 1.0
maxDelaySeconds = 60.0
backoffMultiplier = 2.0
jitter = true
```

### Environment Variables

| Variable | Description |
|----------|-------------|
| `ANTHROPIC_API_KEY` | Required for AI-powered features |
| `IS_LIVE_SERVER` | Set to `true` for live API testing |

## Output Structure

After running the full pipeline, the output directory contains:

```
output/
├── README.md                    # Root documentation
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

## Best Practices

1. **Always run sanitization first**: The sanitizer improves OpenAPI specs for better code generation
2. **Review AI-generated content**: AI output requires human review for accuracy
3. **Use quiet mode for CI/CD**: Combine `yes` and `quiet` for automated pipelines
4. **Check generated tests**: Verify mock data matches expected API responses
5. **Customize examples**: AI-generated examples provide a starting point for customization

## Troubleshooting

### Common Issues

**API Key not configured**
```
⚠  ANTHROPIC_API_KEY not configured
```
Set the `ANTHROPIC_API_KEY` environment variable.

**Build failures after generation**
```bash
bal run -- fix-code ./ballerina yes
```

**Large specs take too long**
- Operations are automatically filtered to the most useful subset
- Use `tags` or `operations` options to limit scope

## License

This project is licensed under the Apache License 2.0. See the [LICENSE](../LICENSE) file for details.

## Contributing

See the [CONTRIBUTING.md](../CONTRIBUTING.md) file for contribution guidelines.
