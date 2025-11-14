import connector_automator.utils;

import ballerina/file;
import ballerina/io;
import ballerina/lang.array;
import ballerina/lang.regexp;

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
        io:println(string `  Analyzing ${filePath} (${errors.length()} error${errors.length() == 1 ? "" : "s"})`);
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
            io:println(string `  ✗ Failed to read ${filePath}`);
        }
        return fileContent;
    }

    // Create fix prompt
    string prompt = createFixPrompt(fileContent, errors, filePath);

    // Get fix from LLM using centralized service
    string|error llmResponse = utils:callAI(prompt);
    if llmResponse is error {
        if !quietMode {
            io:println(string `  ✗ AI failed to generate fix for ${filePath}`);
        }
        return error(string `LLM failed to generate fix: ${llmResponse.message()}`);
    }

    if !quietMode {
        io:println(string `  ✓ Generated fix for ${filePath}`);
    }

    return {
        success: true,
        fixedCode: llmResponse,
        explanation: "Fixed using AI"
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
            io:println(string `  ⚠  Failed to create backup for ${filePath}`);
        }
        return backupResult;
    }

    // Apply fix
    io:Error? writeResult = io:fileWriteString(fullFilePath, fixedCode, io:OVERWRITE);
    if writeResult is io:Error {
        if !quietMode {
            io:println(string `  ✗ Failed to apply fix to ${filePath}`);
        }

        // Attempt to restore from backup
        io:Error? restoreResult = io:fileWriteString(fullFilePath, originalContent, io:OVERWRITE);
        if restoreResult is io:Error && !quietMode {
            io:println(string `  ⚠  Failed to restore original content for ${filePath}`);
        }
        return writeResult;
    }

    if !quietMode {
        io:println(string `  ✓ Applied fix to ${filePath}`);
    }
    return true;
}

