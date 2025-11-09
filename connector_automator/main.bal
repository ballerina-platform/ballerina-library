import connector_automator.client_generator;
import connector_automator.code_fixer;
import connector_automator.cost_calculator;
import connector_automator.doc_generator;
import connector_automator.example_generator;
import connector_automator.sanitizor;
import connector_automator.test_generator;

import ballerina/io;
import ballerina/os;

const string VERSION = "0.1.0";
public function main(string... args) returns error? {
    // Check for API key
    string|error apiKey = os:getEnv("ANTHROPIC_API_KEY");
    if apiKey is error {
        io:println("⚠ ANTHROPIC_API_KEY not configured.");
        io:println("AI-powered features will not be available.");
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
            io:println("✗ Unknown command '" + command + "'");
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
    // Build a separator line of 80 '=' characters 
    string sep = "";
    int i = 0;
    while i < 80 {
        sep += "=";
        i += 1;
    }

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

    // Ask for optional configurations
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

    // Ask for optional configurations
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
        // // License file
        // string|io:Error licenseInput = getUserInput("license file path (optional): ");
        // if licenseInput is string && licenseInput.trim().length() > 0 {
        //     args.push(string `license=${licenseInput.trim()}`);
        // }

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

    return example_generator:executeExampleGen(connectorPath.trim());
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

    // Add quiet mode confirmation 
    boolean quietMode = getUserConfirmation("Enable quiet mode?");

    string[] args = [connectorPath.trim(), specPath.trim()];

    // Add quiet mode flag if selected
    if quietMode {
        args.push("quiet");
    }

    return test_generator:executeTestGen(...args);
}

function handleDocGeneration() returns error? {
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

    boolean autoYes = getUserConfirmation("Auto-confirm fixes?");
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

    string[] args = [openApiSpec.trim(), outputDir.trim()];
    if autoYes {
        args.push("yes");
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
    string sep = "";
    int i = 0;
    while i < 100 {
        sep += "=";
        i += 1;
    }
    io:println(sep);
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

    cost_calculator:resetCostTracking();

    printSectionHeader("Connector Automation Pipeline");
    io:println(string `Specification : ${openApiSpec}`);
    io:println(string `Output        : ${outputDir}`);
    io:println("");

    decimal sanitizationCost = 0.0d;
    decimal exampleGenCost = 0.0d;
    decimal testGenCost = 0.0d;
    decimal docGenCost = 0.0d;
    decimal codeFixCost = 0.0d;

    // Step 1: Sanitize OpenAPI spec
    printStepHeader(1, "Sanitizing OpenAPI Specification");
    string[] sanitizeArgs = [openApiSpec, outputDir];
    sanitizeArgs.push(...pipelineOptions);
    error? sanitizeResult = sanitizor:executeSanitizor(...sanitizeArgs);
    if sanitizeResult is error {
        io:println(string `✗ Sanitization failed: ${sanitizeResult.message()}`);
        decimal partialCost = cost_calculator:getTotalCost();
        if partialCost > 0.0d {
            io:println(string `Cost incurred before failure: $${partialCost.toString()}`);
        }
        return sanitizeResult;
    }

    sanitizationCost = cost_calculator:getTotalCost();
    io:println(string `✓ Sanitization completed (Cost: $${sanitizationCost.toString()})`);

    // Step 2: Generate Ballerina client
    printStepHeader(2, "Generating Ballerina Client");
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

    // Step 3: Build and validate client (check for compilation errors)
    printStepHeader(3, "Building and Validating Client");
    string[] buildArgs = [clientPath];
    buildArgs.push(...pipelineOptions);
    error? buildResult = code_fixer:executeCodeFixer(...buildArgs);
    if buildResult is error {
        io:println(string `✗ Build validation failed: ${buildResult.message()}`);
        decimal partialCost = cost_calculator:getTotalCost();
        io:println(string ` Cost incurred before pipeline termination: $${partialCost.toString()}`);
        io:println("\nThe pipeline has been terminated due to client compilation errors.");
        io:println("Please review the generated client code and fix the compilation errors manually.");
        return buildResult;
    }
    decimal totalAfterFixing = cost_calculator:getTotalCost();
    codeFixCost = totalAfterFixing - sanitizationCost;
    if codeFixCost > 0.0d {
        io:println(string `✓ Code fixing completed (Cost: $${codeFixCost.toString()})`);
    } else {
        io:println("✓ Client built successfully without compilation errors");
    }

    // Step 4: Generate examples
    printStepHeader(4, "Generating Examples");
    decimal beforeExamples = cost_calculator:getTotalCost();
    string[] exampleArgs = [outputDir];
    error? exampleResult = example_generator:executeExampleGen(...exampleArgs);
    if exampleResult is error {
        io:println(string `⚠  Example generation failed: ${exampleResult.message()}`);
        io:println("   Continuing pipeline...");
    } else {

        decimal afterExamples = cost_calculator:getTotalCost();
        exampleGenCost = afterExamples - beforeExamples;
        io:println(string `✓ Example generation completed (Cost: $${exampleGenCost.toString()})`);
    }

    // Step 5: Generate tests
    printStepHeader(5, "Generating Tests");
    decimal beforeTests = cost_calculator:getTotalCost();
    string[] testArgs = [outputDir, sanitizedSpec];
    testArgs.push(...pipelineOptions);
    error? testResult = test_generator:executeTestGen(...testArgs);
    if testResult is error {
        io:println(string `⚠  Test generation failed: ${testResult.message()}`);
        io:println("   Continuing pipeline...");
    } else {
        decimal afterTests = cost_calculator:getTotalCost();
        testGenCost = afterTests - beforeTests;
        io:println(string `✓ Test generation completed (Cost: $${testGenCost.toString()})`);
    }

    // Step 6: Generate documentation
    printStepHeader(6, "Generating Documentation");
    decimal beforeDocs = cost_calculator:getTotalCost();
    string[] docArgs = ["generate-all", outputDir];
    docArgs.push(...pipelineOptions);
    error? docResult = doc_generator:executeDocGen(...docArgs);
    if docResult is error {
        io:println(string `⚠  Documentation generation failed: ${docResult.message()}`);
    } else {
        decimal afterDocs = cost_calculator:getTotalCost();
        docGenCost = afterDocs - beforeDocs;
        io:println(string `✓ Documentation generation completed (Cost: $${docGenCost.toString()})`);
    }



    decimal totalPipelineCost = cost_calculator:getTotalCost();

    repeat();
    io:println("CONNECTOR AUTOMATION PIPELINE - FINAL COST SUMMARY");
    repeat();

    // Stage-by-stage breakdown
    io:println("COST BREAKDOWN BY PIPELINE STAGE:");
    repeat();
    io:println(string `1. OpenAPI Sanitization: $${sanitizationCost.toString()}`);
    if codeFixCost > 0.0d {
        io:println(string `2. Client Generation & Fixing: $${codeFixCost.toString()}`);
    } else {
        io:println("2. Client Generation & Fixing: $0.00 (no fixes needed)");
    }
    io:println(string `3. Example Generation: $${exampleGenCost.toString()}`);
    io:println(string `4. Test Generation: $${testGenCost.toString()}`);
    io:println(string `5. Documentation Generation: $${docGenCost.toString()}`);
    repeat();
    io:println(string `TOTAL PIPELINE COST: $${totalPipelineCost.toString()}`);

    // ✅ Detailed AI usage breakdown by operation type
    io:println("\nDETAILED AI OPERATION COSTS:");
    repeat();

    // Sanitization operations
    decimal operationIdCost = cost_calculator:getStageCost("sanitizor_operationids");
    decimal schemaRenameCost = cost_calculator:getStageCost("sanitizor_schema_names");
    decimal descriptionsCost = cost_calculator:getStageCost("sanitizor_descriptions");

    if sanitizationCost > 0.0d {
        io:println("Sanitization Operations:");
        io:println(string `  • OperationId Generation: $${operationIdCost.toString()}`);
        io:println(string `  • Schema Renaming: $${schemaRenameCost.toString()}`);
        io:println(string `  • Documentation Enhancement: $${descriptionsCost.toString()}`);
    }

    // Example generation operations
    decimal useCaseCost = cost_calculator:getStageCost("example_generator_usecase");
    decimal codeCost = cost_calculator:getStageCost("example_generator_code");
    decimal nameCost = cost_calculator:getStageCost("example_generator_name");

    if exampleGenCost > 0.0d {
        io:println("Example Generation Operations:");
        io:println(string `  • Use Case Generation: $${useCaseCost.toString()}`);
        io:println(string `  • Code Generation: $${codeCost.toString()}`);
        io:println(string `  • Name Generation: $${nameCost.toString()}`);
    }

    // Test generation operations
    decimal mockCost = cost_calculator:getStageCost("test_generator_mock");
    decimal testCost = cost_calculator:getStageCost("test_generator");
    decimal selectionCost = cost_calculator:getStageCost("test_generator_selection");

    if testGenCost > 0.0d {
        io:println("Test Generation Operations:");
        io:println(string `  • Mock Server Generation: $${mockCost.toString()}`);
        io:println(string `  • Test Code Generation: $${testCost.toString()}`);
        if selectionCost > 0.0d {
            io:println(string `  • Operation Selection: $${selectionCost.toString()}`);
        }
    }

    // Documentation generation operations  
    decimal overviewCost = cost_calculator:getStageCost("doc_generator_overview");
    decimal setupCost = cost_calculator:getStageCost("doc_generator_setup");
    decimal quickstartCost = cost_calculator:getStageCost("doc_generator_quickstart");
    decimal exampleDocsCost = cost_calculator:getStageCost("doc_generator_examples");
    decimal testDocsCost = cost_calculator:getStageCost("doc_generator_tests");
    decimal individualCost = cost_calculator:getStageCost("doc_generator_individual");
    decimal mainExamplesCost = cost_calculator:getStageCost("doc_generator_main_examples");

    if docGenCost > 0.0d {
        io:println("Documentation Generation Operations:");
        io:println(string `  • Overview Sections: $${overviewCost.toString()}`);
        io:println(string `  • Setup Guides: $${setupCost.toString()}`);
        io:println(string `  • Quickstart Sections: $${quickstartCost.toString()}`);
        io:println(string `  • Example Documentation: $${exampleDocsCost.toString()}`);
        io:println(string `  • Test Documentation: $${testDocsCost.toString()}`);
        io:println(string `  • Individual Example READMEs: $${individualCost.toString()}`);
        io:println(string `  • Main Examples READMEs: $${mainExamplesCost.toString()}`);
    }

    // Code fixing operations (if any)
    decimal fixingCost = cost_calculator:getStageCost("code_fixer");
    if fixingCost > 0.0d {
        io:println("Code Fixing Operations:");
        io:println(string `  • Compilation Error Fixes: $${fixingCost.toString()}`);
    }

    io:println("\n=== Pipeline Completed Successfully! ===");
    io:println("Generated files are available in: " + outputDir);

    if totalPipelineCost > 0.0d {
        string costReportPath = outputDir + "/cost_report.json";
        error? exportResult = cost_calculator:exportCostReport(costReportPath);
        if exportResult is error {
            io:println("Warning: Failed to export detailed cost report");
        } else {
            io:println(string `Detailed cost report exported to: ${costReportPath}`);
        }
    }

    return;
}

function printStepHeader(int stepNum, string title) {
    string sep = "";
    int i = 0;
    while i < 100 {
        sep += "-";
        i += 1;
    }
    io:println(sep);
    io:println("");
    io:println(string `[${stepNum}/6] ${title}`);
    io:println(sep);
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
    io:println("  yes      Auto-confirm all prompts");
    io:println("  quiet    Minimal logging output");
    io:println("");
    io:println("EXAMPLES");
    io:println("  bal run -- sanitize ./openapi.yaml ./output");
    io:println("  bal run -- generate-client ./spec.json ./client");
    io:println("  bal run -- pipeline ./openapi.yaml ./output yes");
    io:println("");
    io:println("ENVIRONMENT");
    io:println("  ANTHROPIC_API_KEY    Required for AI-powered features");
    io:println("");
}
function repeat() {
    string sep = "";
    int i = 0;
    while i < 80 {
        sep += "=";
        i += 1;
    }
    io:println(sep);
}
