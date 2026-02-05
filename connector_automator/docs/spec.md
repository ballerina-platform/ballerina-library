# Connector Automator - Technical Specification

This document provides comprehensive implementation details for the Connector Automator package, describing the architecture, module internals, algorithms, and integration patterns.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Module Specifications](#module-specifications)
   - [Main Entry Point](#main-entry-point)
   - [Sanitizor Module](#sanitizor-module)
   - [Client Generator Module](#client-generator-module)
   - [Example Generator Module](#example-generator-module)
   - [Test Generator Module](#test-generator-module)
   - [Doc Generator Module](#doc-generator-module)
   - [Code Fixer Module](#code-fixer-module)
   - [Utils Module](#utils-module)
3. [AI Integration](#ai-integration)
4. [Error Handling](#error-handling)
5. [Configuration Management](#configuration-management)
6. [Data Types](#data-types)

---

## Architecture Overview

The Connector Automator follows a modular architecture where each module handles a specific aspect of connector automation. All modules share common utilities through the `utils` module and leverage AI capabilities via Anthropic's Claude model.

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                           main.bal                               │
│  ┌─────────────┐ ┌──────────────┐ ┌─────────────┐               │
│  │Interactive  │ │Command-Line  │ │ Full        │               │
│  │Mode         │ │Mode          │ │ Pipeline    │               │
│  └──────┬──────┘ └──────┬───────┘ └──────┬──────┘               │
└─────────┼───────────────┼────────────────┼──────────────────────┘
          │               │                │
          ▼               ▼                ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Module Layer                              │
│  ┌───────────┐ ┌──────────────────┐ ┌───────────────────────┐   │
│  │sanitizor  │ │client_generator  │ │example_generator      │   │
│  └───────────┘ └──────────────────┘ └───────────────────────┘   │
│  ┌───────────────────┐ ┌───────────────────┐ ┌──────────────┐   │
│  │test_generator     │ │doc_generator      │ │code_fixer    │   │
│  └───────────────────┘ └───────────────────┘ └──────────────┘   │
└─────────────────────────────────────────────────────────────────┘
          │               │                │
          ▼               ▼                ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Utils Module                              │
│  ┌───────────────┐ ┌────────────────────┐ ┌─────────────────┐   │
│  │AI Service     │ │Command Executor    │ │Formatting       │   │
│  │(Anthropic)    │ │(bal commands)      │ │(Output utils)   │   │
│  └───────────────┘ └────────────────────┘ └─────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Execution Flow

1. **Entry Point**: `main.bal` handles CLI parsing and mode selection
2. **Interactive Mode**: Menu-driven interface for step-by-step execution
3. **Command-Line Mode**: Direct command execution for automation
4. **Full Pipeline**: Orchestrates all modules in sequence

---

## Module Specifications

### Main Entry Point

**File**: `main.bal`

The main module serves as the entry point and provides two operational modes:

#### Interactive Mode

Triggered when no arguments are provided. Displays a menu with options:

```
1. Sanitize OpenAPI Specification
2. Generate Ballerina Client
3. Generate Examples
4. Generate Test Cases
5. Generate Documentation
6. Fix Code Errors
7. Full Pipeline
8. Help & Usage
9. Exit
```

Each option collects necessary inputs interactively and delegates to the appropriate module.

#### Command-Line Mode

Triggered when arguments are provided. Supports the following commands:

| Command | Handler Function | Module |
|---------|-----------------|--------|
| `sanitize` | `sanitizor:executeSanitizor` | sanitizor |
| `generate-client` | `client_generator:executeClientGen` | client_generator |
| `generate-examples` | `example_generator:executeExampleGen` | example_generator |
| `generate-tests` | `test_generator:executeTestGen` | test_generator |
| `generate-docs` | `doc_generator:executeDocGen` | doc_generator |
| `fix-code` | `code_fixer:executeCodeFixer` | code_fixer |
| `pipeline` | `runFullPipeline` | main |

#### Full Pipeline Implementation

The `runFullPipeline` function orchestrates all modules:

```ballerina
function runFullPipeline(string... args) returns error? {
    // Step 1: Sanitize OpenAPI spec
    // Step 2: Generate Ballerina client
    // Step 3: Build and validate client
    // Step 4: Generate examples
    // Step 5: Generate tests
    // Step 6: Generate documentation
}
```

The pipeline continues on non-critical failures and reports a comprehensive summary at completion.

---

### Sanitizor Module

**Location**: `modules/sanitizor/`

The sanitizor module processes OpenAPI specifications to prepare them for Ballerina client generation.

#### Files

| File | Purpose |
|------|---------|
| `execute.bal` | Main entry point and workflow orchestration |
| `types.bal` | Type definitions for LLM requests/responses |
| `spec_analyzer.bal` | OpenAPI specification parsing and analysis |
| `spec_updater.bal` | Specification modification utilities |
| `ai_generator.bal` | AI prompt construction and response parsing |
| `batch_processor.bal` | Batch processing with retry logic |
| `retry_manager.bal` | Exponential backoff implementation |
| `validation_utils.bal` | Input validation helpers |
| `llm_service.bal` | LLM service initialization |

#### Processing Pipeline

1. **Flatten** (`bal openapi flatten`)
   - Resolves all `$ref` references
   - Creates a single-file specification

2. **Align** (`bal openapi align`)
   - Applies Ballerina naming conventions
   - Adjusts schema structures for optimal code generation

3. **YAML to JSON Conversion**
   - If input is YAML/YML, converts aligned spec to JSON
   - Uses `ballerina/yaml` module for parsing

4. **AI-Powered OperationId Generation**
   - Identifies operations without `operationId`
   - Generates meaningful camelCase identifiers using AI
   - Batch processing with configurable batch size (default: 15)

5. **AI-Powered Schema Renaming**
   - Finds generic `InlineResponse*` schemas
   - Generates descriptive PascalCase names
   - Updates all `$ref` references throughout the spec

6. **AI-Powered Description Enhancement**
   - Identifies fields/parameters missing descriptions
   - Generates contextual descriptions using AI
   - Supports fields, parameters, and operation descriptions

#### Key Types

```ballerina
public type LLMServiceError distinct error;

public type DescriptionRequest record {
    string id;
    string name;
    string context;
    string schemaPath;
};

public type SchemaRenameRequest record {
    string originalName;
    string schemaDefinition;
    string usageContext;
};

public type OperationIdRequest record {
    string id;
    string path;
    string method;
    string summary?;
    string description?;
    string[] tags?;
};

public type RetryConfig record {
    int maxRetries = 3;
    decimal initialDelaySeconds = 1.0;
    decimal maxDelaySeconds = 60.0;
    decimal backoffMultiplier = 2.0;
    boolean jitter = true;
};
```

#### Retry Logic

The retry manager implements exponential backoff with jitter:

```ballerina
public function calculateBackoffDelay(int attempt, RetryConfig config) returns decimal {
    decimal delay = config.initialDelaySeconds;
    
    // Exponential backoff
    int i = 0;
    while i < attempt {
        delay = delay * config.backoffMultiplier;
        i += 1;
    }
    
    // Cap at maximum
    if delay > config.maxDelaySeconds {
        delay = config.maxDelaySeconds;
    }
    
    // Add jitter to prevent thundering herd
    if config.jitter {
        decimal jitterRange = delay * 0.25d;
        decimal randomValue = <decimal>(attempt % 100) / 100.0d;
        decimal randomJitter = (randomValue * jitterRange * 2.0d) - jitterRange;
        delay = delay + randomJitter;
    }
    
    return delay;
}
```

---

### Client Generator Module

**Location**: `modules/client_generator/`

Generates Ballerina client code from OpenAPI specifications using the Ballerina OpenAPI tool.

#### Files

| File | Purpose |
|------|---------|
| `execute.bal` | Entry point and user interaction |
| `types.bal` | Configuration types |
| `command_executor.bal` | OpenAPI tool command execution |

#### Configuration Types

```ballerina
public type OpenAPIToolOptions record {|
    string license = "docs/license.txt";
    string[] tags?;
    string[] operations?;
    "resource"|"remote" clientMethod = "resource";
|};

public type ClientGeneratorConfig record {|
    boolean autoYes = false;
    boolean quietMode = false;
    OpenAPIToolOptions? toolOptions = ();
|};
```

#### Generated Command

The module constructs a `bal openapi` command with appropriate options:

```bash
bal openapi -i <spec> --mode client -o <output> \
    --license <license-file> \
    --tags <tag1,tag2> \
    --operations <op1,op2> \
    --client-methods <resource|remote>
```

#### Output Structure

```
<output-dir>/
├── client.bal      # Generated client with methods
├── types.bal       # Type definitions from schemas
└── utils.bal       # Utility functions
```

---

### Example Generator Module

**Location**: `modules/example_generator/`

Generates usage examples using AI to create realistic, educational code.

#### Files

| File | Purpose |
|------|---------|
| `execute.bal` | Main workflow and orchestration |
| `types.bal` | ConnectorDetails type |
| `analyzer.bal` | Connector code analysis |
| `ai_generator.bal` | AI service calls |
| `prompts.bal` | Prompt templates |

#### Workflow

1. **Connector Analysis**
   - Parse `client.bal` to extract function signatures
   - Read `types.bal` for type information
   - Count API operations to determine example count

2. **Example Count Determination**
   ```ballerina
   public function numberOfExamples(int apiCount) returns int {
       if apiCount < 15 {
           return 1;
       } else if apiCount <= 30 {
           return 2;
       } else if apiCount <= 60 {
           return 3;
       } else {
           return 4;
       }
   }
   ```

3. **Use Case Generation**
   - AI generates realistic use cases
   - Tracks previously used functions to ensure variety
   - Returns JSON with `useCase` and `requiredFunctions`

4. **Context Extraction**
   - Extracts targeted function signatures
   - Identifies dependent types
   - Limits context size for token efficiency

5. **Code Generation**
   - AI generates complete, compilable example code
   - Includes proper imports and error handling

6. **Project Creation**
   - Creates example directory structure
   - Generates `Ballerina.toml` with local dependency
   - Writes `main.bal` with generated code

7. **Compilation Fix**
   - Runs code fixer to resolve any compilation errors

#### ConnectorDetails Type

```ballerina
public type ConnectorDetails record {|
    string connectorName;
    int apiCount;
    string clientBalContent;
    string typesBalContent;
    string functionSignatures;
    string typeNames;
|};
```

---

### Test Generator Module

**Location**: `modules/test_generator/`

Generates comprehensive test suites with mock servers.

#### Files

| File | Purpose |
|------|---------|
| `execute.bal` | Main workflow |
| `types.bal` | ConnectorAnalysis type |
| `ai_generator.bal` | Test and mock generation |
| `mock_service_generator.bal` | Mock server setup |
| `connector_analyzer.bal` | Client analysis |
| `prompts.bal` | Prompt templates |

#### Workflow

1. **Mock Server Module Setup**
   ```bash
   bal add mock.server
   ```
   - Creates module structure
   - Removes auto-generated test directory

2. **Mock Server Generation**
   - Uses `bal openapi` to generate service template
   - For large specs (>30 operations), AI selects most useful operations

3. **Mock Server Completion**
   - AI fills in resource function bodies
   - Generates realistic mock response data
   - Ensures type correctness

4. **Test File Generation**
   - Analyzes client init method signature
   - Generates test functions for each operation
   - Supports both resource and remote method styles
   - Includes proper assertions and test groups

5. **Compilation Fix**
   - Applies code fixer to resolve errors

#### ConnectorAnalysis Type

```ballerina
public type ConnectorAnalysis record {
    string packageName;
    string mockServerContent;
    string initMethodSignature;
    string referencedTypeDefinitions;
    "resource"|"remote" methodType = "resource";
    string remoteMethodSignatures = "";
};
```

#### Test Structure

Generated tests support dual-mode execution:

```ballerina
configurable boolean isLiveServer = os:getEnv("IS_LIVE_SERVER") == "true";
configurable string token = isLiveServer ? os:getEnv("API_TOKEN") : "test_token";
configurable string serviceUrl = isLiveServer ? "https://api.example.com" : "http://localhost:9090";

@test:Config {
    groups: ["live_tests", "mock_tests"]
}
isolated function testGetResource() returns error? {
    // Test implementation
}
```

---

### Doc Generator Module

**Location**: `modules/doc_generator/`

Generates comprehensive documentation using templates and AI.

#### Files

| File | Purpose |
|------|---------|
| `execute.bal` | Command routing and workflow |
| `types.bal` | Metadata and template types |
| `ai_generator.bal` | Template processing and AI calls |
| `connector_analyzer.bal` | Connector metadata extraction |
| `prompts.bal` | Documentation prompts |
| `template_engine.bal` | Template data type |
| `templates/` | Markdown template files |

#### Documentation Types

1. **Ballerina Module README** (`ballerina/README.md`)
   - Overview, setup, quickstart, examples

2. **Tests README** (`tests/README.md`)
   - Testing approach, environment setup

3. **Examples README** (`examples/README.md`)
   - Example catalog and descriptions

4. **Individual Example READMEs** (`examples/*/README.md`)
   - Specific example documentation

5. **Main README** (`README.md`)
   - Root documentation with badges

#### Template System

Templates use `{{PLACEHOLDER}}` syntax:

```markdown
# {{CONNECTOR_NAME}} Connector

{{AI_GENERATED_OVERVIEW}}

## Setup

{{AI_GENERATED_SETUP}}
```

#### TemplateData Type

```ballerina
public type TemplateData record {|
    string CONNECTOR_NAME?;
    string VERSION?;
    string DESCRIPTION?;
    string AI_GENERATED_OVERVIEW?;
    string AI_GENERATED_SETUP?;
    string AI_GENERATED_QUICKSTART?;
    string AI_GENERATED_EXAMPLES?;
    string AI_GENERATED_USAGE?;
    string AI_GENERATED_TESTING_APPROACH?;
    string AI_GENERATED_TEST_SCENARIOS?;
    string AI_GENERATED_EXAMPLE_DESCRIPTIONS?;
    string AI_GENERATED_GETTING_STARTED?;
    string AI_GENERATED_HEADER_AND_BADGES?;
    string AI_GENERATED_USEFUL_LINKS?;
    string AI_GENERATED_INDIVIDUAL_README?;
    string AI_GENERATED_MAIN_EXAMPLES_README?;
|};
```

---

### Code Fixer Module

**Location**: `modules/code_fixer/`

AI-powered automatic resolution of Ballerina compilation errors.

#### Files

| File | Purpose |
|------|---------|
| `execute.bal` | CLI entry point |
| `code_fixer.bal` | Fix logic and iteration |
| `types.bal` | Error and result types |
| `prompts.bal` | Fix prompt generation |

#### Fix Algorithm

```
1. Build project
2. If build succeeds → Done
3. Parse compilation errors
4. Group errors by file
5. For each file with errors:
   a. Read file content
   b. Generate fix prompt
   c. Call AI for fix
   d. If user confirms (or autoYes):
      - Create backup
      - Apply fix
6. If no fixes applied → Stop
7. Repeat from step 1 (max iterations)
8. Final build check and summary
```

#### Key Types

```ballerina
public type FixResult record {|
    boolean success;
    int errorsFixed;
    int errorsRemaining;
    string[] appliedFixes;
    string[] remainingFixes;
|};

public type CompilationError record {|
    string filePath;
    int line;
    int column;
    string message;
    string severity;
    string code?;
|};

public type FixResponse record {|
    boolean success;
    string fixedCode;
    string explanation;
|};
```

#### Error Parsing

Compilation errors are parsed from `bal build` stderr:

```
ERROR [file.bal:(10:5,10:20)] undefined symbol 'xyz'
       │        │       │           │
       │        │       │           └── Error message
       │        │       └── End position (line:col)
       │        └── Start position (line:col)
       └── File path
```

---

### Utils Module

**Location**: `modules/utils/`

Shared utilities used across all modules.

#### Files

| File | Purpose |
|------|---------|
| `ai_service.bal` | AI (Anthropic) integration |
| `command_executor.bal` | Shell command execution |
| `formatting.bal` | Output formatting helpers |
| `types.bal` | Shared type definitions |

#### AI Service

Provides centralized AI capabilities:

```ballerina
public function initAIService(boolean quietMode = false) returns error? {
    ai:ModelProvider|error modelProvider = new anthropic:ModelProvider(
        apiKey,
        anthropic:CLAUDE_SONNET_4_20250514,
        maxTokens = 64000,
        timeout = 400
    );
    // ...
}

public function callAI(string prompt) returns string|error {
    // Send prompt to Claude and return response
}

public function isAIServiceInitialized() returns boolean {
    return anthropicModel !is ();
}
```

#### Command Executor

Executes shell commands with output capture:

```ballerina
public function executeCommand(string command, string workingDir, boolean quietMode = false) 
    returns CommandResult {
    // Creates temp files for stdout/stderr
    // Executes via sh -c
    // Parses compilation errors from output
    // Returns structured result
}
```

Specialized command functions:
- `executeBalFlatten(inputPath, outputPath)`
- `executeBalAlign(inputPath, outputPath)`
- `executeBalClientGenerate(inputPath, outputPath)`
- `executeBalBuild(projectPath, quietMode)`

#### CommandResult Type

```ballerina
public type CommandResult record {|
    string command;
    boolean success;
    int exitCode;
    string stdout;
    string stderr;
    CmdCompilationError[] compilationErrors;
    decimal executionTime;
|};

public type CmdCompilationError record {|
    string fileName;
    int line;
    int column;
    string message;
    string errorType;
    string filePath?;
|};
```

---

## AI Integration

### Model Configuration

The tool uses Anthropic's Claude Sonnet model:

- **Model**: `claude-sonnet-4-20250514`
- **Max Tokens**: 64,000
- **Timeout**: 400 seconds

### Prompt Engineering

All AI prompts follow a structured format:

1. **Role Definition**: Expert role (e.g., "Ballerina developer")
2. **Context Section**: Relevant code/data
3. **Reflection Phase**: Analysis steps for AI to follow
4. **Requirements**: Specific constraints and rules
5. **Output Format**: Expected response structure

### Response Handling

JSON responses are parsed and validated:

```ballerina
string|error response = utils:callAI(prompt);
if response is error {
    return error LLMServiceError("AI generation failed", response);
}

json|error jsonResult = response.fromJsonString();
// Validate and extract structured data
```

### Rate Limiting

The retry manager handles rate limits with exponential backoff:

- Initial delay: 1 second
- Max delay: 60 seconds
- Backoff multiplier: 2x
- Jitter: ±25% randomization

---

## Error Handling

### Error Types

Each module defines distinct error types:

```ballerina
public type LLMServiceError distinct error;      // sanitizor
public type CommandExecutorError distinct error;  // utils
public type BallerinaFixerError error;            // code_fixer
```

### Error Propagation

Errors propagate using Ballerina's `check` expression:

```ballerina
public function processSpec(string path) returns error? {
    json specJson = check io:fileReadJson(path);
    string aiResult = check utils:callAI(prompt);
    check io:fileWriteString(outputPath, result);
}
```

### User-Facing Errors

Interactive operations display user-friendly error messages:

```ballerina
if result is error {
    io:println(string `✗ Operation failed: ${result.message()}`);
    
    if !getUserConfirmation("Continue despite failure?", autoYes) {
        return result;
    }
}
```

---

## Configuration Management

### Configurable Variables

Modules use Ballerina's configurable syntax:

```ballerina
// API key from environment or Config.toml
configurable string apiKey = ?;

// Retry configuration with defaults
configurable RetryConfig retryConfig = {};

// Code fixer iterations
configurable int maxIterations = ?;
```

### Config.toml Structure

```toml
[connector_automator.utils]
apiKey = "sk-ant-..."

[connector_automator.sanitizor]
maxRetries = 3
initialDelaySeconds = 1.0
maxDelaySeconds = 60.0
backoffMultiplier = 2.0
jitter = true

[connector_automator.code_fixer]
maxIterations = 5

[connector_automator.client_generator.options]
license = "docs/license.txt"
clientMethod = "resource"
```

### Environment Variables

| Variable | Used By | Purpose |
|----------|---------|---------|
| `ANTHROPIC_API_KEY` | utils | AI service authentication |
| `IS_LIVE_SERVER` | Generated tests | Test mode selection |

---

## Data Types

### Shared Types (utils)

```ballerina
public type CommandResult record {|
    string command;
    boolean success;
    int exitCode;
    string stdout;
    string stderr;
    CmdCompilationError[] compilationErrors;
    decimal executionTime;
|};

public type CmdCompilationError record {|
    string fileName;
    int line;
    int column;
    string message;
    string errorType;
    string filePath?;
|};
```

### Sanitizor Types

```ballerina
public type LLMServiceError distinct error;

public type DescriptionRequest record {
    string id;
    string name;
    string context;
    string schemaPath;
};

public type BatchDescriptionResponse record {
    string id;
    string description;
};

public type SchemaRenameRequest record {
    string originalName;
    string schemaDefinition;
    string usageContext;
};

public type BatchRenameResponse record {
    string originalName;
    string newName;
};

public type OperationIdRequest record {
    string id;
    string path;
    string method;
    string summary?;
    string description?;
    string[] tags?;
};

public type BatchOperationIdResponse record {
    string id;
    string operationId;
};

public type RetryConfig record {
    int maxRetries = 3;
    decimal initialDelaySeconds = 1.0;
    decimal maxDelaySeconds = 60.0;
    decimal backoffMultiplier = 2.0;
    boolean jitter = true;
};
```

### Example Generator Types

```ballerina
public type ConnectorDetails record {|
    string connectorName;
    int apiCount;
    string clientBalContent;
    string typesBalContent;
    string functionSignatures;
    string typeNames;
|};
```

### Test Generator Types

```ballerina
public type ConnectorAnalysis record {
    string packageName;
    string mockServerContent;
    string initMethodSignature;
    string referencedTypeDefinitions;
    "resource"|"remote" methodType = "resource";
    string remoteMethodSignatures = "";
};
```

### Doc Generator Types

```ballerina
public type ConnectorMetadata record {
    string connectorName;
    string version;
    string[] examples;
    string clientBalContent;
    string typesBalContent;
};

public type ExampleData record {|
    string exampleName;
    string exampleDirName;
    string[] balFiles;
    string[] balFileContents;
    string mainBalContent;
|};

public type TemplateData record {|
    string CONNECTOR_NAME?;
    string VERSION?;
    string DESCRIPTION?;
    string AI_GENERATED_OVERVIEW?;
    string AI_GENERATED_SETUP?;
    string AI_GENERATED_QUICKSTART?;
    string AI_GENERATED_EXAMPLES?;
    string AI_GENERATED_USAGE?;
    string AI_GENERATED_TESTING_APPROACH?;
    string AI_GENERATED_TEST_SCENARIOS?;
    string AI_GENERATED_EXAMPLE_DESCRIPTIONS?;
    string AI_GENERATED_GETTING_STARTED?;
    string AI_GENERATED_HEADER_AND_BADGES?;
    string AI_GENERATED_USEFUL_LINKS?;
    string AI_GENERATED_INDIVIDUAL_README?;
    string AI_GENERATED_MAIN_EXAMPLES_README?;
|};
```

### Code Fixer Types

```ballerina
public type FixResult record {|
    boolean success;
    int errorsFixed;
    int errorsRemaining;
    string[] appliedFixes;
    string[] remainingFixes;
|};

public type CompilationError record {|
    string filePath;
    int line;
    int column;
    string message;
    string severity;
    string code?;
|};

public type FixRequest record {|
    string projectPath;
    string filePath;
    string code;
    CompilationError[] errors;
|};

public type FixResponse record {|
    boolean success;
    string fixedCode;
    string explanation;
|};

public type BallerinaFixerError error;
```

---

## Dependencies

The package depends on the following Ballerina modules:

| Module | Purpose |
|--------|---------|
| `ballerina/io` | File I/O operations |
| `ballerina/os` | Environment variables and process execution |
| `ballerina/file` | File system operations |
| `ballerina/log` | Logging |
| `ballerina/time` | Timing and timestamps |
| `ballerina/regex` | Pattern matching |
| `ballerina/yaml` | YAML parsing |
| `ballerina/ai` | AI integration base |
| `ballerina/lang.array` | Array operations |
| `ballerina/lang.regexp` | Regular expressions |
| `ballerina/lang.runtime` | Runtime operations (sleep) |
| `ballerina/lang.string` | String operations |
| `ballerina/data.jsondata` | JSON prettification |
| `ballerinax/ai.anthropic` | Claude API client |

---

## Version History

| Version | Changes |
|---------|---------|
| 0.1.0 | Initial release with full pipeline support |
