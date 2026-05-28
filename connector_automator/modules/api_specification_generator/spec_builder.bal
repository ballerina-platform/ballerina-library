// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

// Ballerina reserved keywords that require a leading single-quote escape
final map<boolean> & readonly BALLERINA_KEYWORDS = {
    "type": true,
    "limit": true,
    "version": true,
    "order": true,
    "class": true,
    "error": true,
    "check": true,
    "start": true,
    "lock": true,
    "fork": true,
    "match": true,
    "string": true,
    "int": true,
    "float": true,
    "boolean": true,
    "byte": true,
    "decimal": true,
    "json": true,
    "xml": true,
    "map": true,
    "table": true,
    "object": true,
    "record": true,
    "service": true,
    "function": true,
    "return": true,
    "if": true,
    "else": true,
    "while": true,
    "foreach": true,
    "break": true,
    "continue": true,
    "new": true,
    "self": true,
    "from": true,
    "select": true,
    "where": true,
    "let": true,
    "join": true,
    "on": true,
    "equals": true,
    "into": true,
    "do": true,
    "conflict": true,
    "rollback": true,
    "commit": true,
    "retry": true,
    "transactional": true,
    "transaction": true,
    "import": true,
    "as": true,
    "public": true,
    "private": true,
    "isolated": true,
    "final": true,
    "readonly": true,
    "distinct": true,
    "never": true,
    "any": true,
    "anydata": true,
    "future": true,
    "stream": true,
    "typedesc": true,
    "handle": true,
    "true": true,
    "false": true,
    "null": true,
    "panic": true,
    "trap": true,
    "wait": true,
    "flush": true,
    "send": true,
    "receive": true,
    "default": true,
    "external": true,
    "resource": true,
    "remote": true,
    "worker": true,
    "client": true,
    "key": true,
    "abstract": true,
    "annotation": true,
    "enum": true,
    "listener": true,
    "xmlns": true,
    "var": true
};

# Build a complete Ballerina API specification source string from the IR.
#
# + ir - Intermediate Representation
# + return - Ballerina source code string
public function buildSpec(IntermediateRepresentation ir) returns string {
    string[] parts = [];

    // 1. Enums (declared before records so types are in scope)
    foreach IREnum e in ir.enums {
        string enumSrc = buildEnum(e);
        if enumSrc.length() > 0 {
            parts.push(enumSrc);
        }
    }

    // 2. ConnectionConfig record
    if ir.connectionFields.length() > 0 {
        parts.push(buildConnectionConfig(ir));
    }

    // 3. Structure records (request / response / support types)
    foreach IRStructure s in ir.structures {
        parts.push(buildStructure(s));
    }

    // 4. Per-function Config records for optional parameters
    foreach IRFunction fn in ir.functions {
        IRStructure? reqStruct = findRequestStruct(fn, ir.structures);
        string configSrc = buildFunctionConfigRecord(fn.name, reqStruct);
        if configSrc.length() > 0 {
            parts.push(configSrc);
        }
    }

    // 5. Client class
    parts.push(buildClientClass(ir));

    return string:'join("\n\n", ...parts);
}

# Generate a Ballerina enum definition.
#
# + irEnum - IR enum entry
# + return - Ballerina enum source string, or empty string if no values
function buildEnum(IREnum irEnum) returns string {
    if irEnum.values.length() == 0 {
        return "";
    }

    string[] lines = [];
    lines.push(string `# Represents the ${irEnum.name} enumeration.`);
    lines.push(string `public enum ${irEnum.name} {`);

    int last = irEnum.values.length() - 1;
    foreach int i in 0 ..< irEnum.values.length() {
        IREnumValue ev = irEnum.values[i];
        string comma = i < last ? "," : "";
        lines.push(string `    ${ev.member} = "${ev.value}"${comma}`);
    }

    lines.push("}");
    return string:'join("\n", ...lines);
}

# Generate the ConnectionConfig record from IR connection fields.
#
# + ir - Full IR (clientName used for doc comment)
# + return - Ballerina record source string
function buildConnectionConfig(IntermediateRepresentation ir) returns string {
    string baseName = deriveBaseName(ir.clientName);
    string[] lines = [];
    lines.push(string `# Configuration for the ${baseName} client connection.`);
    lines.push("public type ConnectionConfig record {|");

    foreach IRField f in ir.connectionFields {
        lines.push(buildFieldDeclaration(f, "    "));
    }

    lines.push("|};");
    return string:'join("\n", ...lines);
}

# Generate a Ballerina closed record from an IR structure.
#
# + structure - IR structure entry
# + return - Ballerina record source string
function buildStructure(IRStructure structure) returns string {
    string[] lines = [];
    lines.push(string `# Represents a ${structure.name} record.`);
    lines.push(string `public type ${structure.name} record {|`);

    foreach IRField f in structure.fields {
        lines.push(buildFieldDeclaration(f, "    "));
    }

    lines.push("|};");
    return string:'join("\n", ...lines);
}

