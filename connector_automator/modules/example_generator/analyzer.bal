import connector_automator.code_fixer;

import ballerina/file;
import ballerina/io;
import ballerina/lang.'string as strings;
import ballerina/lang.regexp;
import ballerina/os;

// Helper function to check if array contains a value
function arrayContains(string[] arr, string value) returns boolean {
    foreach string item in arr {
        if item == value {
            return true;
        }
    }
    return false;
}

public function analyzeConnector(string connectorPath) returns ConnectorDetails|error {
    string clientBalPath = connectorPath + "/ballerina/client.bal";
    string typesBalPath = connectorPath + "/ballerina/types.bal";
    string ballerinaTomlPath = connectorPath + "/ballerina/Ballerina.toml";

    string clientContent = check io:fileReadString(clientBalPath);
    string typesContent = check io:fileReadString(typesBalPath);
    string balTomlContent = check io:fileReadString(ballerinaTomlPath);

    int apiCount = countApiOperations(clientContent);
    // get the connector name from Ballerina.toml
    string connectorName = "";
    string[] tomlLines = regexp:split(re `\n`, balTomlContent);
    foreach string line in tomlLines {
        string trimmedLine = strings:trim(line);
        if strings:startsWith(trimmedLine, "name") {
            string[] parts = regexp:split(re `=`, trimmedLine);
            if parts.length() > 1 {
                connectorName = strings:trim(regexp:replaceAll(re `"`, parts[1], ""));
            }
        }
    }

    // Extract function signatures
    string functionSignatures = extractFunctionSignatures(clientContent);

    return {
        connectorName: connectorName,
        apiCount: apiCount,
        clientBalContent: clientContent,
        typesBalContent: typesContent,
        functionSignatures: functionSignatures,
        typeNames: ""
    };
}

function countApiOperations(string clientContent) returns int {
    int count = 0;

    // Count resource functions
    regexp:RegExp resourcePattern = re `resource\s+isolated\s+function`;
    regexp:Span[] resourceMatches = resourcePattern.findAll(clientContent);
    count += resourceMatches.length();

    // Count remote functions
    regexp:RegExp remotePattern = re `remote\s+isolated\s+function`;
    regexp:Span[] remoteMatches = remotePattern.findAll(clientContent);
    count += remoteMatches.length();

    return count;
}

public function extractFunctionSignatures(string clientContent) returns string {
    string[] signatures = [];
    // This regex now correctly handles various return types and function structures
    regexp:RegExp functionPattern = re `(resource|remote)\s+isolated\s+function\s+[\s\S]*?returns\s+[^{]+`;
    regexp:Span[] matches = functionPattern.findAll(clientContent);

    foreach regexp:Span span in matches {
        string signature = clientContent.substring(span.startIndex, span.endIndex);
        // Clean up whitespace for better LLM understanding
        signature = regexp:replaceAll(re `\s+`, signature, " ").trim();
        signatures.push(signature);
    }

    return string:'join("\n", ...signatures);
}

// Find a matching function in client content based on LLM-provided function name
public function findMatchingFunction(string clientContent, string llmFunctionName) returns string? {
    // Extract all function definitions
    regexp:RegExp functionPattern = re `(resource\s+isolated\s+function|remote\s+isolated\s+function)\s+[^{]+\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}`;
    regexp:Span[] matches = functionPattern.findAll(clientContent);

    foreach regexp:Span span in matches {
        string functionDef = clientContent.substring(span.startIndex, span.endIndex);

        // Check if this function could match the LLM-provided name
        // For resource functions like "get advisories" -> look for "get" method in path with "advisories"
        // For remote functions, match by function name more directly
        if isMatchingFunction(functionDef, llmFunctionName) {
            return functionDef;
        }
    }

    return ();
}

// Helper to determine if a function definition matches the LLM-provided name
public function isMatchingFunction(string functionDef, string llmFunctionName) returns boolean {
    // Clean the function definition by removing Ballerina's path escapes `\.` -> `.`
    // and convert to lowercase for case-insensitive comparison.
    string cleanFuncDef = regexp:replaceAll(re `\\\.`, functionDef, ".").toLowerAscii();

    // Convert the LLM function name to lowercase as well.
    string lowerLLMName = llmFunctionName.toLowerAscii();

    // For resource functions, check if the cleaned function definition contains the LLM name
    // For example: "get admin\.apps\.requests\.list" becomes "get admin.apps.requests.list"  
    // and should match "get admin.apps.requests.list"
    if lowerLLMName.includes(" ") {
        // Resource function - check if the entire pattern matches
        return cleanFuncDef.includes(lowerLLMName);
    } else {
        // Remote function - check function name only
        return cleanFuncDef.includes(lowerLLMName);
    }
}

