import ballerina/io;
import ballerina/lang.'string as strings;
import ballerina/lang.regexp;

public type ConnectorAnalysis record {
    string packageName;
    string mockServerContent;
    string initMethodSignature;
    string referencedTypeDefinitions;
};

function analyzeConnectorForTests(string connectorPath) returns ConnectorAnalysis|error {
    // Read Ballerina.toml to get package name
    string tomlContent = check io:fileReadString(connectorPath + "/ballerina/Ballerina.toml");
    string packageName = extractPackageName(tomlContent);

    // Read mock server content
    string mockServerContent = check io:fileReadString(connectorPath + "/ballerina/modules/mock.server/mock_server.bal");

    // Read client.bal to extract the init method - FIX THIS
    string clientContent = check io:fileReadString(connectorPath + "/ballerina/client.bal");
    string initMethodSignature = extractInitMethodComplete(clientContent);

    // read types.bal to get type definitions
    string typesContent = check io:fileReadString(connectorPath + "/ballerina/types.bal");

    // extract all types referenced in the init method signatures
    string[] referencedTypes = findTypesInSignatures(initMethodSignature);
    string[] allDependentTypes = [];
    allDependentTypes.push(...referencedTypes);

    // find nested types 
    findEssentialNestedTypes(referencedTypes, typesContent, allDependentTypes, maxDepth = 2);

    // Extract type definitions
    string referencedTypeDefinitions = "";
    if allDependentTypes.length() > 0 {
        foreach string typeName in allDependentTypes {
            string typeDef = extractCompactTypeDefinition(typesContent, typeName);
            if typeDef != "" {
                referencedTypeDefinitions += typeDef + "\n\n";
            }
        }
    }

    return {
        packageName,
        mockServerContent,
        initMethodSignature,
        referencedTypeDefinitions
    };
}

function findInitSignature(string clientContent) returns string? {
    // Look for the init function more broadly
    string[] lines = regexp:split(re `\n`, clientContent);
    string initMethod = "";
    boolean inInitFunction = false;
    boolean foundStart = false;
    int braceCount = 0;

    foreach string line in lines {
        string trimmedLine = strings:trim(line);

        // Look for documentation comments before init
        if strings:startsWith(trimmedLine, "#") && !foundStart {
            initMethod += line + "\n";
        }
        // Look for init function start
        else if strings:includes(trimmedLine, "function init(") {
            inInitFunction = true;
            foundStart = true;
            initMethod += line + "\n";
        }
        else if inInitFunction {
            initMethod += line + "\n";

            // Count braces to find end of function signature
            if strings:includes(line, "{") {
                braceCount += 1;
                break; // Stop at opening brace of function body
            }
        }
        else if foundStart && !inInitFunction {
            // Reset if we didn't find the function properly
            initMethod = "";
            foundStart = false;
        }
    }

    if initMethod.length() > 0 {
        return initMethod.trim();
    }
    return ();
}

function findInitSignatureRegex(string clientContent) returns string? {
    // More flexible regex pattern
    regexp:RegExp initPattern = re `public\sisolated\sfunction\sinit\s*\([^{]*\)\sreturns\s[^{]+`;
    regexp:Span[] matches = initPattern.findAll(clientContent);

    if matches.length() > 0 {
        regexp:Span span = matches[0];
        string signature = clientContent.substring(span.startIndex, span.endIndex).trim();

        // Extract documentation before the function
        string docComment = extractFunctionDocumentation(clientContent, span.startIndex);

        if docComment != "" {
            return docComment + "\n" + signature + ";";
        } else {
            return signature + ";";
        }
    }
    return ();
}

// Combine both approaches
function extractInitMethodComplete(string clientContent) returns string {
    // Try the line-by-line approach first
    string? result = findInitSignature(clientContent);

    // Fallback to regex approach
    if result is () {
        result = findInitSignatureRegex(clientContent);
    }

    return result ?: "";
}

function findTypesInSignatures(string signatures) returns string[] {
    regexp:RegExp typePattern = re `[A-Z][a-zA-Z0-9_]*`;
    regexp:Span[] matches = typePattern.findAll(signatures);
    string[] types = [];
    foreach regexp:Span span in matches {
        string typeName = signatures.substring(span.startIndex, span.endIndex);
        if !arrayContains(types, typeName) {
            types.push(typeName);
        }
    }
    return types;
}

function findEssentialNestedTypes(string[] typesToSearch, string typesContent, string[] foundTypes, int maxDepth) {
    if maxDepth <= 0 {
        return;
    }

    string[] newTypesFound = [];
    foreach string typeName in typesToSearch {
        if isEssentialType(typeName) {
            string typeDef = extractCompactTypeDefinition(typesContent, typeName);
            if typeDef != "" {
                string[] nested = findTypesInSignatures(typeDef);
                foreach string nestedType in nested {
                    if !arrayContains(foundTypes, nestedType) && isEssentialType(nestedType) {
                        newTypesFound.push(nestedType);
                        foundTypes.push(nestedType);
                    }
                }
            }
        }
    }

    if newTypesFound.length() > 0 {
        findEssentialNestedTypes(newTypesFound, typesContent, foundTypes, maxDepth - 1);
    }
}

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

function extractCompactTypeDefinition(string typesContent, string typeName) returns string {
    string typeDef = extractBlock(typesContent, "public type " + typeName, "{", "}");
    if typeDef == "" {
        typeDef = extractBlock(typesContent, "public type " + typeName + " ", ";", ";");
    }

    if typeDef != "" && typeDef.length() > 1000 {
        string[] lines = regexp:split(re `\n`, typeDef);
        if lines.length() > 15 {
            string[] limitedLines = [];
            int count = 0;
            foreach string line in lines {
                limitedLines.push(line);
                count += 1;
                if count >= 12 {
                    limitedLines.push("    // ... (additional fields omitted for brevity)");
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

function extractFunctionDocumentation(string content, int functionStartIndex) returns string {
    int currentIndex = functionStartIndex - 1;
    string docComment = "";

    // Skip whitespace
    while currentIndex >= 0 && (content.substring(currentIndex, currentIndex + 1) == " " ||
            content.substring(currentIndex, currentIndex + 1) == "\n" ||
            content.substring(currentIndex, currentIndex + 1) == "\r" ||
            content.substring(currentIndex, currentIndex + 1) == "\t") {
        currentIndex -= 1;
    }

    if currentIndex >= 1 && content.substring(currentIndex - 1, currentIndex + 1) == "*/" {
        int? commentStartIndex = content.lastIndexOf("/*", currentIndex - 1);
        if commentStartIndex is int {
            string comment = content.substring(commentStartIndex, currentIndex + 1);
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

function arrayContains(string[] arr, string value) returns boolean {
    foreach string item in arr {
        if item == value {
            return true;
        }
    }
    return false;
}

function extractPackageName(string tomlContent) returns string {
    string connectorName = "";
    string[] tomlLines = regexp:split(re `\n`, tomlContent);
    foreach string line in tomlLines {
        string trimmedLine = strings:trim(line);
        if strings:startsWith(trimmedLine, "name") {
            string[] parts = regexp:split(re `=`, trimmedLine);
            if parts.length() > 1 {
                connectorName = strings:trim(regexp:replaceAll(re `"`, parts[1], ""));
            }
        }
    }
    return connectorName;
}
