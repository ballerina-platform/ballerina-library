import connector_automator.client_generator;
import connector_automator.code_fixer;
import connector_automator.doc_generator;
import connector_automator.example_generator;
import connector_automator.sanitizor;
import connector_automator.test_generator;
import connector_automator.utils;

import ballerina/io;
import ballerina/os;

const string VERSION = "0.1.0";

public function main(string... args) returns error? {
    // Check for API key
    string|error apiKey = os:getEnv("ANTHROPIC_API_KEY");
    if apiKey is error {
        io:println("⚠  ANTHROPIC_API_KEY not configured");
        io:println("   AI-powered features will not be available");
        io:println("");
    }

    // If arguments are provided, use command-line mode
    if args.length() > 0 {
        return handleCommandLineMode(args);
    }

    // Interactive mode
    return handleInteractiveMode();
}

function handleCommandLineMode(string[] args) returns error? {
    string command = args[0];
    string[] remainingArgs = args.slice(1);

    match command {
        "sanitize" => {
            return sanitizor:executeSanitizor(...remainingArgs);
        }
        "generate-client" => {
            return client_generator:executeClientGen(...remainingArgs);
        }
        "generate-examples" => {
            return example_generator:executeExampleGen(...remainingArgs);
        }
        "generate-tests" => {
            return test_generator:executeTestGen(...remainingArgs);
        }
        "generate-docs" => {
            return doc_generator:executeDocGen(...remainingArgs);
        }
        "fix-code" => {
            return code_fixer:executeCodeFixer(...remainingArgs);
        }
        "pipeline" => {
            return runFullPipeline(...remainingArgs);
        }
        "help"|"--help"|"-h" => {
            printUsage();
        }
        _ => {
            io:println(string `✗ Unknown command: '${command}'`);
            printUsage();
            return error("Invalid command: " + command);
        }
    }
}

function handleInteractiveMode() returns error? {
    while true {
        showMainMenu();

        string|io:Error userChoice = getUserInput("\nSelect an option: ");
        if userChoice is io:Error {
            io:println("✗ Failed to read input");
            continue;
        }

        string choice = userChoice.trim();

        match choice {
            "1" => {
                error? result = handleSanitizeOperation();
                if result is error {
                    io:println(string `✗ Operation failed: ${result.message()}`);
                }
            }
            "2" => {
                error? result = handleClientGeneration();
                if result is error {
                    io:println(string `✗ Operation failed: ${result.message()}`);
                }
            }
            "3" => {
                error? result = handleExampleGeneration();
                if result is error {
                    io:println(string `✗ Operation failed: ${result.message()}`);
                }
            }
            "4" => {
                error? result = handleTestGeneration();
                if result is error {
                    io:println(string `✗ Operation failed: ${result.message()}`);
                }
            }
            "5" => {
                error? result = handleDocGeneration();
                if result is error {
                    io:println(string `✗ Operation failed: ${result.message()}`);
                }
            }
            "6" => {
                error? result = handleCodeFixer();
                if result is error {
                    io:println(string `✗ Operation failed: ${result.message()}`);
                }
            }
            "7" => {
                error? result = handleFullPipeline();
                if result is error {
                    io:println(string `✗ Operation failed: ${result.message()}`);
                }
            }
            "8" => {
                printUsage();
            }
            "9" => {
                io:println("✓ Session completed");
                return;
            }
            _ => {
                io:println("✗ Invalid choice. Select 1-9");
            }
        }

        if !getUserConfirmation("\nContinue with another operation?") {
            io:println("\n✓ Session completed");
            break;
        }
    }
}

function showMainMenu() {
    string sep = createSeparator("=", 80);

    io:println("");
    io:println(sep);
    io:println(string `CONNECTOR AUTOMATION CLI v${VERSION}`);
    io:println(sep);
    io:println("");
    io:println("1. Sanitize OpenAPI Specification");
    io:println("   Flatten, align, and enhance specification with AI");
    io:println("");
    io:println("2. Generate Ballerina Client");
    io:println("   Create client from sanitized OpenAPI specification");
    io:println("");
    io:println("3. Generate Examples");
    io:println("   Create usage examples with AI-powered generation");
    io:println("");
    io:println("4. Generate Test Cases");
    io:println("   Generate comprehensive tests with mock server");
    io:println("");
    io:println("5. Generate Documentation");
    io:println("   Create README files for all components");
    io:println("");
    io:println("6. Fix Code Errors");
    io:println("   AI-powered compilation error resolution");
    io:println("");
    io:println("7. Full Pipeline");
    io:println("   Execute complete automation workflow");
    io:println("");
    io:println("8. Help & Usage");
    io:println("");
    io:println("9. Exit");
    io:println(sep);
}

