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

import ballerina/regex;
import wso2/connector_automator.utils;

# Resolve an underlying Request/Response ClassInfo from a parameter
#
# + param - Parameter to analyze
# + allClasses - All classes for type lookup
# + methodName - Method name for heuristics
# + return - Resolved class or null
public function resolveRequestClassFromParameter(ParameterInfo param, ClassInfo[] allClasses, string methodName)
    returns ClassInfo? {
    string[] candidates = [];

    // Add the parameter's declared type first
    if param.typeName != "" {
        candidates.push(param.typeName);
    }

    foreach string raw in candidates {
        string[] normCandidates = normalizeCandidateTypeNames(raw);
        foreach string cand in normCandidates {
            if cand.endsWith("Request") || cand.endsWith("Response") {
                ClassInfo? found = findClassByName(cand, allClasses);
                if found is ClassInfo {
                    return found;
                }
            }
        }
    }

    foreach string raw in candidates {
        ClassInfo? found = findClassByName(raw, allClasses);
        if found is ClassInfo {
            return found;
        }
    }

    if candidates.length() == 1 {
        string rawOnly = candidates[0];
        string lower = rawOnly.toLowerAscii();
        if lower.includes("consumer") || lower.includes("function") || lower.includes("supplier") {
            string pascal = methodName.substring(0, 1).toUpperAscii() + methodName.substring(1);
            string guess = pascal + "Request";
            ClassInfo? guessCls = findClassByName(guess, allClasses);
            if guessCls is ClassInfo {
                return guessCls;
            }
        }
    }

    return null;
}

# Normalize a type name to candidates for lookup
#
# + raw - Raw type name
# + return - Array of normalized candidate names
public function normalizeCandidateTypeNames(string raw) returns string[] {
    string[] out = [];
    if raw == "" {
        return out;
    }

    if raw.includes("<") && raw.includes(">") {
        string[] parts = regex:split(raw, "<|>");
        if parts.length() >= 2 {
            string inner = parts[1];
            out.push(inner);
        }
        string withoutGenerics = regex:replace(raw, "<.*>", "");
        out.push(withoutGenerics);
    }

    out.push(raw);

    if raw.endsWith(".Builder") {
        string removed = regex:replace(raw, "\\.Builder$", "");
        out.push(removed);
    } else if raw.endsWith("Builder") {
        if raw.includes("$") {
            string maybe = regex:replace(raw, "\\$Builder$", "");
            if maybe != raw {
                out.push(maybe);
            }
        }
        string stripped = regex:replace(raw, "Builder$", "");
        out.push(stripped);
    }

    if raw.includes("$") {
        string dotForm = regex:replace(raw, "\\$", ".");
        out.push(dotForm);
        if dotForm.endsWith(".Builder") {
            string removedDotBuilder = regex:replace(dotForm, "\\.Builder$", "");
            out.push(removedDotBuilder);
        }
    }

    string[] parts = regex:split(raw, "\\.");
    if parts.length() > 0 {
        string simple = parts[parts.length() - 1];
        out.push(simple);
        if simple.endsWith("Builder") {
            string simpleStripped = regex:replace(simple, "Builder$", "");
            out.push(simpleStripped);
        }
    }

    string[] uniq = [];
    foreach string s in out {
        if s == "" {
            continue;
        }
        boolean present = uniq.some(function(string x) returns boolean {
            return x == s;
        });
        if !present {
            uniq.push(s);
        }
    }

    return uniq;
}

# Find class by name in the class list
#
# + className - Class name to find
# + allClasses - All available classes
# + return - Found class or null
public function findClassByName(string className, ClassInfo[] allClasses) returns ClassInfo? {
    foreach ClassInfo cls in allClasses {
        if cls.className == className || cls.simpleName == className {
            return cls;
        }
    }
    return null;
}

