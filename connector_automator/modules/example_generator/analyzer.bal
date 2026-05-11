import wso2/connector_automator.code_fixer;

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
    string connectorOrg = "generated";
    string connectorName = "connector";
    string connectorVersion = "0.1.0";
    string connectorDistribution = "2201.13.1";
    boolean inPackageSection = false;
    string[] tomlLines = regexp:split(re `\n`, balTomlContent);
    foreach string line in tomlLines {
        string trimmedLine = strings:trim(line);
        if trimmedLine == "[package]" {
            inPackageSection = true;
            continue;
        }
        if strings:startsWith(trimmedLine, "[") && trimmedLine != "[package]" {
            inPackageSection = false;
            continue;
        }
        if !inPackageSection {
            continue;
        }

        int? equalIndex = trimmedLine.indexOf("=");
        if equalIndex is int {
            string key = strings:trim(trimmedLine.substring(0, <int>equalIndex));
            string rawValue = strings:trim(trimmedLine.substring(<int>equalIndex + 1));
            string value = strings:trim(regexp:replaceAll(re `"`, rawValue, ""));

            if key == "org" {
                connectorOrg = value;
            } else if key == "name" {
                connectorName = value;
            } else if key == "version" {
                connectorVersion = value;
            } else if key == "distribution" {
                connectorDistribution = value;
            }
        }
    }

    // Extract function signatures
    string functionSignatures = extractFunctionSignatures(clientContent);

    return {
        connectorOrg: connectorOrg,
        connectorName: connectorName,
        connectorVersion: connectorVersion,
        connectorDistribution: connectorDistribution,
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
        if isMatchingFunction(functionDef, llmFunctionName) {
            return functionDef;
        }
    }

    return ();
}

