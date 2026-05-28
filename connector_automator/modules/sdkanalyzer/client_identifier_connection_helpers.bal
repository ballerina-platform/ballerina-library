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
import ballerina/log;
import ballerina/os;
import wso2/connector_automator.utils;

# Check if a type name is a primitive or standard Java type
#
# + typeName - Type name to check
# + return - True if primitive or standard type, false otherwise
function isPrimitiveType(string typeName) returns boolean {
    string lower = typeName.toLowerAscii();
    return lower == "int" || lower == "long" || lower == "float" || lower == "double" ||
            lower == "boolean" || lower == "byte" || lower == "char" || lower == "short" ||
            lower == "string" || lower == "java.lang.string" || lower == "java.lang.object" ||
            lower == "void" || lower == "java.lang.integer" || lower == "java.lang.long" ||
            lower == "java.lang.boolean" || lower == "java.lang.double";
}

# Check if a type is a standard Java library type (java.*, javax.*) that doesn't need a typeReference.
#
# + typeName - Fully qualified type name to check
# + return - True if standard Java type, false otherwise
function isStandardJavaType(string typeName) returns boolean {
    return typeName.startsWith("java.") || typeName.startsWith("javax.");
}

# Find a class by name in the resolved classes, or lazily resolve from dependency JARs.
# If resolved from dependencies, the class is added to the resolvedClasses array for future lookups.
#
# + className - The class name to find
# + resolvedClasses - Mutable array of all resolved classes
# + dependencyJarPaths - Paths to dependency JARs for resolving external classes
# + return - The ClassInfo if found, otherwise ()
function findOrResolveClass(string className, ClassInfo[] resolvedClasses, string[] dependencyJarPaths) returns ClassInfo? {
    log:printDebug("Looking up class", className = className, resolvedCount = resolvedClasses.length(), depJarCount = dependencyJarPaths.length());
    string[] candidates = normalizeCandidateTypeNames(className);
    if candidates.length() == 0 {
        candidates.push(className);
    }

    // First try to find in already-resolved classes
    foreach string candidate in candidates {
        string[] lookupCandidates = buildLookupCandidates(candidate);
        foreach string lookupCandidate in lookupCandidates {
            if lookupCandidate == "" {
                continue;
            }

            ClassInfo? found = findClassByName(lookupCandidate, resolvedClasses);
            if found is ClassInfo {
                log:printDebug("Class found in resolved cache", className = found.className);
                return found;
            }
        }
    }

    // Try to resolve from dependency JARs
    if dependencyJarPaths.length() > 0 {
        log:printDebug("Class not in cache, searching dependency JARs", className = className, jarCount = dependencyJarPaths.length());
        foreach string candidate in candidates {
            string[] lookupCandidates = buildLookupCandidates(candidate);
            foreach string lookupCandidate in lookupCandidates {
                if lookupCandidate == "" {
                    continue;
                }

                ClassInfo? resolved = resolveClassFromJars(lookupCandidate, dependencyJarPaths);
                if resolved is ClassInfo {
                    // Add to resolved classes for future lookups
                    boolean alreadyResolved = false;
                    foreach ClassInfo cls in resolvedClasses {
                        if cls.className == resolved.className {
                            alreadyResolved = true;
                            break;
                        }
                    }

                    if !alreadyResolved {
                        resolvedClasses.push(resolved);
                    }

                    log:printInfo("Type resolved from external dependency JAR", className = resolved.className);
                    return resolved;
                }
            }
        }
    }

    log:printDebug("Class not found anywhere", className = className);
    return ();
}

function buildLookupCandidates(string rawTypeName) returns string[] {
    string[] out = [];
    string candidate = rawTypeName.trim();

    if candidate == "" {
        return out;
    }

    out.push(candidate);

    if candidate.startsWith("? extends ") {
        out.push(candidate.substring(10));
    } else if candidate.startsWith("? super ") {
        out.push(candidate.substring(8));
    }

    int? angleStart = candidate.indexOf("<");
    if angleStart is int && angleStart > 0 {
        out.push(candidate.substring(0, angleStart));
        string? genericType = extractGenericTypeParameter(candidate);
        if genericType is string {
            out.push(genericType);
        }
    }

    if candidate.endsWith("[]") && candidate.length() > 2 {
        out.push(candidate.substring(0, candidate.length() - 2));
    }

    string[] uniq = [];
    foreach string value in out {
        string cleaned = value.trim();
        if cleaned == "" || cleaned == "?" {
            continue;
        }
        boolean present = uniq.some(function(string x) returns boolean {
            return x == cleaned;
        });
        if !present {
            uniq.push(cleaned);
        }
    }

    return uniq;
}