# Extract request fields from a Request class
#
# + requestClass - The Request class to analyze
# + return - List of request field information
public function extractRequestFields(ClassInfo requestClass) returns RequestFieldInfo[] {
    RequestFieldInfo[] requestFields = [];
    map<boolean> addedFields = {};

    foreach MethodInfo method in requestClass.methods {
        if method.isStatic {
            continue;
        }
        if method.parameters.length() == 0 && method.returnType != "void" &&
            method.name != "toString" && method.name != "hashCode" &&
            method.name != "equals" && method.name != "getClass" {

            if shouldFilterField(method.name, method.returnType) {
                continue;
            }

            string fieldName = deriveFieldName(method.name);

            if addedFields.hasKey(fieldName) {
                continue;
            }
            addedFields[fieldName] = true;

            string simpleTypeName = extractSimpleTypeName(method.returnType);

            RequestFieldInfo fieldInfo = {
                name: fieldName,
                typeName: simpleTypeName,
                fullType: method.returnType,
                isRequired: false
            };

            if method.description != () {
                fieldInfo.description = method.description;
            }

            requestFields.push(fieldInfo);
        }
    }

    return requestFields;
}

# Extract response fields from a Response/Result class
#
# + responseClass - The Response class to analyze
# + return - List of response field information
public function extractResponseFields(ClassInfo responseClass) returns RequestFieldInfo[] {
    RequestFieldInfo[] responseFields = [];
    map<boolean> addedFields = {};

    foreach MethodInfo method in responseClass.methods {
        if method.parameters.length() == 0 && method.returnType != "void" &&
            method.name != "toString" && method.name != "hashCode" &&
            method.name != "equals" && method.name != "getClass" {

            if method.isStatic {
                continue;
            }

            if shouldFilterField(method.name, method.returnType) {
                continue;
            }

            string fieldName = deriveFieldName(method.name);

            if addedFields.hasKey(fieldName) {
                continue;
            }
            addedFields[fieldName] = true;

            string simpleTypeName = extractSimpleTypeName(method.returnType);

            RequestFieldInfo fieldInfo = {
                name: fieldName,
                typeName: simpleTypeName,
                fullType: method.returnType,
                isRequired: false
            };

            if method.description != () {
                fieldInfo.description = method.description;
            }

            responseFields.push(fieldInfo);
        }
    }

    return responseFields;
}

# Check if a field should be filtered out (builders, utility methods, SDK internals, etc.)
#
# + fieldName - Name of the field/method
# + fieldType - Type of the field/return type
# + return - true if field should be filtered out
function shouldFilterField(string fieldName, string fieldType) returns boolean {
    // Filter Builder types
    if fieldType.endsWith("$Builder") || fieldType.endsWith(".Builder") {
        return true;
    }

    if fieldName == "type" && fieldType.indexOf("$") != -1 && fieldType.endsWith("$Type") {
        return true;
    }

    string[] filteredNames = [
        "toBuilder",
        "builder",
        "serializableBuilderClass",
        "sdkFields",
        "sdkFieldNameToField",
        "defaultProvider",
        "create",
        "copy",
        "clone",
        "getClassInfo",
        "getUnknownKeys",
        "getFactory"
    ];

    foreach string name in filteredNames {
        if fieldName == name {
            return true;
        }
    }

    if fieldName.startsWith("sdk") {
        return true;
    }

    if fieldName.startsWith("has") && fieldName.length() > 3 {
        string afterHas = fieldName.substring(3, 4);
        if afterHas == afterHas.toUpperAscii() {
            return true;
        }
    }

    string simpleType = extractSimpleTypeName(fieldType);

    if fieldType == "java.lang.Class" || simpleType == "Class" || simpleType == "CompletableFuture" ||
        simpleType == "Supplier" || simpleType == "Consumer" || simpleType == "Function" ||
        simpleType == "Predicate" {
        return true;
    }

    if fieldType.includes("SdkField") {
        return true;
    }

    if fieldType.includes(".crt.") {
        return true;
    }

    if fieldType.includes(".internal.") || fieldType.includes(".impl.") {
        return true;
    }

    return false;
}

