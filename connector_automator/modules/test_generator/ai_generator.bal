import connector_automator.code_fixer;
import connector_automator.cost_calculator;
import connector_automator.utils;

import ballerina/io;
import ballerina/lang.'string as strings;

const int MAX_OPERATIONS = 30;

function completeMockServer(string mockServerPath, string typesPath, boolean quietMode = false) returns error? {
    // Read the generated mock server template
    string mockServerContent = check io:fileReadString(mockServerPath);
    string typesContent = check io:fileReadString(typesPath);

    // generate completed mock server using LLM
    string prompt = createMockServerPrompt(mockServerContent, typesContent);

    string completeMockServer = check utils:callAI(prompt);

    cost_calculator:trackUsageFromText("test_generator_mock", prompt, completeMockServer, "claude-4-sonnet");

    check io:fileWriteString(mockServerPath, completeMockServer);

    if !quietMode {
        io:println("✓ Mock server template completed successfully");
    }
    return;
}

function generateTestFile(string connectorPath, boolean quietMode = false) returns error? {
    // Simplified analysis - only get package name and mock server content
    ConnectorAnalysis analysis = check analyzeConnectorForTests(connectorPath);

    // Generate test content using AI
    string testContent = check generateTestsWithAI(analysis);

    // Write test file
    string testFilePath = connectorPath + "/ballerina/tests/test.bal";
    check io:fileWriteString(testFilePath, testContent);

    if !quietMode {
        io:println("✓ Test file generated successfully");
    }
    return;
}

function generateTestsWithAI(ConnectorAnalysis analysis) returns string|error {
    string prompt = createTestGenerationPrompt(analysis);

    string result = check utils:callAI(prompt);

    cost_calculator:trackUsageFromText("test_generator", prompt, result, "claude-4-sonnet");

    return result;
}

function fixTestFileErrors(string connectorPath, boolean quietMode = false) returns error? {
    if !quietMode {
        io:println("Checking and fixing compilation errors in the entire project...");
    }

    string ballerinaDir = connectorPath + "/ballerina";

    // Use the fixer to fix all compilation errors related to tests
    code_fixer:FixResult|code_fixer:BallerinaFixerError fixResult = code_fixer:fixAllErrors(ballerinaDir, autoYes = true, quietMode = quietMode);

    if fixResult is code_fixer:FixResult {
        if fixResult.success {
            if !quietMode {
                io:println("✓ All files compile successfully!");
                if fixResult.errorsFixed > 0 {
                    io:println(string `  Fixed ${fixResult.errorsFixed} compilation errors`);
                    if fixResult.appliedFixes.length() > 0 {
                        io:println("  Applied fixes:");
                        foreach string fix in fixResult.appliedFixes {
                            io:println(string `    • ${fix}`);
                        }
                    }
                }
            }
        } else {
            if !quietMode {
                io:println("⚠ Project partially fixed:");
                io:println(string `  Fixed ${fixResult.errorsFixed} errors`);
                io:println(string `  ${fixResult.errorsRemaining} errors remain`);
                if fixResult.appliedFixes.length() > 0 {
                    io:println("  Applied fixes:");
                    foreach string fix in fixResult.appliedFixes {
                        io:println(string `    • ${fix}`);
                    }
                }
                io:println("  Some errors may require manual intervention");
            }
        }
    } else {
        if !quietMode {
            io:println(string `✗ Failed to fix project: ${fixResult.message()}`);
        }
        return error("Failed to fix compilation errors in the project", fixResult);
    }

    return;
}

function selectOperationsUsingAI(string specPath, boolean quietMode = false) returns string|error {
    string[] allOperationIds = check extractOperationIdsFromSpec(specPath);

    string prompt = createOperationSelectionPrompt(allOperationIds, MAX_OPERATIONS);

    // Track input cost
    cost_calculator:trackUsageFromText("test_generator_selection", prompt, "", "claude-4-sonnet");

    string aiResponse = check utils:callAI(prompt);

    // Track output cost
    cost_calculator:trackUsageFromText("test_generator_selection", "", aiResponse, "claude-4-sonnet");

    // Clean up the AI response - simple string operations
    string cleanedResponse = strings:trim(aiResponse);
    // Remove code blocks if present
    if strings:includes(cleanedResponse, "```") {
        int? startIndexOpt = cleanedResponse.indexOf("```");
        if startIndexOpt is int {
            int startIndex = startIndexOpt;
            int? endIndexOpt = cleanedResponse.indexOf("```", startIndex + 3);
            if endIndexOpt is int && endIndexOpt > startIndex {
                cleanedResponse = cleanedResponse.substring(startIndex + 3, endIndexOpt);
                cleanedResponse = strings:trim(cleanedResponse);
            }
        }
    }

    // Validate that we got a proper comma-separated list
    if !strings:includes(cleanedResponse, ",") {
        return error("AI did not return a proper comma-separated list of operations");
    }

    if !quietMode {
        io:println("✓ Operations selected using AI");
    }

    return cleanedResponse;
}

function extractOperationIdsFromSpec(string specPath) returns string[]|error {
    string specContent = check io:fileReadString(specPath);

    string[] operationIds = [];
    string searchPattern = "\"operationId\"";
    int currentPos = 0;

    while true {
        int? foundPos = specContent.indexOf(searchPattern, currentPos);
        if foundPos is () {
            break;
        }

        int searchPos = foundPos + searchPattern.length();
        int? colonPos = specContent.indexOf(":", searchPos);
        if colonPos is () {
            currentPos = foundPos + 1;
            continue;
        }

        int? firstQuotePos = specContent.indexOf("\"", colonPos + 1);
        if firstQuotePos is () {
            currentPos = foundPos + 1;
            continue;
        }

        int? secondQuotePos = specContent.indexOf("\"", firstQuotePos + 1);
        if secondQuotePos is () {
            currentPos = foundPos + 1;
            continue;
        }

        string operationId = specContent.substring(firstQuotePos + 1, secondQuotePos);
        if operationId.length() > 0 {
            operationIds.push(operationId);
        }

        currentPos = secondQuotePos + 1;
    }

    return operationIds;
}