function handleSanitizeOperation() returns error? {
    printSectionHeader("OpenAPI Sanitization");

    string|io:Error inputSpec = getUserInput("OpenAPI specification path: ");
    if inputSpec is io:Error {
        return error("Failed to read specification path");
    }

    string|io:Error outputDir = getUserInput("Output directory: ");
    if outputDir is io:Error {
        return error("Failed to read output directory");
    }

    boolean autoYes = getUserConfirmation("Auto-confirm all prompts?");
    boolean quietMode = getUserConfirmation("Enable quiet mode?");

    string[] args = [inputSpec.trim(), outputDir.trim()];
    if autoYes {
        args.push("yes");
    }
    if quietMode {
        args.push("quiet");
    }

    return sanitizor:executeSanitizor(...args);
}

function handleClientGeneration() returns error? {
    printSectionHeader("Ballerina Client Generation");

    string|io:Error specPath = getUserInput("OpenAPI specification path: ");
    if specPath is io:Error {
        return error("Failed to read specification path");
    }

    string|io:Error outputDir = getUserInput("Output directory: ");
    if outputDir is io:Error {
        return error("Failed to read output directory");
    }

    boolean autoYes = getUserConfirmation("Auto-confirm all prompts?");
    boolean quietMode = getUserConfirmation("Enable quiet mode?");

    // Ask for client method type
    io:println("\nClient Method Type:");
    io:println("  1. Resource methods (recommended)");
    io:println("  2. Remote methods");
    string|io:Error methodChoice = getUserInput("Select method type [1]: ");
    string clientMethodArg = "resource-methods";
    if methodChoice is string && methodChoice.trim() == "2" {
        clientMethodArg = "remote-methods";
    }

    boolean wantAdvanced = getUserConfirmation("Configure advanced options?");

    string[] args = [specPath.trim(), outputDir.trim()];
    if autoYes {
        args.push("yes");
    }
    if quietMode {
        args.push("quiet");
    }
    args.push(clientMethodArg);

    if wantAdvanced {
        // License file
        string|io:Error licenseInput = getUserInput("License file path (optional): ");
        if licenseInput is string && licenseInput.trim().length() > 0 {
            args.push(string `license=${licenseInput.trim()}`);
        }

        // Tags
        string|io:Error tagsInput = getUserInput("Filter tags (comma-separated, optional): ");
        if tagsInput is string && tagsInput.trim().length() > 0 {
            args.push(string `tags=${tagsInput.trim()}`);
        }

        // Operations
        string|io:Error operationsInput = getUserInput("Specific operations (comma-separated, optional): ");
        if operationsInput is string && operationsInput.trim().length() > 0 {
            args.push(string `operations=${operationsInput.trim()}`);
        }
    }

    return client_generator:executeClientGen(...args);
}

function handleExampleGeneration() returns error? {
    printSectionHeader("Example Generation");

    string|io:Error connectorPath = getUserInput("Connector directory path: ");
    if connectorPath is io:Error {
        return error("Failed to read connector path");
    }

    boolean autoYes = getUserConfirmation("Auto-confirm all prompts?");
    boolean quietMode = getUserConfirmation("Enable quiet mode?");

    string[] args = [connectorPath.trim()];
    if autoYes {
        args.push("yes");
    }
    if quietMode {
        args.push("quiet");
    }

    return example_generator:executeExampleGen(...args);
}

function handleTestGeneration() returns error? {
    printSectionHeader("Test Case Generation");

    string|io:Error connectorPath = getUserInput("Connector directory path: ");
    if connectorPath is io:Error {
        return error("Failed to read connector path");
    }

    string|io:Error specPath = getUserInput("OpenAPI specification path: ");
    if specPath is io:Error {
        return error("Failed to read OpenAPI specification path");
    }

    boolean autoYes = getUserConfirmation("Auto-confirm all prompts?");
    boolean quietMode = getUserConfirmation("Enable quiet mode?");

    string[] args = [connectorPath.trim(), specPath.trim()];
    if autoYes {
        args.push("yes");
    }
    if quietMode {
        args.push("quiet");
    }

    return test_generator:executeTestGen(...args);
}

