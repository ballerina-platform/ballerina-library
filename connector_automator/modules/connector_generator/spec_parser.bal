import ballerina/io;
import ballerina/regex;

# Parse API spec file and extract types block and client method signatures.
#
# + apiSpecPath - path to the API spec file, expected to contain a `public isolated client class Client` declaration with method signatures.
# + return - Parsed API spec containing the header/types block and an array of client method signatures, or error on failure.
public function parseApiSpec(string apiSpecPath) returns ParsedApiSpec|error {
    string content = check io:fileReadString(apiSpecPath);
    int? classIdx = content.indexOf("public isolated client class Client {");
    if classIdx is () {
        return error("API spec does not contain Client class");
    }

    string headerAndTypes = stripTrailingClientDocLines(content.substring(0, <int>classIdx));
    string clientBlock = content.substring(<int>classIdx);

    SpecMethodSignature[] methods = [];
    string configTypeName = "ConnectionConfig";
    string[] lines = regex:split(clientBlock, "\n");
    foreach string rawLine in lines {
        string line = rawLine.trim();
        if line.startsWith("remote isolated function ") {
            SpecMethodSignature|error parsed = parseMethodSignature(line);
            if parsed is SpecMethodSignature {
                methods.push(parsed);
            }
        } else if line.includes("function init(") {
            string extracted = extractInitConfigType(line);
            if extracted.length() > 0 {
                configTypeName = extracted;
            }
        }
    }

    return {
        headerAndTypes: headerAndTypes,
        clientMethods: methods,
        configTypeName: configTypeName
    };
}

function stripTrailingClientDocLines(string headerAndTypes) returns string {
    string[] lines = regex:split(headerAndTypes, "\n");
    int endExclusive = lines.length();

    while endExclusive > 0 {
        string trimmed = lines[endExclusive - 1].trim();
        if trimmed.length() == 0 || trimmed.startsWith("#") || trimmed.startsWith("//") ||
                trimmed.startsWith("+") {
            endExclusive -= 1;
            continue;
        }
        break;
    }

    if endExclusive <= 0 {
        return "";
    }

    return string:'join("\n", ...lines.slice(0, endExclusive)).trim();
}

function parseMethodSignature(string line) returns SpecMethodSignature|error {
    int? fnStart = line.indexOf("function ");
    if fnStart is () {
        return error("Invalid method signature: function keyword not found");
    }

    int nameStart = <int>fnStart + 9;
    int? parenStart = line.indexOf("(");
    if parenStart is () {
        return error("Invalid method signature: opening parenthesis not found");
    }
    string methodName = line.substring(nameStart, <int>parenStart).trim();

    int? returnsIdx = line.indexOf(") returns ");
    if returnsIdx is () {
        return error("Invalid method signature: returns clause not found");
    }

    string paramsSegment = line.substring(<int>parenStart + 1, <int>returnsIdx).trim();
    string returnType = line.substring(<int>returnsIdx + 10).trim();
    if returnType.endsWith("{") {
        returnType = returnType.substring(0, returnType.length() - 1).trim();
    }

    SpecMethodParameter[] params = [];
    if paramsSegment.length() > 0 {
        string[] rawParams = splitSignatureParameters(paramsSegment);
        foreach string rawParam in rawParams {
            SpecMethodParameter|error p = parseParameter(rawParam.trim());
            if p is SpecMethodParameter {
                params.push(p);
            }
        }
    }

    return {
        name: methodName,
        parameters: params,
        returnType: returnType
    };
}

function splitSignatureParameters(string paramsSegment) returns string[] {
    string[] parts = [];
    int cursor = 0;
    int depth = 0;

    foreach int i in 0 ..< paramsSegment.length() {
        string ch = paramsSegment.substring(i, i + 1);
        if ch == "<" || ch == "(" || ch == "[" {
            depth += 1;
        } else if ch == ">" || ch == ")" || ch == "]" {
            if depth > 0 {
                depth -= 1;
            }
        } else if ch == "," && depth == 0 {
            parts.push(paramsSegment.substring(cursor, i).trim());
            cursor = i + 1;
        }
    }

    if cursor < paramsSegment.length() {
        parts.push(paramsSegment.substring(cursor).trim());
    }
    return parts;
}

function parseParameter(string rawParam) returns SpecMethodParameter|error {
    boolean isConfigSpread = rawParam.startsWith("*");
    string segment = isConfigSpread ? rawParam.substring(1).trim() : rawParam;

    int? lastSpace = segment.lastIndexOf(" ");
    if lastSpace is () {
        return {
            'type: segment,
            name: "arg",
            isConfigSpread: isConfigSpread
        };
    }

    string pType = segment.substring(0, <int>lastSpace).trim();
    string pName = segment.substring(<int>lastSpace + 1).trim();
    int? eqIdx = pName.indexOf("=");
    if eqIdx is int {
        pName = pName.substring(0, eqIdx).trim();
    }

    return {
        'type: pType,
        name: pName,
        isConfigSpread: isConfigSpread
    };
}

// Extract the config type name from an init signature line.
function extractInitConfigType(string line) returns string {
    int? parenOpen = line.indexOf("(");
    int? parenClose = line.indexOf(")");
    if parenOpen is () || parenClose is () || <int>parenClose <= <int>parenOpen + 1 {
        return "";
    }
    string paramSegment = line.substring(<int>parenOpen + 1, <int>parenClose).trim();
    if paramSegment.length() == 0 {
        return "";
    }
    // Strip leading spread operator if present
    string segment = paramSegment.startsWith("*") ? paramSegment.substring(1).trim() : paramSegment;
    // The type is everything up to the last space (name follows)
    int? lastSpace = segment.lastIndexOf(" ");
    if lastSpace is () {
        return segment; // entire segment is the type
    }
    return segment.substring(0, <int>lastSpace).trim();
}