# Derive a field name from a method name.
#
# + methodName - The zero-arg method name
# + return - Derived camelCase field name
function deriveFieldName(string methodName) returns string {
    string name = methodName;
    if name.startsWith("get") && name.length() > 3 {
        string afterGet = name.substring(3, 4);
        if afterGet == afterGet.toUpperAscii() {
            name = name.substring(3);
        }
    }
    else if name.startsWith("is") && name.length() > 2 {
        string afterIs = name.substring(2, 3);
        if afterIs == afterIs.toUpperAscii() {
            name = name.substring(2);
        }
    }
    // Lowercase the first character
    if name.length() > 0 {
        string firstChar = name.substring(0, 1).toLowerAscii();
        name = firstChar + name.substring(1);
    }
    return name;
}

# Extract simple type name from fully qualified name
#
# + fullTypeName - Fully qualified type name
# + return - Simple type name (last component)
function extractSimpleTypeName(string fullTypeName) returns string {
    if fullTypeName == "" {
        return "";
    }

    string baseType = fullTypeName;
    int? angleBracket = fullTypeName.indexOf("<");
    if angleBracket is int && angleBracket >= 0 {
        baseType = fullTypeName.substring(0, angleBracket);
    }

    int? lastDot = baseType.lastIndexOf(".");
    if lastDot is int && lastDot >= 0 {
        return baseType.substring(lastDot + 1);
    }
    return baseType;
}

# Extract generic type parameter from a parameterized type (e.g., List<String> -> String)
#
# + fullTypeName - Fully qualified type name with generics
# + return - The generic type parameter, or null if not a generic type
public function extractGenericTypeParameter(string fullTypeName) returns string? {
    if fullTypeName == "" {
        return ();
    }

    // Look for angle brackets indicating generic types
    int? openBracket = fullTypeName.indexOf("<");
    int? closeBracket = fullTypeName.lastIndexOf(">");

    if openBracket is int && closeBracket is int && openBracket < closeBracket {
        string genericPart = fullTypeName.substring(openBracket + 1, closeBracket);
        string[] args = splitTopLevelGenericArgs(genericPart);

        if args.length() >= 2 {
            return sanitizeGenericTypeArg(args[1]);
        }

        if args.length() == 1 {
            return sanitizeGenericTypeArg(args[0]);
        }
    }

    return ();
}

function splitTopLevelGenericArgs(string genericPart) returns string[] {
    string[] args = [];
    int depth = 0;
    int segmentStart = 0;
    int length = genericPart.length();

    foreach int i in 0 ..< length {
        string ch = genericPart.substring(i, i + 1);
        if ch == "<" {
            depth += 1;
        } else if ch == ">" {
            if depth > 0 {
                depth -= 1;
            }
        } else if ch == "," && depth == 0 {
            args.push(genericPart.substring(segmentStart, i).trim());
            segmentStart = i + 1;
        }
    }

    if segmentStart < length {
        args.push(genericPart.substring(segmentStart, length).trim());
    }

    return args;
}

function sanitizeGenericTypeArg(string rawArg) returns string {
    string value = rawArg.trim();

    if value.startsWith("? extends ") {
        value = value.substring(10).trim();
    } else if value.startsWith("? super ") {
        value = value.substring(8).trim();
    } else if value == "?" {
        return "";
    }

    int? nestedStart = value.indexOf("<");
    if nestedStart is int && nestedStart > 0 {
        value = value.substring(0, nestedStart);
    }

    if value.endsWith("[]") && value.length() > 2 {
        value = value.substring(0, value.length() - 2);
    }

    return value.trim();
}

# Check if a type is a collection type
#
# + typeName - Simple or full type name
# + return - true if the type is a collection type
public function isCollectionType(string typeName) returns boolean {
    string simple = extractSimpleTypeName(typeName).toLowerAscii();
    string[] collectionTypes = [
        "list", "set", "collection", "map",
        "arraylist", "hashset", "hashmap",
        "linkedlist", "treeset", "treemap",
        "linkedhashset", "linkedhashmap",
        "sortedset", "sortedmap",
        "concurrenthashmap", "copyonwritearraylist"
    ];
    foreach string ct in collectionTypes {
        if simple == ct {
            return true;
        }
    }
    return false;
}