// Helper to determine if a function definition matches the LLM-provided name
public function isMatchingFunction(string functionDef, string llmFunctionName) returns boolean {
    string cleanFuncDef = regexp:replaceAll(re `\\\.`, functionDef, ".").toLowerAscii();

    // Convert the LLM function name to lowercase as well.
    string lowerLLMName = llmFunctionName.toLowerAscii();

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

public function writeExampleToFile(string connectorPath, string exampleName, string useCase, string exampleCode,
    string connectorOrg, string connectorName, string connectorVersion, string connectorDistribution) returns error? {
    // Create examples directory if it doesn't exist
    string examplesDir = connectorPath + "/examples";
    check file:createDir(examplesDir, file:RECURSIVE);

    // Use the provided example name directly
    string exampleDir = examplesDir + "/" + exampleName;

    // Create example directory
    check file:createDir(exampleDir, file:RECURSIVE);

    // Write main.bal file
    string mainBalPath = exampleDir + "/main.bal";
    check io:fileWriteString(mainBalPath, exampleCode);

    // Write Ballerina.toml file
    string ballerinaTomlPath = exampleDir + "/Ballerina.toml";
    string ballerinaTomlContent = generateBallerinaToml(exampleName, connectorOrg, connectorName,
        connectorVersion, connectorDistribution);
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

function generateBallerinaToml(string exampleName, string connectorOrg, string connectorName,
        string connectorVersion, string connectorDistribution) returns string {
    string packageName = sanitizePackageName(exampleName);

    return string `[package]
org = "generated_examples"
name = "${packageName}"
version = "0.1.0"
distribution = "${connectorDistribution}"

[build-options]
observabilityIncluded = true

[[dependency]]
org = "${connectorOrg}"
name = "${connectorName}"
version = "${connectorVersion}"
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
            io:println("  Some errors may require manual intervention");
            return error(string `Example '${exampleName}' still has ${fixResult.errorsRemaining} unresolved compilation errors`);
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
        } else {
        }
    }

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

            if docLines.length() > 0 && docLines.length() <= 5 { 
                docComment = string:'join("\n", ...docLines);
            }
        }
    }

    return docComment;
}

// Limited depth nested type search to avoid infinite recursion
function findEssentialNestedTypes(string[] typesToSearch, string typesContent, string[] foundTypes, int maxDepth) {
    if maxDepth <= 0 {
        return;
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

    if typeDef != "" && typeDef.length() > 1000 { 
        // If type is too large, create a simplified version
        string[] lines = regexp:split(re `\n`, typeDef);
        if lines.length() > 15 {
            string[] limitedLines = [];
            int count = 0;
            foreach string line in lines {
                limitedLines.push(line);
                count += 1;
                if count >= 12 {
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

    check ensureConnectorReadme(ballerinaDir);

    error? prepareError = prepareNativeInteropForPack(connectorPath, ballerinaDir);
    if prepareError is error {
        return prepareError;
    }

    // Execute bal pack with working directory specified
    io:println("Running 'bal pack' in connector directory...");
    int|error packExitCode = runShellInDir(ballerinaDir, "bal pack");
    if packExitCode is error {
        return error("Failed to execute 'bal pack' command", packExitCode);
    }

    if packExitCode != 0 {
        io:println("'bal pack' failed. Attempting automated connector fixes before retry...");

        code_fixer:FixResult|code_fixer:BallerinaFixerError javaFixResult =
            code_fixer:fixJavaNativeAdaptorErrors(connectorPath, quietMode = true, autoYes = true);
        if javaFixResult is code_fixer:BallerinaFixerError {
            return error("'bal pack' failed and Java native auto-fix failed", javaFixResult);
        }

        code_fixer:FixResult|code_fixer:BallerinaFixerError balFixResult =
            code_fixer:fixAllErrors(ballerinaDir, quietMode = true, autoYes = true);
        if balFixResult is code_fixer:BallerinaFixerError {
            return error("'bal pack' failed and Ballerina auto-fix failed", balFixResult);
        }

        io:println("Retrying 'bal pack' after automated fixes...");
        int|error retryPackExitCode = runShellInDir(ballerinaDir, "bal pack");
        if retryPackExitCode is error {
            return error("Failed to execute retry 'bal pack' command", retryPackExitCode);
        }
        if retryPackExitCode != 0 {
            return error("'bal pack' command failed after retry with exit code: " + retryPackExitCode.toString());
        }
    }

    io:println("Running 'bal push --repository=local' in connector directory...");
    int|error pushExitCode = runShellInDir(ballerinaDir, "bal push --repository=local");
    if pushExitCode is error {
        return error("Failed to execute 'bal push --repository=local' command", pushExitCode);
    }

    if pushExitCode != 0 {
        return error("'bal push --repository=local' command failed with exit code: " + pushExitCode.toString());
    }

    return;
}

function ensureConnectorReadme(string ballerinaDir) returns error? {
    string readmePath = ballerinaDir + "/README.md";
    boolean|error readmeExists = file:test(readmePath, file:EXISTS);
    if readmeExists is error {
        return readmeExists;
    }
    if !readmeExists {
        string defaultReadme = "# Generated Connector\n\nThis package is auto-generated by connector automation.\n";
        check io:fileWriteString(readmePath, defaultReadme);
    }
}

function runShellInDir(string workingDir, string shellCommand) returns int|error {
    string redirectedCommand = string `cd "${workingDir}" && ${shellCommand}`;

    os:Command cmd = {
        value: "sh",
        arguments: ["-c", redirectedCommand]
    };

    os:Process|error process = os:exec(cmd);
    if process is error {
        return process;
    }

    int|error exitCode = process.waitForExit();
    if exitCode is error {
        return exitCode;
    }

    return exitCode;
}

function prepareNativeInteropForPack(string connectorPath, string ballerinaDir) returns error? {
    boolean|error hasBuildGradle = file:test(connectorPath + "/build.gradle", file:EXISTS);
    boolean|error hasNativeBuildGradle = file:test(connectorPath + "/native/build.gradle", file:EXISTS);
    boolean nativeRequired = (hasBuildGradle is boolean && hasBuildGradle) ||
                             (hasNativeBuildGradle is boolean && hasNativeBuildGradle);
    if !nativeRequired {
        return;
    }

    // A build.gradle alone does not mean native Java source exists (e.g. OpenAPI connectors
    // may inherit one from a parent directory). Only proceed if Java source files are present.
    boolean|error hasNativeSrc = file:test(connectorPath + "/native/src", file:EXISTS);
    boolean|error hasTopLevelSrc = file:test(connectorPath + "/src/main/java", file:EXISTS);
    boolean javaSourceExists = (hasNativeSrc is boolean && hasNativeSrc) ||
                               (hasTopLevelSrc is boolean && hasTopLevelSrc);
    if !javaSourceExists {
        return;
    }

    string nativeDir = resolveNativeProjectDir(connectorPath);

    check ensureBuildGradleCompatibility(nativeDir);
    check ensureBuildGradleProducesFatJar(nativeDir);

    io:println("Building native adaptor JAR...");
    record {|int exitCode; string stdout; string stderr;|}|error gradleRun = runGradleJarInDir(nativeDir);
    if gradleRun is error {
        return error("Failed to execute 'gradle jar'", gradleRun);
    }
    int gradleExit = gradleRun.exitCode;
    if gradleExit != 0 {
        io:println("'gradle jar' failed; attempting Java native auto-fix...");
        string firstGradleError = firstNonEmptyLine(gradleRun.stderr);
        if firstGradleError.length() > 0 {
            io:println(string `  Gradle error: ${firstGradleError}`);
        }
        code_fixer:FixResult|code_fixer:BallerinaFixerError javaFixResult =
            code_fixer:fixJavaNativeAdaptorErrors(nativeDir, quietMode = true, autoYes = true);

        if javaFixResult is code_fixer:BallerinaFixerError {
            string? existingJarPath = findNativeJarRelativePath(nativeDir);
            if existingJarPath is string {
                io:println("Java native auto-fix failed; using existing native adaptor JAR...");
            } else {
                return error("'gradle jar' command failed and Java native auto-fix failed", javaFixResult);
            }
        } else {
            record {|int exitCode; string stdout; string stderr;|}|error retryGradleRun = runGradleJarInDir(nativeDir);
            if retryGradleRun is error {
                return error("Failed to execute retry 'gradle jar'", retryGradleRun);
            }
            int retryGradleExit = retryGradleRun.exitCode;
            if retryGradleExit != 0 {
                string retryGradleError = firstNonEmptyLine(retryGradleRun.stderr);
                if retryGradleError.length() > 0 {
                    io:println(string `  Retry gradle error: ${retryGradleError}`);
                }
                boolean fallbackCopied = check tryUseExistingNativeJar(nativeDir);
                if fallbackCopied {
                    io:println("Retry 'gradle jar' failed; reused existing native adaptor JAR for this dataset...");
                }
                string? existingJarPath = findNativeJarRelativePath(nativeDir);
                if existingJarPath is string {
                    io:println("Retry 'gradle jar' failed; using existing native adaptor JAR...");
                } else {
                    return error("'gradle jar' command failed after Java native auto-fix with exit code: " +
                        retryGradleExit.toString());
                }
            }
        }
    }

    string? jarRelativePath = findNativeJarRelativePath(nativeDir);
    if jarRelativePath is () {
        return error("Native adaptor JAR not found under build/libs after gradle build");
    }

    check ensureClientInteropClassBinding(nativeDir, ballerinaDir);

    string tomlPath = ballerinaDir + "/Ballerina.toml";
    string tomlContent = check io:fileReadString(tomlPath);
    string dependencyBlock = string `[[platform.java21.dependency]]
path = "${<string>jarRelativePath}"`;

    if tomlContent.includes("[[platform.java21.dependency]]") && tomlContent.includes(<string>jarRelativePath) {
        return;
    }

    string updatedToml = tomlContent.trim();
    if !updatedToml.includes("\"ballerina/jballerina.java\"") {
        if !updatedToml.includes("[dependencies]") {
            updatedToml += "\n\n[dependencies]\n";
        }
        updatedToml += "\n\"ballerina/jballerina.java\" = \"0.0.0\"\n";
    }

    if updatedToml.includes("[[platform.java21.dependency]]") {
        if !updatedToml.includes(<string>jarRelativePath) {
            updatedToml += "\n\n" + dependencyBlock + "\n";
        }
    } else {
        updatedToml += "\n\n" + dependencyBlock + "\n";
    }

    check io:fileWriteString(tomlPath, updatedToml + "\n");
}

function ensureClientInteropClassBinding(string connectorPath, string ballerinaDir) returns error? {
    string? nativeClassFqcn = detectNativeAdaptorClassFromJar(connectorPath);
    if nativeClassFqcn is () {
        nativeClassFqcn = detectNativeAdaptorClass(connectorPath);
    }
    if nativeClassFqcn is () {
        return;
    }

    string clientPath = ballerinaDir + "/client.bal";
    boolean|error clientExists = file:test(clientPath, file:EXISTS);
    if clientExists is error {
        return clientExists;
    }
    if !clientExists {
        return;
    }

    string clientContent = check io:fileReadString(clientPath);
    if clientContent.includes(string `'class: "${<string>nativeClassFqcn}"`) {
        return;
    }

    string updatedClient = regexp:replaceAll(re `'class:\s*"[^"]+"`, clientContent,
        string `'class: "${<string>nativeClassFqcn}"`);
    check io:fileWriteString(clientPath, updatedClient);
}

function detectNativeAdaptorClassFromJar(string connectorPath) returns string? {
    record {|int exitCode; string stdout; string stderr;|}|error jarResult = executeShellInDir(connectorPath,
        "jar tf build/libs/generated-native-adaptor.jar | grep -E 'Adaptor\\.class$' | head -n 1");
    if jarResult is error || jarResult.exitCode != 0 {
        return;
    }

    string classEntry = jarResult.stdout.trim();
    if classEntry.length() == 0 || !classEntry.endsWith(".class") {
        return;
    }

    string fqcnPath = classEntry.substring(0, classEntry.length() - 6);
    return regexp:replaceAll(re `/`, fqcnPath, ".");
}

function detectNativeAdaptorClass(string connectorPath) returns string? {
    record {|int exitCode; string stdout; string stderr;|}|error findResult = executeShellInDir(connectorPath,
        "find src/main/java -type f -name '*Adaptor.java' | head -n 1");
    if findResult is error || findResult.exitCode != 0 {
        return;
    }

    string relPath = findResult.stdout.trim();
    if relPath.length() == 0 {
        return;
    }

    string sourcePath = connectorPath + "/" + relPath;
    string|io:Error sourceRead = io:fileReadString(sourcePath);
    if sourceRead is io:Error {
        return;
    }
    string sourceContent = sourceRead;
    string packageName = "";
    string className = "";

    string[] lines = regexp:split(re `\n`, sourceContent);
    foreach string line in lines {
        string trimmed = line.trim();
        if packageName == "" && trimmed.startsWith("package ") && trimmed.endsWith(";") {
            packageName = trimmed.substring(8, trimmed.length() - 1).trim();
        }
        if className == "" && trimmed.includes(" class ") {
            int? classIndex = trimmed.indexOf(" class ");
            if classIndex is int {
                string afterClass = trimmed.substring(<int>classIndex + 7, trimmed.length());
                string[] classTokens = regexp:split(re `\s|\{`, afterClass);
                if classTokens.length() > 0 {
                    className = classTokens[0].trim();
                }
            }
        }
        if packageName != "" && className != "" {
            break;
        }
    }

    if className == "" {
        return;
    }
    if packageName == "" {
        return className;
    }

    return packageName + "." + className;
}

function executeShellInDir(string workingDir, string shellCommand) returns record {|int exitCode; string stdout; string stderr;|}|error {
    string stdoutFile = ".example_generator.stdout.log";
    string stderrFile = ".example_generator.stderr.log";
    string stdoutPath = workingDir + "/" + stdoutFile;
    string stderrPath = workingDir + "/" + stderrFile;
    string command = string `cd "${workingDir}" && ${shellCommand} > "${stdoutFile}" 2> "${stderrFile}"`;

    os:Process process = check os:exec({
        value: "bash",
        arguments: ["-c", command]
    });
    int exitCode = check process.waitForExit();

    string stdout = "";
    string|io:Error stdoutRead = io:fileReadString(stdoutPath);
    if stdoutRead is string {
        stdout = stdoutRead;
    }

    string stderr = "";
    string|io:Error stderrRead = io:fileReadString(stderrPath);
    if stderrRead is string {
        stderr = stderrRead;
    }

    boolean|error stdoutExists = file:test(stdoutPath, file:EXISTS);
    if stdoutExists is boolean && stdoutExists {
        if file:remove(stdoutPath) is error {
        }
    }
    boolean|error stderrExists = file:test(stderrPath, file:EXISTS);
    if stderrExists is boolean && stderrExists {
        if file:remove(stderrPath) is error {
        }
    }

    return {
        exitCode: exitCode,
        stdout: stdout,
        stderr: stderr
    };
}

function resolveNativeProjectDir(string connectorPath) returns string {
    string nativeSubdir = connectorPath + "/native";
    boolean|error nativeExists = file:test(nativeSubdir + "/build.gradle", file:EXISTS);
    if nativeExists is boolean && nativeExists {
        return nativeSubdir;
    }
    return connectorPath;
}

function runGradleJarInDir(string workingDir) returns record {|int exitCode; string stdout; string stderr;|}|error {
    string buildRoot = workingDir;
    string gradlewInCurrent = workingDir + "/gradlew";
    boolean hasLocalGradlew = check file:test(gradlewInCurrent, file:EXISTS);
    if !hasLocalGradlew {
        string parentDir = resolveParentDir(workingDir);
        string gradlewInParent = parentDir + "/gradlew";
        boolean hasParentGradlew = check file:test(gradlewInParent, file:EXISTS);
        if hasParentGradlew {
            buildRoot = parentDir;
        }
    }

    string jdkEnvPrefix = "if [ -x /usr/lib/jvm/java-21-openjdk-amd64/bin/javac ]; then export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64; " +
        "elif command -v javac >/dev/null 2>&1; then export JAVA_HOME=\"$(dirname $(dirname $(readlink -f $(command -v javac))))\"; fi; " +
        "if [ -n \"$JAVA_HOME\" ]; then export PATH=\"$JAVA_HOME/bin:$PATH\"; fi; " +
        "gradleJvmArg=\"\"; if [ -n \"$JAVA_HOME\" ]; then gradleJvmArg=\"-Dorg.gradle.java.home=$JAVA_HOME\"; fi; ";

    string jarCommand = jdkEnvPrefix +
        "if [ -x ./gradlew ]; then ./gradlew $gradleJvmArg jar --console=plain --no-daemon; " +
        "elif [ -x ../../sdkanalyzer/native/gradlew ]; then ../../sdkanalyzer/native/gradlew -p . $gradleJvmArg jar --console=plain --no-daemon; " +
        "elif [ -x /usr/bin/gradle ]; then /usr/bin/gradle $gradleJvmArg jar --console=plain --no-daemon; " +
        "elif command -v gradle >/dev/null 2>&1; then gradle $gradleJvmArg jar --console=plain --no-daemon; " +
        "else echo 'Gradle executable not found (checked ./gradlew, ../../sdkanalyzer/native/gradlew, gradle in PATH)' >&2; exit 127; fi";

    return executeShellInDir(buildRoot, jarCommand);
}

function resolveParentDir(string dirPath) returns string {
    string normalized = dirPath.endsWith("/") ? dirPath.substring(0, dirPath.length() - 1) : dirPath;
    int? lastSlash = normalized.lastIndexOf("/");
    if lastSlash is int && lastSlash > 0 {
        return normalized.substring(0, lastSlash);
    }
    return dirPath;
}

function firstNonEmptyLine(string text) returns string {
    string[] lines = regexp:split(re `\n`, text);
    foreach string line in lines {
        string trimmed = line.trim();
        if trimmed.length() > 0 {
            return trimmed;
        }
    }

    return "";
}

function tryUseExistingNativeJar(string connectorPath) returns boolean|error {
    string existingJar = check file:joinPath(connectorPath, "build", "libs", "generated-native-adaptor.jar");
    boolean|error jarExists = file:test(existingJar, file:EXISTS);
    if jarExists is error {
        return jarExists;
    }
    return jarExists;
}

function ensureBuildGradleCompatibility(string connectorPath) returns error? {
    string gradlePath = connectorPath + "/build.gradle";
    boolean|error exists = file:test(gradlePath, file:EXISTS);
    if exists is error {
        return exists;
    }
    if !exists {
        return;
    }

    string gradleContent = check io:fileReadString(gradlePath);
    if !(gradleContent.includes("java {") && gradleContent.includes("toolchain")) {
        return;
    }

    string updated = removeJavaToolchainBlock(gradleContent);
    if !updated.includes("sourceCompatibility") {
        updated = updated.trim() + "\n\nsourceCompatibility = '21'\n";
    }
    if !updated.includes("targetCompatibility") {
        updated = updated.trim() + "\ntargetCompatibility = '21'\n";
    }
    if !updated.includes("tasks.withType(JavaCompile)") {
        updated = updated.trim() + string `

tasks.withType(JavaCompile) {
    options.encoding = 'UTF-8'
    options.compilerArgs = ['-source', '21', '-target', '21']
}
`;
    }

    check io:fileWriteString(gradlePath, updated.trim() + "\n");
}

function removeJavaToolchainBlock(string content) returns string {
    int? javaIndex = content.indexOf("java {");
    if javaIndex is () {
        return content;
    }

    int? firstBrace = content.indexOf("{", <int>javaIndex);
    if firstBrace is () {
        return content;
    }

    int depth = 1;
    int cursor = <int>firstBrace + 1;
    while cursor < content.length() && depth > 0 {
        string ch = content.substring(cursor, cursor + 1);
        if ch == "{" {
            depth += 1;
        } else if ch == "}" {
            depth -= 1;
        }
        cursor += 1;
    }

    if depth != 0 {
        return content;
    }

    int startIndex = <int>javaIndex;
    int endIndex = cursor;
    while endIndex < content.length() {
        string ch = content.substring(endIndex, endIndex + 1);
        if ch == "\n" || ch == "\r" || ch == " " || ch == "\t" {
            endIndex += 1;
            continue;
        }
        break;
    }

    return content.substring(0, startIndex) + content.substring(endIndex, content.length());
}

function ensureBuildGradleProducesFatJar(string connectorPath) returns error? {
    string gradlePath = connectorPath + "/build.gradle";
    boolean|error exists = file:test(gradlePath, file:EXISTS);
    if exists is error {
        return exists;
    }
    if !exists {
        return;
    }

    string gradleContent = check io:fileReadString(gradlePath);
    if (gradleContent.includes("archiveFileName = 'generated-native-adaptor.jar'") ||
        gradleContent.includes("archiveName = 'generated-native-adaptor.jar'")) &&
        gradleContent.includes("configurations.runtimeClasspath") {
        return;
    }

    string fatJarBlock = string `

jar {
    if (project.gradle.gradleVersion.tokenize('.')[0].toInteger() >= 5) {
        archiveFileName = 'generated-native-adaptor.jar'
    } else {
        archiveName = 'generated-native-adaptor.jar'
    }
    from {
        configurations.runtimeClasspath.collect { it.isDirectory() ? it : zipTree(it) }
    }
}
`;

    check io:fileWriteString(gradlePath, gradleContent.trim() + fatJarBlock + "\n");
}

function findNativeJarRelativePath(string connectorPath) returns string? {
    string libsDir = connectorPath + "/build/libs";
    boolean|error exists = file:test(libsDir, file:EXISTS);
    if exists is error || !exists {
        return;
    }

    string relativePrefix = connectorPath.endsWith("/native") ? "../native/build/libs/" : "../build/libs/";

    file:MetaData[]|error entries = file:readDir(libsDir);
    if entries is error {
        return;
    }

    foreach file:MetaData entry in entries {
        string absPath = entry.absPath;
        if absPath.endsWith("/generated-native-adaptor.jar") {
            return relativePrefix + "generated-native-adaptor.jar";
        }
    }

    foreach file:MetaData entry in entries {
        string absPath = entry.absPath;
        if absPath.endsWith(".jar") {
            int? idx = absPath.lastIndexOf("/");
            if idx is int {
                string fileName = absPath.substring(<int>idx + 1);
                return relativePrefix + fileName;
            }
        }
    }

    return;
}
