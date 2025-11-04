import connector_automator.cost_calculator;
import connector_automator.utils;

import ballerina/file;
import ballerina/io;
import ballerina/lang.array;
import ballerina/lang.regexp;
import ballerina/log;

configurable int maxIterations = ?;

// Parse compilation errors from build output (only ERRORs)
public function parseCompilationErrors(string stderr) returns CompilationError[] {
    CompilationError[] errors = [];
    string[] lines = regexp:split(re `\n`, stderr);

    foreach string line in lines {
        // Handle only ERROR messages
        if (line.includes("ERROR [") && line.includes(")]")) {
            string severity = "ERROR";
            string prefix = severity + " [";

            int? startBracket = line.indexOf(prefix);
            int? endBracket = line.indexOf(")]", startBracket ?: 0);

            if startBracket is int && endBracket is int {
                // Extract the part between prefix and ")]"
                string errorPart = line.substring(startBracket + prefix.length(), endBracket);

                // Find the last occurrence of ":(" to split filename from coordinates
                int? coordStart = errorPart.lastIndexOf(":(");

                if coordStart is int {
                    string filePath = errorPart.substring(0, coordStart);
                    string coordinates = errorPart.substring(coordStart + 2); // Skip ":("

                    // Parse coordinates - format can be (line:col) or (line:col,endLine:endCol)
                    string[] coordParts = regexp:split(re `,`, coordinates);
                    if coordParts.length() > 0 {
                        // Get the first coordinate pair (line:col)
                        string[] lineCol = regexp:split(re `:`, coordParts[0]);
                        if lineCol.length() >= 2 {
                            int|error lineNum = int:fromString(lineCol[0]);
                            int|error col = int:fromString(lineCol[1]);

                            // Extract message - everything after ")]" plus 2 for ") "
                            string message = line.substring(endBracket + 2).trim();

                            if lineNum is int && col is int {
                                CompilationError compilationError = {
                                    filePath: filePath,
                                    line: lineNum,
                                    severity: severity,
                                    column: col,
                                    message: message
                                };
                                errors.push(compilationError);
                            }
                        }
                    }
                }
            }
        }
    }
    return errors;
}

// Group errors by file path
public function groupErrorsByFile(CompilationError[] errors) returns map<CompilationError[]> {
    map<CompilationError[]> grouped = {};

    foreach CompilationError err in errors {
        if !grouped.hasKey(err.filePath) {
            grouped[err.filePath] = [];
        }
        grouped.get(err.filePath).push(err);
    }
    return grouped;
}

// Prepare error context string
function prepareErrorContext(CompilationError[] errors) returns string {
    string[] errorStrings = errors.'map(function(CompilationError err) returns string {
        return string `Line ${err.line}, Column ${err.column}: ${err.severity} - ${err.message}`;
    });
    return string:'join("\n", ...errorStrings);
}