# Enhance parameters with resolved request class information
#
# + parameters - Original parameters
# + allClasses - All classes for type resolution
# + methodName - Method name for heuristics
# + return - Enhanced parameters with field information
public function extractEnhancedParameters(ParameterInfo[] parameters, ClassInfo[] allClasses, string methodName)
    returns ParameterInfo[] {
    ParameterInfo[] enhancedParams = [];
    foreach ParameterInfo param in parameters {
        ParameterInfo enhancedParam = param;
        ClassInfo? resolved = resolveRequestClassFromParameter(param, allClasses, methodName);
        if resolved is ClassInfo {
            RequestFieldInfo[] requestFields = extractRequestFields(resolved);
            RequestFieldInfo[] merged = [];
            map<string> providedDesc = {};
            if param.requestFields is RequestFieldInfo[] {
                RequestFieldInfo[] provided = <RequestFieldInfo[]>param.requestFields;
                foreach RequestFieldInfo pf in provided {
                    if pf.description != () {
                        providedDesc[pf.name] = <string>pf.description;
                    }
                }
            }

            foreach RequestFieldInfo rf in requestFields {
                RequestFieldInfo copy = rf;
                if (copy.description == () && providedDesc.hasKey(copy.name)) {
                    copy.description = providedDesc[copy.name];
                }
                merged.push(copy);
            }

            // If the resolved extraction returned nothing, fall back to the provided fields
            if merged.length() == 0 && param.requestFields is RequestFieldInfo[] {
                RequestFieldInfo[] provided2 = <RequestFieldInfo[]>param.requestFields;
                if provided2.length() > 0 {
                    merged = provided2;
                }
            }

            enhancedParam = {
                name: param.name,
                typeName: param.typeName,
                requestFields: merged
            };
        }
        enhancedParams.push(enhancedParam);
    }
    return enhancedParams;
}

# Check if a type is a simple/primitive type
#
# + typeName - Type name to check
# + return - True if simple type
public function isSimpleType(string typeName) returns boolean {
    return typeName == "int" || typeName == "long" || typeName == "boolean" ||
            typeName == "String" || typeName == "double" || typeName == "float" ||
            typeName == "byte" || typeName == "char" || typeName == "short" ||
            typeName == "java.lang.String" || typeName == "java.lang.Object";
}

# Extract enum metadata from an enum class
#
# + enumClass - The enum ClassInfo
# + return - Enum metadata with values
public function extractEnumMetadata(ClassInfo enumClass) returns EnumMetadata {
    string[] values = [];
    boolean hasFromValueMethod = hasStringFromValueMethod(enumClass);

    foreach FieldInfo fieldInfo in enumClass.fields {
        if fieldInfo.isStatic && fieldInfo.isFinal && isSelfTypedField(fieldInfo, enumClass) {
            string enumValue = fieldInfo.name;
            if fieldInfo.literalValue is string {
                string literalValue = <string>fieldInfo.literalValue;
                if literalValue.trim().length() > 0 {
                    enumValue = literalValue;
                }
            } else if enumClass.isEnum && hasFromValueMethod && fieldInfo.name != "UNKNOWN_TO_SDK_VERSION" {
                enumValue = deriveEnumLiteralFromConstant(fieldInfo.name);
            } else if !enumClass.isEnum && fieldInfo.javadoc is string {
                string literalValue = <string>fieldInfo.javadoc;
                if literalValue.trim().length() > 0 {
                    enumValue = literalValue;
                }
            }
            values.push(enumValue);
        }
    }

    string? defaultName = ();
    foreach string v in values {
        if v == "DEFAULT" {
            defaultName = v;
            break;
        }
    }
    if defaultName is () {
        foreach string v in values {
            if v != "UNKNOWN_TO_SDK_VERSION" {
                defaultName = v;
                break;
            }
        }
    }
    if defaultName is () {
        if values.length() > 0 {
            defaultName = values[0];
        }
    }

    // Build output strings, marking the default entry
    string[] outValues = [];
    foreach string v in values {
        if defaultName is string && v == defaultName {
            outValues.push(v + " - default");
        } else {
            outValues.push(v);
        }
    }

    return {
        simpleName: enumClass.simpleName,
        values: outValues
    };
}

