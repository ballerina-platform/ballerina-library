import ballerina/io;
import ballerina/file;
import ballerina/regex;

type TypeDefinition record {|
    string content;
    string name;
    string typeKind;
    int startLine;
    int endLine;
|};

function extractTypeName(string line) returns string {
    string trimmed = regex:replaceAll(line.trim(), "\\s+", " ");
    string[] tokens = regex:split(trimmed, " ");

    foreach int i in 0 ..< tokens.length() {
        if tokens[i] == "type" {
            if i + 1 < tokens.length() {
                string name = tokens[i + 1];
                name = regex:replaceAll(name, "[=;].*$", "");
                return name;
            }
        } else if tokens[i] == "const" {
            if i + 2 < tokens.length() {
                string name = tokens[i + 2];
                name = regex:replaceAll(name, "[=;].*$", "");
                return name;
            }
        }
    }

    return "";
}

function extractTypeKind(string content) returns string {
    if content.includes("record {") || content.includes("record {|") {
        return "record";
    } else if content.includes("\"|\"") {
        return "enum";
    } else if content.includes("const ") {
        return "const";
    } else {
        return "type";
    }
}

// countChar is defined in sort_ballerina_client.bal and shared within this module

function extractAllTypes(string content) returns [TypeDefinition[], int, int] {
    string[] lines = regex:split(content, "\n");
    TypeDefinition[] typeDefs = [];

    int firstTypeLine = -1;
    int lastTypeLine = -1;

    int i = 0;
    while i < lines.length() {
        string line = lines[i];
        string stripped = line.trim();

        if regex:matches(stripped, "public\\s+(type|const)") {
            if firstTypeLine == -1 {
                firstTypeLine = i;
            }

            string typeName = extractTypeName(stripped);
            string[] typeLines = [line];
            int startLine = i;

            if stripped.includes(";") && !stripped.includes("record") {
                lastTypeLine = i;
                string typeContent = line;
                string typeKind = extractTypeKind(typeContent);

                typeDefs.push({
                    content: typeContent,
                    name: typeName,
                    typeKind: typeKind,
                    startLine: startLine,
                    endLine: i
                });
                i += 1;
                continue;
            }

            int braceCount = countChar(line, "{") - countChar(line, "}");
            i += 1;

            while i < lines.length() {
                string currentLine = lines[i];
                typeLines.push(currentLine);
                braceCount += countChar(currentLine, "{") - countChar(currentLine, "}");

                string currentStripped = currentLine.trim();
                if braceCount == 0 && (currentStripped.endsWith("};") || currentStripped.endsWith("|};")) {
                    lastTypeLine = i;
                    string typeContent = string:'join("\n", ...typeLines);
                    string typeKind = extractTypeKind(typeContent);

                    typeDefs.push({
                        content: typeContent,
                        name: typeName,
                        typeKind: typeKind,
                        startLine: startLine,
                        endLine: i
                    });
                    i += 1;
                    break;
                }
                i += 1;
            }
        } else {
            i += 1;
        }
    }

    return [typeDefs, firstTypeLine, lastTypeLine];
}

function compareTypeDefinitions(TypeDefinition a, TypeDefinition b) returns int {
    string nameA = a.name.toLowerAscii();
    string nameB = b.name.toLowerAscii();

    if nameA < nameB {
        return -1;
    } else if nameA > nameB {
        return 1;
    }

    if a.typeKind < b.typeKind {
        return -1;
    } else if a.typeKind > b.typeKind {
        return 1;
    }

    return 0;
}

function sortTypeDefinitions(TypeDefinition[] types) returns TypeDefinition[] {
    TypeDefinition[] sorted = [...types];
    int n = sorted.length();
    foreach int i in 0 ..< n {
        foreach int j in i + 1 ..< n {
            if compareTypeDefinitions(sorted[i], sorted[j]) > 0 {
                TypeDefinition temp = sorted[i];
                sorted[i] = sorted[j];
                sorted[j] = temp;
            }
        }
    }
    return sorted;
}

function sortAndWriteType(string inputPath, string outputPath) returns error? {
    string content = check io:fileReadString(inputPath);
    string[] lines = regex:split(content, "\n");

    [TypeDefinition[], int, int] result = extractAllTypes(content);
    TypeDefinition[] typeDefs = result[0];
    int firstTypeLine = result[1];
    int lastTypeLine = result[2];

    if typeDefs.length() == 0 {
        check io:fileWriteString(outputPath, content);
        io:println("No type definitions found, file copied as-is");
        return;
    }

    TypeDefinition[] sortedTypes = sortTypeDefinitions(typeDefs);

    string[] outputLines = [];

    foreach int i in 0 ..< firstTypeLine {
        outputLines.push(lines[i]);
    }

    foreach int idx in 0 ..< sortedTypes.length() {
        TypeDefinition typeDef = sortedTypes[idx];
        outputLines.push(typeDef.content);

        if idx < sortedTypes.length() - 1 {
            outputLines.push("");
        }
    }

    foreach int i in (lastTypeLine + 1) ..< lines.length() {
        outputLines.push(lines[i]);
    }

    check io:fileWriteString(outputPath, string:'join("\n", ...outputLines));

    io:println(string `Sorted ${typeDefs.length()} type definitions`);
    io:println(string `Written to: ${outputPath}`);
}

public function runSortBallerinaType(string[] args) returns error? {
    if args.length() != 2 {
        io:println("Usage: bal run sort_ballerina_types.bal -- <input_file> <output_file>");
        return error("Invalid arguments");
    }

    string inputFile = args[0];
    string outputFile = args[1];

    if !check file:test(inputFile, file:EXISTS) {
        io:println(string `Input file not found: ${inputFile}`);
        return error("Input file not found");
    }

    check sortAndWriteType(inputFile, outputFile);
}
