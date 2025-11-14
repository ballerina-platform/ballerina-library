import ballerina/io;
import ballerina/lang.runtime;

public function executeExampleGen(string... args) returns error? {
    if args.length() < 1 {
        printUsage();
        return;
    }

    string connectorPath = args[0];

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

    printExampleGenerationPlan(connectorPath, quietMode);

    if !getUserConfirmation("Proceed with example generation?", autoYes) {
        io:println("✗ Operation cancelled");
        return;
    }

    io:println("");
    io:println("Analyzing connector...");

    // 1. Analyze the connector
    ConnectorDetails|error details = analyzeConnector(connectorPath);
    if details is error {
        io:println(string `✗ Connector analysis failed: ${details.message()}`);
        return details;
    }

    if !quietMode {
        io:println(string `✓ Analyzed connector: ${details.connectorName}`);
        io:println(string `  Found ${details.apiCount} API operations`);
    }

    // Initialize AI generator
    io:println("Initializing AI generator...");
    error? initResult = initExampleGenerator();
    if initResult is error {
        io:println(string `✗ AI initialization failed: ${initResult.message()}`);
        return error("AI generator initialization failed: " + initResult.message());
    }

    if !quietMode {
        io:println("✓ AI generator initialized");
    }

    // 2. Pack and push connector to local repository
    io:println("Preparing connector for examples...");
    error? packResult = packAndPushConnector(connectorPath);
    if packResult is error {
        io:println(string `✗ Failed to prepare connector: ${packResult.message()}`);
        io:println("  This is required for examples to resolve dependencies");
        return packResult;
    }
    io:println("✓ Connector prepared successfully");

    // 3. Determine the number of examples
    int numExamples = numberOfExamples(details.apiCount);

    io:println("");
    io:println(string `Generating ${numExamples} example${numExamples == 1 ? "" : "s"}...`);

    // Array to track used functions
    string[] usedFunctionNames = [];
    int successCount = 0;

    // 4. Generate each example
    foreach int i in 1 ... numExamples {
        if !quietMode {
            io:println("");
            io:println(string `[Example ${i}/${numExamples}] Generating use case...`);
        }

        json|error useCaseResponse = generateUseCaseAndFunctions(details, usedFunctionNames);
        if useCaseResponse is error {
            io:println(string `  ✗ Failed to generate use case: ${useCaseResponse.message()}`);
            continue;
        }

        string useCase = check useCaseResponse.useCase.ensureType();
        json functionNamesJson = check useCaseResponse.requiredFunctions.ensureType();
        string[] functionNames = [];

        // Convert json array to string array
        if functionNamesJson is json[] {
            foreach json item in functionNamesJson {
                if item is string {
                    functionNames.push(item);
                }
            }
        } else {
            io:println(string `  ✗ Invalid function list for example ${i}`);
            continue;
        }

        // Track used functions
        usedFunctionNames.push(...functionNames);

        if !quietMode {
            io:println(string `  ✓ Generated use case (${functionNames.length()} operation${functionNames.length() == 1 ? "" : "s"})`);
        }

        // Extract targeted context based on required functions
        string|error targetedContext = extractTargetedContext(details, functionNames);
        if targetedContext is error {
            io:println(string `  ✗ Failed to extract context: ${targetedContext.message()}`);
            continue;
        }

        if !quietMode {
            io:println("  ✓ Extracted context");
        }

        // Generate example code
        string|error generatedCode = generateExampleCode(details, useCase, targetedContext);
        if generatedCode is error {
            io:println(string `  ✗ Failed to generate code: ${generatedCode.message()}`);
            continue;
        }

        if !quietMode {
            io:println("  ✓ Generated code");
        }

        // Generate example name
        string|error exampleNameResult = generateExampleName(useCase);
        string exampleName;
        if exampleNameResult is error {
            if !quietMode {
                io:println(string `  ⚠  Failed to generate name, using fallback: ${exampleNameResult.message()}`);
            }
            exampleName = "example_" + i.toString();
        } else {
            exampleName = exampleNameResult;
        }

        if !quietMode {
            io:println(string `  ✓ Example name: ${exampleName}`);
        }

        // Write example to file
        error? writeResult = writeExampleToFile(connectorPath, exampleName, useCase, generatedCode, details.connectorName);
        if writeResult is error {
            io:println(string `  ✗ Failed to write example: ${writeResult.message()}`);
            continue;
        }

        if !quietMode {
            io:println("  ✓ Written to file system");
        }

        runtime:sleep(10);

        // Fix compilation errors in the generated example
        string exampleDir = connectorPath + "/examples/" + exampleName;
        error? fixResult = fixExampleCode(exampleDir, exampleName);
        if fixResult is error {
            io:println(string `  ⚠  Failed to fix compilation errors: ${fixResult.message()}`);
            io:println("     Example may require manual intervention");
        } else if !quietMode {
            io:println("  ✓ Fixed compilation issues");
        }

        successCount += 1;
        io:println(string `✓ Example ${i} (${exampleName}) completed`);
    }

    // Print final summary
    printExampleSummary(connectorPath, numExamples, successCount, quietMode);
}