function hasStringFromValueMethod(ClassInfo cls) returns boolean {
    foreach MethodInfo method in cls.methods {
        if method.name != "fromValue" {
            continue;
        }
        if method.parameters.length() != 1 {
            continue;
        }
        string paramType = method.parameters[0].typeName;
        if paramType == "String" || paramType == "java.lang.String" {
            return true;
        }
    }
    return false;
}

function deriveEnumLiteralFromConstant(string constantName) returns string {
    if !constantName.includes("_") {
        return constantName;
    }

    string[] parts = regex:split(constantName, "_");
    string literal = "";
    foreach string part in parts {
        if part.length() == 0 {
            continue;
        }
        string lower = part.toLowerAscii();
        literal += lower.substring(0, 1).toUpperAscii() + lower.substring(1);
    }
    return literal.length() > 0 ? literal : constantName;
}

# Check whether a class contains enum-like constants (static final self-typed fields)
#
# + cls - Class information to inspect
# + return - True if class appears enum-like
public function hasEnumLikeConstants(ClassInfo cls) returns boolean {
    int constantCount = 0;
    foreach FieldInfo fieldInfo in cls.fields {
        if fieldInfo.isStatic && fieldInfo.isFinal && isSelfTypedField(fieldInfo, cls) {
            constantCount += 1;
            if constantCount >= 2 {
                return true;
            }
        }
    }
    return false;
}

function isSelfTypedField(FieldInfo fieldInfo, ClassInfo ownerClass) returns boolean {
    string typeName = fieldInfo.typeName;

    return typeName == ownerClass.className ||
            typeName == ownerClass.simpleName;
}

# Get descriptions for request fields from LLM (only for fields without descriptions)
#
# + fields - Request fields to get descriptions for
# + return - Fields with descriptions added
public function addRequestFieldDescriptions(RequestFieldInfo[] fields) returns RequestFieldInfo[]|error {
    if fields.length() == 0 {
        return fields;
    }

    RequestFieldInfo[] needsDescription = [];
    int[] needsDescriptionIndices = [];
    foreach int i in 0 ..< fields.length() {
        if fields[i].description is () || fields[i].description == "" {
            needsDescription.push(fields[i]);
            needsDescriptionIndices.push(i);
        }
    }

    if needsDescription.length() == 0 {
        return fields;
    }

    if !utils:isAIServiceInitialized() {
        return fields;
    }

    string fieldList = "";
    foreach int i in 0 ..< needsDescription.length() {
        RequestFieldInfo f = needsDescription[i];
        fieldList = fieldList + (i + 1).toString() + ". " + f.name + " (" + f.typeName + ")\n";
    }

    string systemPrompt = string `You are a Java SDK expert. Provide one-line descriptions for the given request fields.
        Each description should clearly explain what the field represents in user-friendly language.
        Return ONLY the descriptions, one per line, in the same order as the input fields.
        Do not include field names or numbers, just pure descriptions.`;

    string userPrompt = string `Provide one-line descriptions for these request fields:
        ${fieldList}
        Descriptions (one per line, in same order):`;

    string|error responseResult = utils:callAIAdvanced(userPrompt, systemPrompt, 5000);

    if responseResult is string {
        string responseText = responseResult.trim();
        if responseText != "" {
            string[] descriptions = regex:split(responseText, "\n");
            descriptions = descriptions.map(d => d.trim()).filter(d => d.length() > 0);

            RequestFieldInfo[] result = fields.clone();
            foreach int i in 0 ..< needsDescriptionIndices.length() {
                if i < descriptions.length() {
                    int fieldIndex = needsDescriptionIndices[i];
                    result[fieldIndex].description = descriptions[i];
                }
            }
            return result;
        }
    }

    return fields;
}
