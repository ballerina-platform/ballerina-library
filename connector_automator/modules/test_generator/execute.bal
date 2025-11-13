import connector_automator.utils;

import ballerina/io;
import ballerina/os;

public function executeTestGen(string... args) returns error? {
    if args.length() < 2 {
        printUsage();
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
    error? testGenResult = generateTestFile(connectorPath, quietMode);
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
    printTestGenerationSummary(connectorPath, quietMode);
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

function printTestGenerationSummary(string connectorPath, boolean quietMode) {
    string sep = createSeparator("=", 70);

    io:println("");
    io:println(sep);
    io:println("✓ Test Generation Complete");
    io:println(sep);
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

function printUsage() {
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