# Extract enum constants from an enum class
#
# + enumClass - The enum ClassInfo
# + return - List of enum constants as RequestFieldInfo
function extractEnumConstants(ClassInfo enumClass) returns RequestFieldInfo[] {
    RequestFieldInfo[] constants = [];

    foreach FieldInfo fld in enumClass.fields {
        if fld.isStatic && fld.isFinal {
            if fld.name.startsWith("$") || fld.name == "UNKNOWN_TO_SDK_VERSION" {
                continue;
            }

            RequestFieldInfo constInfo = {
                name: fld.name,
                typeName: enumClass.simpleName,
                fullType: enumClass.className,
                isRequired: false
            };

            if fld.javadoc != () {
                constInfo.description = fld.javadoc;
            }

            constants.push(constInfo);
        }
    }

    return constants;
}

# Build a level 1 context string for a class, used for LLM enrichment of connection fields.
#
# + cls - The ClassInfo to analyze
# + return - A string describing the class category and key methods/fields for LLM context
function buildLevel1Context(ClassInfo cls) returns string {
    string category;
    if cls.isEnum {
        category = "Enum";
    } else if cls.isInterface {
        category = "Interface";
    } else if cls.isAbstract {
        category = "AbstractClass";
    } else {
        category = "Class";
    }

    if cls.isEnum {
        string[] constants = [];
        foreach FieldInfo fld in cls.fields {
            if fld.isStatic && fld.isFinal && !fld.name.startsWith("$") &&
                fld.name != "UNKNOWN_TO_SDK_VERSION" {
                constants.push(fld.name);
                if constants.length() >= 8 {
                    break;
                }
            }
        }
        if constants.length() > 0 {
            return category + " with values: " + string:'join(", ", ...constants);
        }
        return category;
    }

    string[] methodNames = [];
    string[] skipNames = [
        "toString",
        "hashCode",
        "equals",
        "getClass",
        "notify",
        "notifyAll",
        "wait",
        "clone",
        "finalize"
    ];
    foreach MethodInfo m in cls.methods {
        boolean skip = false;
        foreach string s in skipNames {
            if m.name == s {
                skip = true;
                break;
            }
        }
        if !skip {
            methodNames.push(m.name);
        }
        if methodNames.length() >= 10 {
            break;
        }
    }

    if methodNames.length() > 0 {
        return category + " with methods: " + string:'join(", ", ...methodNames);
    }
    return category;
}

# Check if SDK_VERBOSE environment variable is set to enable verbose logging for connection field enrichment.
# + return - True if verbose logging is enabled, false otherwise
function isSdkVerboseEnabled() returns boolean {
    string? envVal = os:getEnv("SDK_VERBOSE");
    if envVal is string {
        string lower = envVal.toLowerAscii();
        return lower == "1" || lower == "true" || lower == "yes";
    }
    return false;
}

# Helper function to print logs related to connection field enrichment, only if verbose logging is enabled.
#
# + message - The log message to print
function printConnectionEnrichLog(string message) {
    if isSdkVerboseEnabled() {
        io:println(string `  [connection-enrich] ${message}`);
    }
}