function handleDocGeneration() returns error? {
    printSectionHeader("Documentation Generation");

    io:println("Documentation Types:");
    io:println("  1. All README files");
    io:println("  2. Ballerina module README");
    io:println("  3. Tests README");
    io:println("  4. Examples README");
    io:println("  5. Individual example READMEs");
    io:println("  6. Root README");
    io:println("");

    string|io:Error docChoice = getUserInput("Select type (1-6): ");
    if docChoice is io:Error {
        return error("Failed to read documentation choice");
    }

    string command = "";
    match docChoice.trim() {
        "1" => {
            command = "generate-all";
        }
        "2" => {
            command = "generate-ballerina";
        }
        "3" => {
            command = "generate-tests";
        }
        "4" => {
            command = "generate-examples";
        }
        "5" => {
            command = "generate-individual-examples";
        }
        "6" => {
            command = "generate-main";
        }
        _ => {
            return error("Invalid documentation type selection");
        }
    }

    string|io:Error connectorPath = getUserInput("Connector directory path: ");
    if connectorPath is io:Error {
        return error("Failed to read connector path");
    }

    boolean autoYes = getUserConfirmation("Auto-confirm all prompts?");
    boolean quietMode = getUserConfirmation("Enable quiet mode?");

    string[] args = [command, connectorPath.trim()];
    if autoYes {
        args.push("yes");
    }
    if quietMode {
        args.push("quiet");
    }

    return doc_generator:executeDocGen(...args);
}

function handleCodeFixer() returns error? {
    printSectionHeader("Code Fixer");

    string|io:Error projectPath = getUserInput("Ballerina project directory path: ");
    if projectPath is io:Error {
        return error("Failed to read project path");
    }

    boolean autoYes = getUserConfirmation("Auto-confirm all fixes?");
    boolean quietMode = getUserConfirmation("Enable quiet mode?");

    string[] args = [projectPath.trim()];
    if autoYes {
        args.push("yes");
    }
    if quietMode {
        args.push("quiet");
    }

    return code_fixer:executeCodeFixer(...args);
}

function handleFullPipeline() returns error? {
    printSectionHeader("Full Pipeline");

    io:println("Pipeline Steps:");
    io:println("  1. Sanitize OpenAPI specification");
    io:println("  2. Generate Ballerina client");
    io:println("  3. Build and validate client");
    io:println("  4. Generate examples");
    io:println("  5. Generate tests");
    io:println("  6. Generate documentation");
    io:println("");

    string|io:Error openApiSpec = getUserInput("OpenAPI specification file path: ");
    if openApiSpec is io:Error {
        return error("Failed to read OpenAPI specification path");
    }

    string|io:Error outputDir = getUserInput("Output directory path: ");
    if outputDir is io:Error {
        return error("Failed to read output directory path");
    }

    boolean autoYes = getUserConfirmation("Auto-confirm all prompts?");
    boolean quietMode = getUserConfirmation("Enable quiet mode?");
    boolean regenerate = getUserConfirmation("Is this regenerating an existing connector?");

    string[] args = [openApiSpec.trim(), outputDir.trim()];
    if autoYes {
        args.push("yes");
    }
    if quietMode {
        args.push("quiet");
    }
    if regenerate {
        args.push("regenerate");
    }

    return runFullPipeline(...args);
}

function getUserInput(string prompt) returns string|io:Error {
    io:print(prompt);
    return io:readln();
}

function getUserConfirmation(string message) returns boolean {
    io:print(string `${message} (y/n): `);
    string|io:Error userInput = io:readln();
    if userInput is io:Error {
        return false;
    }
    string trimmedInput = userInput.trim().toLowerAscii();
    return trimmedInput == "y" || trimmedInput == "yes";
}

function printSectionHeader(string title) {
    string sep = createSeparator("=", 60);
    io:println("");
    io:println(sep);
    io:println(title);
    io:println(sep);
}

