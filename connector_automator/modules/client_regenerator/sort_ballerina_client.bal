// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/io;
import ballerina/file;
import ballerina/regex;

const string METHOD_GET = "get";
const string METHOD_POST = "post";
const string METHOD_PUT = "put";
const string METHOD_DELETE = "delete";
const string METHOD_PATCH = "patch";
const string METHOD_REMOTE = "remote";
const string METHOD_UNKNOWN = "unknown";

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
        return METHOD_UNKNOWN;
    }

    string firstLine = regex:replaceAll(lines[0].trim(), "\\s+", " ");
    string[] tokens = regex:split(firstLine, " ");

    boolean isRemote = false;
    foreach string token in tokens {
        if token == "remote" {
            isRemote = true;
            break;
        }
    }

    // For resource functions: HTTP method is the keyword immediately before the path
    // e.g. `resource function get /users[string id](...)`
    foreach int i in 0 ..< tokens.length() {
        if tokens[i] == "function" && i + 1 < tokens.length() {
            string nameOrMethod = tokens[i + 1];
            if nameOrMethod == METHOD_GET || nameOrMethod == METHOD_POST || nameOrMethod == METHOD_PUT ||
                    nameOrMethod == METHOD_DELETE || nameOrMethod == METHOD_PATCH {
                return nameOrMethod;
            }
            break;
        }
    }

    // For remote functions: read the HTTP method from the client call in the function body.
    // `bal openapi` always generates `self.clientEp->get(...)`, `->post(...)`, etc.
    // This is accurate regardless of how the function is named.
    if isRemote {
        return extractHttpMethodFromBody(content);
    }

    return METHOD_UNKNOWN;
}

function extractHttpMethodFromBody(string content) returns string {
    string lower = content.toLowerAscii();
    if lower.includes("->get(") { return METHOD_GET; }
    if lower.includes("->post(") { return METHOD_POST; }
    if lower.includes("->put(") { return METHOD_PUT; }
    if lower.includes("->delete(") { return METHOD_DELETE; }
    if lower.includes("->patch(") { return METHOD_PATCH; }
    return METHOD_REMOTE;
}

function extractPath(string content) returns string {
    string[] lines = regex:split(content, "\n");
    if lines.length() == 0 {
        return "";
    }

    string firstLine = regex:replaceAll(lines[0].trim(), "\\s+", " ");
    string[] tokens = regex:split(firstLine, " ");

    boolean isRemote = false;
    foreach string token in tokens {
        if token == "remote" {
            isRemote = true;
            break;
        }
    }

    foreach int i in 0 ..< tokens.length() {
        if tokens[i] == "function" && i + 1 < tokens.length() {
            if isRemote {
                string funcName = tokens[i + 1];
                string[] nameParts = regex:split(funcName, "\\(");
                return nameParts.length() > 0 ? nameParts[0] : funcName;
            }
            break;
        }
    }

    foreach int i in 0 ..< tokens.length() {
        if (tokens[i] == METHOD_GET || tokens[i] == METHOD_POST || tokens[i] == METHOD_PUT ||
                tokens[i] == METHOD_DELETE || tokens[i] == METHOD_PATCH) && i + 1 < tokens.length() {
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
        [METHOD_GET]: "1",
        [METHOD_POST]: "2",
        [METHOD_PUT]: "3",
        [METHOD_DELETE]: "4",
        [METHOD_PATCH]: "5",
        [METHOD_REMOTE]: "6",
        [METHOD_UNKNOWN]: "9"
    };

    string priority = methodPriority[methodType] ?: "9";
    string joinedPath = string:'join("/", ...segments);

    return [joinedPath, priority, path];
}

// Shared across client and type sort files within this module
function countChar(string str, string char) returns int {
    return re`${char}`.findAll(str).length();
}

function extractAllBlocks(string content) returns [ContentBlock[], int, int] {
    string[] lines = regex:split(content, "\n");
    ContentBlock[] blocks = [];

    int firstMethodLine = -1;
    int lastMethodLine = -1;

    int i = 0;
    while i < lines.length() {
        string line = lines[i];

        if regex:matches(line, "\\s*(resource\\s+isolated|isolated\\s+resource|remote\\s+isolated|isolated\\s+remote)\\s+function\\s+.*") {
            if firstMethodLine == -1 {
                firstMethodLine = i;
            }

            string[] methodLines = [line];
            int startLine = i;

            // Initialize braceCount from the first signature line
            int braceCount = countChar(line, "{") - countChar(line, "}");
            i += 1;

            // If opening brace is not on the first line, advance through multi-line signatures
            while i < lines.length() && braceCount == 0 {
                string sigLine = lines[i];
                methodLines.push(sigLine);
                i += 1;
                braceCount += countChar(sigLine, "{") - countChar(sigLine, "}");
            }

            // Track brace nesting until body is fully captured
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

    io:println(string `Sorted ${methods.length()} client methods (resource + remote)`);
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
