import connector_automator.utils;

import ballerina/file;
import ballerina/io;
import ballerina/log;
import ballerina/regex;
import ballerina/yaml;

public function executeSanitizor(string... args) returns error? {
    if args.length() < 2 {
        printUsage();
        return;
    }

    string inputSpecPath = args[0];
    string outputDir = args[1];

    // Check for auto flag for automated mode and quiet mode for log control
    boolean autoYes = false;
    boolean quietMode = false;
    foreach string arg in args {
        if arg == "yes" {
            autoYes = true;
        } else if arg == "quiet" {
            quietMode = true;
        }
    }

    if autoYes && !quietMode {
        io:println("ℹ  Auto-confirm mode enabled");
    }
    if quietMode {
        io:println("ℹ  Quiet mode enabled");
    }

    printSanitizationPlan(inputSpecPath, outputDir, quietMode);

    if !getUserConfirmation("\nProceed with sanitization?", autoYes) {
        io:println("✗ Operation cancelled");
        return;
    }

    // Initialize LLM service
    LLMServiceError? llmInitResult = initLLMService(quietMode);
    if llmInitResult is LLMServiceError {
        if !quietMode {
            log:printError("Failed to initialize LLM service", 'error = llmInitResult);
        }
        io:println("⚠  Warning: AI service not available. Only programmatic fixes will be applied.");

        if !getUserConfirmation("Continue without AI-powered features?", autoYes) {
            io:println("✗ Operation cancelled. Please check your ANTHROPIC_API_KEY configuration.");
            return;
        }
    } else {
        if !quietMode {
            log:printInfo("LLM service initialized successfully");
        }
        io:println("✓ AI service initialized successfully");
    }

    // Step 1: Execute OpenAPI flatten
    printStepHeader(1, "Flattening OpenAPI Specification", quietMode);
    string flattenedSpecPath = outputDir + "/docs/spec";
    utils:CommandResult flattenResult = utils:executeBalFlatten(inputSpecPath, flattenedSpecPath);
    if !utils:isCommandSuccessfull(flattenResult) {
        if !quietMode {
            log:printError("OpenAPI flatten failed", result = flattenResult);
        }
        io:println("✗ Flatten operation failed:");
        io:println(flattenResult.stderr);

        if !getUserConfirmation("Continue despite flatten failure?", autoYes) {
            return error("Flatten operation failed: " + flattenResult.stderr);
        }
    } else {
        if !quietMode {
            log:printInfo("OpenAPI spec flattened successfully", outputPath = flattenedSpecPath);
        }
        io:println("✓ OpenAPI spec flattened successfully");
        if !quietMode {
            showOperationSummary("Flatten", flattenResult);
        }
    }

    // Step 2: Execute OpenAPI align on flattened spec
    printStepHeader(2, "Aligning OpenAPI Specification", quietMode);
    string alignedSpecPath = outputDir + "/docs/spec";

    // Determine flattened spec path based on input format
    string flattenedSpec;
    if isYamlFormat(inputSpecPath) {
        // If input was YAML, flattened spec will also be YAML
        string yamlFlattenedSpec = flattenedSpecPath + "/flattened_openapi.yaml";
        string ymlFlattenedSpec = flattenedSpecPath + "/flattened_openapi.yml";

        // Check which extension the flattened spec actually has
        boolean|file:Error yamlExists = file:test(yamlFlattenedSpec, file:EXISTS);
        if yamlExists is boolean && yamlExists {
            flattenedSpec = yamlFlattenedSpec;
        } else {
            boolean|file:Error ymlExists = file:test(ymlFlattenedSpec, file:EXISTS);
            if ymlExists is boolean && ymlExists {
                flattenedSpec = ymlFlattenedSpec;
            } else {
                // Fallback to .yaml extension (most common)
                flattenedSpec = yamlFlattenedSpec;
            }
        }
    } else {
        // If input was JSON, flattened spec will be JSON
        flattenedSpec = flattenedSpecPath + "/flattened_openapi.json";
    }

    utils:CommandResult alignResult = utils:executeBalAlign(flattenedSpec, alignedSpecPath);
    if !utils:isCommandSuccessfull(alignResult) {
        if !quietMode {
            log:printError("OpenAPI align failed", result = alignResult);
        }
        io:println("✗ Align operation failed:");
        io:println(alignResult.stderr);

        if !getUserConfirmation("Continue despite align failure?", autoYes) {
            return error("Align operation failed: " + alignResult.stderr);
        }
    } else {
        if !quietMode {
            log:printInfo("OpenAPI spec aligned successfully");
        }
        io:println("✓ OpenAPI spec aligned successfully");
        if !quietMode {
            showOperationSummary("Align", alignResult);
        }
    }

    // Check if input spec was YAML/YML and convert aligned spec to JSON if needed
    if isYamlFormat(inputSpecPath) {
        printStepHeader(2.5, "Converting YAML to JSON", quietMode);
        error? conversionResult = convertAlignedYamlToJson(alignedSpecPath, quietMode);
        if conversionResult is error {
            if !quietMode {
                log:printError("Failed to convert aligned YAML spec to JSON", 'error = conversionResult);
            }
            io:println("✗ YAML to JSON conversion failed:");
            io:println(conversionResult.message());

            if !getUserConfirmation("Continue despite conversion failure?", autoYes) {
                return error("YAML to JSON conversion failed: " + conversionResult.message());
            }
        } else {
            if !quietMode {
                log:printInfo("Aligned YAML spec converted to JSON successfully");
            }
            //io:println("✓ Aligned YAML spec converted to JSON");
        }
    }

    // Step 3: Apply operationId fix on aligned spec 
    string alignedSpec = alignedSpecPath + "/aligned_ballerina_openapi.json";

    printStepHeader(3, "AI-Powered OperationId Generation", quietMode);
    if !quietMode {
        io:println("Adding meaningful operationIds to operations that are missing them");
        io:println("AI analyzes HTTP method, path, and context for appropriate names");
    }

    if !getUserConfirmation("Proceed with operationId generation?", autoYes) {
        io:println("⚠  Skipping operationId generation");
    } else {
        io:println("Generating operationIds...");
        int|LLMServiceError operationIdResult = addMissingOperationIdsBatchWithRetry(
                alignedSpec,
                15, // batchSize
                quietMode // quietMode
        );
        if operationIdResult is LLMServiceError {
            if !quietMode {
                log:printError("Failed to add missing operationIds (batch)", 'error = operationIdResult);
            }
            io:println(string `✗ OperationId generation failed: ${operationIdResult.message()}`);

            if !getUserConfirmation("Continue despite operationId generation failure?", autoYes) {
                return error("OperationId generation failed: " + operationIdResult.message());
            }
        } else {
            if !quietMode {
                log:printInfo("Batch operationId generation completed", operationIdsAdded = operationIdResult);
            }
            io:println(string `✓ Added ${operationIdResult} missing operationId${operationIdResult == 1 ? "" : "s"}`);

            if operationIdResult > 0 && !autoYes {
                if getUserConfirmation("Review the generated operationIds?", autoYes) {
                    io:println(string `  Output: ${alignedSpec}`);
                    io:println("  Press Enter to continue...");
                    _ = io:readln();
                }
            }
        }
    }

    // Step 4: Apply schema renaming fix on aligned spec (BATCH VERSION)
    printStepHeader(4, "AI-Powered Schema Renaming", quietMode);
    if !quietMode {
        io:println("Renaming generic 'InlineResponse' schemas to meaningful names");
        io:println("AI analyzes schema structure and usage context for better names");
    }

    if !getUserConfirmation("Proceed with schema renaming?", autoYes) {
        io:println("⚠  Skipping schema renaming");
    } else {
        io:println("Renaming schemas...");
        int|LLMServiceError schemaRenameResult = renameInlineResponseSchemasBatchWithRetry(
                alignedSpec,
                8, // batchSize
                quietMode // quietMode
        );
        if schemaRenameResult is LLMServiceError {
            if !quietMode {
                log:printError("Failed to rename InlineResponse schemas (batch)", 'error = schemaRenameResult);
            }
            io:println(string `✗ Schema renaming failed: ${schemaRenameResult.message()}`);

            if !getUserConfirmation("Continue despite schema renaming failure?", autoYes) {
                return error("Schema renaming failed: " + schemaRenameResult.message());
            }
        } else {
            if !quietMode {
                log:printInfo("Batch schema renaming completed", schemasRenamed = schemaRenameResult);
            }
            io:println(string `✓ Renamed ${schemaRenameResult} schema${schemaRenameResult == 1 ? "" : "s"} to meaningful names`);

            if schemaRenameResult > 0 && !autoYes {
                if getUserConfirmation("Review the renamed schemas?", autoYes) {
                    io:println(string `  Output: ${alignedSpec}`);
                    io:println("  Press Enter to continue...");
                    _ = io:readln();
                }
            }
        }
    }

    // Step 5: Apply documentation fix on the same spec (BATCH VERSION)
    printStepHeader(5, "AI-Powered Documentation Enhancement", quietMode);
    if !quietMode {
        io:println("Adding meaningful descriptions to fields missing documentation");
        io:println("AI analyzes field names, types, and context for appropriate descriptions");
    }

    if !getUserConfirmation("Proceed with documentation enhancement?", autoYes) {
        io:println("⚠  Skipping documentation enhancement");
    } else {
        io:println("Enhancing documentation...");
        int|LLMServiceError descriptionsResult = addMissingDescriptionsBatchWithRetry(
                alignedSpec,
                20, // batchSize
                quietMode // quietMode
        );
        if descriptionsResult is LLMServiceError {
            if !quietMode {
                log:printError("Failed to add missing descriptions (batch)", 'error = descriptionsResult);
            }
            io:println(string `✗ Documentation enhancement failed: ${descriptionsResult.message()}`);

            if !getUserConfirmation("Continue despite documentation enhancement failure?", autoYes) {
                return error("Documentation fix failed: " + descriptionsResult.message());
            }
        } else {
            if !quietMode {
                log:printInfo("Batch documentation fix completed", descriptionsAdded = descriptionsResult);
            }
            io:println(string `✓ Added ${descriptionsResult} missing field description${descriptionsResult == 1 ? "" : "s"}`);

            if descriptionsResult > 0 && !autoYes {
                if getUserConfirmation("Review the enhanced documentation?", autoYes) {
                    io:println(string `  Output: ${alignedSpec}`);
                    io:println("  Press Enter to continue...");
                    _ = io:readln();
                }
            }
        }
    }

    // Final completion summary
    printCompletionSummary(alignedSpec, inputSpecPath, outputDir, quietMode);
}

function printSanitizationPlan(string inputSpecPath, string outputDir, boolean quietMode) {
    if quietMode {
        return;
    }

    string sep = createSeparator("=", 70);
    io:println(sep);
    io:println("OpenAPI Sanitization Plan");
    io:println(sep);
    io:println(string `Input  : ${inputSpecPath}`);
    io:println(string `Output : ${outputDir}/docs/spec/aligned_ballerina_openapi.json`);
    io:println("");
    io:println("Operations:");
    io:println("  1. Flatten OpenAPI specification");
    io:println("  2. Align with Ballerina conventions");
    io:println("  3. Generate missing operationIds (AI)");
    io:println("  4. Rename inline response schemas (AI)");
    io:println("  5. Add missing field descriptions (AI)");
    io:println(sep);
}

function printStepHeader(decimal stepNum, string title, boolean quietMode) {
    if quietMode {
        return;
    }

    string sep = createSeparator("-", 60);
    io:println("");
    io:println(string `Step ${stepNum.toString()}: ${title}`);
    io:println(sep);
}

function printCompletionSummary(string alignedSpec, string inputSpecPath, string outputDir, boolean quietMode) {
    string sep = createSeparator("=", 70);

    io:println("");
    io:println(sep);
    io:println("✓ OpenAPI Sanitization Complete");
    io:println(sep);
    io:println("");
    io:println(string `Sanitized: ${alignedSpec}`);

    if !quietMode {
        io:println("");
        io:println("What was processed:");
        io:println("  • Flattened nested references");
        io:println("  • Aligned with Ballerina conventions");
        io:println("  • Enhanced with AI-generated metadata");
    }

    io:println("");
    io:println("Next Steps:");
    io:println("  • Generate client: bal run -- client-gen <spec> <output>");
    io:println("  • Run full pipeline: bal run -- pipeline <spec> <output>");

    if !quietMode {
        io:println("");
        io:println("Commands:");
        io:println(string `  bal run -- client-gen ${alignedSpec} ${outputDir}/ballerina`);
        io:println(string `  bal run -- pipeline ${inputSpecPath} ${outputDir}`);
    }

    io:println(sep);
}

// Helper function to get user confirmation
function getUserConfirmation(string message, boolean autoYes = false) returns boolean {
    if autoYes {
        return true;
    }

    io:print(string `${message} (y/n): `);
    string|io:Error userInput = io:readln();
    if userInput is io:Error {
        log:printError("Failed to read user input", 'error = userInput);
        return false;
    }
    string trimmedInput = userInput.trim().toLowerAscii();
    return trimmedInput == "y" || trimmedInput == "Y" || trimmedInput == "yes";
}

// Helper function to show operation summary
function showOperationSummary(string operationName, utils:CommandResult result) {
    io:println(string `  Execution time: ${result.executionTime} seconds`);
    if result.stdout.length() > 0 {
        io:println("  Output summary:");
        string[] lines = regex:split(result.stdout, "\n");
        int maxLines = lines.length() > 3 ? 3 : lines.length();
        foreach int i in 0 ..< maxLines {
            io:println(string `    ${lines[i]}`);
        }
        if lines.length() > 3 {
            io:println(string `    ... (${lines.length() - 3} more lines)`);
        }
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
    io:println("OpenAPI Sanitizor");
    io:println("");
    io:println("USAGE");
    io:println("  bal run -- sanitize <input-spec> <output-dir> [options]");
    io:println("");
    io:println("ARGUMENTS");
    io:println("  <input-spec>     Path to OpenAPI specification file");
    io:println("  <output-dir>     Directory for processed files");
    io:println("");
    io:println("OPTIONS");
    io:println("  yes      Auto-confirm all prompts");
    io:println("  quiet    Minimal logging output");
    io:println("");
    io:println("EXAMPLES");
    io:println("  bal run -- sanitize /path/to/openapi.yaml ./output");
    io:println("  bal run -- sanitize /path/to/openapi.json ./output yes");
    io:println("  bal run -- sanitize /path/to/openapi.yaml ./output yes quiet");
    io:println("");
    io:println("ENVIRONMENT");
    io:println("  ANTHROPIC_API_KEY    Required for AI-powered enhancements");
    io:println("");
    io:println("FEATURES");
    io:println("  • Flatten nested OpenAPI references");
    io:println("  • Align with Ballerina conventions");
    io:println("  • AI-generated operationIds and schema names");
    io:println("  • AI-enhanced field descriptions");
    io:println("  • Step-by-step confirmation prompts");
    io:println("  • CI/CD friendly with auto-confirm mode");
    io:println("");
}

// Helper function to check if the input file is in YAML format
function isYamlFormat(string filePath) returns boolean {
    string lowerPath = filePath.toLowerAscii();
    return lowerPath.endsWith(".yaml") || lowerPath.endsWith(".yml");
}

function convertAlignedYamlToJson(string alignedSpecPath, boolean quietMode = false) returns error? {
    // The aligned spec will be in YAML format if input was YAML
    string yamlAlignedSpec = alignedSpecPath + "/aligned_ballerina_openapi.yaml";
    string jsonAlignedSpec = alignedSpecPath + "/aligned_ballerina_openapi.json";

    // Check if YAML aligned spec exists
    boolean|file:Error yamlExists = file:test(yamlAlignedSpec, file:EXISTS);
    if yamlExists is file:Error || !yamlExists {
        // Try .yml extension as well
        string ymlAlignedSpec = alignedSpecPath + "/aligned_ballerina_openapi.yml";
        boolean|file:Error ymlExists = file:test(ymlAlignedSpec, file:EXISTS);
        if ymlExists is file:Error || !ymlExists {
            if !quietMode {
                log:printWarn("No YAML aligned spec found to convert", yamlPath = yamlAlignedSpec, ymlPath = ymlAlignedSpec);
            }
            return; // No YAML file to convert
        }
        yamlAlignedSpec = ymlAlignedSpec;
    }

    if !quietMode {
        log:printInfo("Converting YAML aligned spec to JSON", yamlPath = yamlAlignedSpec, jsonPath = jsonAlignedSpec);
    }

    // Read YAML content
    string|io:Error yamlContent = io:fileReadString(yamlAlignedSpec);
    if yamlContent is io:Error {
        return error("Failed to read YAML aligned spec file: " + yamlContent.message());
    }

    // Parse YAML to JSON
    json|yaml:Error jsonData = yaml:readString(yamlContent);
    if jsonData is yaml:Error {
        return error("Failed to parse YAML content: " + jsonData.message());
    }

    // Write JSON content
    io:Error? writeResult = io:fileWriteJson(jsonAlignedSpec, jsonData);
    if writeResult is io:Error {
        return error("Failed to write JSON aligned spec file: " + writeResult.message());
    }

    if !quietMode {
        log:printInfo("Successfully converted YAML aligned spec to JSON",
                yamlPath = yamlAlignedSpec,
                jsonPath = jsonAlignedSpec);
    }

    return;
}

// Helper function to check if file exists
function fileExists(string filePath) returns boolean {
    boolean|file:Error exists = file:test(filePath, file:EXISTS);
    return exists is boolean ? exists : false;
}