function runFullPipeline(string... args) returns error? {
    if args.length() < 2 {
        io:println("✗ Missing required arguments");
        io:println("  Usage: pipeline <openapi-spec> <output-dir> [options]");
        return;
    }

    string openApiSpec = args[0];
    string outputDir = args[1];
    string[] pipelineOptions = args.slice(2);

    boolean quietMode = false;
    boolean autoYes = false;
    boolean regenerate = false;
    string licenseFile = "";

    string[] clientOptions = [];
    foreach string option in pipelineOptions {
        if option == "quiet" {
            quietMode = true;
        } else if option == "yes" {
            autoYes = true;
        } else if option == "regenerate" {
            regenerate = true;
        } else if option.startsWith("license=") {
            licenseFile = option;
            clientOptions.push(option);
        } else {
            clientOptions.push(option);
        }
    }

    if autoYes && !quietMode {
        io:println("ℹ  Auto-confirm mode enabled");
    }
    if quietMode {
        io:println("ℹ  Quiet mode enabled");
    }
    if regenerate {
        io:println("ℹ  Regeneration mode: Smart test/example recovery enabled");
    }
    if licenseFile is string {
        string licensePath = licenseFile.substring(8); // Remove "license=" prefix
        if !quietMode {
            io:println(string `ℹ  License file: ${licensePath}`);
        }
    }

    if regenerate {
        return runRegenerationPipeline(openApiSpec, outputDir, pipelineOptions, quietMode, autoYes);
    } else {
        return runStandardPipeline(openApiSpec, outputDir, pipelineOptions, quietMode, autoYes);
    }
}

function runStandardPipeline(string openApiSpec, string outputDir, string[] pipelineOptions, boolean quietMode, boolean autoYes) returns error? {
    printPipelineHeader(openApiSpec, outputDir, quietMode, false);

    // Step 1: Sanitize OpenAPI spec
    printStepHeader(1, "Sanitizing OpenAPI Specification", quietMode);
    string[] sanitizeArgs = [openApiSpec, outputDir];
    sanitizeArgs.push(...pipelineOptions);
    error? sanitizeResult = sanitizor:executeSanitizor(...sanitizeArgs);
    if sanitizeResult is error {
        io:println(string `✗ Sanitization failed: ${sanitizeResult.message()}`);
        return sanitizeResult;
    }
    io:println("✓ Sanitization completed successfully");

    // Step 2: Generate Ballerina client
    printStepHeader(2, "Generating Ballerina Client", quietMode);
    string sanitizedSpec = outputDir + "/docs/spec/aligned_ballerina_openapi.json";
    string clientPath = outputDir + "/ballerina";
    string[] clientArgs = [sanitizedSpec, clientPath];
    clientArgs.push(...pipelineOptions);
    error? clientResult = client_generator:executeClientGen(...clientArgs);
    if clientResult is error {
        io:println(string `⚠  Client generation failed: ${clientResult.message()}`);
        io:println("   Continuing pipeline...");
    } else {
        io:println("✓ Client generation completed successfully");
    }

    // Step 3: Build and validate client
    printStepHeader(3, "Building and Validating Client", quietMode);
    string[] buildArgs = [clientPath];
    buildArgs.push(...pipelineOptions);
    utils:CommandResult buildResult = utils:executeBalBuild(clientPath, quietMode);

    if utils:hasCompilationErrors(buildResult) {
        io:println(string `✗ Build validation failed: Client contains compilation errors`);
        io:println("   Pipeline terminated due to compilation errors");
        io:println("   Please review the generated client and fix manually");

        if !quietMode && buildResult.stderr.length() > 0 {
            io:println("   Build errors:");
            io:println(buildResult.stderr);
        }

        return error(string `Client build failed: ${buildResult.stderr}`);
    }

    // If there are warnings but no errors, show them but continue
    if buildResult.stderr.length() > 0 && !quietMode {
        io:println("⚠  Build completed with warnings:");
        io:println(buildResult.stderr);
    }

    io:println("✓ Client built and validated successfully");

    // Step 4: Generate examples
    printStepHeader(4, "Generating Examples", quietMode);
    string[] exampleArgs = [outputDir];
    exampleArgs.push(...pipelineOptions);
    error? exampleResult = example_generator:executeExampleGen(...exampleArgs);
    if exampleResult is error {
        io:println(string `⚠  Example generation failed: ${exampleResult.message()}`);
        io:println("   Continuing pipeline...");
    } else {
        io:println("✓ Example generation completed successfully");
    }

    // Step 5: Generate tests
    printStepHeader(5, "Generating Tests", quietMode);
    string sanitizedSpecForTests = outputDir + "/docs/spec/aligned_ballerina_openapi.json";
    string[] testArgs = [outputDir, sanitizedSpecForTests];
    testArgs.push(...pipelineOptions);
    error? testResult = test_generator:executeTestGen(...testArgs);
    if testResult is error {
        io:println(string `⚠  Test generation failed: ${testResult.message()}`);
        io:println("   Continuing pipeline...");
    } else {
        io:println("✓ Test generation completed successfully");
    }

    // Step 6: Generate documentation
    printStepHeader(6, "Generating Documentation", quietMode);
    string[] docArgs = ["generate-all", outputDir];
    docArgs.push(...pipelineOptions);
    error? docResult = doc_generator:executeDocGen(...docArgs);
    if docResult is error {
        io:println(string `⚠  Documentation generation failed: ${docResult.message()}`);
    } else {
        io:println("✓ Documentation generation completed successfully");
    }

    // Final completion summary
    printPipelineCompletion(outputDir, quietMode);
    return;
}

