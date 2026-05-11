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

import ballerina/io;
import ballerina/regex;
import wso2/connector_automator.utils;

# Generate an IntermediateRepresentation by sending the raw metadata JSON
# to the LLM and parsing its structured IR JSON response.
#
# + metadataPath - Path to the sdk_analyzer metadata JSON file
# + config - Generator configuration
# + return - IntermediateRepresentation or error
public function generateIRFromMetadata(string metadataPath, GeneratorConfig config)
        returns IntermediateRepresentation|error {

    // Read raw metadata JSON text
    string metadataJson = check io:fileReadString(metadataPath);

    // Filter enum-typed entries from memberClasses before sending to the LLM.
    string metadataForLLM = metadataJson;
    string|error filteredMeta = filterEnumClassesFromMemberClasses(metadataJson);
    if filteredMeta is string {
        metadataForLLM = filteredMeta;
    }

    string systemPrompt = getIRGenerationSystemPrompt();
    string userPrompt = getIRGenerationUserPrompt(metadataForLLM);

    // Call LLM via shared utils service
    string responseText = check utils:callAIAdvanced(userPrompt, systemPrompt, config.maxTokens,
            config.enableExtendedThinking, config.thinkingBudgetTokens);

    // Extract JSON from response text
    string irJsonStr = check utils:extractJsonFromLLMResponse(responseText);

    // Validate JSON is complete before parsing
    if !isCompleteJson(irJsonStr) {
        // Save the incomplete JSON for debugging
        string debugPath = string `${config.outputDir}/incomplete-ir-response.json`;
        return error(string `IR JSON is incomplete or truncated (${irJsonStr.length()} chars). ` +
                    string `The LLM response may have exceeded token limits. ` +
                    string `Try increasing maxTokens in GeneratorConfig or reducing the SDK complexity. ` +
                    string `Incomplete JSON saved to: ${debugPath}`);
    }

    // Parse JSON string to IR – provide a useful snippet on failure
    json|error irJsonResult = irJsonStr.fromJsonString();
    if irJsonResult is error {
        int snippetLen = irJsonStr.length() < 300 ? irJsonStr.length() : 300;
        int tailStart = irJsonStr.length() > 200 ? irJsonStr.length() - 200 : 0;
        string head = irJsonStr.substring(0, snippetLen);
        string tail = irJsonStr.substring(tailStart);
        // Save the malformed JSON for debugging
        string debugPath = string `${config.outputDir}/malformed-ir-response.json`;
        return error(string `IR JSON parse failed (total ${irJsonStr.length()} chars). ` +
                    string `HEAD: ${head} ... TAIL: ${tail}. ` +
                    string `Malformed JSON saved to: ${debugPath}`, irJsonResult);
    }
    json irJson = irJsonResult;
    IntermediateRepresentation|error irResult = irJson.cloneWithType(IntermediateRepresentation);
    if irResult is error {
        return error("IR JSON structure does not match IntermediateRepresentation schema: " +
                    irResult.message(), irResult);
    }
    IntermediateRepresentation ir = irResult;

    // Replace LLM-generated enums with deterministically extracted enums from the metadata's `enums` map
    IREnum[]|error programmaticEnums = extractEnumsFromMetadata(metadataJson);
    if programmaticEnums is IREnum[] {
        map<boolean> enumNameSet = {};
        foreach IREnum e in programmaticEnums {
            enumNameSet[canonicalizeTypeName(e.name)] = true;
        }
        IRStructure[] structsWithoutEnums = [];
        foreach IRStructure s in ir.structures {
            if !enumNameSet.hasKey(canonicalizeTypeName(s.name)) {
                structsWithoutEnums.push(s);
            }
        }
        ir = {
            sdkName: ir.sdkName,
            version: ir.version,
            clientName: ir.clientName,
            clientDescription: ir.clientDescription,
            connectionFields: ir.connectionFields,
            functions: ir.functions,
            structures: structsWithoutEnums,
            enums: programmaticEnums,
            collections: ir.collections
        };
    }

    // Post-process: ensure every referenced type is defined in structures/enums/collections.
    IntermediateRepresentation completeIr = ensureIRCompleteness(ir);

    // Enrich any empty structures using field data already present in the metadata JSON.
    IntermediateRepresentation|error enrichedIr = enrichEmptyStructuresFromMetadata(completeIr, metadataJson);
    if enrichedIr is IntermediateRepresentation {
        return enrichedIr;
    }
    return completeIr;
}