// Main function to fix all errors in a project
public function fixAllErrors(string projectPath, boolean quietMode = true, boolean autoYes = false) returns FixResult|BallerinaFixerError {
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

    if !quietMode {
        io:println("Starting error fixing process...");
    }

    while iteration <= maxIterations {
        if !quietMode {
            io:println("");
            io:println(string `[Iteration ${iteration}/${maxIterations}] Building project...`);
        }

        // Build the project and get diagnostics
        utils:CommandResult buildResult = utils:executeBalBuild(projectPath, quietMode);

        if utils:isCommandSuccessfull(buildResult) {
            result.success = true;
            result.errorsRemaining = 0;

            if iteration == 1 {
                result.errorsFixed = 0;
                if !quietMode {
                    io:println("✓ Project builds successfully (no errors to fix)");
                }
            } else {
                result.errorsFixed = initialErrorCount;
                if !quietMode {
                    io:println("✓ All compilation errors resolved!");
                }
            }
            return result;
        }

        // Parse errors from build output
        CompilationError[] currentErrors = parseCompilationErrors(buildResult.stderr);

        if currentErrors.length() == 0 {
            result.success = true;
            result.errorsRemaining = 0;
            result.errorsFixed = initialErrorCountSet ? initialErrorCount : 0;

            if !quietMode {
                io:println("✓ No compilation errors detected");
            }
            return result;
        }

        // Set initial error count for tracking progress
        if !initialErrorCountSet {
            initialErrorCount = currentErrors.length();
            initialErrorCountSet = true;

            if !quietMode {
                io:println(string `Found ${initialErrorCount} compilation error${initialErrorCount == 1 ? "" : "s"}`);
            }
        }

        // Check progress
        if iteration > 1 {
            int progressMade = previousErrors.length() - currentErrors.length();

            if progressMade > 0 {
                if !quietMode {
                    io:println(string `  Progress: Fixed ${progressMade} error${progressMade == 1 ? "" : "s"}`);
                }
            } else if currentErrors.length() >= previousErrors.length() {
                boolean sameErrors = checkIfErrorsAreSame(currentErrors, previousErrors);
                if sameErrors {
                    if !quietMode {
                        io:println("  ⚠  No progress made - same errors persist");
                    }
                    result.remainingFixes.push(string `Iteration ${iteration}: No progress - same errors persist`);
                    break;
                }
            }
        }

        // Store current errors for next iteration comparison
        previousErrors = currentErrors.clone();
        result.errorsRemaining = currentErrors.length();

        // Group errors by file
        map<CompilationError[]> errorsByFile = groupErrorsByFile(currentErrors);

        if !quietMode {
            io:println(string `Processing ${errorsByFile.keys().length()} file${errorsByFile.keys().length() == 1 ? "" : "s"}...`);
        }

        boolean anyFixApplied = false;

        // Process each file
        foreach string filePath in errorsByFile.keys() {
            CompilationError[] fileErrors = errorsByFile.get(filePath);

            // Get fix from LLM
            FixResponse|error fixResponse = fixFileWithLLM(projectPath, filePath, fileErrors, quietMode);
            if fixResponse is error {
                if !quietMode {
                    io:println(string `  ⚠  Could not generate fix for ${filePath}: ${fixResponse.message()}`);
                }
                result.remainingFixes.push(string `Iteration ${iteration}: Failed to fix ${filePath}: ${fixResponse.message()}`);
                continue;
            }

            // Show fix to user and ask for confirmation
            boolean shouldApplyFix = false;

            if autoYes {
                shouldApplyFix = true;
                if !quietMode {
                    io:println(string `  Auto-applying fix to ${filePath} [${fileErrors.length()} error${fileErrors.length() == 1 ? "" : "s"}]`);
                }
            } else {
                // Show the fix to user
                io:println("");
                io:println(string `Fix for ${filePath}:`);
                io:println("  Errors:");
                foreach CompilationError err in fileErrors {
                    io:println(string `    Line ${err.line}: ${err.message}`);
                }
                io:println("");
                io:println("  Proposed solution:");
                io:println("```ballerina");
                io:println(fixResponse.fixedCode);
                io:println("```");
                io:println("");

                io:print("Apply this fix? (y/n): ");
                string|io:Error userInput = io:readln();
                if userInput is io:Error {
                    io:println("  ⚠  Failed to read input - skipping fix");
                    continue;
                }

                string trimmedInput = userInput.trim().toLowerAscii();
                shouldApplyFix = trimmedInput == "y" || trimmedInput == "yes";

                if shouldApplyFix {
                    io:println("  ✓ Fix approved");
                } else {
                    io:println("  ✗ Fix declined");
                }
            }

            if shouldApplyFix {
                // Apply the fix
                boolean|error applyResult = applyFix(projectPath, filePath, fixResponse.fixedCode, quietMode);
                if applyResult is error {
                    if !quietMode {
                        io:println(string `  ✗ Failed to apply fix: ${applyResult.message()}`);
                    }
                    result.remainingFixes.push(string `Iteration ${iteration}: Failed to apply fix to ${filePath}: ${applyResult.message()}`);
                    continue;
                }

                anyFixApplied = true;
                result.appliedFixes.push(string `Fixed ${filePath} (${fileErrors.length()} error${fileErrors.length() == 1 ? "" : "s"})`);
            } else {
                result.remainingFixes.push(string `User declined fix for ${filePath}`);
            }
        }

        // If no fixes were applied, break to avoid infinite loop
        if !anyFixApplied {
            if !quietMode {
                io:println("  ⚠  No fixes were applied - stopping iterations");
            }
            result.remainingFixes.push(string `Iteration ${iteration}: No fixes applied - stopping iterations`);
            break;
        }

        iteration += 1;
    }

    // Final status check
    if iteration > maxIterations {
        if !quietMode {
            io:println(string `⚠  Reached maximum iterations (${maxIterations})`);
        }
        result.remainingFixes.push(string `Maximum iterations (${maxIterations}) reached`);
    }

    // Final build check
    if !quietMode {
        io:println("");
        io:println("Running final build check...");
    }

    utils:CommandResult finalBuildResult = utils:executeBalBuild(projectPath, true); // Always quiet for final check

    if utils:isCommandSuccessfull(finalBuildResult) {
        result.success = true;
        result.errorsRemaining = 0;
        result.errorsFixed = initialErrorCount;

        if !quietMode {
            io:println("✓ Final build successful - all errors resolved!");
        }
    } else {
        CompilationError[] remainingErrors = parseCompilationErrors(finalBuildResult.stderr);
        result.errorsRemaining = remainingErrors.length();
        result.errorsFixed = initialErrorCount - remainingErrors.length();

        if !quietMode {
            io:println(string `⚠  ${remainingErrors.length()} error${remainingErrors.length() == 1 ? "" : "s"} still remain`);
            if remainingErrors.length() <= 5 {
                io:println("  Remaining errors:");
                foreach CompilationError err in remainingErrors {
                    io:println(string `    ${err.filePath}:${err.line} - ${err.message}`);
                }
            }
        }
    }

    // Print summary
    if !quietMode && (result.appliedFixes.length() > 0 || !result.success) {
        printFixingSummary(result, iteration - 1);
    }

    return result;
}

// Print a user-friendly summary of the fixing process
function printFixingSummary(FixResult result, int totalIterations) {
    // Create separator using array concatenation
    string[] separatorChars = [];
    int i = 0;
    while i < 50 {
        separatorChars.push("-");
        i += 1;
    }
    string sep = string:'join("", ...separatorChars);

    io:println("");
    io:println(sep);
    io:println("ERROR FIXING SUMMARY");
    io:println(sep);

    io:println(string `Iterations: ${totalIterations}`);
    io:println(string `Fixed     : ${result.errorsFixed} error${result.errorsFixed == 1 ? "" : "s"}`);
    io:println(string `Remaining : ${result.errorsRemaining} error${result.errorsRemaining == 1 ? "" : "s"}`);

    if result.success {
        io:println("Status    : ✓ All errors resolved");
    } else {
        io:println("Status    : ⚠  Some errors remain");
    }

    if result.appliedFixes.length() > 0 {
        io:println("");
        io:println("Applied fixes:");
        foreach string fix in result.appliedFixes {
            io:println(string `  • ${fix}`);
        }
    }

    if result.remainingFixes.length() > 0 && result.errorsRemaining > 0 {
        io:println("");
        io:println("Manual intervention may be required for remaining errors.");
    }

    io:println(sep);
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
