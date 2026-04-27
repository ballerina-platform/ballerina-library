import ballerina/io;
import ballerina/file;
import ballerina/regex;

type ResourceMethod record {|
    string content;
    int startLine;
    int endLine;
    string methodType;
    string path;
    [string, string, string] sortKey;
|};

type ContentBlock record {|
    int startLine;
    int endLine;
    string content;
    string blockType;
|};

function extractMethodType(string content) returns string {
    string[] lines = regex:split(content, "\n");
    if lines.length() == 0 {
        return "unknown";
    }

    string firstLine = regex:replaceAll(lines[0].trim(), "\\s+", " ");
    string[] tokens = regex:split(firstLine, " ");

    foreach int i in 0 ..< tokens.length() {
        if tokens[i] == "function" && i + 1 < tokens.length() {
            string method = tokens[i + 1];
            if method == "get" || method == "post" || method == "put" || method == "delete" || method == "patch" {
                return method;
            }
        }
    }

    return "unknown";
}

function extractPath(string content) returns string {
    string[] lines = regex:split(content, "\n");
    if lines.length() == 0 {
        return "";
    }

    string firstLine = regex:replaceAll(lines[0].trim(), "\\s+", " ");
    string[] tokens = regex:split(firstLine, " ");

    foreach int i in 0 ..< tokens.length() {
        if (tokens[i] == "get" || tokens[i] == "post" || tokens[i] == "put" || tokens[i] == "delete" ||
            tokens[i] == "patch") && i + 1 < tokens.length() {
            string rawPath = tokens[i + 1];
            string[] pathParts = regex:split(rawPath, "\\(");
            string path = pathParts.length() > 0 ? pathParts[0] : rawPath;
            path = regex:replaceAll(path, "\\[[\\w:]+\\s+(\\w+)\\]", "[$1]");
            return path;
        }
    }

    return "";
}

function generateSortKey(string methodType, string path) returns [string, string, string] {
    string normalizedPath = regex:replaceAll(path, "\\\\-", "-");
    string[] segments = regex:split(normalizedPath, "/");

    map<string> methodPriority = {
        "get": "1",
        "post": "2",
        "put": "3",
        "delete": "4",
        "patch": "5",
        "unknown": "9"
    };

    string priority = methodPriority[methodType] ?: "9";
    string joinedPath = string:'join("/", ...segments);

    return [joinedPath, priority, path];
}

// Shared across client and type sort files within this module
function countChar(string str, string char) returns int {
    int count = 0;
    foreach int i in 0 ..< str.length() {
        if str.substring(i, i + 1) == char {
            count += 1;
        }
    }
    return count;
}

function extractAllBlocks(string content) returns [ContentBlock[], int, int] {
    string[] lines = regex:split(content, "\n");
    ContentBlock[] blocks = [];

    int firstMethodLine = -1;
    int lastMethodLine = -1;

    int i = 0;
    while i < lines.length() {
        string line = lines[i];

        if regex:matches(line, "\\s*resource\\s+isolated\\s+function\\s+(get|post|put|delete|patch)") {
            if firstMethodLine == -1 {
                firstMethodLine = i;
            }

            string[] methodLines = [line];
            int startLine = i;
            int braceCount = countChar(line, "{") - countChar(line, "}");
            i += 1;

            while i < lines.length() && braceCount > 0 {
                string currentLine = lines[i];
                methodLines.push(currentLine);
                braceCount += countChar(currentLine, "{") - countChar(currentLine, "}");
                i += 1;
            }

            lastMethodLine = i - 1;

            string methodContent = string:'join("\n", ...methodLines);
            blocks.push({
                startLine: startLine,
                endLine: i - 1,
                content: methodContent,
                blockType: "method"
            });
        } else {
            i += 1;
        }
    }

    return [blocks, firstMethodLine, lastMethodLine];
}

function compareResourceMethods(ResourceMethod a, ResourceMethod b) returns int {
    [string, string, string] keyA = a.sortKey;
    [string, string, string] keyB = b.sortKey;

    if keyA[0] < keyB[0] {
        return -1;
    } else if keyA[0] > keyB[0] {
        return 1;
    }

    if keyA[1] < keyB[1] {
        return -1;
    } else if keyA[1] > keyB[1] {
        return 1;
    }

    if keyA[2] < keyB[2] {
        return -1;
    } else if keyA[2] > keyB[2] {
        return 1;
    }

    return 0;
}

function sortResourceMethods(ResourceMethod[] methods) returns ResourceMethod[] {
    ResourceMethod[] sorted = [...methods];
    int n = sorted.length();
    foreach int i in 0 ..< n {
        foreach int j in i + 1 ..< n {
            if compareResourceMethods(sorted[i], sorted[j]) > 0 {
                ResourceMethod temp = sorted[i];
                sorted[i] = sorted[j];
                sorted[j] = temp;
            }
        }
    }
    return sorted;
}

function sortAndWriteClient(string inputPath, string outputPath) returns error? {
    string content = check io:fileReadString(inputPath);
    string[] lines = regex:split(content, "\n");

    [ContentBlock[], int, int] result = extractAllBlocks(content);
    ContentBlock[] methodBlocks = result[0];
    int firstMethodLine = result[1];
    int lastMethodLine = result[2];

    if methodBlocks.length() == 0 {
        check io:fileWriteString(outputPath, content);
        io:println("No resource methods found, file copied as-is");
        return;
    }

    ResourceMethod[] methods = [];
    foreach ContentBlock block in methodBlocks {
        string methodType = extractMethodType(block.content);
        string path = extractPath(block.content);
        [string, string, string] sortKey = generateSortKey(methodType, path);

        methods.push({
            content: block.content,
            startLine: block.startLine,
            endLine: block.endLine,
            methodType: methodType,
            path: path,
            sortKey: sortKey
        });
    }

    ResourceMethod[] sortedMethods = sortResourceMethods(methods);

    string[] outputLines = [];

    foreach int i in 0 ..< firstMethodLine {
        outputLines.push(lines[i]);
    }

    foreach int idx in 0 ..< sortedMethods.length() {
        ResourceMethod method = sortedMethods[idx];
        outputLines.push(method.content);

        if idx < sortedMethods.length() - 1 {
            outputLines.push("");
        }
    }

    foreach int i in (lastMethodLine + 1) ..< lines.length() {
        outputLines.push(lines[i]);
    }

    check io:fileWriteString(outputPath, string:'join("\n", ...outputLines));

    io:println(string `Sorted ${methods.length()} resource methods`);
    io:println(string `Written to: ${outputPath}`);
}

public function runSortBallerinaClient(string[] args) returns error? {
    if args.length() != 2 {
        io:println("Usage: bal run sort_ballerina_client.bal -- <input_file> <output_file>");
        return error("Invalid arguments");
    }

    string inputFile = args[0];
    string outputFile = args[1];

    if !check file:test(inputFile, file:EXISTS) {
        io:println(string `Input file not found: ${inputFile}`);
        return error("Input file not found");
    }

    check sortAndWriteClient(inputFile, outputFile);
}