function printExampleGenerationPlan(string connectorPath, boolean quietMode) {
    if quietMode {
        return;
    }

    string sep = createSeparator("=", 70);
    io:println(sep);
    io:println("Example Generation");
    io:println(sep);
    io:println(string `Connector: ${connectorPath}`);
    io:println("");
    io:println("Operations:");
    io:println("  1. Analyze connector APIs");
    io:println("  2. Pack connector to local repo");
    io:println("  3. Generate AI-powered examples");
    io:println("  4. Fix compilation errors");
    io:println("  5. Create example projects");
    io:println(sep);
}

function printExampleSummary(string connectorPath, int totalExamples, int successCount, boolean quietMode) {
    string sep = createSeparator("=", 70);

    io:println("");
    io:println(sep);

    if successCount == totalExamples {
        io:println("✓ Example Generation Complete");
    } else {
        io:println("⚠  Example Generation Partial Success");
    }

    io:println(sep);
    io:println("");
    io:println(string `Generated: ${successCount}/${totalExamples} example${totalExamples == 1 ? "" : "s"}`);

    if successCount > 0 {
        io:println(string `Output   : ${connectorPath}/examples/`);
    }

    if successCount < totalExamples {
        io:println("");
        io:println("⚠  Some examples failed to generate");
        io:println("   Manual review may be required");
    }

    if !quietMode && successCount > 0 {
        io:println("");
        io:println("Generated Examples:");
        // Note: In a real implementation, you'd track example names and list them here
        io:println(string `  • Check ${connectorPath}/examples/ for all generated examples`);
    }

    io:println("");
    io:println("Next Steps:");
    if successCount > 0 {
        io:println("  • Review generated examples for accuracy");
        io:println("  • Test examples with your API credentials");
        io:println("  • Update Config.toml files as needed");
        io:println("  • Generate documentation: bal run -- generate-docs generate-examples <path>");
    } else {
        io:println("  • Check connector analysis results");
        io:println("  • Verify AI service configuration");
        io:println("  • Review error messages above");
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
    io:println("Example Generator");
    io:println("");
    io:println("USAGE");
    io:println("  bal run -- generate-examples <connector-path> [options]");
    io:println("");
    io:println("OPTIONS");
    io:println("  yes      Auto-confirm all prompts");
    io:println("  quiet    Minimal logging output");
    io:println("");
    io:println("EXAMPLES");
    io:println("  bal run -- generate-examples ./connector");
    io:println("  bal run -- generate-examples ./connector yes");
    io:println("  bal run -- generate-examples ./connector yes quiet");
    io:println("");
    io:println("ENVIRONMENT");
    io:println("  ANTHROPIC_API_KEY    Required for AI-powered generation");
    io:println("");
    io:println("FEATURES");
    io:println("  • AI-generated use cases and code");
    io:println("  • Automatic compilation error fixing");
    io:println("  • Smart function usage tracking");
    io:println("  • Ballerina project structure creation");
    io:println("  • CI/CD friendly with auto-confirm mode");
    io:println("");
}