public function numberOfExamples(int apiCount) returns int {
    if apiCount < 15 {
        return 1;
    } else if apiCount <= 30 {
        return 2;
    } else if apiCount <= 60 {
        return 3;
    } else {
        return 4;
    }
}

public function writeExampleToFile(string connectorPath, string exampleName, string useCase, string exampleCode, string connectorName) returns error? {
    // Create examples directory if it doesn't exist
    string examplesDir = connectorPath + "/examples";
    check file:createDir(examplesDir, file:RECURSIVE);

    // Use the provided example name directly
    string exampleDir = examplesDir + "/" + exampleName;

    // Create example directory
    check file:createDir(exampleDir, file:RECURSIVE);

    // Create .github directory
    string githubDir = exampleDir + "/.github";
    check file:createDir(githubDir, file:RECURSIVE);

    // Write main.bal file
    string mainBalPath = exampleDir + "/main.bal";
    check io:fileWriteString(mainBalPath, exampleCode);

    // Write Ballerina.toml file
    string ballerinaTomlPath = exampleDir + "/Ballerina.toml";
    string ballerinaTomlContent = generateBallerinaToml(exampleName, connectorName);
    check io:fileWriteString(ballerinaTomlPath, ballerinaTomlContent);
}

// Function to sanitize example name for Ballerina package name
function sanitizePackageName(string exampleName) returns string {
    string sanitized = regexp:replaceAll(re `-`, exampleName, "_");

    sanitized = regexp:replaceAll(re `[^a-zA-Z0-9_.]`, sanitized, "");
    // Ensure it's not empty
    if sanitized == "" {
        sanitized = "example";
    }

    return sanitized;
}

function generateBallerinaToml(string exampleName, string connectorName) returns string {
    string packageName = sanitizePackageName(exampleName);

    return string `[package]
org = "wso2"
name = "${packageName}"
version = "0.1.0"
distribution = "2201.10.0"

[build-options]
observabilityIncluded = true

[[dependency]]
org = "ballerinax"
name = "${connectorName}"
version = "0.1.0"
repository = "local"
`;
}

public function fixExampleCode(string exampleDir, string exampleName) returns error? {
    //io:println(string `Checking and fixing compilation errors for example: ${exampleName}`);

    // Use the fixer to fix all compilation errors in the example directory
    code_fixer:FixResult|code_fixer:BallerinaFixerError fixResult = code_fixer:fixAllErrors(exampleDir, autoYes = true, quietMode = true);

    if fixResult is code_fixer:FixResult {
        if fixResult.success {
            io:println(string `✓ Example '${exampleName}' compiles successfully!`);
            if fixResult.errorsFixed > 0 {
                io:println(string `  Fixed ${fixResult.errorsFixed} compilation errors`);
                if fixResult.appliedFixes.length() > 0 {
                    io:println("  Applied fixes:");
                    foreach string fix in fixResult.appliedFixes {
                        io:println(string `    • ${fix}`);
                    }
                }
            }
        } else {
            io:println(string `⚠ Example '${exampleName}' partially fixed:`);
            io:println(string `  Fixed ${fixResult.errorsFixed} errors`);
            io:println(string `  ${fixResult.errorsRemaining} errors remain`);
            if fixResult.appliedFixes.length() > 0 {
                io:println("  Applied fixes:");
                foreach string fix in fixResult.appliedFixes {
                    io:println(string `    • ${fix}`);
                }
            }
            // Don't fail completely, but warn about remaining errors
            io:println("  Some errors may require manual intervention");
        }
    } else {
        io:println(string `✗ Failed to fix example '${exampleName}': ${fixResult.message()}`);
        return error(string `Failed to fix compilation errors in example: ${exampleName}`, fixResult);
    }

    return;
}