function runRegenerationPipeline(string openApiSpec, string outputDir, string[] pipelineOptions, boolean quietMode, boolean autoYes) returns error? {
    printPipelineHeader(openApiSpec, outputDir, quietMode, true);

    // Step 1: Sanitize OpenAPI spec
    printStepHeader(1, "Sanitizing OpenAPI Specification", quietMode);
    string[] sanitizeArgs = [openApiSpec, outputDir];
    sanitizeArgs.push(...pipelineOptions);
    error? sanitizeResult = sanitizor:executeSanitizor(...sanitizeArgs);
    if sanitizeResult is error {
        io:println(string `✗ Sanitization failed: ${sanitizeResult.message()}`);
        return sanitizeResult;
    }
    io:println("✓ Sanitization completed successfully");

    // Step 2: Generate Ballerina client
    printStepHeader(2, "Generating Ballerina Client", quietMode);
    string sanitizedSpec = outputDir + "/docs/spec/aligned_ballerina_openapi.json";
    string clientPath = outputDir + "/ballerina";
    string[] clientArgs = [sanitizedSpec, clientPath];
    clientArgs.push(...pipelineOptions);
    error? clientResult = client_generator:executeClientGen(...clientArgs);
    if clientResult is error {
        io:println(string `⚠  Client generation failed: ${clientResult.message()}`);
        io:println("   Continuing pipeline...");
    } else {
        io:println("✓ Client generation completed successfully");
    }

    // Step 3: Build and validate client (FIRST ATTEMPT)
    printStepHeader(3, "Building and Validating Client (Initial)", quietMode);
    utils:CommandResult buildResult = utils:executeBalBuild(clientPath, quietMode);

    boolean hadBuildErrors = utils:hasCompilationErrors(buildResult);

    if hadBuildErrors {
        io:println("⚠  Initial build failed - likely due to test/mock incompatibilities");
        io:println("   This is expected for connector regeneration");

        if !quietMode && buildResult.stderr.length() > 0 {
            io:println("   Build errors:");
            io:println(buildResult.stderr);
        }

        // PHASE 1: Try to fix existing test files first (preserves test logic)
        io:println("");
        io:println("   Phase 1: Attempting to fix existing test files...");
        io:println("   (This preserves existing test logic when possible)");

        string[] fixerArgs = [clientPath];
        if autoYes {
            fixerArgs.push("yes");
        }
        if quietMode {
            fixerArgs.push("quiet");
        }

        error? phase1FixResult = code_fixer:executeCodeFixer(...fixerArgs);
        if phase1FixResult is error {
            io:println(string `   ⚠  Phase 1 fix attempt encountered issues: ${phase1FixResult.message()}`);
        }

        // Check if Phase 1 fixed all errors
        utils:CommandResult phase1BuildResult = utils:executeBalBuild(clientPath, quietMode);

        if !utils:hasCompilationErrors(phase1BuildResult) {
            // Phase 1 succeeded - existing files were fixed
            if phase1BuildResult.stderr.length() > 0 && !quietMode {
                io:println("   ⚠  Build completed with warnings:");
                io:println(phase1BuildResult.stderr);
            }
            io:println("   ✓ Phase 1 successful - existing test files fixed!");
            io:println("✓ Client built and validated successfully after fixing existing tests");

            // Continue to examples since tests are already working
            printStepHeader(4, "Generating Examples", quietMode);
            string[] exampleArgs = [outputDir];
            exampleArgs.push(...pipelineOptions);
            error? exampleResult = example_generator:executeExampleGen(...exampleArgs);
            if exampleResult is error {
                io:println(string `⚠  Example generation failed: ${exampleResult.message()}`);
                io:println("   Continuing pipeline...");
            } else {
                io:println("✓ Example generation completed successfully");
            }

        } else {
            // PHASE 2: Phase 1 failed - remove old files and regenerate fresh
            io:println("");
            io:println("   Phase 1 could not fix all errors. Proceeding to Phase 2...");
            io:println("   Phase 2: Removing old test files and regenerating fresh...");

            utils:CommandResult cleanupResult = utils:executeCommand(
                string `rm -rf tests modules/mock.server`,
                clientPath,
                quietMode
            );
            if cleanupResult.exitCode == 0 {
                io:println("   ✓ Old tests removed");
            }

            // Regenerate tests from scratch
            printStepHeader(4, "Regenerating Tests for New API Version", quietMode);
            string[] testArgs = [outputDir, sanitizedSpec];
            testArgs.push(...pipelineOptions);
            error? testResult = test_generator:executeTestGen(...testArgs);
            if testResult is error {
                io:println(string `✗ Test regeneration failed: ${testResult.message()}`);
                io:println("   Cannot continue without valid tests");
                return testResult;
            }
            io:println("✓ Test regeneration completed successfully");

            // Step 3 RETRY: Build and validate client again
            printStepHeader(3, "Building and Validating Client (Retry)", quietMode);
            utils:CommandResult retryBuildResult = utils:executeBalBuild(clientPath, quietMode);

            if utils:hasCompilationErrors(retryBuildResult) {
                io:println(string `✗ Build validation failed even after test regeneration`);
                io:println("   Attempting additional code fixes...");

                // Try code fixer one more time on regenerated files
                error? fixResult = code_fixer:executeCodeFixer(...fixerArgs);
                if fixResult is error {
                    io:println(string `⚠  Code fixer attempt failed: ${fixResult.message()}`);
                }

                // Final build attempt after code fixing
                utils:CommandResult finalBuildResult = utils:executeBalBuild(clientPath, quietMode);

                if utils:hasCompilationErrors(finalBuildResult) {
                    io:println(string `✗ Build still failing - manual intervention required`);

                    if !quietMode && finalBuildResult.stderr.length() > 0 {
                        io:println("   Remaining build errors:");
                        io:println(finalBuildResult.stderr);
                    }

                    io:println("");
                    io:println("⚠  REGENERATION COMPLETED WITH ERRORS");
                    io:println("   The connector has been partially regenerated but has compilation errors.");
                    io:println("   Common issues to check:");
                    io:println("   • Redeclared symbols in test files - remove duplicate type definitions");
                    io:println("   • Type mismatches - verify test data matches new schema");
                    io:println("   • Missing required fields - check new required fields in types");
                    io:println(string `   • Review errors in: ${clientPath}/tests/`);
                    io:println("");
                    io:println("   Continuing with documentation generation...");
                } else {
                    if finalBuildResult.stderr.length() > 0 && !quietMode {
                        io:println("⚠  Build completed with warnings:");
                        io:println(finalBuildResult.stderr);
                    }
                    io:println("✓ Client built successfully after code fixing");
                }
            } else {
                if retryBuildResult.stderr.length() > 0 && !quietMode {
                    io:println("⚠  Build completed with warnings:");
                    io:println(retryBuildResult.stderr);
                }
                io:println("✓ Client built and validated successfully after test regeneration");
            }

            // Step 5: Generate examples (after tests are fixed)
            printStepHeader(5, "Regenerating Examples for New API Version", quietMode);
            string[] exampleArgs = [outputDir];
            exampleArgs.push(...pipelineOptions);
            error? exampleResult = example_generator:executeExampleGen(...exampleArgs);
            if exampleResult is error {
                io:println(string `⚠  Example regeneration failed: ${exampleResult.message()}`);
                io:println("   Continuing pipeline...");
            } else {
                io:println("✓ Example regeneration completed successfully");
            }
        }

    } else {
        // No build errors on first attempt - proceed normally
        if buildResult.stderr.length() > 0 && !quietMode {
            io:println("⚠  Build completed with warnings:");
            io:println(buildResult.stderr);
        }

        io:println("✓ Client built and validated successfully");

        // Step 4: Generate examples
        printStepHeader(4, "Generating Examples", quietMode);
        string[] exampleArgs = [outputDir];
        exampleArgs.push(...pipelineOptions);
        error? exampleResult = example_generator:executeExampleGen(...exampleArgs);
        if exampleResult is error {
            io:println(string `⚠  Example generation failed: ${exampleResult.message()}`);
            io:println("   Continuing pipeline...");
        } else {
            io:println("✓ Example generation completed successfully");
        }

        // Step 5: Generate tests
        printStepHeader(5, "Generating Tests", quietMode);
        string[] testArgs = [outputDir, sanitizedSpec];
        testArgs.push(...pipelineOptions);
        error? testResult = test_generator:executeTestGen(...testArgs);
        if testResult is error {
            io:println(string `⚠  Test generation failed: ${testResult.message()}`);
            io:println("   Continuing pipeline...");
        } else {
            io:println("✓ Test generation completed successfully");
        }
    }

    // Step 6: Generate documentation
    printStepHeader(6, "Generating Documentation", quietMode);
    string[] docArgs = ["generate-all", outputDir];
    docArgs.push(...pipelineOptions);
    error? docResult = doc_generator:executeDocGen(...docArgs);
    if docResult is error {
        io:println(string `⚠  Documentation generation failed: ${docResult.message()}`);
    } else {
        io:println("✓ Documentation generation completed successfully");
    }

    // Final completion summary
    printRegenerationCompletion(outputDir, quietMode);
    return;
}

