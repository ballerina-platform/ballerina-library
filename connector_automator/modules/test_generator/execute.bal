import wso2/connector_automator.utils;

import ballerina/io;
import ballerina/time;
import ballerina/lang.regexp;
import ballerina/os;

// Unified entry point: dispatches to OpenAPI (mock + live) or SDK (live only) test generation.
public function executeTestGen(string workflowType, string... args) returns error? {
    match workflowType {
        "openapi" => {
            return executeOpenApiTestGen(...args);
        }
        "sdk" => {
            return executeSdkTestGen(...args);
        }
        _ => {
            return error(string `Unknown workflow type: '${workflowType}'. Use 'openapi' or 'sdk'.`);
        }
    }
}

// SDK live-test execution flow (no mock server; live API tests only).
function executeSdkTestGen(string... args) returns error? {
    if args.length() < 2 {
        printSdkUsage();
        return;
    }

    string connectorPath = args[0];
    string specPath = args[1];

    boolean quietMode = false;
    boolean autoYes = false;
    foreach string arg in args {
        if arg == "quiet" {
            quietMode = true;
        } else if arg == "yes" {
            autoYes = true;
        }
    }

    if autoYes && !quietMode {
        io:println("ℹ  Auto-confirm mode enabled");
    }
    if quietMode {
        io:println("ℹ  Quiet mode enabled");
    }

    printSdkTestGenerationPlan(connectorPath, specPath, quietMode);

    if !getUserConfirmation("Proceed with test generation?", autoYes) {
        io:println("✗ Operation cancelled");
        return;
    }

    check validateApiKey();

    time:Utc startTime = time:utcNow();

    io:println("Initializing AI service...");
    error? initResult = utils:initAIService(quietMode);
    if initResult is error {
        io:println(string `✗ AI initialization failed: ${initResult.message()}`);
        return initResult;
    }

    if !quietMode {
        io:println("✓ AI service initialized");
    }

    // Step 1: Select operations for test generation when specs are large
    printStepHeader(1, "Preparing live test operation scope", quietMode);
    int operationCount = check sdkCountOperationsInSpec(specPath);
    string[]? selectedOperationIds = ();

    if operationCount > SDK_MAX_OPERATIONS {
        string operationsList = check sdkSelectOperationsUsingAI(specPath, quietMode);
        string[] rawIds = regexp:split(re `,`, operationsList);
        string[] trimmedIds = [];
        foreach string id in rawIds {
            string trimmedId = id.trim();
            if trimmedId.length() > 0 {
                trimmedIds.push(trimmedId);
            }
        }
        selectedOperationIds = trimmedIds;
        if !quietMode {
            io:println(string `Selected operations (${trimmedIds.length()}): ${string:'join(",", ...trimmedIds)}`);
        }
    }

    io:println("✓ Live test operation scope prepared");

    // Step 2: Generate tests
    printStepHeader(2, "Generating live test file", quietMode);
    error? testGenResult = sdkGenerateTestFile(connectorPath, selectedOperationIds, quietMode);
    if testGenResult is error {
        io:println(string `✗ Test file generation failed: ${testGenResult.message()}`);
        return testGenResult;
    }
    io:println("✓ Test file generated");

    // Step 3: Fix all compilation errors related to tests
    printStepHeader(3, "Fixing compilation errors", quietMode);
    error? fixResult = sdkFixTestFileErrors(connectorPath, quietMode);
    if fixResult is error {
        io:println(string `⚠  Some compilation errors remain: ${fixResult.message()}`);
        if !quietMode {
            io:println("  Manual intervention may be required");
        }
    } else {
        io:println("✓ All compilation errors fixed");
    }

    time:Utc endTime = time:utcNow();
    decimal duration = time:utcDiffSeconds(endTime, startTime);
    printSdkTestGenerationSummary(connectorPath, duration, quietMode);
}

function printSdkTestGenerationPlan(string connectorPath, string specPath, boolean quietMode) {
    if quietMode {
        return;
    }

    string sep = createSeparator("=", 70);
    io:println(sep);
    io:println("Test Generation Plan (SDK / Live)");
    io:println(sep);
    io:println(string `Connector: ${connectorPath}`);
    io:println(string `Spec: ${specPath}`);
    io:println("");
    io:println("Operations:");
    io:println("  1. Prepare live operation scope");
    io:println("  2. Generate live test file");
    io:println("  3. Fix compilation errors automatically");
    io:println(sep);
}

function printSdkTestGenerationSummary(string connectorPath, decimal duration, boolean quietMode) {
    string sep = createSeparator("=", 70);

    io:println("");
    io:println(sep);
    io:println("✓ Test Generation Complete (SDK / Live)");
    io:println(sep);
    io:println(string `  • duration: ${duration}s`);
    io:println("");
    io:println("Generated Files:");
    io:println(string `  • ${connectorPath}/ballerina/tests/test.bal`);

    if !quietMode {
        io:println("");
        io:println("What was created:");
        io:println("  • Live server test suite using generated Ballerina client");
        io:println("  • Runtime credential/env gating for live tests");
        io:println("  • Automated compilation error fixes");
    }

    io:println("");
    io:println("Next Steps:");
    io:println("  • Review generated tests for completeness");
    io:println("  • Update test configurations if needed");
    io:println("  • Run tests: bal test");

    if !quietMode {
        io:println("");
        io:println("Commands:");
        io:println(string `  cd ${connectorPath}/ballerina && bal test`);
        io:println(string `  cd ${connectorPath}/ballerina && bal test --code-coverage`);
    }

    io:println(sep);
}