# Enrich connection fields using LLM to determine if they are required, adjust types, and add descriptions.
#
# + fields - The array of connection fields to enrich
# + sdkPackage - The SDK package name
# + clientSimpleName - The simple name of the client
# + return - The enriched connection fields and synthetic type metadata
function enrichConnectionFieldsWithLLM(
        ConnectionFieldInfo[] fields,
        string sdkPackage,
        string clientSimpleName
) returns [ConnectionFieldInfo[], SyntheticTypeMetadata[]] {

    SyntheticTypeMetadata[] syntheticMeta = [];

    if fields.length() == 0 {
        return [fields, syntheticMeta];
    }

    if !utils:isAIServiceInitialized() {
        printConnectionEnrichLog("LLM not configured — skipping enrichment");
        return [fields, syntheticMeta];
    }

    ConnectionFieldInfo[] llmCandidates = [];
    foreach ConnectionFieldInfo f in fields {
        string level1Context = "";
        if f.level1Context is string {
            level1Context = <string>f.level1Context;
        }
        boolean hasResolvedContext = level1Context.trim().length() > 0;
        boolean hasTypeRef = f.typeReference is string && (<string>f.typeReference).trim().length() > 0;
        boolean hasEnumRef = f.enumReference is string && (<string>f.enumReference).trim().length() > 0;

        if !hasResolvedContext && (hasTypeRef || hasEnumRef) {
            llmCandidates.push(f);
        }
    }

    if llmCandidates.length() == 0 {
        printConnectionEnrichLog("All connection fields resolved from classes/JARs — skipping LLM enrichment");
        return [fields, syntheticMeta];
    }

    string systemPrompt = getConnectionFieldEnrichmentSystemPrompt();
    string userPrompt = getConnectionFieldEnrichmentUserPrompt(sdkPackage, clientSimpleName, llmCandidates);

    printConnectionEnrichLog(string `Enriching ${llmCandidates.length()} unresolved connection fields via LLM...`);

    string|error responseResult = utils:callAIAdvanced(userPrompt, systemPrompt, 5000);
    if responseResult is error {
        printConnectionEnrichLog(string `LLM call failed: ${responseResult.message()} — using raw fields`);
        return [fields, syntheticMeta];
    }

    string responseText = responseResult.trim();
    if responseText.length() == 0 {
        printConnectionEnrichLog("Empty LLM response — using raw fields");
        return [fields, syntheticMeta];
    }

    // Strip markdown code fences
    string jsonText = responseText;
    if jsonText.startsWith("```json") {
        jsonText = jsonText.substring(7);
    } else if jsonText.startsWith("```") {
        jsonText = jsonText.substring(3);
    }
    if jsonText.endsWith("```") {
        jsonText = jsonText.substring(0, jsonText.length() - 3);
    }
    jsonText = jsonText.trim();

    // Extract outermost JSON array
    int? arrayStart = jsonText.indexOf("[");
    int? arrayEnd = jsonText.lastIndexOf("]");
    if arrayStart is int && arrayEnd is int && arrayEnd > arrayStart {
        jsonText = jsonText.substring(arrayStart, arrayEnd + 1);
    }

    json|error parsed = jsonText.fromJsonString();
    if parsed is error {
        printConnectionEnrichLog(string `JSON parse error: ${parsed.message()} — using raw fields`);
        return [fields, syntheticMeta];
    }

    if !(parsed is json[]) {
        printConnectionEnrichLog("LLM response was not a JSON array — using raw fields");
        return [fields, syntheticMeta];
    }

    json[] llmEntries = <json[]>parsed;

    map<map<json>> enrichmentMap = {};
    foreach json entry in llmEntries {
        if entry is map<json> {
            json nameVal = entry["name"];
            if nameVal is string {
                enrichmentMap[nameVal] = entry;
            }
        }
    }

    int enrichedCount = 0;
    ConnectionFieldInfo[] result = [];

    foreach ConnectionFieldInfo f in fields {
        string level1Context = "";
        if f.level1Context is string {
            level1Context = <string>f.level1Context;
        }
        boolean hasResolvedContext = level1Context.trim().length() > 0;
        boolean hasTypeRef = f.typeReference is string && (<string>f.typeReference).trim().length() > 0;
        boolean hasEnumRef = f.enumReference is string && (<string>f.enumReference).trim().length() > 0;
        boolean needsLlm = !hasResolvedContext && (hasTypeRef || hasEnumRef);

        if !needsLlm {
            result.push(f);
            continue;
        }

        map<json>? enrichment = enrichmentMap[f.name];

        if enrichment is () {
            result.push(f);
            continue;
        }

        map<json> e = enrichment;

        string? newDesc = f.description;
        json descVal = e["description"];
        if descVal is string && descVal.trim().length() > 0 {
            newDesc = descVal.trim();
        }

        boolean newRequired = f.isRequired;
        json reqVal = e["isRequired"];
        if reqVal is boolean {
            newRequired = reqVal;
        }

        string newTypeName = f.typeName;
        string? newEnumRef = f.enumReference;
        string? newTypeRef = f.typeReference;

        json btVal = e["ballerinaType"];
        string ballerinaType = "";
        if btVal is string {
            ballerinaType = btVal.trim().toLowerAscii();
        }

        if ballerinaType == "enum" {
            if newTypeRef is string {
                newEnumRef = newTypeRef;
                newTypeRef = ();
            }

        } else if ballerinaType == "string" || ballerinaType == "uri" {
            newTypeRef = ();
            newTypeName = "string";

        } else if ballerinaType == "int" {
            newTypeRef = ();
            newTypeName = "int";

        } else if ballerinaType == "boolean" {
            newTypeRef = ();
            newTypeName = "boolean";
        }

        if ballerinaType == "enum" && newEnumRef is string {
            string enumRefKey = <string>newEnumRef;
            string[] syntheticEnumValues = [];
            json enumValsJson = e["enumValues"];
            if enumValsJson is json[] {
                foreach json ev in enumValsJson {
                    if ev is string {
                        syntheticEnumValues.push(ev);
                    }
                }
            }
            SyntheticTypeMetadata stm = {
                fullType: enumRefKey,
                simpleName: f.typeName,
                ballerinaType: "enum",
                enumValues: syntheticEnumValues,
                subFields: []
            };
            boolean alreadyAdded = false;
            foreach SyntheticTypeMetadata existing in syntheticMeta {
                if existing.fullType == enumRefKey {
                    alreadyAdded = true;
                    break;
                }
            }
            if !alreadyAdded {
                syntheticMeta.push(stm);
            }

        } else if (ballerinaType == "record" || ballerinaType == "object") &&
                    newTypeRef is string {
            string typeRefKey = <string>newTypeRef;
            RequestFieldInfo[] syntheticSubFields = [];
            json subFieldsJson = e["subFields"];
            if subFieldsJson is json[] {
                foreach json sf in subFieldsJson {
                    if sf is map<json> {
                        json sfName = sf["name"];
                        json sfType = sf["type"];
                        json sfDesc = sf["description"];
                        json sfReq = sf["isRequired"];
                        if sfName is string && sfType is string {
                            RequestFieldInfo rfi = {
                                name: sfName,
                                typeName: sfType,
                                fullType: sfType,
                                isRequired: sfReq is boolean ? sfReq : false,
                                description: sfDesc is string ? sfDesc : ()
                            };
                            syntheticSubFields.push(rfi);
                        }
                    }
                }
            }
            SyntheticTypeMetadata stm = {
                fullType: typeRefKey,
                simpleName: f.typeName,
                ballerinaType: ballerinaType,
                enumValues: [],
                subFields: syntheticSubFields
            };
            boolean alreadyAdded = false;
            foreach SyntheticTypeMetadata existing in syntheticMeta {
                if existing.fullType == typeRefKey {
                    alreadyAdded = true;
                    break;
                }
            }
            if !alreadyAdded {
                syntheticMeta.push(stm);
            }
        }

        ConnectionFieldInfo enriched = {
            name: f.name,
            typeName: newTypeName,
            fullType: f.fullType,
            isRequired: newRequired,
            enumReference: newEnumRef,
            memberReference: f.memberReference,
            typeReference: newTypeRef,
            description: newDesc,
            level1Context: f.level1Context,
            interfaceImplementations: f.interfaceImplementations
        };

        result.push(enriched);
        enrichedCount += 1;
    }

    printConnectionEnrichLog(string `Enriched ${enrichedCount}/${llmCandidates.length()} unresolved fields; ` +
                string `${syntheticMeta.length()} synthetic type entries generated`);
    return [result, syntheticMeta];
}