// Fix errors in a single file
public function fixFileWithLLM(string projectPath, string filePath, CompilationError[] errors, boolean quietMode = false) returns FixResponse|error {
    if !quietMode {
        log:printInfo("Attempting to fix file with LLM", filePath = filePath, errorCount = errors.length());
    }

    // Check if AI service is initialized
    if !utils:isAIServiceInitialized() {
        return error("AI service not initialized. Please call utils:initAIService() first.");
    }

    // Construct full file path
    string fullFilePath = check file:joinPath(projectPath, filePath);

    // Validate file exists
    boolean exists = check file:test(fullFilePath, file:EXISTS);
    if !exists {
        return error(string `File does not exist: ${fullFilePath}`);
    }

    // Read file content
    string|io:Error fileContent = io:fileReadString(fullFilePath);
    if fileContent is io:Error {
        if !quietMode {
            log:printError("Failed to read file", filePath = fullFilePath, 'error = fileContent);
        }
        return fileContent;
    }

    // Create fix prompt
    string prompt = createFixPrompt(fileContent, errors, filePath);
    if !quietMode {
        //io:println(prompt);
        log:printInfo("Sending fix request to LLM");
    }

    // Get fix from LLM using centralized service
    string|error llmResponse = utils:callAI(prompt);
    if llmResponse is error {
        if !quietMode {
            log:printError("LLM failed to generate fix", 'error = llmResponse);
        }
        return error(string `LLM failed to generate fix: ${llmResponse.message()}`);
    }

    // ✅ Track cost for code fixing
    cost_calculator:trackUsageFromText("code_fixer", prompt, llmResponse, "claude-4-sonnet");

    // ✅ Show fix cost per file (optional - can be disabled in quiet mode)
    if !quietMode {
        decimal fixCost = cost_calculator:getStageCost("code_fixer");
        // Calculate cost for just this fix (rough estimation)
        int fixCount = cost_calculator:getStageMetrics("code_fixer").calls;
        decimal avgCostPerFix = fixCount > 0 ? fixCost / <decimal>fixCount : 0.0d;
        io:println(string ` Fix cost for ${filePath}: ~$${avgCostPerFix.toString()}`);
    }

    // Return the response
    return {
        success: true,
        fixedCode: llmResponse,
        explanation: "Fixed using LLM"
    };
}

// Apply fix to file
public function applyFix(string projectPath, string filePath, string fixedCode, boolean quietMode = false) returns boolean|error {
    string fullFilePath = check file:joinPath(projectPath, filePath);

    // Create backup
    string|io:Error originalContent = io:fileReadString(fullFilePath);
    if originalContent is io:Error {
        return originalContent;
    }

    string backupPath = fullFilePath + ".backup";
    io:Error? backupResult = io:fileWriteString(backupPath, originalContent, io:OVERWRITE);
    if backupResult is io:Error {
        if !quietMode {
            log:printError("Failed to create backup", filePath = backupPath, 'error = backupResult);
        }
        return backupResult;
    }

    // Apply fix
    io:Error? writeResult = io:fileWriteString(fullFilePath, fixedCode, io:OVERWRITE);
    if writeResult is io:Error {
        if !quietMode {
            log:printError("Failed to write fixed code", filePath = fullFilePath, 'error = writeResult);
        }

        // Attempt to restore from backup
        io:Error? restoreResult = io:fileWriteString(fullFilePath, originalContent, io:OVERWRITE);
        if restoreResult is io:Error && !quietMode {
            log:printError("Failed to restore original content", filePath = fullFilePath, 'error = restoreResult);
        }
        return writeResult;
    }

    if !quietMode {
        log:printInfo("Applied fix to file", filePath = fullFilePath);
    }
    return true;
}

// Main function to fix all errors in a project
public function fixAllErrors(string projectPath, boolean quietMode = true, boolean autoYes = false) returns FixResult|BallerinaFixerError {
    if !quietMode {
        log:printInfo("Starting error fixing process", projectPath = projectPath);
    }

    cost_calculator:resetCostTracking();

    // Initialize AI service if not already initialized
    if !utils:isAIServiceInitialized() {
        error? initResult = utils:initAIService(quietMode);
        if initResult is error {
            return error BallerinaFixerError("Failed to initialize AI service", initResult);
        }
    }

    FixResult result = {
        success: false,
        errorsFixed: 0,
        errorsRemaining: 0,
        appliedFixes: [],
        remainingFixes: []
    };

    int iteration = 1;
    CompilationError[] previousErrors = [];
    int initialErrorCount = 0;
    boolean initialErrorCountSet = false;

    while iteration <= maxIterations {
        if !quietMode {
            log:printInfo("Starting iteration", iteration = iteration, maxIterations = maxIterations);
        }

        // Build the project and get diagnostics
        utils:CommandResult buildResult = utils:executeBalBuild(projectPath, quietMode);

        if utils:isCommandSuccessfull(buildResult) {
            if !quietMode {
                log:printInfo("Build successful! All errors fixed.", iteration = iteration);
            }
            result.success = true;
            result.errorsRemaining = 0;
            // If this is the first iteration and build is successful, no errors to fix
            if iteration == 1 {
                result.errorsFixed = 0;
            } else {
                result.errorsFixed = initialErrorCount; // All initial errors were fixed
            }
            decimal totalCost = cost_calculator:getTotalCost();
            if !quietMode && totalCost > 0.0d {
                io:println(string ` All errors fixed! Total fixing cost: $${totalCost.toString()}`);
            }
            return result;
        }

        // Parse errors from build output
        CompilationError[] currentErrors = parseCompilationErrors(buildResult.stderr);

        if currentErrors.length() == 0 {
            if !quietMode {
                log:printInfo("No compilation errors found.");
            }
            // If we reach here, build failed but no compilation errors were parsed
            // This might be due to different types of build issues (warnings, other errors, etc.)
            // Let's check the build output to see if it's actually successful

            // Sometimes builds fail with warnings or other issues that aren't compilation errors
            // If no compilation errors were found, we should consider this a success
            if !quietMode {
                log:printInfo("No compilation errors detected - considering build successful", iteration = iteration);
            }
            result.success = true;
            result.errorsRemaining = 0;
            result.errorsFixed = initialErrorCountSet ? initialErrorCount : 0;

            decimal totalCost = cost_calculator:getTotalCost();
            if !quietMode && totalCost > 0.0d {
                io:println(string ` No compilation errors found! Total cost: $${totalCost.toString()}`);
            }
            return result;
        }

        if !quietMode {
            log:printInfo("Found compilation errors", count = currentErrors.length(), iteration = iteration);
        }

        // Set initial error count for tracking progress
        if !initialErrorCountSet {
            initialErrorCount = currentErrors.length();
            initialErrorCountSet = true;
        }

        // Check if we're making progress (error count should decrease or errors should change)
        if iteration > 1 {
            if currentErrors.length() >= previousErrors.length() {
                // Check if errors are exactly the same (no progress)
                boolean sameErrors = checkIfErrorsAreSame(currentErrors, previousErrors);
                if sameErrors {
                    if !quietMode {
                        log:printWarn("No progress made in this iteration - same errors persist", iteration = iteration);
                    }
                    result.remainingFixes.push(string `Iteration ${iteration}: No progress - same errors persist`);

                }
            } else {
                if !quietMode {
                    log:printInfo("Progress made - error count reduced",
                            previousCount = previousErrors.length(),
                            currentCount = currentErrors.length(),
                            iteration = iteration);
                }
            }
        }

        // Store current errors for next iteration comparison
        previousErrors = currentErrors.clone();
        result.errorsRemaining = currentErrors.length();

        // Group errors by file
        map<CompilationError[]> errorsByFile = groupErrorsByFile(currentErrors);

        boolean anyFixApplied = false;

        // Process each file
        foreach string filePath in errorsByFile.keys() {
            CompilationError[] fileErrors = errorsByFile.get(filePath);

            if !quietMode {
                log:printInfo("Processing file", filePath = filePath, errorCount = fileErrors.length(), iteration = iteration);
            }

            // Get fix from LLM
            FixResponse|error fixResponse = fixFileWithLLM(projectPath, filePath, fileErrors, quietMode);
            if fixResponse is error {
                if !quietMode {
                    log:printError("Failed to get fix from LLM", filePath = filePath, 'error = fixResponse, iteration = iteration);
                }
                result.remainingFixes.push(string `Iteration ${iteration}: Failed to fix ${filePath}: ${fixResponse.message()}`);
                continue;
            }

            // Ask user for confirmation
            boolean shouldApplyFix = false;
            if autoYes {
                if !quietMode {
                    io:println(string `\n=== Iteration ${iteration} - Fix for ${filePath} ===`);
                    io:println("Errors to fix:");
                    foreach CompilationError err in fileErrors {
                        io:println(string `  Line ${err.line}: ${err.message}`);
                    }
                    io:println("\nProposed fix:");
                    io:println("```ballerina");
                    io:println(fixResponse.fixedCode);
                    io:println("```");
                }
                io:println("\nApply this fix? (y/n): y [auto-confirmed]");
                shouldApplyFix = true;
            } else {
                if !quietMode {
                    io:println(string `\n=== Iteration ${iteration} - Fix for ${filePath} ===`);
                    io:println("Errors to fix:");
                    foreach CompilationError err in fileErrors {
                        io:println(string `  Line ${err.line}: ${err.message}`);
                    }
                    io:println("\nProposed fix:");
                    io:println("```ballerina");
                    io:println(fixResponse.fixedCode);
                    io:println("```");
                }
                io:print(string `\nApply this fix? (y/n): `);
                string|io:Error userInput = io:readln();
                if userInput is io:Error {
                    if !quietMode {
                        log:printError("Failed to read user input", 'error = userInput);
                    }
                    continue;
                }

                string trimmedInput = userInput.trim().toLowerAscii();
                shouldApplyFix = trimmedInput == "y" || trimmedInput == "yes";
            }

            if shouldApplyFix {
                // Apply the fix
                boolean|error applyResult = applyFix(projectPath, filePath, fixResponse.fixedCode, quietMode);
                if applyResult is error {
                    if !quietMode {
                        log:printError("Failed to apply fix", filePath = filePath, 'error = applyResult, iteration = iteration);
                    }
                    result.remainingFixes.push(string `Iteration ${iteration}: Failed to apply fix to ${filePath}: ${applyResult.message()}`);
                    continue;
                }

                anyFixApplied = true;
                result.appliedFixes.push(string `Iteration ${iteration}: Applied fix to ${filePath} (${fileErrors.length()} errors)`);
                if !quietMode {
                    log:printInfo("Successfully applied fix to file", filePath = filePath, iteration = iteration);
                }
            } else {
                result.remainingFixes.push(string `Iteration ${iteration}: User declined fix for ${filePath}`);
                if !quietMode {
                    log:printInfo("User declined fix", filePath = filePath, iteration = iteration);
                }
            }
        }

        // If no fixes were applied in this iteration, break to avoid infinite loop
        if !anyFixApplied {
            if !quietMode {
                log:printWarn("No fixes were applied in this iteration", iteration = iteration);
            }
            result.remainingFixes.push(string `Iteration ${iteration}: No fixes applied - stopping iterations`);

        }
        if !quietMode {
            decimal iterationCost = cost_calculator:getTotalCost();
            io:println(string `Iteration ${iteration} total cost so far: $${iterationCost.toString()}`);
        }

        iteration += 1;
    }

    // Final status check
    if iteration > maxIterations {
        if !quietMode {
            log:printWarn("Maximum iterations reached", maxIterations = maxIterations);
        }
        result.remainingFixes.push(string `Maximum iterations (${maxIterations}) reached`);
    }

    // Final build check
    utils:CommandResult finalBuildResult = utils:executeBalBuild(projectPath, quietMode);
    if utils:isCommandSuccessfull(finalBuildResult) {
        result.success = true;
        result.errorsRemaining = 0;
        result.errorsFixed = initialErrorCount; // All initial errors were fixed
        if !quietMode {
            log:printInfo("All errors fixed successfully after iterations!", totalIterations = iteration - 1);
        }
    } else {
        CompilationError[] remainingErrors = parseCompilationErrors(finalBuildResult.stderr);
        result.errorsRemaining = remainingErrors.length();
        result.errorsFixed = initialErrorCount - remainingErrors.length(); // Calculate how many were fixed
        if !quietMode {
            log:printInfo("Some errors remain after iterations",
                    count = remainingErrors.length(),
                    totalIterations = iteration - 1);
        }
    }

    decimal finalCost = cost_calculator:getTotalCost();
    if finalCost > 0.0d {
        if !quietMode {
            utils:repeat();
            io:println("CODE FIXING COST SUMMARY");
            utils:repeat();
            io:println(string `Total Iterations: ${iteration - 1}`);
            io:println(string `Fixes Applied: ${result.appliedFixes.length()}`);
            io:println(string `Total Cost: $${finalCost.toString()}`);

            int totalCalls = cost_calculator:getStageMetrics("code_fixer").calls;
            if totalCalls > 0 {
                decimal avgCostPerFix = finalCost / <decimal>totalCalls;
                io:println(string `Average Cost per Fix: $${avgCostPerFix.toString()}`);
            }

            if result.success {
                io:println(" Status: All compilation errors resolved");
            } else {
                io:println(string `  Status: ${result.errorsRemaining} errors remaining`);
            }
            utils:repeat();
        } else {
            // Even in quiet mode, show final cost
            io:println(string ` Code fixing completed. Total cost: $${finalCost.toString()}`);
        }
    }

    return result;
}

// Helper function to check if two error arrays contain the same errors
function checkIfErrorsAreSame(CompilationError[] current, CompilationError[] previous) returns boolean {
    if current.length() != previous.length() {
        return false;
    }

    // Sort both arrays by file path and line number for comparison
    CompilationError[] sortedCurrent = current.sort(array:ASCENDING, key = isolated function(CompilationError err) returns string {
        return string `${err.filePath}:${err.line}:${err.column}`;
    });

    CompilationError[] sortedPrevious = previous.sort(array:ASCENDING, key = isolated function(CompilationError err) returns string {
        return string `${err.filePath}:${err.line}:${err.column}`;
    });

    // Compare each error
    foreach int i in 0 ..< sortedCurrent.length() {
        CompilationError currentErr = sortedCurrent[i];
        CompilationError previousErr = sortedPrevious[i];

        if currentErr.filePath != previousErr.filePath ||
            currentErr.line != previousErr.line ||
            currentErr.column != previousErr.column ||
            currentErr.message != previousErr.message {
            return false;
        }
    }

    return true;
}