# Extract the base type name from a Ballerina type expression.
#
# + typeName - Full type string
# + return - Base type name
function extractBaseType(string typeName) returns string {
    string t = typeName.trim();
    if t.startsWith("map<") && t.endsWith(">") {
        return t.substring(4, t.length() - 1).trim();
    }
    if t.endsWith("[]") {
        return t.substring(0, t.length() - 2).trim();
    }
    return t;
}

# Canonicalize Java-derived type names for stable IR matching.
#
# + typeName - parameter description
# + return - return value description
function canonicalizeTypeName(string typeName) returns string {
    string t = typeName.trim();
    if t.length() == 0 {
        return t;
    }
    return regex:replaceAll(t, "\\$", "");
}

# Return true if the type name is a Ballerina built-in that needs no definition.
#
# + typeName - Base type name (no wrappers)
# + return - true when the type is a built-in
function isBuiltinBallerina(string typeName) returns boolean {
    string[] builtins = [
        "string",
        "int",
        "float",
        "boolean",
        "byte",
        "decimal",
        "anydata",
        "json",
        "xml",
        "byte[]",
        "anydata[]",
        "map<anydata>",
        "map<string>",
        "map<json>",
        "()",
        "void",
        ""
    ];
    foreach string b in builtins {
        if typeName == b {
            return true;
        }
    }
    return false;
}

# Add each base type from a possibly-union type string to the referenced set.
#
# + typeStr - Ballerina type expression (may be a union)
# + referenced - Mutable set to add resolved base type names into
function addTypeRef(string typeStr, map<boolean> referenced) {
    string base = canonicalizeTypeName(extractBaseType(typeStr));
    if base.includes("|") {
        string[] parts = regex:split(base, "\\|");
        foreach string part in parts {
            string trimmed = part.trim();
            if trimmed.length() > 0 {
                referenced[trimmed] = true;
            }
        }
    } else if base.length() > 0 {
        referenced[base] = true;
    }
}

