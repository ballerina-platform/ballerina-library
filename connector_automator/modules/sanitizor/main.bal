import connector_automator.cost_calculator;
import connector_automator.utils;

import ballerina/file;
import ballerina/io;
import ballerina/log;
import ballerina/regex;
import ballerina/yaml;

public function main(string... args) returns error? {
    io:println("Starting OpenAPI Sanitizor...");
    // Check command line arguments
    if args.length() < 2 {
        printUsage();
        return;
    }

    string inputSpecPath = args[0]; // /home/hansika/dev/sanitizor/temp-workspace/docs/spec/openapi.json
    string outputDir = args[1]; // /home/hansika/dev/sanitizor/temp-workspace

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

    if autoYes {
        if !quietMode {
            io:println("Running in automated mode - all prompts will be auto-confirmed");
        }
    }

    if quietMode {
        if !autoYes {
            io:println("Running in quiet mode - reduced logging output");
        }
        io:println("Quiet mode enabled - minimal logging output");
    }

    cost_calculator:resetCostTracking();

    if !quietMode {
        log:printInfo("Processing OpenAPI spec", inputSpec = inputSpecPath, outputDir = outputDir);
    }

    // Human acknowledgment: Show operation plan
    io:println("=== OpenAPI Sanitization Plan ===");
    io:println(string `Input OpenAPI spec: ${inputSpecPath}`);
    io:println(string `Output directory: ${outputDir}`);
    io:println("\nOperations to be performed:");
    io:println("1. Flatten OpenAPI specification");
    io:println("2. Align OpenAPI specification with Ballerina conventions");
    io:println("3. Add missing operationIds using AI");
    io:println("4. Rename inline response schemas using AI");
    io:println("5. Add missing field descriptions using AI");

    if !getUserConfirmation("\nProceed with sanitization?", autoYes) {
        io:println("Operation cancelled by user.");
        return;
    }

    // Initialize LLM service
    LLMServiceError? llmInitResult = initLLMService(quietMode);
    if llmInitResult is LLMServiceError {
        if !quietMode {
            log:printError("Failed to initialize LLM service", 'error = llmInitResult);
        }
        io:println("⚠ Warning: LLM service not available. Only programmatic fixes will be applied.");

        if !getUserConfirmation("Continue without AI-powered features?", autoYes) {
            io:println("Operation cancelled. Please check your ANTHROPIC_API_KEY configuration.");
            return;
        }
    } else {
        if !quietMode {
            log:printInfo("LLM service initialized successfully");
        }
        io:println("✓ LLM service initialized successfully");
    }

    // Step 1: Execute OpenAPI flatten
    io:println("\n=== Step 1: Flattening OpenAPI Specification ===");
    string flattenedSpecPath = outputDir + "/docs/spec";
    utils:CommandResult flattenResult = utils:executeBalFlatten(inputSpecPath, flattenedSpecPath);
    if !utils:isCommandSuccessfull(flattenResult) {
        if !quietMode {
            log:printError("OpenAPI flatten failed", result = flattenResult);
        }
        io:println("Flatten operation failed:");
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
    io:println("\n=== Step 2: Aligning OpenAPI Specification ===");
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
        io:println("Align operation failed:");
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
    //string alignedSpec = alignedSpecPath + "/aligned_ballerina_openapi.json";
    if isYamlFormat(inputSpecPath) {
        io:println("\n=== Converting YAML Aligned Spec to JSON ===");
        error? conversionResult = convertAlignedYamlToJson(alignedSpecPath, quietMode);
        if conversionResult is error {
            if !quietMode {
                log:printError("Failed to convert aligned YAML spec to JSON", 'error = conversionResult);
            }
            io:println("YAML to JSON conversion failed:");
            io:println(conversionResult.message());

            if !getUserConfirmation("Continue despite conversion failure?", autoYes) {
                return error("YAML to JSON conversion failed: " + conversionResult.message());
            }
        } else {
            if !quietMode {
                log:printInfo("Aligned YAML spec converted to JSON successfully");
            }
            io:println("✓ Aligned YAML spec converted to JSON");
        }
    }

    // Step 3: Apply operationId fix on aligned spec 
    string alignedSpec = alignedSpecPath + "/aligned_ballerina_openapi.json";

    io:println("\n=== Step 3: AI-Powered OperationId Generation ===");
    io:println("This step will add meaningful operationIds to operations that are missing them.");
    io:println("The AI will analyze the HTTP method, path, and operation context to suggest appropriate names.");

    if !getUserConfirmation("\nProceed with AI-powered operationId generation?", autoYes) {
        io:println("⚠ Skipping operationId generation. Missing operationIds will remain.");
    } else {
        io:println("Processing operationId generation with AI...");
        int|LLMServiceError operationIdResult = addMissingOperationIdsBatchWithRetry(
                alignedSpec,
                15, // batchSize
                quietMode // quietMode
        );
        if operationIdResult is LLMServiceError {
            if !quietMode {
                log:printError("Failed to add missing operationIds (batch)", 'error = operationIdResult);
            }
            io:println("OperationId generation failed:");
            io:println(operationIdResult.message());

            if !getUserConfirmation("Continue despite operationId generation failure?", autoYes) {
                return error("OperationId generation failed: " + operationIdResult.message());
            }
        } else {
            if !quietMode {
                log:printInfo("Batch operationId generation completed", operationIdsAdded = operationIdResult);
            }
            decimal operationIdCost = cost_calculator:getStageCost("sanitizor_operationids");
            io:println(string `✓ Added ${operationIdResult} missing operationIds (Cost: $${operationIdCost.toString()})`);

            if operationIdResult > 0 {
                if getUserConfirmation("Review the generated operationIds in the spec file?", autoYes) {
                    io:println(string `You can check the updated operationIds in: ${alignedSpec}`);
                    if !autoYes {
                        io:println("Press Enter to continue...");
                        _ = io:readln();
                    }
                }
            }
        }
    }

    // Step 4: Apply schema renaming fix on aligned spec (BATCH VERSION)
    io:println("\n=== Step 4: AI-Powered Schema Renaming ===");
    io:println("This step will rename generic 'InlineResponse' schemas to meaningful names using AI.");
    io:println("The AI will analyze the schema structure and usage context to suggest better names.");

    if !getUserConfirmation("\nProceed with AI-powered schema renaming?", autoYes) {
        io:println("⚠ Skipping schema renaming. Generic schema names will be preserved.");
    } else {
        io:println("Processing schema renaming with AI...");
        int|LLMServiceError schemaRenameResult = renameInlineResponseSchemasBatchWithRetry(
                alignedSpec,
                8, // batchSize
                quietMode // quietMode
        );
        if schemaRenameResult is LLMServiceError {
            if !quietMode {
                log:printError("Failed to rename InlineResponse schemas (batch)", 'error = schemaRenameResult);
            }
            io:println("Schema renaming failed:");
            io:println(schemaRenameResult.message());

            if !getUserConfirmation("Continue despite schema renaming failure?", autoYes) {
                return error("Schema renaming failed: " + schemaRenameResult.message());
            }
        } else {
            if !quietMode {
                log:printInfo("Batch schema renaming completed", schemasRenamed = schemaRenameResult);
            }
            decimal schemaRenameCost = cost_calculator:getStageCost("sanitizor_schema_names");
            io:println(string `✓ Renamed ${schemaRenameResult} InlineResponse schemas to meaningful names (Cost: $${schemaRenameCost.toString()})`);

            if schemaRenameResult > 0 {
                if getUserConfirmation("Review the renamed schemas in the spec file?", autoYes) {
                    io:println(string `You can check the updated schema names in: ${alignedSpec}`);
                    if !autoYes {
                        io:println("Press Enter to continue...");
                        _ = io:readln();
                    }
                }
            }
        }
    }

    // Step 5: Apply documentation fix on the same spec (BATCH VERSION)
    io:println("\n=== Step 5: AI-Powered Documentation Enhancement ===");
    io:println("This step will add meaningful descriptions to fields that are missing documentation.");
    io:println("The AI will analyze field names, types, and context to generate appropriate descriptions.");

    if !getUserConfirmation("Proceed with AI-powered documentation enhancement?", autoYes) {
        io:println("⚠ Skipping documentation enhancement. Missing descriptions will remain.");
    } else {
        io:println("Processing documentation enhancement with AI...");
        int|LLMServiceError descriptionsResult = addMissingDescriptionsBatchWithRetry(
                alignedSpec,
                20, // batchSize
                quietMode // quietMode
        );
        if descriptionsResult is LLMServiceError {
            if !quietMode {
                log:printError("Failed to add missing descriptions (batch)", 'error = descriptionsResult);
            }
            io:println("Documentation enhancement failed:");
            io:println(descriptionsResult.message());

            if !getUserConfirmation("Continue despite documentation enhancement failure?", autoYes) {
                return error("Documentation fix failed: " + descriptionsResult.message());
            }
        } else {
            if !quietMode {
                log:printInfo("Batch documentation fix completed", descriptionsAdded = descriptionsResult);
            }
            decimal descriptionsCost = cost_calculator:getStageCost("sanitizor_descriptions");
            io:println(string `✓ Added ${descriptionsResult} missing field descriptions (Cost: $${descriptionsCost.toString()})`);

            if descriptionsResult > 0 {
                if getUserConfirmation("Review the enhanced documentation in the spec file?", autoYes) {
                    io:println(string `You can check the updated descriptions in: ${alignedSpec}`);
                    if !autoYes {
                        io:println("Press Enter to continue...");
                        _ = io:readln();
                    }
                }
            }
        }
    }

    decimal totalCost = cost_calculator:getTotalCost();
    if totalCost > 0.0d {
        utils:repeat();
        io:println("SANITIZATION COST SUMMARY");
        utils:repeat();

        decimal operationIdCost = cost_calculator:getStageCost("sanitizor_operationids");
        decimal schemaRenameCost = cost_calculator:getStageCost("sanitizor_schema_names");
        decimal descriptionsCost = cost_calculator:getStageCost("sanitizor_descriptions");

        io:println(string `OperationId Generation: $${operationIdCost.toString()}`);
        io:println(string `Schema Renaming: $${schemaRenameCost.toString()}`);
        io:println(string `Documentation Enhancement: $${descriptionsCost.toString()}`);
        utils:repeat();
        io:println(string `Total AI Cost: $${totalCost.toString()}`);

        io:println("\n=== OpenAPI Sanitization Completed Successfully! ===");
        io:println(string `Sanitized OpenAPI specification: ${alignedSpec}`);
        io:println("\nNext Steps:");
        io:println("1. Generate Ballerina client using the client_generator module");
        io:println("2. Or run the full pipeline to complete the entire workflow");
        io:println("\nCommands:");
        io:println(string `  bal run client_generator -- ${alignedSpec} ${outputDir}/ballerina`);
        io:println(string `  bal run -- pipeline ${inputSpecPath} ${outputDir}`);

    }
}

// Helper function to get user confirmation
function getUserConfirmation(string message, boolean autoYes = false) returns boolean {
    if autoYes {
        io:println(string `${message} (y/n): y [auto-confirmed]`);
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
    io:println(string `Execution time: ${result.executionTime} seconds`);
    if result.stdout.length() > 0 {
        io:println("Output summary:");
        string[] lines = regex:split(result.stdout, "\n");
        int maxLines = lines.length() > 3 ? 3 : lines.length();
        foreach int i in 0 ..< maxLines {
            io:println(string `     ${lines[i]}`);
        }
        if lines.length() > 3 {
            io:println(string `     ... (${lines.length() - 3} more lines)`);
        }
    }
}

function printUsage() {
    io:println("Usage: bal run -- <input-openapi-spec> <output-directory> [yes] [quiet]");
    io:println("  <input-openapi-spec>: Path to the OpenAPI specification file");
    io:println("  <output-directory>: Directory where processed files will be stored");
    io:println("  yes: Automatically answer 'yes' to all prompts (for CI/CD)");
    io:println("  quiet: Reduce logging output (minimal logs for CI/CD)");
    io:println("");
    io:println("Example:");
    io:println("  bal run -- /path/to/openapi.yaml ./output");
    io:println("  bal run -- /path/to/openapi.yaml ./output yes");
    io:println("  bal run -- /path/to/openapi.yaml ./output yes quiet");
    io:println("");
    io:println("Environment Variables:");
    io:println("  ANTHROPIC_API_KEY: Required for LLM-based fixes");
    io:println("");
    io:println("Interactive Features:");
    io:println("  • Step-by-step confirmation for each operation");
    io:println("  • Review AI-generated changes before applying");
    io:println("  • Continue/skip options for failed operations");
    io:println("  • Progress feedback and operation summaries");
    io:println("  • Use 'yes' argument to skip all prompts for automated execution");
    io:println("  • Use 'quiet' argument to reduce logging output for CI/CD");
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