function printSdkUsage() {
    io:println("Test Generator (SDK / Live)");
    io:println("");
    io:println("USAGE");
    io:println("  bal run -- sdk generate-tests <output-dir> [options]");
    io:println("");
    io:println("ARGUMENTS");
    io:println("  <output-dir>    Path to connector output root");
    io:println("");
    io:println("OPTIONS");
    io:println("  yes      Auto-confirm all prompts");
    io:println("  quiet    Minimal logging output");
    io:println("");
    io:println("EXAMPLES");
    io:println("  bal run -- sdk generate-tests /home/user/my-connector");
    io:println("  bal run -- sdk generate-tests /home/user/my-connector yes");
    io:println("  bal run -- sdk generate-tests /home/user/my-connector yes quiet");
    io:println("");
    io:println("ENVIRONMENT");
    io:println("  ANTHROPIC_API_KEY    Required for AI-powered generation");
    io:println("");
    io:println("FEATURES");
    io:println("  • AI-generated live test suites using connector client");
    io:println("  • Runtime credential-gated live test execution");
    io:println("  • Automatic compilation error detection and fixing");
    io:println("  • Step-by-step confirmation prompts");
    io:println("  • CI/CD friendly with auto-confirm mode");
    io:println("");
}

// OpenAPI workflow: mock server + live tests.
function executeOpenApiTestGen(string... args) returns error? {
    if args.length() < 2 {
        printOpenApiUsage();
        return;
    }

    string connectorPath = args[0];
    string specPath = args[1];

    // Parse options
    boolean quietMode = false;
    boolean autoYes = false;
    foreach string arg in args {
        if arg == "quiet" {
            quietMode = true;
        } else if arg == "yes" {
            autoYes = true;
        }
    }

    if autoYes && !quietMode {
        io:println("ℹ  Auto-confirm mode enabled");
    }
    if quietMode {
        io:println("ℹ  Quiet mode enabled");
    }

    printTestGenerationPlan(connectorPath, specPath, quietMode);

    if !getUserConfirmation("Proceed with test generation?", autoYes) {
        io:println("✗ Operation cancelled");
        return;
    }

    // Check API key
    check validateApiKey();

    time:Utc startTime = time:utcNow();

    // Initialize AI service
    io:println("Initializing AI service...");
    error? initResult = utils:initAIService(quietMode);
    if initResult is error {
        io:println(string `✗ AI initialization failed: ${initResult.message()}`);
        return initResult;
    }

    if !quietMode {
        io:println("✓ AI service initialized");
    }

    // Step 1: Setup mock server module
    printStepHeader(1, "Setting up mock server module", quietMode);
    error? mockSetupResult = setupMockServerModule(connectorPath, quietMode);
    if mockSetupResult is error {
        io:println(string `✗ Mock server setup failed: ${mockSetupResult.message()}`);
        return mockSetupResult;
    }
    io:println("✓ Mock server module set up");

    // Step 2: Generate mock server implementation
    printStepHeader(2, "Generating mock server implementation", quietMode);
    error? mockGenResult = generateMockServer(connectorPath, specPath, quietMode);
    if mockGenResult is error {
        io:println(string `✗ Mock server generation failed: ${mockGenResult.message()}`);
        return mockGenResult;
    }

    // Extract operation IDs that were used for mock server generation
    int operationCount = check countOperationsInSpec(specPath);
    string[]? selectedOperationIds = ();

    if operationCount > MAX_OPERATIONS {
        string operationsList = check selectOperationsUsingAI(specPath, quietMode);
        // Trim whitespace from each operation ID
        string[] rawIds = regexp:split(re `,`, operationsList);
        string[] trimmedIds = [];
        foreach string id in rawIds {
            string trimmedId = id.trim();
            if trimmedId.length() > 0 {
                trimmedIds.push(trimmedId);
            }
        }
        selectedOperationIds = trimmedIds;
        if !quietMode {
            io:println(string `Selected operations (${trimmedIds.length()}): ${string:'join(",", ...trimmedIds)}`);
        }
    }

    io:println("✓ Mock server implementation generated");

    string mockServerPath = connectorPath + "/ballerina/modules/mock.server/mock_server.bal";
    string typesPath = connectorPath + "/ballerina/modules/mock.server/types.bal";

    // Step 3: Complete mock server template
    printStepHeader(3, "Completing mock server template", quietMode);
    error? completeResult = completeMockServer(mockServerPath, typesPath, quietMode);
    if completeResult is error {
        io:println(string `✗ Mock server completion failed: ${completeResult.message()}`);
        return completeResult;
    }
    io:println("✓ Mock server template completed");

    // Step 4: Generate tests
    printStepHeader(4, "Generating test file", quietMode);
    error? testGenResult = generateTestFile(connectorPath, selectedOperationIds, quietMode);
    if testGenResult is error {
        io:println(string `✗ Test file generation failed: ${testGenResult.message()}`);
        return testGenResult;
    }
    io:println("✓ Test file generated");

    // Step 5: Fix all compilation errors related to tests
    printStepHeader(5, "Fixing compilation errors", quietMode);
    error? fixResult = fixTestFileErrors(connectorPath, quietMode);
    if fixResult is error {
        io:println(string `⚠  Some compilation errors remain: ${fixResult.message()}`);
        if !quietMode {
            io:println("  Manual intervention may be required");
        }
    } else {
        io:println("✓ All compilation errors fixed");
    }

    // Final summary
    time:Utc openApiEndTime = time:utcNow();
    decimal openApiDuration = time:utcDiffSeconds(openApiEndTime, startTime);
    printTestGenerationSummary(connectorPath, openApiDuration, quietMode);
}