public function extractTargetedContext(ConnectorDetails details, string[] functionNames) returns string|error {
    string clientContent = details.clientBalContent;
    string typesContent = details.typesBalContent;

    // io:println("=== EXTRACTING TARGETED CONTEXT ===");
    // io:println("Original client.bal size: ", clientContent.length(), " chars");
    // io:println("Original types.bal size: ", typesContent.length(), " chars");
    // io:println("Function names to match: ", functionNames.toString());

    string context = "// CLIENT INITIALIZATION\n\n";
    string[] allDependentTypes = [];

    // always extract the init function and ConnectionConfig

    string? initSignature = findInitFunctionSignature(clientContent);
    if initSignature is string {
        context += initSignature + "\n\n";

        // extract ConnectionConfig and related types
        string[] initTypes = findTypesInSignatures(initSignature);
        allDependentTypes.push(...initTypes);
    }

    context += "\n//FUNCTION SIGNATURES\n\n";

    // Extract only function signatures (not implementations) by matching the LLM-provided names

    int matchedFunctions = 0;
    foreach string funcName in functionNames {
        string? matchedSignature = findMatchingFunctionSignature(clientContent, funcName);
        if matchedSignature is string {
            context += matchedSignature + "\n\n";
            matchedFunctions += 1;
            // io:println("✓ Matched function: '", funcName, "' -> signature length: ", matchedSignature.length(), " chars");
        } else {
            // io:println("✗ No match found for: '", funcName, "'");
        }
    }
    //  io:println("Total matched functions: ", matchedFunctions, "/", functionNames.length());

    // Find all types used in the function signatures (parameters and return types)
    string[] directTypes = findTypesInSignatures(context);
    allDependentTypes.push(...directTypes);

    // Selectively find only essential nested types (limited depth)
    findEssentialNestedTypes(directTypes, typesContent, allDependentTypes, maxDepth = 2);

    // Add type definitions section
    if allDependentTypes.length() > 0 {
        context += "\n// TYPE DEFINITIONS\n\n";
        // Extract only essential type definitions with size limits
        foreach string typeName in allDependentTypes {
            string typeDef = extractCompactTypeDefinition(typesContent, typeName);
            if typeDef != "" {
                context += typeDef + "\n\n";
            }
        }
    }

    // io:println("Final targeted context size: ", context.length(), " chars");
    // int originalSize = clientContent.length() + typesContent.length();
    // int reductionPercent = (originalSize - context.length()) * 100 / originalSize;
    // io:println("Size reduction: ", reductionPercent, "%");

    return context;
}

function findInitFunctionSignature(string clientContent) returns string? {
    regexp:RegExp initPattern = re `public\sisolated\sfunction\sinit\s*\([^{]*\)\sreturns\s[^{]+`;
    regexp:Span[] matches = initPattern.findAll(clientContent);

    if matches.length() > 0 {
        regexp:Span span = matches[0];
        string signature = clientContent.substring(span.startIndex, span.endIndex).trim();

        string cleanSignature = regexp:replaceAll(re `\s+`, signature, " ");

        string docComment = extractFunctionDocumentation(clientContent, span.startIndex);

        if docComment != "" {
            return docComment + "\n" + cleanSignature + ";";
        } else {
            return cleanSignature + ";";
        }
    }

    return ();

}

function findNestedTypes(string[] typesToSearch, string typesContent, string[] foundTypes) {
    string[] newTypesFound = [];
    foreach string typeName in typesToSearch {
        string typeDef = extractBlock(typesContent, "public type " + typeName, "{", "}");
        if typeDef == "" {
            typeDef = extractBlock(typesContent, "public type " + typeName, ";", ";");
        }

        if typeDef != "" {
            string[] nested = findTypesInSignatures(typeDef);
            foreach string nestedType in nested {
                // If it's a new type we haven't processed yet, add it to the list
                if !arrayContains(foundTypes, nestedType) {
                    newTypesFound.push(nestedType);
                    foundTypes.push(nestedType);
                }
            }
        }
    }
    // If we found new types, we need to search within them as well
    if newTypesFound.length() > 0 {
        findNestedTypes(newTypesFound, typesContent, foundTypes);
    }
}

function findTypesInSignatures(string signatures) returns string[] {
    regexp:RegExp typePattern = re `[A-Z][a-zA-Z0-9_]*`;
    regexp:Span[] matches = typePattern.findAll(signatures);
    string[] types = [];
    foreach regexp:Span span in matches {
        types.push(signatures.substring(span.startIndex, span.endIndex));
    }
    return types;
}