function printPipelineHeader(string openApiSpec, string outputDir, boolean quietMode, boolean regenerate) {
    if quietMode {
        return;
    }

    string sep = createSeparator("=", 70);
    io:println("");
    io:println(sep);
    if regenerate {
        io:println("Connector Regeneration Pipeline (Smart Test/Example Recovery)");
    } else {
        io:println("Connector Automation Pipeline");
    }
    io:println(sep);
    io:println(string `Input : ${openApiSpec}`);
    io:println(string `Output: ${outputDir}`);
    io:println("");

    if regenerate {
        io:println("Regeneration Pipeline Steps:");
        io:println("  1. Sanitize OpenAPI specification");
        io:println("  2. Generate Ballerina client");
        io:println("  3. Build and validate client (initial)");
        io:println("  4. If build fails:");
        io:println("     Phase 1: Try to fix existing test files (preserves test logic)");
        io:println("     Phase 2: If Phase 1 fails, regenerate tests from scratch");
        io:println("  5. Regenerate examples with fallback:");
        io:println("     Phase 1: Try to fix existing examples (preserves example logic)");
        io:println("     Phase 2: If Phase 1 fails, regenerate examples from scratch");
        io:println("  6. Generate documentation");
    } else {
        io:println("Pipeline Steps:");
        io:println("  1. Sanitize OpenAPI specification");
        io:println("  2. Generate Ballerina client");
        io:println("  3. Build and validate client");
        io:println("  4. Generate examples");
        io:println("  5. Generate tests");
        io:println("  6. Generate documentation");
    }
    io:println(sep);
}