# Build a single field declaration (doc comment + declaration) for a record.
#
# + irField - IR field
# + indent - Indentation prefix string
# + return - Multi-line string: doc comment line + field declaration line
function buildFieldDeclaration(IRField irField, string indent) returns string {
    string safeName = safeIdentifier(irField.name);
    string[] lines = [];

    // Inline doc comment
    string doc = irField.description.length() > 0
        ? irField.description
        : string `The ${irField.name} field`;
    string docText = trimTrailingPeriod(doc);
    lines.push(string `${indent}# ${docText}`);

    // Declaration line based on field kind
    if irField.kind == REQUIRED {
        lines.push(string `${indent}${irField.'type} ${safeName};`);
    } else if irField.kind == DEFAULT {
        string defVal = formatDefaultValue(irField.'type, irField.defaultValue);
        lines.push(string `${indent}${irField.'type} ${safeName} = ${defVal};`);
    } else {
        // INCLUDED – optional field
        lines.push(string `${indent}${irField.'type} ${safeName}?;`);
    }

    return string:'join("\n", ...lines);
}

# Generate the isolated client class with init and all remote functions.
#
# + ir - Full IR
# + return - Ballerina client class source string
function buildClientClass(IntermediateRepresentation ir) returns string {
    string baseName = deriveBaseName(ir.clientName);
    string[] lines = [];

    lines.push(string `# ${ir.clientDescription}`);
    lines.push("public isolated client class Client {");
    lines.push("");

    // init function
    lines.push(string `    # Initializes the ${baseName} Client.`);
    lines.push("    #");
    lines.push("    # + config - The connection configuration");
    lines.push("    # + return - An error if initialization fails");
    lines.push("    public isolated function init(*ConnectionConfig config) returns error? {");
    lines.push("    }");

    // Remote functions
    foreach IRFunction fn in ir.functions {
        lines.push("");
        lines.push(buildRemoteFunction(fn, ir.structures));
    }

    lines.push("}");
    return string:'join("\n", ...lines);
}

# Generate a single remote function declaration.
#
# + fn - IR function
# + structures - All IR structures (to look up request types)
# + return - Indented function source string (doc comment + signature + empty body)
function buildRemoteFunction(IRFunction fn, IRStructure[] structures) returns string {
    string[] lines = [];

    IRStructure? reqStruct = findRequestStruct(fn, structures);
    lines.push(buildFunctionDoc(fn, reqStruct));

    string params = buildFunctionSignatureParams(fn, reqStruct);
    string returnType = buildReturnType(fn.'return);
    lines.push(string `    remote isolated function ${fn.name}(${params}) returns ${returnType} {`);
    lines.push("    }");

    return string:'join("\n", ...lines);
}

# Build the Ballerina doc comment block for a remote function.
#
# + fn - IR function
# + reqStruct - The resolved request structure, or nil for simple functions
# + return - Indented Ballerina doc comment string
function buildFunctionDoc(IRFunction fn, IRStructure? reqStruct) returns string {
    string[] lines = [];

    string desc = fn.description.length() > 0
        ? fn.description
        : string `Executes the ${fn.name} operation`;
    lines.push(string `    # ${trimTrailingPeriod(desc)}`);
    lines.push("    #");

    if reqStruct is IRStructure {
        // Document each required field as an individual param
        foreach IRField f in reqStruct.fields {
            if f.kind == REQUIRED {
                string safeName = safeIdentifier(f.name);
                string fDesc = f.description.length() > 0
                    ? f.description
                    : string `The ${f.name} value`;
                lines.push(string `    # + ${safeName} - ${trimTrailingPeriod(fDesc)}`);
            }
        }
        // Document the config record if there are optional fields
        boolean hasOptional = false;
        foreach IRField f in reqStruct.fields {
            if f.kind == INCLUDED || f.kind == DEFAULT {
                hasOptional = true;
                break;
            }
        }
        if hasOptional {
            string configName = capitalizeFirst(fn.name) + "Config";
            lines.push(string `    # + config - Optional ${configName} parameters`);
        }
    } else {
        // Fallback: document raw IR parameters
        foreach IRParameter p in fn.parameters {
            string safeName = safeIdentifier(p.name);
            string pDesc = p.description.length() > 0
                ? p.description
                : string `The ${p.'type} parameter`;
            lines.push(string `    # + ${safeName} - ${trimTrailingPeriod(pDesc)}`);
        }
    }

    lines.push(string `    # + return - ${buildReturnDescription(fn.'return)}`);

    return string:'join("\n", ...lines);
}

# Build the parameter list for a remote function signature.
#
# + fn - IR function
# + reqStruct - The resolved request structure, or nil
# + return - Comma-separated parameter list string
function buildFunctionSignatureParams(IRFunction fn, IRStructure? reqStruct) returns string {
    if reqStruct is () {
        // No request struct – use raw IR parameters as-is
        if fn.parameters.length() == 0 {
            return "";
        }
        string[] parts = [];
        foreach IRParameter p in fn.parameters {
            string safeName = safeIdentifier(p.name);
            parts.push(string `${p.'type} ${safeName}`);
        }
        return string:'join(", ", ...parts);
    }

    string[] parts = [];

    // Required fields → direct positional params
    foreach IRField f in reqStruct.fields {
        if f.kind == REQUIRED {
            string safeName = safeIdentifier(f.name);
            parts.push(string `${f.'type} ${safeName}`);
        }
    }

    // Optional / default fields → included *Config record
    boolean hasOptional = false;
    foreach IRField f in reqStruct.fields {
        if f.kind == INCLUDED || f.kind == DEFAULT {
            hasOptional = true;
            break;
        }
    }
    if hasOptional {
        string configName = capitalizeFirst(fn.name) + "Config";
        parts.push(string `*${configName} config`);
    }

    return string:'join(", ", ...parts);
}

# Find the request struct for a function, if the function has a single parameter
# whose referenceType points to a STRUCTURE in the IR.
#
# + fn - IR function
# + structures - All IR structures
# + return - The matched IRStructure, or nil
function findRequestStruct(IRFunction fn, IRStructure[] structures) returns IRStructure? {
    if fn.parameters.length() != 1 {
        return ();
    }
    IRParameter p = fn.parameters[0];
    string? refType = p.referenceType;
    if refType is () {
        return ();
    }
    foreach IRStructure s in structures {
        if s.name == refType {
            return s;
        }
    }
    return ();
}

# Build a <FnName>Config record containing the optional / default fields of
# the request struct.  Returns an empty string when there are no optional fields.
#
# + fnName - camelCase function name (e.g. "sendMessage")
# + reqStruct - The request structure to inspect, or nil
# + return - Ballerina type declaration string, or empty string
function buildFunctionConfigRecord(string fnName, IRStructure? reqStruct) returns string {
    if reqStruct is () {
        return "";
    }

    IRField[] optionalFields = [];
    foreach IRField f in reqStruct.fields {
        if f.kind == INCLUDED || f.kind == DEFAULT {
            optionalFields.push(f);
        }
    }

    if optionalFields.length() == 0 {
        return "";
    }

    string configName = capitalizeFirst(fnName) + "Config";
    string[] lines = [];
    lines.push(string `# Optional parameters for the ${fnName} operation.`);
    lines.push(string `public type ${configName} record {|`);
    foreach IRField f in optionalFields {
        lines.push(buildFieldDeclaration(f, "    "));
    }
    lines.push("|};");
    return string:'join("\n", ...lines);
}

# Build the Ballerina return type annotation string.
#
# + ret - IR return descriptor
# + return - e.g. "error?" or "PutObjectResponse|error"
function buildReturnType(IRReturn ret) returns string {
    string t = ret.'type;
    if t == "()" || t == "void" || t == "" {
        return "error?";
    }
    return string `${t}|error`;
}

# Build the return-value description for the doc comment.
#
# + ret - IR return descriptor
# + return - Human-readable description string
function buildReturnDescription(IRReturn ret) returns string {
    string t = ret.'type;
    if t == "()" || t == "void" || t == "" {
        return "An error if the operation fails, or nil on success";
    }
    if ret.description.length() > 0 {
        return trimTrailingPeriod(ret.description);
    }
    return string `The ${t} result or an error`;
}

# Return a source-safe identifier, prefixing a single quote for Ballerina keywords.
#
# + name - Original identifier name (camelCase)
# + return - Source-safe identifier
function safeIdentifier(string name) returns string {
    if name.startsWith("'") {
        return name;
    }
    if BALLERINA_KEYWORDS.hasKey(name) {
        return string `'${name}`;
    }
    return name;
}

# Format a default value for emission in a field declaration.
# String-typed fields are wrapped in double quotes; others are used as-is.
#
# + fieldType - Ballerina type name of the field
# + defaultValue - Default value string from the IR (null falls back to "()")
# + return - Formatted default value string ready for source code
function formatDefaultValue(string fieldType, string? defaultValue) returns string {
    string dv = defaultValue ?: "()";
    if fieldType == "string" {
        if dv.startsWith("\"") && dv.endsWith("\"") {
            return dv;
        }
        return string `"${dv}"`;
    }
    return dv;
}

# Strip a trailing period from a documentation string.
#
# + text - Input text
# + return - Text without trailing period
function trimTrailingPeriod(string text) returns string {
    if text.endsWith(".") {
        return text.substring(0, text.length() - 1);
    }
    return text;
}

# Derive a human-friendly base name by stripping a trailing "Client" suffix.
#
# + clientName - Full client name
# + return - Base name
function deriveBaseName(string clientName) returns string {
    if clientName.endsWith("Client") {
        return clientName.substring(0, clientName.length() - 6);
    }
    return clientName;
}

# Capitalize the first character of a string (camelCase → PascalCase prefix).
#
# + s - Input string
# + return - String with first character uppercased
function capitalizeFirst(string s) returns string {
    if s.length() == 0 {
        return s;
    }
    return s.substring(0, 1).toUpperAscii() + s.substring(1);
}