function printTestGenerationPlan(string connectorPath, string specPath, boolean quietMode) {
    if quietMode {
        return;
    }

    string sep = createSeparator("=", 70);
    io:println(sep);
    io:println("Test Generation Plan");
    io:println(sep);
    io:println(string `Connector: ${connectorPath}`);
    io:println(string `Spec: ${specPath}`);
    io:println("");
    io:println("Operations:");
    io:println("  1. Set up mock server module");
    io:println("  2. Generate mock server implementation");
    io:println("  3. Complete mock server template with AI");
    io:println("  4. Generate comprehensive test file");
    io:println("  5. Fix compilation errors automatically");
    io:println(sep);
}

function printStepHeader(int stepNum, string title, boolean quietMode) {
    if quietMode {
        return;
    }

    string sep = createSeparator("-", 50);
    io:println("");
    io:println(string `Step ${stepNum}: ${title}`);
    io:println(sep);
}

function printTestGenerationSummary(string connectorPath, decimal duration, boolean quietMode) {
    string sep = createSeparator("=", 70);

    io:println("");
    io:println(sep);
    io:println("✓ Test Generation Complete");
    io:println(sep);
    io:println(string `  • duration: ${duration}s`);
    io:println("");
    io:println("Generated Files:");
    io:println(string `  • ${connectorPath}/ballerina/modules/mock.server/`);
    io:println(string `  • ${connectorPath}/ballerina/tests/test.bal`);

    if !quietMode {
        io:println("");
        io:println("What was created:");
        io:println("  • Mock server module with AI-generated responses");
        io:println("  • Comprehensive test suite covering key operations");
        io:println("  • Automated compilation error fixes");
    }

    io:println("");
    io:println("Next Steps:");
    io:println("  • Review generated tests for completeness");
    io:println("  • Update test configurations if needed");
    io:println("  • Run tests: bal test");

    if !quietMode {
        io:println("");
        io:println("Commands:");
        io:println(string `  cd ${connectorPath}/ballerina && bal test`);
        io:println(string `  cd ${connectorPath}/ballerina && bal test --code-coverage`);
    }

    io:println(sep);
}

function getUserConfirmation(string message, boolean autoYes) returns boolean {
    if autoYes {
        return true;
    }
    io:print(string `${message} (y/n): `);
    string|io:Error userInput = io:readln();
    if userInput is io:Error {
        return false;
    }
    return userInput.trim().toLowerAscii() is "y"|"yes";
}

function validateApiKey() returns error? {
    string|error apiKey = os:getEnv("ANTHROPIC_API_KEY");
    if apiKey is error {
        return error("ANTHROPIC_API_KEY not configured");
    }
}

function createSeparator(string char, int length) returns string {
    string[] chars = [];
    int i = 0;
    while i < length {
        chars.push(char);
        i += 1;
    }
    return string:'join("", ...chars);
}

function printOpenApiUsage() {
    io:println("Test Generator");
    io:println("");
    io:println("USAGE");
    io:println("  bal run -- generate-tests <connector-path> <spec-path> [options]");
    io:println("");
    io:println("ARGUMENTS");
    io:println("  <connector-path>    Path to connector directory");
    io:println("  <spec-path>         Path to OpenAPI specification");
    io:println("");
    io:println("OPTIONS");
    io:println("  yes      Auto-confirm all prompts");
    io:println("  quiet    Minimal logging output");
    io:println("");
    io:println("EXAMPLES");
    io:println("  bal run -- generate-tests ./connector ./spec.yaml");
    io:println("  bal run -- generate-tests ./connector ./spec.yaml yes");
    io:println("  bal run -- generate-tests ./connector ./spec.yaml yes quiet");
    io:println("");
    io:println("ENVIRONMENT");
    io:println("  ANTHROPIC_API_KEY    Required for AI-powered generation");
    io:println("");
    io:println("FEATURES");
    io:println("  • AI-generated mock servers with realistic responses");
    io:println("  • Comprehensive test suites covering key operations");
    io:println("  • Automatic compilation error detection and fixing");
    io:println("  • Step-by-step confirmation prompts");
    io:println("  • CI/CD friendly with auto-confirm mode");
    io:println("");
}