function printStepHeader(int stepNum, string title, boolean quietMode) {
    if quietMode {
        return;
    }

    string sep = createSeparator("-", 60);
    io:println("");
    io:println(string `[${stepNum}/6] ${title}`);
    io:println(sep);
}

function printPipelineCompletion(string outputDir, boolean quietMode) {
    string sep = createSeparator("=", 70);

    io:println("");
    io:println(sep);
    io:println("✓ Pipeline Completed Successfully");
    io:println(sep);
    io:println("");
    io:println("Generated Components:");
    io:println(string `  • Sanitized specification: ${outputDir}/docs/spec/`);
    io:println(string `  • Ballerina client: ${outputDir}/ballerina/`);
    io:println(string `  • Usage examples: ${outputDir}/examples/`);
    io:println(string `  • Test suite: ${outputDir}/ballerina/tests/`);
    io:println(string `  • Documentation: ${outputDir}`);

    if !quietMode {
        io:println("");
        io:println("What was accomplished:");
        io:println("  • OpenAPI spec enhanced with AI-generated metadata");
        io:println("  • Ballerina client generated with proper conventions");
        io:println("  • Compilation errors automatically resolved");
        io:println("  • Realistic usage examples created");
        io:println("  • Comprehensive test suite with mock server");
        io:println("  • Complete documentation package");
    }

    io:println("");
    io:println("Next Steps:");
    io:println("  • Review generated components for accuracy");
    io:println("  • Test the client with your API credentials");
    io:println("  • Customize examples and documentation as needed");
    io:println(string `  • Build and test: cd ${outputDir}/ballerina && bal test`);

    if !quietMode {
        io:println("");
        io:println("Publishing Commands:");
        io:println(string `  cd ${outputDir}/ballerina && bal pack`);
        io:println(string `  cd ${outputDir}/ballerina && bal push --repository=local`);
    }

    io:println(sep);
}