function extractBlock(string content, string startPattern, string openChar, string closeChar) returns string {
    // This is a simplified block extractor. It finds the start pattern and then balances
    // the open/close characters to find the end of the block.
    int? startIndex = content.indexOf(startPattern);
    if startIndex is () {
        return "";
    }

    int? openBraceIndex = content.indexOf(openChar, startIndex);
    if openBraceIndex is () {
        return "";
    }

    int braceCount = 1;
    int currentIndex = openBraceIndex + 1;
    while (braceCount > 0 && currentIndex < content.length()) {
        if content.substring(currentIndex, currentIndex + 1) == openChar {
            braceCount += 1;
        } else if content.substring(currentIndex, currentIndex + 1) == closeChar {
            braceCount -= 1;
        }
        currentIndex += 1;
    }

    return content.substring(startIndex, currentIndex);
}

// Extract only function signature without implementation
function findMatchingFunctionSignature(string clientContent, string llmFunctionName) returns string? {
    // Find all function starts and then extract the complete signature manually
    regexp:RegExp functionStartPattern = re `(resource\s+isolated\s+function|remote\s+isolated\s+function)`;
    regexp:Span[] startMatches = functionStartPattern.findAll(clientContent);

    foreach regexp:Span startSpan in startMatches {
        // From the start of the function, find the complete signature up to the function body brace
        int startIndex = startSpan.startIndex;

        // Find the pattern "returns ... {" to identify the function body start
        int? returnsIndex = clientContent.indexOf("returns", startIndex);

        if returnsIndex is int {
            // Find the opening brace after "returns"
            int? braceIndex = clientContent.indexOf("{", returnsIndex);

            if braceIndex is int {
                string functionSignature = clientContent.substring(startIndex, braceIndex).trim();

                // Check if this function could match the LLM-provided name
                if isMatchingFunction(functionSignature, llmFunctionName) {
                    // Clean up the signature by removing extra whitespace and normalizing
                    string cleanSignature = regexp:replaceAll(re `\s+`, functionSignature.trim(), " ");

                    // Extract documentation comment if available
                    string docComment = extractFunctionDocumentation(clientContent, startIndex);

                    if docComment != "" {
                        return docComment + "\n" + cleanSignature + ";";
                    } else {
                        return cleanSignature + ";";
                    }
                }
            }
        }
    }

    return ();
}

// Extract function documentation comments
function extractFunctionDocumentation(string content, int functionStartIndex) returns string {
    // Look backwards from function start to find documentation comment
    int currentIndex = functionStartIndex - 1;
    string docComment = "";

    // Skip whitespace
    while currentIndex >= 0 && (content.substring(currentIndex, currentIndex + 1) == " " ||
            content.substring(currentIndex, currentIndex + 1) == "\n" ||
            content.substring(currentIndex, currentIndex + 1) == "\r" ||
            content.substring(currentIndex, currentIndex + 1) == "\t") {
        currentIndex -= 1;
    }

    // Check if there's a documentation comment ending here
    if currentIndex >= 1 && content.substring(currentIndex - 1, currentIndex + 1) == "*/" {
        // Find the start of the comment
        int? commentStartIndex = content.lastIndexOf("/*", currentIndex - 1);
        if commentStartIndex is int {
            string comment = content.substring(commentStartIndex, currentIndex + 1);
            // Extract only the essential parts (# lines)
            string[] lines = regexp:split(re `\n`, comment);
            string[] docLines = [];

            foreach string line in lines {
                string trimmed = line.trim();
                if trimmed.startsWith("#") || trimmed.startsWith("# +") || trimmed.startsWith("# -") {
                    docLines.push(trimmed);
                }
            }

            if docLines.length() > 0 && docLines.length() <= 5 { // Limit doc comment size
                docComment = string:'join("\n", ...docLines);
            }
        }
    }

    return docComment;
}

// Limited depth nested type search to avoid infinite recursion
function findEssentialNestedTypes(string[] typesToSearch, string typesContent, string[] foundTypes, int maxDepth) {
    if maxDepth <= 0 {
        return; // Stop recursion at max depth
    }

    string[] newTypesFound = [];
    foreach string typeName in typesToSearch {
        // Only search for essential types (skip Headers, Queries, and overly generic types)
        if isEssentialType(typeName) {
            string typeDef = extractCompactTypeDefinition(typesContent, typeName);

            if typeDef != "" {
                string[] nested = findTypesInSignatures(typeDef);
                foreach string nestedType in nested {
                    // If it's a new essential type we haven't processed yet, add it
                    if !arrayContains(foundTypes, nestedType) && isEssentialType(nestedType) {
                        newTypesFound.push(nestedType);
                        foundTypes.push(nestedType);
                    }
                }
            }
        }
    }

    // Continue search with remaining depth
    if newTypesFound.length() > 0 {
        findEssentialNestedTypes(newTypesFound, typesContent, foundTypes, maxDepth - 1);
    }
}