# Build a context string summarising concrete implementations of an interface-typed field.
#
# + implClasses - Concrete (non-abstract, non-interface) implementing classes, up to 3
# + return - Multi-line context string, one line per implementation
function buildInterfaceImplementationsContext(ClassInfo[] implClasses) returns string {
    if implClasses.length() == 0 {
        return "";
    }
    string[] parts = [];
    parts.push(string `Interface with ${implClasses.length()} implementation(s):`);
    foreach ClassInfo impl in implClasses {
        string simpleName = extractSimpleTypeName(impl.className);
        string[] fieldDescs = [];
        foreach FieldInfo fld in impl.fields {
            if fld.isStatic || fld.name.startsWith("$") || fld.name.startsWith("_") {
                continue;
            }
            string fldSimple = extractSimpleTypeName(fld.typeName);
            fieldDescs.push(string `${fld.name}:${fldSimple}`);
            if fieldDescs.length() >= 5 {
                break;
            }
        }
        if fieldDescs.length() > 0 {
            parts.push(string `  ${simpleName}: [${string:'join(", ", ...fieldDescs)}]`);
        } else {
            // Fallback: constructor parameter names
            string[] ctorParams = [];
            foreach MethodInfo m in impl.methods {
                if m.name == "<init>" && m.parameters.length() > 0 {
                    foreach ParameterInfo p in m.parameters {
                        ctorParams.push(p.name);
                    }
                    break;
                }
            }
            if ctorParams.length() > 0 {
                parts.push(string `  ${simpleName}: [${string:'join(", ", ...ctorParams)}]`);
            } else {
                parts.push(string `  ${simpleName}`);
            }
        }
    }
    return string:'join("\n", ...parts);
}