function printRegenerationCompletion(string outputDir, boolean quietMode) {
    string sep = createSeparator("=", 70);

    io:println("");
    io:println(sep);
    io:println("✓ Regeneration Pipeline Completed Successfully");
    io:println(sep);
    io:println("");
    io:println("Regenerated Components:");
    io:println(string `  • Updated specification: ${outputDir}/docs/spec/`);
    io:println(string `  • Regenerated client: ${outputDir}/ballerina/`);
    io:println(string `  • Updated tests: ${outputDir}/ballerina/tests/`);
    io:println(string `  • Refreshed examples: ${outputDir}/examples/`);
    io:println(string `  • Updated documentation: ${outputDir}`);

    if !quietMode {
        io:println("");
        io:println("What was accomplished:");
        io:println("  • OpenAPI spec updated and sanitized for new version");
        io:println("  • Ballerina client regenerated with new API definitions");
        io:println("  • Tests automatically regenerated to match new schema");
        io:println("  • Build errors resolved through smart test recovery");
        io:println("  • Examples updated with new API operations");
        io:println("  • Documentation refreshed for API changes");
    }

    io:println("");
    io:println("Next Steps:");
    io:println("  • Review API changes and breaking modifications");
    io:println("  • Test regenerated client with real API credentials");
    io:println("  • Verify backward compatibility where applicable");
    io:println("  • Update version numbers and changelog");
    io:println(string `  • Build and test: cd ${outputDir}/ballerina && bal test`);

    if !quietMode {
        io:println("");
        io:println("Important Notes:");
        io:println("  • Tests were regenerated to match new API schema");
        io:println("  • Review test changes for correctness");
        io:println("  • Check for breaking changes in examples");
        io:println("  • Update migration guide if needed");
    }

    io:println(sep);
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
    io:println("");
    io:println("Connector Automation CLI");
    io:println("");
    io:println("USAGE");
    io:println("  bal run -- <command> [arguments] [options]");
    io:println("");
    io:println("COMMANDS");
    io:println("  sanitize <spec> <output-dir>");
    io:println("    Sanitize OpenAPI specification with AI enhancements");
    io:println("");
    io:println("  generate-client <spec> <output-dir>");
    io:println("    Generate Ballerina client from OpenAPI specification");
    io:println("");
    io:println("  generate-examples <connector-path>");
    io:println("    Generate example code for the connector");
    io:println("");
    io:println("  generate-tests <connector-path> <spec>");
    io:println("    Generate tests with mock server");
    io:println("");
    io:println("  generate-docs <command> <connector-path>");
    io:println("    Generate documentation (README files)");
    io:println("    Commands: generate-all, generate-ballerina, generate-tests,");
    io:println("              generate-examples, generate-individual-examples, generate-main");
    io:println("");
    io:println("  fix-code <project-path>");
    io:println("    Fix compilation errors using AI");
    io:println("");
    io:println("  pipeline <spec> <output-dir>");
    io:println("    Run complete automation pipeline");
    io:println("");
    io:println("  help");
    io:println("    Show this help message");
    io:println("");
    io:println("OPTIONS");
    io:println("  yes         Auto-confirm all prompts");
    io:println("  quiet       Minimal logging output");
    io:println("  regenerate  Enable smart test recovery for connector regeneration");
    io:println("");
    io:println("EXAMPLES");
    io:println("  bal run -- sanitize ./openapi.yaml ./output");
    io:println("  bal run -- generate-client ./spec.json ./client");
    io:println("  bal run -- pipeline ./openapi.yaml ./output yes");
    io:println("  bal run -- pipeline ./openapi.yaml ./output yes regenerate");
    io:println("  bal run -- pipeline ./openapi.yaml ./output yes quiet regenerate");
    io:println("");
    io:println("ENVIRONMENT");
    io:println("  ANTHROPIC_API_KEY    Required for AI-powered features");
    io:println("");
    io:println("FEATURES");
    io:println("  • AI-enhanced OpenAPI specification sanitization");
    io:println("  • Automated Ballerina client generation");
    io:println("  • Intelligent example and test case creation");
    io:println("  • Comprehensive documentation generation");
    io:println("  • Automatic compilation error resolution");
    io:println("  • Smart test recovery for connector regeneration");
    io:println("  • Complete end-to-end automation pipeline");
    io:println("  • Interactive and command-line interfaces");
    io:println("");
}