// Check if a type is essential (not a header, query, or internal type)
function isEssentialType(string typeName) returns boolean {
    string lowerType = typeName.toLowerAscii();

    // Skip non-essential types
    if lowerType.endsWith("headers") || lowerType.endsWith("queries") ||
        lowerType.endsWith("header") || lowerType.endsWith("query") ||
        lowerType.startsWith("http") || lowerType.startsWith("internal") ||
        lowerType == "error" || lowerType == "string" || lowerType == "decimal" ||
        lowerType == "int" || lowerType == "boolean" || lowerType == "json" ||
        lowerType.length() < 3 {
        return false;
    }

    return true;
}

// Extract compact type definition (limit size and complexity)
function extractCompactTypeDefinition(string typesContent, string typeName) returns string {
    string typeDef = extractBlock(typesContent, "public type " + typeName, "{", "}");
    if typeDef == "" {
        typeDef = extractBlock(typesContent, "public type " + typeName + " ", ";", ";");
    }

    if typeDef != "" && typeDef.length() > 1000 { // Limit type definition size
        // If type is too large, create a simplified version
        string[] lines = regexp:split(re `\n`, typeDef);
        if lines.length() > 15 { // If too many fields, show only first 10
            string[] limitedLines = [];
            int count = 0;
            foreach string line in lines {
                limitedLines.push(line);
                count += 1;
                if count >= 12 { // Keep first few lines including opening
                    limitedLines.push("    // ... (additional fields omitted for brevity)");
                    // Find and add the closing brace
                    foreach int i in (lines.length() - 3) ... (lines.length() - 1) {
                        if i < lines.length() && lines[i].includes("}") {
                            limitedLines.push(lines[i]);
                            break;
                        }
                    }
                    break;
                }
            }
            typeDef = string:'join("\n", ...limitedLines);
        }
    }

    return typeDef;
}

function packAndPushConnector(string connectorPath) returns error? {
    string ballerinaDir = connectorPath + "/ballerina";

    // Check if ballerina directory exists
    boolean|error ballerinaExists = file:test(ballerinaDir, file:EXISTS);
    if ballerinaExists is error || !ballerinaExists {
        return error("Ballerina directory not found at: " + ballerinaDir);
    }

    // Execute bal pack with working directory specified
    io:println("Running 'bal pack' in connector directory...");
    string packCommand = "bal pack";
    string redirectedPackCommand = string `cd "${ballerinaDir}" && ${packCommand}`;

    os:Command packCmd = {
        value: "sh",
        arguments: ["-c", redirectedPackCommand]
    };

    os:Process|error packProcess = os:exec(packCmd);
    if packProcess is error {
        return error("Failed to execute 'bal pack' command", packProcess);
    }

    int|error packExitCode = packProcess.waitForExit();
    if packExitCode is error {
        return error("Failed to wait for 'bal pack' process", packExitCode);
    }

    if packExitCode != 0 {
        return error("'bal pack' command failed with exit code: " + packExitCode.toString());
    }

    // Execute bal push --repository=local with working directory specified
    io:println("Running 'bal push --repository=local' in connector directory...");
    string pushCommand = "bal push --repository=local";
    string redirectedPushCommand = string `cd "${ballerinaDir}" && ${pushCommand}`;

    os:Command pushCmd = {
        value: "sh",
        arguments: ["-c", redirectedPushCommand]
    };

    os:Process|error pushProcess = os:exec(pushCmd);
    if pushProcess is error {
        return error("Failed to execute 'bal push --repository=local' command", pushProcess);
    }

    int|error pushExitCode = pushProcess.waitForExit();
    if pushExitCode is error {
        return error("Failed to wait for 'bal push' process", pushExitCode);
    }

    if pushExitCode != 0 {
        return error("'bal push --repository=local' command failed with exit code: " + pushExitCode.toString());
    }

    return;
}