function collectReferencedTypes(IntermediateRepresentation ir) returns map<boolean> {
    map<boolean> referenced = {};

    // Connection fields (may include union types like "A|B|C")
    foreach IRField f in ir.connectionFields {
        addTypeRef(f.'type, referenced);
    }

    // Function parameters and returns
    foreach IRFunction fn in ir.functions {
        foreach IRParameter p in fn.parameters {
            addTypeRef(p.'type, referenced);
            string? ref = p.referenceType;
            if ref is string {
                referenced[canonicalizeTypeName(ref)] = true;
            }
        }
        addTypeRef(fn.'return.'type, referenced);
        string? retRef = fn.'return.referenceType;
        if retRef is string {
            referenced[canonicalizeTypeName(retRef)] = true;
        }
    }

    // Structure fields (one level deep)
    foreach IRStructure s in ir.structures {
        foreach IRField f in s.fields {
            addTypeRef(f.'type, referenced);
        }
    }

    return referenced;
}

# Determine whether a type name looks like an enum based on common suffixes.
#
# + typeName - Type name to test
# + return - true if the name has a typical enum suffix
function looksLikeEnum(string typeName) returns boolean {
    string[] enumSuffixes = [
        "Mode",
        "Type",
        "Status",
        "Class",
        "Algorithm",
        "ACL",
        "Payer",
        "Encryption",
        "Protocol",
        "Access",
        "Permission",
        "Tier",
        "Action",
        "State",
        "Policy",
        "Direction"
    ];
    foreach string suffix in enumSuffixes {
        if typeName.endsWith(suffix) {
            return true;
        }
    }
    return false;
}

# Ensure the IR is complete: every type referenced must be defined.
# Adds empty stub entries for any missing types.
#
# + ir - Raw IR from LLM
# + return - IR with stubs added for every undefined type
function ensureIRCompleteness(IntermediateRepresentation ir) returns IntermediateRepresentation {
    // Build a set of already-defined type names
    map<boolean> defined = {};
    foreach IRStructure s in ir.structures {
        defined[canonicalizeTypeName(s.name)] = true;
    }
    foreach IREnum e in ir.enums {
        defined[canonicalizeTypeName(e.name)] = true;
    }
    foreach IRCollection c in ir.collections {
        defined[canonicalizeTypeName(c.name)] = true;
    }

    // Collect referenced types
    map<boolean> referenced = collectReferencedTypes(ir);

    // Find gaps and build stub lists
    IRStructure[] extraStructures = [];
    IREnum[] extraEnums = [];

    foreach string typeName in referenced.keys() {
        if isBuiltinBallerina(typeName) || defined.hasKey(typeName) {
            continue;
        }
        // Add stub
        if looksLikeEnum(typeName) {
            extraEnums.push({name: typeName, kind: "ENUM", nativeType: "string", values: []});
        } else {
            extraStructures.push({name: typeName, kind: "STRUCTURE", fields: []});
        }
        defined[typeName] = true;
    }

    if extraStructures.length() == 0 && extraEnums.length() == 0 {
        return ir;
    }

    IRStructure[] allStructures = [...ir.structures, ...extraStructures];
    IREnum[] allEnums = [...ir.enums, ...extraEnums];
    return {
        sdkName: ir.sdkName,
        version: ir.version,
        clientName: ir.clientName,
        clientDescription: ir.clientDescription,
        connectionFields: ir.connectionFields,
        functions: ir.functions,
        structures: allStructures,
        enums: allEnums,
        collections: ir.collections
    };
}

# Check if a JSON string is syntactically complete (balanced braces/brackets).
#
# + jsonStr - JSON string to validate
# + return - true if JSON appears complete
function isCompleteJson(string jsonStr) returns boolean {
    int braceCount = 0;
    int bracketCount = 0;
    boolean inString = false;
    boolean escaped = false;

    int i = 0;
    while i < jsonStr.length() {
        string char = jsonStr.substring(i, i + 1);

        if escaped {
            escaped = false;
            i += 1;
            continue;
        }

        if char == "\\" {
            escaped = true;
            i += 1;
            continue;
        }

        if char == "\"" {
            inString = !inString;
            i += 1;
            continue;
        }

        if !inString {
            if char == "{" {
                braceCount += 1;
            } else if char == "}" {
                braceCount -= 1;
            } else if char == "[" {
                bracketCount += 1;
            } else if char == "]" {
                bracketCount -= 1;
            }
        }

        i += 1;
    }

    // JSON is complete if all braces and brackets are balanced and we're not in a string
    return braceCount == 0 && bracketCount == 0 && !inString;
}


# Derive a SCREAMING_SNAKE_CASE Ballerina enum member name from a raw value string.
#
# + rawValue - The cleaned enum value string (with " - default" already stripped)
# + return - SCREAMING_SNAKE_CASE member name suitable for a Ballerina enum identifier
function deriveMemberName(string rawValue) returns string {
    string v = rawValue.trim();
    if v.length() == 0 {
        return "UNKNOWN";
    }

    // Insert an underscore before each uppercase letter that directly follows
    // a lowercase letter or a digit.
    string phased = "";
    int idx = 0;
    while idx < v.length() {
        string ch = v.substring(idx, idx + 1);
        if idx > 0 {
            string prev = v.substring(idx - 1, idx);
            boolean chUpper = regex:matches(ch, "[A-Z]");
            boolean prevLower = regex:matches(prev, "[a-z]");
            boolean prevDigit = regex:matches(prev, "[0-9]");
            if chUpper && (prevLower || prevDigit) {
                phased += "_";
            }
        }
        phased += ch;
        idx += 1;
    }

    // Replace every non-alphanumeric character with an underscore.
    string replaced = "";
    int idx2 = 0;
    while idx2 < phased.length() {
        string ch = phased.substring(idx2, idx2 + 1);
        if regex:matches(ch, "[A-Za-z0-9]") {
            replaced += ch;
        } else {
            replaced += "_";
        }
        idx2 += 1;
    }

    // Uppercase everything.
    string upper = replaced.toUpperAscii();

    // Collapse consecutive underscores.
    upper = regex:replaceAll(upper, "_+", "_");

    // Trim leading and trailing underscores.
    int trimStart = 0;
    while trimStart < upper.length() && upper.substring(trimStart, trimStart + 1) == "_" {
        trimStart += 1;
    }
    int trimEnd = upper.length();
    while trimEnd > trimStart && upper.substring(trimEnd - 1, trimEnd) == "_" {
        trimEnd -= 1;
    }
    if trimStart >= trimEnd {
        return "UNKNOWN";
    }
    return upper.substring(trimStart, trimEnd);
}

# Return true when the value is a sentinel that should always be filtered from enums.
#
# + value - Cleaned enum value string
# + return - true if this value is a sentinel
function isSentinelEnumValue(string value) returns boolean {
    string upper = value.toUpperAscii();
    return upper == "UNKNOWN_TO_SDK_VERSION" || upper == "SDK_UNKNOWN" || upper == "UNKNOWN";
}

# Extract IREnum entries deterministically from the metadata JSON's top-level `enums` map.
#
# + metadataJson - Raw metadata JSON string produced by sdk_analyzer
# + return - Array of fully-populated IREnum entries, or error
function extractEnumsFromMetadata(string metadataJson) returns IREnum[]|error {
    json metaJson = check metadataJson.fromJsonString();

    // Gracefully handle metadata that has no enums map at all.
    json|error enumsFieldResult = metaJson.enums;
    if enumsFieldResult is error {
        return [];
    }
    map<json>|error enumsMapResult = enumsFieldResult.cloneWithType();
    if enumsMapResult is error {
        return [];
    }
    map<json> enumsMap = enumsMapResult;

    IREnum[] result = [];
    foreach string fqClassName in enumsMap.keys() {
        json|() enumEntryOpt = enumsMap[fqClassName];
        if enumEntryOpt is () {
            continue;
        }
        json enumEntry = enumEntryOpt;

        // Extract simpleName.
        json|error snResult = enumEntry.simpleName;
        if snResult is error {
            continue;
        }
        string|error sn = snResult.cloneWithType(string);
        if sn is error {
            continue;
        }
        string simpleName = canonicalizeTypeName(sn);

        // Extract values array.
        json|error valuesResult = enumEntry.values;
        if valuesResult is error {
            continue;
        }
        json[]|error valuesArrResult = valuesResult.cloneWithType();
        if valuesArrResult is error {
            continue;
        }
        json[] valuesArr = valuesArrResult;

        IREnumValue[] irValues = [];
        foreach json valJson in valuesArr {
            string|error rawValResult = valJson.cloneWithType(string);
            if rawValResult is error {
                continue;
            }
            string rawVal = rawValResult;

            // Strip the " - default" annotation to get the actual SDK string value.
            string cleanVal = rawVal;
            if cleanVal.endsWith(" - default") {
                cleanVal = cleanVal.substring(0, cleanVal.length() - " - default".length()).trim();
            }

            // Filter sentinel values that carry no meaningful API information.
            if isSentinelEnumValue(cleanVal) {
                continue;
            }

            // Derive a stable SCREAMING_SNAKE_CASE member name from the value.
            string memberName = deriveMemberName(cleanVal);
            irValues.push({member: memberName, value: cleanVal});
        }

        // Only include the enum when at least one value was extracted.
        if irValues.length() > 0 {
            result.push({name: simpleName, kind: "ENUM", nativeType: "string", values: irValues});
        }
    }

    return deduplicateEnumMemberNames(result);
}

# Ensure all enum member names are globally unique across every enum in the array.
#
# + enums - Input IREnum array that may have duplicate member names across enums
# + return - IREnum array with globally unique member names
function deduplicateEnumMemberNames(IREnum[] enums) returns IREnum[] {
    // Count occurrences of each member name across all enums.
    map<int> memberCount = {};
    foreach IREnum e in enums {
        foreach IREnumValue v in e.values {
            int existing = memberCount[v.member] ?: 0;
            memberCount[v.member] = existing + 1;
        }
    }

    // For conflicting members, prefix with the enum's SCREAMING_SNAKE name.
    IREnum[] result = [];
    foreach IREnum e in enums {
        string enumPrefix = deriveMemberName(e.name);
        IREnumValue[] newValues = [];
        foreach IREnumValue v in e.values {
            int count = memberCount[v.member] ?: 0;
            if count > 1 {
                newValues.push({member: enumPrefix + "_" + v.member, value: v.value});
            } else {
                newValues.push(v);
            }
        }
        result.push({name: e.name, kind: "ENUM", nativeType: "string", values: newValues});
    }
    return result;
}

# Remove entries from the metadata `memberClasses` map whose fully-qualified class name
# also appears as a key in the `enums` map.
#
# + metadataJson - Raw metadata JSON string
# + return - Modified metadata JSON string, or error if the JSON cannot be processed
function filterEnumClassesFromMemberClasses(string metadataJson) returns string|error {
    json metaJson = check metadataJson.fromJsonString();
    map<json> metaMap = check metaJson.cloneWithType();

    // Collect the set of fully-qualified enum class names.
    json enumsRaw = metaMap["enums"] ?: {};
    map<json> enumsMap = check enumsRaw.cloneWithType();

    // Rebuild memberClasses without any entry whose key is a known enum class.
    json memberClassesRaw = metaMap["memberClasses"] ?: {};
    map<json> memberClasses = check memberClassesRaw.cloneWithType();

    map<json> filteredMemberClasses = {};
    foreach string key in memberClasses.keys() {
        if !enumsMap.hasKey(key) {
            json|() val = memberClasses[key];
            if val is json {
                filteredMemberClasses[key] = val;
            }
        }
    }

    metaMap["memberClasses"] = filteredMemberClasses;
    json updatedJson = metaMap;
    return updatedJson.toJsonString();
}

# Map a Java simple type name to the corresponding Ballerina built-in type.
# For unknown types the original name is returned unchanged.
#
# + javaType - Java type simple name (e.g. "String", "Integer", "boolean")
# + return - Ballerina type name
function mapJavaTypeToBallerinaType(string javaType) returns string {
    match javaType {
        "String"|"java.lang.String" => {
            return "string";
        }
        "Integer"|"int"|"Long"|"long"|"Short"|"short" => {
            return "int";
        }
        "Double"|"double"|"Float"|"float" => {
            return "float";
        }
        "Boolean"|"boolean" => {
            return "boolean";
        }
        "Byte"|"byte" => {
            return "byte";
        }
        "BigDecimal"|"BigInteger"|"java.math.BigDecimal"|"java.math.BigInteger" => {
            return "decimal";
        }
        "void" => {
            return "()";
        }
        "Object"|"java.lang.Object" => {
            return "anydata";
        }
        "URI"|"URL"|"java.net.URI"|"java.net.URL" => {
            return "string";
        }
        "InputStream"|"OutputStream"|"java.io.InputStream"|"java.io.OutputStream" => {
            return "byte[]";
        }
        "List"|"ArrayList"|"java.util.List"|"java.util.ArrayList" => {
            return "anydata[]";
        }
        "Map"|"HashMap"|"java.util.Map"|"java.util.HashMap" => {
            return "map<anydata>";
        }
        "Set"|"HashSet"|"java.util.Set"|"java.util.HashSet" => {
            return "anydata[]";
        }
        _ => {
            return javaType.trim().length() > 0 ? javaType : "anydata";
        }
    }
}

# Map a single raw field JSON object to an IRField
#
# + fieldJson - Raw field JSON from metadata memberClasses entry
# + enumSimpleNames - Set of simple names of known enum types for type resolution
# + return - IRField or error
function mapJsonFieldToIRField(json fieldJson, map<boolean> enumSimpleNames) returns IRField|error {
    string fieldName = check (check fieldJson.name).cloneWithType(string);
    boolean isRequired = check (check fieldJson.isRequired).cloneWithType(boolean);

    string balType;

    // Field is directly typed as an enum.
    json|error enumRefResult = fieldJson.enumReference;
    if enumRefResult is string && enumRefResult.trim().length() > 0 {
        string[] parts = regex:split(enumRefResult, "\\.");
        balType = canonicalizeTypeName(parts[parts.length() - 1]);
    } else {
        // Interface field with concrete implementations — emit a union type.
        json|error ifaceImplsResult = fieldJson.interfaceImplementations;
        json[]|error ifaceImplsArr = ifaceImplsResult is json[] ? ifaceImplsResult : error("not array");
        if ifaceImplsArr is json[] && ifaceImplsArr.length() > 0 {
            string[] implSimpleNames = [];
            foreach json implFqn in ifaceImplsArr {
                if implFqn is string && implFqn.trim().length() > 0 {
                    string[] parts = regex:split(implFqn, "\\.");
                    implSimpleNames.push(canonicalizeTypeName(parts[parts.length() - 1]));
                }
            }
            balType = implSimpleNames.length() > 0
                ? string:'join("|", ...implSimpleNames)
                : "anydata";
        } else {
            // Field is a collection whose element is a member-class type.
            json|error memberRefResult = fieldJson.memberReference;
            if memberRefResult is string && memberRefResult.trim().length() > 0 {
                string[] parts = regex:split(memberRefResult, "\\.");
                string memberSimpleName = canonicalizeTypeName(parts[parts.length() - 1]);

                string fullType = "";
                json|error ftResult = fieldJson.fullType;
                if ftResult is string {
                    fullType = ftResult;
                }

                if fullType.includes("java.util.List") || fullType.includes("java.util.Set") {
                    balType = memberSimpleName + "[]";
                } else if fullType.includes("java.util.Map") {
                    balType = "map<" + memberSimpleName + ">";
                } else {
                    balType = memberSimpleName;
                }
            } else {
                // Plain scalar field — map using standard Java to Ballerina rules.
                string typeName = "";
                json|error tnResult = fieldJson.typeName;
                if tnResult is string {
                    typeName = tnResult;
                }
                balType = mapJavaTypeToBallerinaType(canonicalizeTypeName(typeName));
            }
        }
    }

    string kind = isRequired ? "Required" : "Included";
    return {name: fieldName, kind: kind, 'type: balType, description: ""};
}

# Attempt to populate empty STRUCTURE entries in the IR using field data that is
# already present in the metadata JSON's `memberClasses` map.
#
# + ir - IntermediateRepresentation potentially containing empty-field structures
# + metadataJson - Raw metadata JSON string used as the field data source
# + return - Enriched IR, or error if the metadata JSON cannot be processed
function enrichEmptyStructuresFromMetadata(IntermediateRepresentation ir, string metadataJson)
        returns IntermediateRepresentation|error {

    json metaJson = check metadataJson.fromJsonString();

    // Build a simpleName → entry lookup from memberClasses.
    json|error memberClassesResult = metaJson.memberClasses;
    map<json> memberClassesMap = {};
    if memberClassesResult is json {
        map<json>|error mcm = memberClassesResult.cloneWithType();
        if mcm is map<json> {
            memberClassesMap = mcm;
        }
    }

    map<json> bySimpleName = {};
    foreach string fqName in memberClassesMap.keys() {
        json|() entry = memberClassesMap[fqName];
        if entry is json {
            json|error snResult = entry.simpleName;
            if snResult is string {
                bySimpleName[canonicalizeTypeName(snResult)] = entry;
            }
        }
    }

    // Build the set of known enum simple names so field type resolution can
    // correctly identify enum-typed fields.
    json|error enumsResult = metaJson.enums;
    map<boolean> enumSimpleNames = {};
    if enumsResult is json {
        map<json>|error enumsMap = enumsResult.cloneWithType();
        if enumsMap is map<json> {
            foreach string fqName in enumsMap.keys() {
                json|() enumEntry = enumsMap[fqName];
                if enumEntry is json {
                    json|error snResult = enumEntry.simpleName;
                    if snResult is string {
                        enumSimpleNames[canonicalizeTypeName(snResult)] = true;
                    }
                }
            }
        }
    }

    // Enrich structures that have zero fields.
    IRStructure[] enrichedStructures = [];
    foreach IRStructure s in ir.structures {
        if s.fields.length() > 0 {
            enrichedStructures.push(s);
            continue;
        }

        // Try to find matching field data in memberClasses by simple name.
        json|() entry = bySimpleName[canonicalizeTypeName(s.name)];
        if entry is () {
            enrichedStructures.push(s);
            continue;
        }

        json|error fieldsResult = entry.fields;
        if fieldsResult is error {
            enrichedStructures.push(s);
            continue;
        }
        json[]|error fieldsArr = fieldsResult.cloneWithType();
        if fieldsArr is error {
            enrichedStructures.push(s);
            continue;
        }

        IRField[] irFields = [];
        foreach json fieldJson in fieldsArr {
            IRField|error irField = mapJsonFieldToIRField(fieldJson, enumSimpleNames);
            if irField is IRField {
                irFields.push(irField);
            }
        }

        enrichedStructures.push({name: s.name, kind: "STRUCTURE", fields: irFields});
    }

    return {
        sdkName: ir.sdkName,
        version: ir.version,
        clientName: ir.clientName,
        clientDescription: ir.clientDescription,
        connectionFields: ir.connectionFields,
        functions: ir.functions,
        structures: enrichedStructures,
        enums: ir.enums,
        collections: ir.collections
    };
}
