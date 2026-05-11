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
import ballerina/regex;
import wso2/connector_automator.utils;

# Use Anthropic LLM to find root client class using weighted scoring
#
# + classes - All classes from SDK
# + maxCandidates - Maximum number of candidates to consider
# + roleHint - Optional target role hint (admin/producer/consumer)
# + return - Sorted candidates with LLM scores
public function identifyClientClassWithLLM(ClassInfo[] classes, int maxCandidates, string? roleHint = ())
        returns [ClassInfo, LLMClientScore][]|AnalyzerError {

    if !utils:isAIServiceInitialized() {
        return error AnalyzerError("Anthropic LLM not configured: LLM-only candidate scoring required");
    }

    // Filter potential candidates using conservative structural rules
    ClassInfo[] potential = [];
    foreach ClassInfo cls in classes {
        if shouldConsiderAsClientCandidate(cls) {
            potential.push(cls);
        }
    }
    if potential.length() > 0 {
        ClassInfo[] prioritized = from ClassInfo c in potential
            order by quickClientCandidatePriority(c) descending
            select c;

        int candidateLimit = maxCandidates * 2;
        if candidateLimit < 12 {
            candidateLimit = 12;
        }
        if candidateLimit > 30 {
            candidateLimit = 30;
        }

        if prioritized.length() > candidateLimit {
            potential = prioritized.slice(0, candidateLimit);
        } else {
            potential = prioritized;
        }
    }

    if potential.length() == 0 {
        // Structural filtering produced no candidates.
        // Fall back to a looser selection.
        ClassInfo[] fallback = [];
        foreach ClassInfo cls in classes {
            if !cls.className.includes("$") && !cls.isEnum && !cls.isAbstract && cls.methods.length() > 0 {
                fallback.push(cls);
            }
        }
        if fallback.length() == 0 {
            return error AnalyzerError("No potential client candidates after structural filtering");
        }
        // Sort fallback by method count descending and take a reasonable sample
        ClassInfo[] sortedFallback = from var c in fallback
            order by c.methods.length() descending
            select c;
        int sampleCount = sortedFallback.length() > 10 ? 10 : sortedFallback.length();
        potential = sortedFallback.slice(0, sampleCount);
    }

    [ClassInfo, LLMClientScore][] scored = [];

    // Score each potential candidate using the LLM exclusively. Propagate or log failures per-class.
    foreach ClassInfo cls in potential {
        LLMClientScore|error score = calculateLLMClientScore(cls, classes, roleHint);
        if score is LLMClientScore {
            scored.push([cls, score]);
        } else {
            error e = <error>score;
            io:println(string `LLM scoring failed for ${cls.className}: ${e.message()}`);
        }
    }

    if scored.length() == 0 {
        return error AnalyzerError("LLM failed to score any client candidates");
    }

    // Sort by LLM total score descending
    [ClassInfo, LLMClientScore][] sorted = from var [cls, score] in scored
        order by score.totalScore descending
        select [cls, score];

    int finalCount = sorted.length() < maxCandidates ? sorted.length() : maxCandidates;
    return sorted.slice(0, finalCount);
}

public function detectClientInitPatternWithLLM(
        ClassInfo rootClient,
        ClassInfo[] allClasses,
        string[] dependencyJarPaths
) returns ClientInitPattern|error {
    if !utils:isAIServiceInitialized() {
        return error("Anthropic LLM not configured: cannot detect init pattern using LLM");
    }

    ClientInitPattern|error patternResult = detectInitPatternWithLLM(rootClient, allClasses, dependencyJarPaths);
    if patternResult is error {
        return patternResult;
    }
    ClientInitPattern pattern = patternResult;

    if pattern.patternName == "builder" || pattern.patternName == "static-factory" ||
        pattern.patternName == "constructor" {
        [string?, ConnectionFieldInfo[], SyntheticTypeMetadata[]] builderResult =
            resolveBuilderConnectionFields(
                rootClient, allClasses, dependencyJarPaths,
                rootClient.packageName, rootClient.simpleName
            );
        pattern.builderClass = builderResult[0];
        pattern.connectionFields = builderResult[1];
        pattern.syntheticTypeMetadata = builderResult[2];
    }

    return pattern;
}

# Extract all public methods from root client class
#
# Extract all public methods from the root client class.
# When the root client exposes very few direct methods but delegates operations to a
# related sub-client class (e.g., via a resource accessor returning an inner class),
# this function traverses one level of delegation to collect the actual API operations.
#
# + rootClient - The root client class
# + allClasses - All available classes, used for delegate traversal (pass [] to skip)
# + return - All public methods with metadata
public function extractPublicMethods(ClassInfo rootClient, ClassInfo[] allClasses) returns MethodInfo[] {
    MethodInfo[] publicMethods = [];

    foreach MethodInfo method in rootClient.methods {
        // Skip constructor methods and private methods
        if !method.name.startsWith("<") && method.name != "toString" &&
            method.name != "hashCode" && method.name != "equals" {
            string methodNameLower = method.name.toLowerAscii();
            if methodNameLower.endsWith("paginator") {
                continue;
            }
            publicMethods.push(method);
        }
    }

    // Delegate traversal: when the root client exposes few direct methods but delegates to
    // related inner/sub-resource classes, collect methods from those classes recursively.
    // This handles SDK structures like:
    //   - AWS:    S3Client → operations directly on root
    //   - Google: Forms → FormsOperations → Responses/Watches → get/list/create...
    // The traversal recurses through classes that are related (same package or inner classes
    // of the root client) and only returns "leaf" methods — methods whose return types are
    // NOT themselves sub-resource accessor classes within the same family.
    if publicMethods.length() <= 5 && allClasses.length() > 0 {
        map<boolean> visitedClasses = {};
        visitedClasses[rootClient.className] = true;
        map<boolean> addedMethodKeys = {};

        // Seed the queue with return types of the root client's methods
        string[] classQueue = [];
        foreach MethodInfo method in publicMethods {
            string returnType = method.returnType;
            if returnType == "void" || isSimpleType(returnType) {
                continue;
            }
            if !visitedClasses.hasKey(returnType) {
                classQueue.push(returnType);
            }
        }

        MethodInfo[] delegateMethods = [];
        int qi = 0;
        // Limit traversal depth to avoid runaway expansion
        int maxTraversals = 50;
        int traversals = 0;

        while qi < classQueue.length() && traversals < maxTraversals {
            string currentType = classQueue[qi];
            qi += 1;
            if visitedClasses.hasKey(currentType) {
                continue;
            }
            visitedClasses[currentType] = true;
            traversals += 1;

            ClassInfo? delegateClass = findClassByName(currentType, allClasses);
            if delegateClass is () || delegateClass.className == rootClient.className {
                continue;
            }
            // Only traverse closely related classes (same package or inner class of root)
            boolean isRelated =
                delegateClass.packageName == rootClient.packageName ||
                delegateClass.className.startsWith(rootClient.className + "$");
            if !isRelated {
                continue;
            }

            foreach MethodInfo dm in delegateClass.methods {
                if dm.name.startsWith("<") || dm.isStatic ||
                    dm.name == "toString" || dm.name == "hashCode" ||
                    dm.name == "equals" || dm.name == "set" || dm.name == "clone" {
                    continue;
                }
                // If the method returns another related inner class, it's a sub-resource
                // accessor — enqueue it for further traversal rather than surfacing it
                // as a leaf operation.
                string dmReturnType = dm.returnType;
                ClassInfo? retClass = findClassByName(dmReturnType, allClasses);
                boolean isSubResourceAccessor = false;
                if retClass is ClassInfo {
                    boolean retIsRelated =
                        retClass.packageName == rootClient.packageName ||
                        retClass.className.startsWith(rootClient.className + "$");
                    // A sub-resource accessor returns a class that itself has non-trivial
                    // methods and takes no parameters (or just a parent reference).
                    if retIsRelated && dm.parameters.length() == 0 && retClass.methods.length() > 1 {
                        isSubResourceAccessor = true;
                        if !visitedClasses.hasKey(dmReturnType) {
                            classQueue.push(dmReturnType);
                        }
                    }
                }
                if isSubResourceAccessor {
                    continue;
                }

                // Build a unique key using name + parameter types + return type to distinguish
                // methods from different delegate classes. Without the return type, operations
                // like responses.list(String)->ListFormResponsesResponse and
                // watches.list(String)->ListWatchesResponse would collide.
                string paramSig = "";
                foreach ParameterInfo p in dm.parameters {
                    paramSig += "|" + p.typeName;
                }
                string methodKey = dm.name + paramSig + "->" + dm.returnType;
                if addedMethodKeys.hasKey(methodKey) {
                    continue;
                }
                addedMethodKeys[methodKey] = true;
                delegateMethods.push(dm);
            }
        }

        // Infer meaningful parameter names for delegate methods whose parameters have
        // generic names (e.g., "string", "arg0"). Many SDKs store path/query parameters as
        // private instance fields in the operation class returned by the method.  When the
        // return type is a known inner class, extract its non-static instance field names
        // that match the parameter types and count, then apply them.
        foreach MethodInfo dm in delegateMethods {
            boolean needsRename = false;
            foreach ParameterInfo p in dm.parameters {
                string pNameLower = p.name.toLowerAscii();
                // Check if parameter name is just a type name or a numbered arg
                if pNameLower == extractSimpleTypeName(p.typeName).toLowerAscii() ||
                    pNameLower.startsWith("arg") {
                    needsRename = true;
                    break;
                }
            }
            if needsRename && dm.parameters.length() > 0 {
                ClassInfo? opClass = findClassByName(dm.returnType, allClasses);
                if opClass is ClassInfo {
                    // Collect non-static instance fields from the operation class.
                    // The first N fields that type-match the method parameters (positionally)
                    // are assumed to be the path/required parameters.
                    FieldInfo[] instanceFields = [];
                    foreach FieldInfo fld in opClass.fields {
                        if fld.isStatic {
                            continue;
                        }
                        instanceFields.push(fld);
                    }
                    // Match positionally: for each method parameter, pick the next instance
                    // field whose type matches. This handles cases where the operation class
                    // has more fields than the method has parameters.
                    ParameterInfo[] renamedParams = [];
                    int fi = 0;
                    boolean allMatched = true;
                    foreach ParameterInfo p in dm.parameters {
                        boolean matched = false;
                        while fi < instanceFields.length() {
                            FieldInfo candidate = instanceFields[fi];
                            fi += 1;
                            string paramSimple = extractSimpleTypeName(p.typeName).toLowerAscii();
                            string fieldSimple = extractSimpleTypeName(candidate.typeName).toLowerAscii();
                            if paramSimple == fieldSimple {
                                renamedParams.push({
                                    name: candidate.name,
                                    typeName: p.typeName,
                                    requestFields: p.requestFields
                                });
                                matched = true;
                                break;
                            }
                        }
                        if !matched {
                            allMatched = false;
                            break;
                        }
                    }
                    if allMatched && renamedParams.length() == dm.parameters.length() {
                        dm.parameters = renamedParams;
                    } else if renamedParams.length() > 0 {
                        // Partial match: rename only the parameters we successfully matched,
                        // keeping original names for the rest.
                        ParameterInfo[] merged = [];
                        int ri = 0;
                        foreach ParameterInfo p in dm.parameters {
                            if ri < renamedParams.length() {
                                merged.push(renamedParams[ri]);
                                ri += 1;
                            } else {
                                merged.push(p);
                            }
                        }
                        dm.parameters = merged;
                    }
                }
            }
            publicMethods.push(dm);
        }

        // Remove the original accessor-only methods from publicMethods if their return
        // type was traversed as a sub-resource (they are just navigation, not operations).
        MethodInfo[] filtered = [];
        foreach MethodInfo m in publicMethods {
            if m.parameters.length() == 0 && visitedClasses.hasKey(m.returnType) &&
                m.returnType != rootClient.className {
                continue; // skip sub-resource accessor
            }
            filtered.push(m);
        }
        publicMethods = filtered;
    }

    return publicMethods;
}

# Use LLM to rank methods by usage frequency  
#
# + methods - All public methods from root client
# + return - Methods ranked by usage frequency (limited to 40 if more)
public function rankMethodsByUsageWithLLM(MethodInfo[] methods) returns MethodInfo[]|error {

    // If 40 or fewer methods, return all without LLM ranking
    if methods.length() <= 40 {
        return methods;
    }

    // If more than 40 methods, use LLM to rank and extract top 40
    if !utils:isAIServiceInitialized() {
        return error("Anthropic LLM not configured: cannot rank methods using LLM");
    }

    // Use LLM to rank methods by usage frequency and return top 40
    return rankMethodsUsingLLM(methods);
}

# Extract request/response parameters and corresponding fields with types
#
# + methods - Methods to analyze for parameters
# + allClasses - All classes for type lookup
# + return - Enhanced methods with parameter field information
public function extractParameterFieldTypes(MethodInfo[] methods, ClassInfo[] allClasses)
        returns MethodInfo[] {

    // Deduplicate overloads preferring variants that resolve to a Request class.
    // Use a compound key (name + parameter count + return type) so that methods from
    // different delegate sub-resources are treated as distinct operations even when
    // they share the same name and arity (e.g., responses.list(String) vs watches.list(String)).
    map<MethodInfo> chosen = {};
    foreach MethodInfo method in methods {
        boolean hasRequestParam = false;
        foreach ParameterInfo p in method.parameters {
            ClassInfo? resolved = resolveRequestClassFromParameter(p, allClasses, method.name);
            if resolved is ClassInfo {
                hasRequestParam = true;
                break;
            }
        }

        string dedupeKey = method.name + "#" + method.parameters.length().toString() + "#" + method.returnType;
        if !chosen.hasKey(dedupeKey) {
            chosen[dedupeKey] = method;
        } else {
            MethodInfo? existing = chosen[dedupeKey];
            if existing is MethodInfo {
                boolean existingHasRequest = false;
                foreach ParameterInfo p in existing.parameters {
                    ClassInfo? r = resolveRequestClassFromParameter(p, allClasses, existing.name);
                    if r is ClassInfo {
                        existingHasRequest = true;
                        break;
                    }
                }
                if !existingHasRequest && hasRequestParam {
                    chosen[dedupeKey] = method;
                } else if existingHasRequest && hasRequestParam {
                    boolean existingDirect = false;
                    boolean currentDirect = false;
                    foreach ParameterInfo p in existing.parameters {
                        if p.typeName != "" && (p.typeName.endsWith("Request") || p.typeName.indexOf("Request") != -1) {
                            existingDirect = true;
                            break;
                        }
                    }
                    foreach ParameterInfo p in method.parameters {
                        if p.typeName != "" && (p.typeName.endsWith("Request") || p.typeName.indexOf("Request") != -1) {
                            currentDirect = true;
                            break;
                        }
                    }
                    if currentDirect && !existingDirect {
                        chosen[dedupeKey] = method;
                    }
                }
            }
        }
    }

    // Reconstruct ordered list preserving first-seen order of original methods
    MethodInfo[] enhancedMethodsOrdered = [];
    map<boolean> added = {};
    foreach MethodInfo m in methods {
        string mKey = m.name + "#" + m.parameters.length().toString() + "#" + m.returnType;
        if !added.hasKey(mKey) {
            MethodInfo? selOpt = chosen[mKey];
            if selOpt is MethodInfo {
                MethodInfo sel = selOpt;
                MethodInfo enhancedMethod = {
                    name: sel.name,
                    returnType: sel.returnType,
                    parameters: extractEnhancedParameters(sel.parameters, allClasses, sel.name),
                    isStatic: sel.isStatic,
                    isFinal: sel.isFinal,
                    isAbstract: sel.isAbstract,
                    isDeprecated: sel.isDeprecated,
                    annotations: sel.annotations,
                    exceptions: sel.exceptions,
                    typeParameters: sel.typeParameters,
                    signature: sel.signature
                };
                enhancedMethodsOrdered.push(enhancedMethod);
                added[mKey] = true;
            }
        }
    }

    return enhancedMethodsOrdered;
}

# Generate structured metadata with all information
#
# + rootClient - The identified root client
# + initPattern - The initialization pattern
# + rankedMethods - Methods ranked by usage
# + allClasses - All classes for context
# + dependencyJarPaths - Dependency JAR paths for resolving external type references
# + config - Analyzer configuration
# + return - Complete structured metadata
public function generateStructuredMetadata(
        ClassInfo rootClient,
        ClientInitPattern initPattern,
        MethodInfo[] rankedMethods,
        ClassInfo[] allClasses,
        string[] dependencyJarPaths,
        AnalyzerConfig config
) returns StructuredSDKMetadata {

    // Track enums globally to avoid duplication
    map<EnumMetadata> enumCache = {};

    // Track member classes referenced in List/Map types
    map<ClassInfo> memberClassCache = {};

    // Step 1: Collect all parameter instances (method::param) and their fields
    map<RequestFieldInfo[]> paramInstanceFieldsMap = {};

    foreach MethodInfo method in rankedMethods {
        foreach ParameterInfo param in method.parameters {
            ClassInfo? requestClass = resolveRequestClassFromParameter(param, allClasses, method.name);
            if requestClass is ClassInfo {
                string instanceKey = string `${method.name}::${param.name}`;
                // Extract fields for this parameter instance (no deduplication to respect per-parameter context)
                RequestFieldInfo[] fields = extractRequestFields(requestClass);
                paramInstanceFieldsMap[instanceKey] = fields;
            }
        }
    }

    // Step 2: Batch analyze all parameter instances with LLM
    map<string[]> requiredFieldsMap = {};

    if !config.disableLLM && paramInstanceFieldsMap.length() > 0 {
        string batchPrompt = "";
        foreach [string, RequestFieldInfo[]] [instanceKey, fields] in paramInstanceFieldsMap.entries() {
            if batchPrompt.length() > 0 {
                batchPrompt += "\n\n";
            }
            batchPrompt += string `${instanceKey}:\n`;
            foreach RequestFieldInfo fld in fields {
                batchPrompt += string `  - ${fld.name}\n`;
            }
        }

        if utils:isAIServiceInitialized() {
            string sysPrompt = "You are an expert Java SDK analyzer. Based on your knowledge of SDK design patterns, " +
                "identify which fields are REQUIRED for each parameter instance. " +
                "Return ONLY valid JSON: {\"Method::ParamName\":[\"requiredField1\",\"requiredField2\"]}";

            string userPrompt = string `Identify REQUIRED fields for these method parameters:\n\n${batchPrompt}\n\nReturn JSON: {"Method::ParamName":["field1","field2"]}`;

            string|error llmResponseResult = utils:callAIAdvanced(userPrompt, sysPrompt, 5000);

            if llmResponseResult is string {
                string jsonText = llmResponseResult.trim();

                // Extract JSON from markdown code blocks or find JSON object
                int? jsonStartIdx = jsonText.indexOf("```json");
                if jsonStartIdx is int {
                    jsonText = jsonText.substring(jsonStartIdx + 7);
                }
                int? codeBlockIdx = jsonText.indexOf("```");
                if codeBlockIdx is int {
                    jsonText = jsonText.substring(0, codeBlockIdx);
                }

                // Find the first { and last }
                int? firstBrace = jsonText.indexOf("{");
                int? lastBrace = jsonText.lastIndexOf("}");
                if firstBrace is int && lastBrace is int && lastBrace > firstBrace {
                    jsonText = jsonText.substring(firstBrace, lastBrace + 1);
                }

                jsonText = jsonText.trim();

                json|error parsedJson = jsonText.fromJsonString();
                if parsedJson is map<json> {
                    foreach [string, json] [instanceKey, fieldData] in parsedJson.entries() {
                        if fieldData is json[] {
                            string[] reqFields = [];
                            foreach json item in fieldData {
                                if item is string {
                                    reqFields.push(item);
                                }
                            }
                            requiredFieldsMap[instanceKey] = reqFields;
                        }
                    }
                }
            }
        }
    }

    // Step 2b: Determine required connection fields via LLM.
    // Connection fields default to isRequired=false during builder traversal.
    // Here we send all connection field names+types to the LLM in the same way
    // request parameter fields are analyzed, so the spec accurately reflects
    // which fields must be supplied for a basic client connection.
    ConnectionFieldInfo[] updatedConnFields = initPattern.connectionFields;
    map<map<boolean>> requiredConnMemberFieldsByClass = {};
    if !config.disableLLM && initPattern.connectionFields.length() > 0 {
        string connFieldList = "";
        map<string> connFieldToMemberRef = {};
        foreach ConnectionFieldInfo cf in initPattern.connectionFields {
            connFieldList += string `  - ${cf.name}: ${cf.typeName}\n`;
            if cf.memberReference is string {
                string memberRef = <string>cf.memberReference;
                connFieldToMemberRef[cf.name] = memberRef;

                ClassInfo? memberClass = findClassByName(memberRef, allClasses);
                if memberClass is () {
                    memberClass = resolveClassFromJars(memberRef, dependencyJarPaths);
                }
                if memberClass is ClassInfo {
                    RequestFieldInfo[] memberFields = extractClassAndAncestorFields(
                        memberClass,
                        allClasses,
                        dependencyJarPaths
                    );
                    map<boolean> seenMemberNames = {};
                    foreach RequestFieldInfo mf in memberFields {
                        if seenMemberNames.hasKey(mf.name) {
                            continue;
                        }
                        seenMemberNames[mf.name] = true;
                        connFieldList += string `  - ${cf.name}.${mf.name}: ${mf.typeName}\n`;
                    }
                }
            }
        }
        if utils:isAIServiceInitialized() {
            string sysPr2b = "You are an expert Java SDK analyzer. " +
                "Identify which CONNECTION/CONFIGURATION fields are REQUIRED for a basic connection. " +
                "Return ONLY valid JSON array of required field names: [\"field1\",\"field2\",\"field.member\"]";
            string usrPr2b = string `For the client type '${initPattern.builderClass ?: "unknown"}',` +
                string ` identify which of these connection configuration fields are REQUIRED. ` +
                string `For member-reference entries, use dotted names like field.memberField:\n\n${connFieldList}\nReturn JSON array.`;
            string|error llmResp2bResult = utils:callAIAdvanced(usrPr2b, sysPr2b, 5000);
            if llmResp2bResult is string {
                string respTxt2b = llmResp2bResult;
                string jTxt2b = respTxt2b.trim();
                int? arrStart = jTxt2b.indexOf("[");
                int? arrEnd = jTxt2b.lastIndexOf("]");
                if arrStart is int && arrEnd is int && arrEnd > arrStart {
                    jTxt2b = jTxt2b.substring(arrStart, arrEnd + 1);
                }
                json|error parsedArr = jTxt2b.fromJsonString();
                if parsedArr is json[] {
                    map<boolean> requiredConnFields = {};
                    foreach json item in parsedArr {
                        if item is string {
                            string requiredName = item.trim();
                            int? dotIdx = requiredName.indexOf(".");
                            if dotIdx is int && dotIdx > 0 && dotIdx < requiredName.length() - 1 {
                                string connFieldName = requiredName.substring(0, dotIdx);
                                string memberFieldName = requiredName.substring(dotIdx + 1);
                                string? memberRefOpt = connFieldToMemberRef[connFieldName];
                                if memberRefOpt is string {
                                    map<boolean> requiredMembers = {};
                                    if requiredConnMemberFieldsByClass.hasKey(memberRefOpt) {
                                        requiredMembers = requiredConnMemberFieldsByClass.get(memberRefOpt);
                                    }
                                    requiredMembers[memberFieldName] = true;
                                    requiredConnMemberFieldsByClass[memberRefOpt] = requiredMembers;
                                    requiredConnFields[connFieldName] = true;
                                    continue;
                                }
                            }
                            requiredConnFields[requiredName] = true;
                        }
                    }
                    ConnectionFieldInfo[] rebuilt = [];
                    foreach ConnectionFieldInfo cf in initPattern.connectionFields {
                        ConnectionFieldInfo updated = cf;
                        if requiredConnFields.hasKey(cf.name) {
                            updated = {
                                name: cf.name,
                                typeName: cf.typeName,
                                fullType: cf.fullType,
                                isRequired: true,
                                enumReference: cf.enumReference,
                                memberReference: cf.memberReference,
                                typeReference: cf.typeReference,
                                description: cf.description,
                                level1Context: cf.level1Context,
                                interfaceImplementations: cf.interfaceImplementations
                            };
                        }
                        rebuilt.push(updated);
                    }
                    updatedConnFields = rebuilt;
                }
            }
        }
    }

    // Step 3: Populate request fields using cached results
    MethodInfo[] methodsWithRequestFields = [];
    foreach int methodIdx in 0 ..< rankedMethods.length() {
        MethodInfo method = rankedMethods[methodIdx];
        MethodInfo updatedMethod = method;

        // Update each parameter with request fields if it's a request object
        ParameterInfo[] updatedParams = [];
        foreach int paramIdx in 0 ..< method.parameters.length() {
            ParameterInfo param = method.parameters[paramIdx];
            ParameterInfo updatedParam = param;

            // Try to resolve the request class via generics, builders, or method-name heuristics
            ClassInfo? requestClass = resolveRequestClassFromParameter(param, allClasses, method.name);
            if requestClass is ClassInfo {
                // Replace the parameter's exposed type with the resolved Request class
                updatedParam.typeName = requestClass.className;

                // Extract request fields
                RequestFieldInfo[] fields = extractRequestFields(requestClass);
                string paramKey = string `${method.name}::${param.name}`;

                // Apply cached LLM results
                string[] requiredFields = [];
                if requiredFieldsMap.hasKey(paramKey) {
                    string[]? reqFieldsVal = requiredFieldsMap.get(paramKey);
                    if reqFieldsVal is string[] {
                        requiredFields = reqFieldsVal;
                    }
                }

                RequestFieldInfo[] updatedFields = [];
                foreach RequestFieldInfo fld in fields {
                    RequestFieldInfo updated = fld;
                    // Check if this field is in the required list
                    boolean isReq = false;
                    foreach string reqField in requiredFields {
                        if fld.name == reqField {
                            isReq = true;
                            break;
                        }
                    }
                    updated.isRequired = isReq;
                    updatedFields.push(updated);
                }
                fields = updatedFields;

                RequestFieldInfo[] enhancedFields = [];

                foreach RequestFieldInfo fieldInfo in fields {
                    // Filter redundant AsString fields (e.g., aclAsString when acl exists)
                    if isRedundantAsStringField(fieldInfo.name, fields) {
                        continue;
                    }

                    RequestFieldInfo enhancedField = fieldInfo;

                    // Check if field type is an enum and extract enum values
                    ClassInfo? enumClass = findClassByName(fieldInfo.fullType, allClasses);
                    if enumClass is ClassInfo && enumClass.isEnum {
                        // Check if already cached
                        if !enumCache.hasKey(fieldInfo.fullType) {
                            // Extract enum metadata
                            EnumMetadata enumMeta = extractEnumMetadata(enumClass);
                            enumCache[fieldInfo.fullType] = enumMeta;
                        }
                        // Set enum reference
                        enhancedField.enumReference = fieldInfo.fullType;
                    }

                    // Check if field type is a collection (List, Set, Map, etc.) and extract memberReference
                    if isCollectionType(fieldInfo.typeName) {
                        string? genericParam = extractGenericTypeParameter(fieldInfo.fullType);
                        if genericParam is string && genericParam.length() > 0 {
                            // Verify the generic parameter class exists
                            ClassInfo? memberClass = findClassByName(genericParam, allClasses);
                            if memberClass is ClassInfo {
                                enhancedField.memberReference = genericParam;
                                // Cache the member class for extraction
                                if !memberClassCache.hasKey(genericParam) {
                                    memberClassCache[genericParam] = memberClass;
                                }
                            }
                        }
                    } else if !isPrimitiveType(fieldInfo.fullType) && !isStandardJavaType(fieldInfo.fullType)
                        && enhancedField.enumReference is () {
                        // Non-primitive, non-collection, non-enum complex type — cache for member extraction
                        ClassInfo? complexClass = findClassByName(fieldInfo.fullType, allClasses);
                        if complexClass is ClassInfo {
                            enhancedField.memberReference = fieldInfo.fullType;
                            if !memberClassCache.hasKey(fieldInfo.fullType) {
                                memberClassCache[fieldInfo.fullType] = complexClass;
                            }
                        }
                    }

                    enhancedFields.push(enhancedField);
                }

                updatedParam.requestFields = enhancedFields;

                // If the parameter name is generic (e.g., 'consumer'), replace it with a sensible name
                if param.name.toLowerAscii().indexOf("consumer") != -1 || param.name.startsWith("arg") {
                    string simple = requestClass.simpleName;
                    if simple.length() > 0 {
                        string newName = simple.substring(0, 1).toLowerAscii() + simple.substring(1);
                        updatedParam.name = newName;
                    }
                }
            }

            updatedParams.push(updatedParam);
        }

        updatedMethod.parameters = updatedParams;

        // Populate returnFields for methods whose return type is a non-simple class
        RequestFieldInfo[] returnFields = [];
        if updatedMethod.returnType != "void" && !isSimpleType(updatedMethod.returnType) {
            ClassInfo? retCls = findClassByName(updatedMethod.returnType, allClasses);

            // If the return class extends a generic base (e.g., FormsRequest<Form>),
            // resolve the actual model type from the generic type parameter and use it.
            // This handles operation-wrapper classes that are not the data model themselves
            // but carry the model type as a generic parameter of their superclass.
            if retCls is ClassInfo && retCls.genericSuperClass.length() > 0 {
                string? genParam = extractGenericTypeParameter(retCls.genericSuperClass);
                if genParam is string && genParam.length() > 0 {
                    ClassInfo? modelCls = findClassByName(genParam, allClasses);
                    if modelCls is ClassInfo {
                        retCls = modelCls;
                        updatedMethod.returnType = modelCls.className;
                    }
                }
            }

            if retCls is ClassInfo {
                RequestFieldInfo[] rawReturnFields = extractResponseFields(retCls);

                // For any enum fields in the response, cache enum metadata and set enumReference
                // Also set memberReference for collection types
                RequestFieldInfo[] enhancedReturnFields = [];
                foreach RequestFieldInfo rf in rawReturnFields {
                    // Filter redundant AsString fields
                    if isRedundantAsStringField(rf.name, rawReturnFields) {
                        continue;
                    }

                    RequestFieldInfo enhancedRf = rf;
                    ClassInfo? enumClass = findClassByName(rf.fullType, allClasses);
                    if enumClass is ClassInfo && enumClass.isEnum {
                        if !enumCache.hasKey(rf.fullType) {
                            EnumMetadata enumMeta = extractEnumMetadata(enumClass);
                            enumCache[rf.fullType] = enumMeta;
                        }
                        enhancedRf.enumReference = rf.fullType;
                    }

                    // Check if field type is a collection (List, Set, Map, etc.) and extract memberReference
                    if isCollectionType(rf.typeName) {
                        string? genericParam = extractGenericTypeParameter(rf.fullType);
                        if genericParam is string && genericParam.length() > 0 {
                            // Verify the generic parameter class exists
                            ClassInfo? memberClass = findClassByName(genericParam, allClasses);
                            if memberClass is ClassInfo {
                                enhancedRf.memberReference = genericParam;
                                // Cache the member class for extraction
                                if !memberClassCache.hasKey(genericParam) {
                                    memberClassCache[genericParam] = memberClass;
                                }
                            }
                        }
                    } else if !isPrimitiveType(rf.fullType) && !isStandardJavaType(rf.fullType)
                        && enhancedRf.enumReference is () {
                        // Non-primitive, non-collection, non-enum complex type — cache for member extraction
                        ClassInfo? complexClass = findClassByName(rf.fullType, allClasses);
                        if complexClass is ClassInfo {
                            enhancedRf.memberReference = rf.fullType;
                            if !memberClassCache.hasKey(rf.fullType) {
                                memberClassCache[rf.fullType] = complexClass;
                            }
                        }
                    }

                    enhancedReturnFields.push(enhancedRf);
                }
                returnFields = enhancedReturnFields;
            }
        }

        updatedMethod.returnFields = returnFields;
        methodsWithRequestFields.push(updatedMethod);
    }

    // resolve from allClasses
    foreach ConnectionFieldInfo connField in initPattern.connectionFields {
        if connField.enumReference is string {
            string enumRef = <string>connField.enumReference;
            if !enumCache.hasKey(enumRef) {
                ClassInfo? enumClass = findClassByName(enumRef, allClasses);
                if enumClass is () {
                    enumClass = resolveClassFromJars(enumRef, dependencyJarPaths);
                }
                // Accept both Java enums and constant-holder classes (non-enum classes
                // whose public static final fields are of their own type, e.g. Region).
                if enumClass is ClassInfo && (enumClass.isEnum || hasEnumLikeConstants(enumClass)) {
                    enumCache[enumRef] = extractEnumMetadata(enumClass);
                }
            }
        }
        if connField.memberReference is string {
            string memberRef = <string>connField.memberReference;
            if !memberClassCache.hasKey(memberRef) {
                ClassInfo? memberClass = findClassByName(memberRef, allClasses);
                if memberClass is () {
                    memberClass = resolveClassFromJars(memberRef, dependencyJarPaths);
                }
                if memberClass is ClassInfo {
                    memberClassCache[memberRef] = memberClass;
                }
            }
        }
        if connField.typeReference is string {
            string typeRef = <string>connField.typeReference;
            ClassInfo? typeClass = findClassByName(typeRef, allClasses);
            if typeClass is () {
                typeClass = resolveClassFromJars(typeRef, dependencyJarPaths);
            }

            if typeClass is ClassInfo {
                // Accept both Java enums and constant-holder classes.
                if typeClass.isEnum || hasEnumLikeConstants(typeClass) {
                    if !enumCache.hasKey(typeRef) {
                        enumCache[typeRef] = extractEnumMetadata(typeClass);
                    }
                } else if !memberClassCache.hasKey(typeRef) {
                    memberClassCache[typeRef] = typeClass;
                }
            }
        }
    }

    // Discover concrete implementations of interface-/abstract-typed connection fields.
    // When a field's type is an interface or abstract class, the user may supply any
    // conforming implementation.  We scan allClasses AND dep JARs for concrete classes
    // that implement or extend that type, then add them to memberClassCache so the
    // spec generator can expose their fields as documentation.
    // This is entirely generic: no SDK-specific knowledge is encoded here.
    map<boolean> discoveredInterfaces = {}; // deduplicate per unique interface type (keyed by fullType)
    foreach ConnectionFieldInfo connField in initPattern.connectionFields {
        // Handle fields where concrete implementations were pre-discovered during builder traversal.
        // These fields have typeReference intentionally cleared (so the empty interface class does
        // not pollute memberClassCache), so they MUST be checked BEFORE the typeRef nil-guard below.
        if connField.interfaceImplementations.length() > 0 {
            string implKey = connField.fullType;
            if !discoveredInterfaces.hasKey(implKey) {
                discoveredInterfaces[implKey] = true;
                foreach string implFqn in connField.interfaceImplementations {
                    if isDisallowedConfigTypeClass(implFqn) || memberClassCache.hasKey(implFqn) {
                        continue;
                    }
                    ClassInfo? preDiscoveredImpl = findClassByName(implFqn, allClasses);
                    if preDiscoveredImpl is () {
                        preDiscoveredImpl = resolveClassFromJars(implFqn, dependencyJarPaths);
                    }
                    if preDiscoveredImpl is ClassInfo {
                        memberClassCache[implFqn] = preDiscoveredImpl;
                        log:printInfo("Implementation added to memberClassCache",
                            interfaceType = implKey, implClass = implFqn);
                    } else {
                        log:printInfo("Implementation not resolvable from JARs",
                            interfaceType = implKey, implFqn = implFqn);
                    }
                }
            }
            continue; // skip Phase 1/2 JAR scan for this field
        }

        string? typeRef = connField.typeReference;
        if typeRef is () || isDisallowedConfigTypeClass(typeRef) {
            continue;
        }
        if discoveredInterfaces.hasKey(typeRef) {
            continue; // already scanned this interface
        }
        discoveredInterfaces[typeRef] = true;

        ClassInfo? ifaceClass = findClassByName(typeRef, allClasses);
        if ifaceClass is () {
            ifaceClass = resolveClassFromJars(typeRef, dependencyJarPaths);
        }
        if !(ifaceClass is ClassInfo) {
            continue;
        }
        // Only expand interfaces and abstract classes — concrete types already resolved
        if !ifaceClass.isInterface && !ifaceClass.isAbstract {
            continue;
        }
        string ifaceFqn = ifaceClass.className;
        string ifaceSimple = ifaceClass.simpleName;

        // Phase 1: Scan already-loaded classes (main JAR + any lazily resolved dep classes)
        foreach ClassInfo candidate in allClasses {
            if candidate.isAbstract || candidate.isEnum {
                continue;
            }
            if isDisallowedConfigTypeClass(candidate.className) {
                continue;
            }
            if memberClassCache.hasKey(candidate.className) {
                continue;
            }
            boolean isImpl = false;
            foreach string iface in candidate.interfaces {
                if iface == ifaceFqn || iface.endsWith("." + ifaceSimple) {
                    isImpl = true;
                    break;
                }
            }
            if !isImpl {
                string? sc = candidate.superClass;
                if sc is string && (sc == ifaceFqn || sc.endsWith("." + ifaceSimple)) {
                    isImpl = true;
                }
            }
            if isImpl {
                memberClassCache[candidate.className] = candidate;
            }
        }

        // Phase 2: Scan dependency JAR files for implementations not loaded in allClasses.
        // findImplementorsInJars uses metadata-only ASM parsing (no method bodies) so it
        // is fast even over many JARs.
        string[] depImplementors = findImplementorsInJars(ifaceFqn, dependencyJarPaths);
        foreach string implName in depImplementors {
            if isDisallowedConfigTypeClass(implName) || memberClassCache.hasKey(implName) {
                continue;
            }
            ClassInfo? implClass = resolveClassFromJars(implName, dependencyJarPaths);
            if implClass is ClassInfo {
                memberClassCache[implName] = implClass;
            }
        }
    }

    map<boolean> connectionConfigScope = buildConnectionConfigScope(initPattern.connectionFields);

    // fill enum gaps with LLM-synthesized metadata
    foreach SyntheticTypeMetadata stm in initPattern.syntheticTypeMetadata {
        if stm.ballerinaType == "enum" && !enumCache.hasKey(stm.fullType) {
            string[] vals = stm.enumValues.length() > 0
                ? stm.enumValues
                : ["(see SDK documentation)"];
            enumCache[stm.fullType] = {
                simpleName: stm.simpleName,
                values: vals
            };
        }
    }

    // Extract JAR-resolved member classes (recursively) including external dependency classes
    map<MemberClassInfo> memberClasses = extractMemberClassInfo(
            memberClassCache,
            allClasses,
            dependencyJarPaths,
            enumCache,
            connectionConfigScope
    );

    // Apply required flags inferred for member-reference connection fields.
    foreach [string, map<boolean>] [memberRef, requiredMemberFields] in requiredConnMemberFieldsByClass.entries() {
        MemberClassInfo? memberInfoOpt = memberClasses[memberRef];
        if memberInfoOpt is MemberClassInfo {
            RequestFieldInfo[] rebuiltMemberFields = [];
            foreach RequestFieldInfo memberFld in memberInfoOpt.fields {
                RequestFieldInfo updatedField = memberFld;
                if requiredMemberFields.hasKey(memberFld.name) {
                    updatedField.isRequired = true;
                }
                rebuiltMemberFields.push(updatedField);
            }
            memberClasses[memberRef] = {
                simpleName: memberInfoOpt.simpleName,
                packageName: memberInfoOpt.packageName,
                fields: rebuiltMemberFields
            };
        }
    }

    // Finalize enum metadata from resolved member classes as well, including
    // enum-like classes that expose public static final self-typed constants.
    foreach [string, ClassInfo] [memberName, memberClass] in memberClassCache.entries() {
        if enumCache.hasKey(memberName) {
            continue;
        }
        ClassInfo classForEnum = memberClass;
        if !classForEnum.isEnum && !hasEnumLikeConstants(classForEnum) {
            ClassInfo? refreshed = resolveClassFromJars(memberName, dependencyJarPaths);
            if refreshed is ClassInfo {
                classForEnum = refreshed;
            }
        }

        if classForEnum.isEnum || hasEnumLikeConstants(classForEnum) {
            EnumMetadata memberEnumMeta = extractEnumMetadata(classForEnum);
            if memberEnumMeta.values.length() > 0 {
                enumCache[memberName] = memberEnumMeta;
            }
        }
    }

    // Inject synthetic MemberClassInfo for record/object types
    foreach SyntheticTypeMetadata stm in initPattern.syntheticTypeMetadata {
        if (stm.ballerinaType == "record" || stm.ballerinaType == "object") &&
            !memberClasses.hasKey(stm.fullType) {
            string syntheticPkg = "";
            int? lastDot = stm.fullType.lastIndexOf(".");
            if lastDot is int && lastDot > 0 {
                syntheticPkg = stm.fullType.substring(0, lastDot);
            }
            memberClasses[stm.fullType] = {
                simpleName: stm.simpleName,
                packageName: syntheticPkg,
                fields: stm.subFields
            };
        }
    }

    return {
        sdkInfo: {
            name: extractSdkNameFromClass(rootClient),
            version: "unknown",
            rootClientClass: rootClient.className
        },
        clientInit: {
            patternName: initPattern.patternName,
            initializationCode: initPattern.initializationCode,
            explanation: initPattern.explanation,
            detectedBy: initPattern.detectedBy,
            builderClass: initPattern.builderClass,
            connectionFields: updatedConnFields,
            syntheticTypeMetadata: initPattern.syntheticTypeMetadata
        },
        rootClient: {
            className: rootClient.className,
            packageName: rootClient.packageName,
            simpleName: rootClient.simpleName,
            isInterface: rootClient.isInterface,
            constructors: rootClient.constructors,
            methods: methodsWithRequestFields
        },
        memberClasses: memberClasses,
        enums: enumCache,
        analysis: {
            totalClassesFound: allClasses.length(),
            totalMethodsInClient: rootClient.methods.length(),
            selectedMethods: methodsWithRequestFields.length(),
            analysisApproach: "JavaParser with LLM enhancement"
        }
    };
}

# Extract SDK name from class information
#
# + rootClient - Root client class
# + return - Inferred SDK name
function extractSdkNameFromClass(ClassInfo rootClient) returns string {
    string packageName = rootClient.packageName;
    if packageName == "" {
        return "Java SDK";
    }

    string[] parts = regex:split(packageName, "\\.");
    // Find the last meaningful segment — skip version-like segments (v1, v2, v1beta1)
    // and very short tokens so the SDK name reflects the service, not an API version.
    string last = "";
    foreach string p in parts.reverse() {
        string pl = p.trim();
        if pl.length() == 0 {
            continue;
        }
        // Skip version-like segments: starts with 'v' + digit (v1, v2, v1beta1, etc.)
        if pl.length() > 1 && pl.startsWith("v") {
            string afterV = pl.substring(1, 2);
            if afterV >= "0" && afterV <= "9" {
                continue;
            }
        }
        // Skip purely numeric segments
        boolean allDigits = true;
        foreach int idx in 0 ..< pl.length() {
            string ch = pl.substring(idx, idx + 1);
            if !(ch >= "0" && ch <= "9") {
                allDigits = false;
                break;
            }
        }
        if allDigits {
            continue;
        }
        last = pl;
        break;
    }

    if last.length() == 0 {
        return "Java SDK";
    }

    // Title-case the last segment
    string namePart = last;
    if namePart.length() > 1 {
        string first = namePart.substring(0, 1).toUpperAscii();
        string rest = namePart.substring(1);
        namePart = first + rest;
    } else {
        namePart = namePart.toUpperAscii();
    }

    return namePart + " SDK";
}

# Extract supporting classes used by the selected methods
#
# + methods - Selected methods 
# + allClasses - All available classes
# + return - Supporting classes information
function extractSupportingClasses(MethodInfo[] methods, ClassInfo[] allClasses)
        returns SupportingClassInfo[] {

    SupportingClassInfo[] supportingClasses = [];
    map<boolean> addedClasses = {};

    foreach MethodInfo method in methods {
        // Check return type
        string returnType = method.returnType;
        if returnType != "void" && !isSimpleType(returnType) {
            ClassInfo? cls = findClassByName(returnType, allClasses);
            if cls is ClassInfo && !addedClasses.hasKey(cls.className) {
                supportingClasses.push({
                    className: cls.className,
                    simpleName: cls.simpleName,
                    packageName: cls.packageName,
                    purpose: "Return type"
                });
                addedClasses[cls.className] = true;
            }
        }

        // Check parameter types
        foreach ParameterInfo param in method.parameters {
            if !isSimpleType(param.typeName) {
                ClassInfo? cls = findClassByName(param.typeName, allClasses);
                if cls is ClassInfo && !addedClasses.hasKey(cls.className) {
                    supportingClasses.push({
                        className: cls.className,
                        simpleName: cls.simpleName,
                        packageName: cls.packageName,
                        purpose: "Parameter type"
                    });
                    addedClasses[cls.className] = true;
                }
            }
        }
    }

    return supportingClasses;
}

# Check if class should be considered as client candidate.
# Vendor-neutral: works for AWS, Google, Azure, and any other Java SDK.
#
# + cls - Class to check
# + return - True if should be considered
function shouldConsiderAsClientCandidate(ClassInfo cls) returns boolean {
    // Never consider enums as clients
    if cls.isEnum {
        return false;
    }

    // Abstract classes are not direct clients (but interfaces are allowed)
    if cls.isAbstract && !cls.isInterface {
        return false;
    }

    string className = cls.className;
    string simpleNameLower = cls.simpleName.toLowerAscii();
    string packageLower = cls.packageName.toLowerAscii();

    // Determine nesting depth from $ separators.
    // Inner classes in Java class files use $ as the separator between outer and inner name.
    string[] classSegments = regex:split(className, "\\$");
    int dollarCount = classSegments.length() - 1;

    // Skip deeply nested inner classes (two or more $ levels) — these are implementation details
    if dollarCount >= 2 {
        return false;
    }

    // Skip anonymous inner classes — their suffix after $ is purely numeric (e.g. Foo$1, Foo$2)
    if dollarCount == 1 {
        string innerSuffix = classSegments[classSegments.length() - 1];
        if innerSuffix.length() > 0 {
            string firstChar = innerSuffix.substring(0, 1);
            if firstChar >= "0" && firstChar <= "9" {
                return false;
            }
        }
    }

    // Helper/utility classes are never root clients
    if isHelperLikeClientType(simpleNameLower) {
        return false;
    }

    // Pure-static utility classes have no instance methods — skip them
    boolean hasInstanceMethod = false;
    foreach MethodInfo m in cls.methods {
        if !m.isStatic {
            hasInstanceMethod = true;
            break;
        }
    }
    if !hasInstanceMethod {
        return false;
    }

    // Service-name signal: simple class name matches a meaningful segment of its package.
    // Example: class "Forms" in package "com.google.api.services.forms.v1" matches "forms".
    // This handles SDKs whose root class is named after the service without a Client/Service suffix.
    boolean hasServiceNameSignal = matchesPackageServiceSegment(simpleNameLower, packageLower);

    boolean hasClientNameSignals = simpleNameLower.includes("client") ||
        simpleNameLower.includes("admin") ||
        simpleNameLower.includes("producer") ||
        simpleNameLower.includes("consumer") ||
        simpleNameLower.includes("service") ||
        simpleNameLower.includes("manager") ||
        simpleNameLower.includes("connection") ||
        simpleNameLower.includes("operations") ||
        hasServiceNameSignal;

    boolean hasClientPackageSignals = packageLower.includes(".clients") ||
        packageLower.includes(".client") ||
        packageLower.includes(".admin") ||
        packageLower.includes(".consumer") ||
        packageLower.includes(".producer") ||
        packageLower.includes(".services");

    // First-level inner class (single $): allow only when it has enough methods and naming/
    // package signals. This captures SDK patterns where operations live on a nested sub-client
    // returned from the root class (common in Google API client libraries).
    if dollarCount == 1 {
        return cls.methods.length() >= 3 && (hasClientNameSignals || hasClientPackageSignals);
    }

    // Top-level class heuristics (vendor-neutral)
    if cls.isInterface {
        if cls.methods.length() >= 5 &&
            (hasClientNameSignals || hasClientPackageSignals || cls.methods.length() >= 12) {
            return true;
        }
    } else {
        if cls.methods.length() >= 6 && (hasClientNameSignals || hasClientPackageSignals) {
            return true;
        }
        // High method count alone is sufficient — implementation classes without naming conventions
        if cls.methods.length() >= 18 {
            return true;
        }
        // Root delegate class: few methods but strong service-name match
        // (e.g., Google's Forms class that only exposes forms() returning an operations sub-client)
        if hasServiceNameSignal {
            return true;
        }
    }
    if cls.methods.length() >= 25 {
        return true;
    }

    return false;
}

# Check whether a class's simple name matches a meaningful service segment in its package.
# Skips very short segments and version-like segments (v1, v2, v1beta1, etc.).
# Example: "Forms" matches "forms" in "com.google.api.services.forms.v1".
#
# + simpleNameLower - Lower-cased simple class name
# + packageLower - Lower-cased package name
# + return - True if a matching segment is found
function matchesPackageServiceSegment(string simpleNameLower, string packageLower) returns boolean {
    string[] parts = regex:split(packageLower, "\\.");
    foreach string part in parts {
        // Skip generic short segments
        if part.length() <= 2 {
            continue;
        }
        // Version-like: starts with 'v' followed by a digit (e.g., v1, v2, v1beta1)
        if part.length() > 1 && part.startsWith("v") {
            string afterV = part.substring(1, 2);
            if afterV >= "0" && afterV <= "9" {
                continue;
            }
        }
        if part == simpleNameLower {
            return true;
        }
    }
    return false;
}

function quickClientCandidatePriority(ClassInfo cls) returns int {
    string simpleNameLower = cls.simpleName.toLowerAscii();
    string packageLower = cls.packageName.toLowerAscii();

    int priority = cls.methods.length();
    if priority > 100 {
        priority = 100;
    }

    if simpleNameLower.includes("client") {
        priority += 40;
    }
    if simpleNameLower.includes("admin") || simpleNameLower.includes("producer") ||
        simpleNameLower.includes("consumer") {
        priority += 35;
    }
    // Operations sub-client (Google-style resource class naming)
    if simpleNameLower.includes("operations") {
        priority += 20;
    }
    if packageLower.includes(".clients") || packageLower.includes(".client") {
        priority += 25;
    }
    // Service name match boosts root delegate classes that name themselves after the service
    if matchesPackageServiceSegment(simpleNameLower, packageLower) {
        priority += 30;
    }
    if cls.isInterface {
        priority += 10;
    }

    return priority;
}

function isHelperLikeClientType(string simpleNameLower) returns boolean {
    // "request" and "response" are intentionally excluded: in some SDKs (e.g., Google API client
    // library) the base request class (e.g., FormsRequest) is a meaningful operational class, not a DTO.
    // Model-package DTOs are already excluded upstream by isRelevantClientClass.
    string[] helperTokens = ["builder", "config", "option", "result", "record",
        "metadata", "context", "factory", "provider", "interceptor", "serializer", "deserializer",
        "authenticator", "readable", "writable", "util", "helper"];
    foreach string token in helperTokens {
        if simpleNameLower.includes(token) {
            return true;
        }
    }
    return false;
}

# Use LLM to detect client initialization pattern and generate example code.
#
# + rootClient - The identified root client class  
# + allClasses - All classes for context
# + dependencyJarPaths - Paths to dependency JARs for deeper analysis if needed
# + return - Detected initialization pattern with example code or error
function detectInitPatternWithLLM(
        ClassInfo rootClient,
        ClassInfo[] allClasses,
        string[] dependencyJarPaths
) returns ClientInitPattern|error {
    if utils:isAIServiceInitialized() {
        string systemPrompt = getInitPatternSystemPrompt();
        string constructorDetails = formatConstructorDetails(rootClient.constructors);
        string staticMethodInfo = formatStaticMethods(rootClient.methods);
        string userPrompt = getInitPatternUserPrompt(
                rootClient.simpleName,
                rootClient.packageName,
                constructorDetails,
                staticMethodInfo,
                rootClient.methods.length(),
                rootClient.isInterface
        );

        string|error responseResult = utils:callAIAdvanced(userPrompt, systemPrompt, 5000);

        if responseResult is string {
            string responseText = responseResult;
            string[] lines = regex:split(responseText, "\n");
            string patternName = "";
            string reason = "";

            foreach string line in lines {
                string trimmed = line.trim();
                if trimmed.startsWith("PATTERN:") {
                    patternName = trimmed.substring(8).trim().toLowerAscii();
                } else if trimmed.startsWith("REASON:") {
                    reason = trimmed.substring(7).trim();
                }
            }

            if patternName == "constructor" || patternName == "builder" ||
                patternName == "static-factory" || patternName == "instance-factory" ||
                patternName == "no-constructor" {
                string initCode = generateInitializationCode(patternName, rootClient);
                ClientInitPattern llmPattern = {
                    patternName: patternName,
                    initializationCode: initCode,
                    explanation: reason == "" ? "Pattern detected by LLM analysis" : reason,
                    detectedBy: "llm"
                };
                if patternName == "builder" || patternName == "static-factory" ||
                    patternName == "constructor" {
                    [string?, ConnectionFieldInfo[], SyntheticTypeMetadata[]] br =
                        resolveBuilderConnectionFields(
                            rootClient, allClasses, dependencyJarPaths,
                            rootClient.packageName, rootClient.simpleName
                        );
                    llmPattern.builderClass = br[0];
                    llmPattern.connectionFields = br[1];
                    llmPattern.syntheticTypeMetadata = br[2];
                }
                return llmPattern;
            }
        } else {
            io:println(string `LLM init pattern detection failed: ${responseResult.message()}`);
        }
    }

    // Fallback to heuristic
    ClientInitPattern heuristicPattern = detectClientInitPatternHeuristically(rootClient);
    if heuristicPattern.patternName == "builder" || heuristicPattern.patternName == "static-factory" ||
        heuristicPattern.patternName == "constructor" {
        [string?, ConnectionFieldInfo[], SyntheticTypeMetadata[]] br =
            resolveBuilderConnectionFields(
                rootClient, allClasses, dependencyJarPaths,
                rootClient.packageName, rootClient.simpleName
            );
        heuristicPattern.builderClass = br[0];
        heuristicPattern.connectionFields = br[1];
        heuristicPattern.syntheticTypeMetadata = br[2];
    }
    return heuristicPattern;
}

# Use LLM to intelligently rank SDK methods by usage frequency and examples
#
# + methods - Methods to rank
# + return - Ranked methods or error
function rankMethodsUsingLLM(MethodInfo[] methods) returns MethodInfo[]|error {
    string systemPrompt = getMethodRankingSystemPrompt();
    string methodsList = formatMethodsListForRanking(methods);
    string userPrompt = getMethodRankingUserPrompt(methods.length(), methodsList);

    string|error responseResult = utils:callAIAdvanced(userPrompt, systemPrompt, 5000);

    if responseResult is string {
        string responseText = responseResult;

        // Parse the comma-separated method names
        string[] rankedNames = regex:split(responseText, ",");
        string[] trimmedNames = rankedNames.map(n => n.trim()).filter(n => n.length() > 0);

        if trimmedNames.length() > 0 {
            // Create a map for quick lookup
            map<MethodInfo> methodMap = {};
            foreach MethodInfo method in methods {
                methodMap[method.name] = method;
            }

            // Build result maintaining LLM's priority order, limited to first 40 methods
            MethodInfo[] reordered = [];
            foreach string methodName in trimmedNames {
                if reordered.length() >= 40 {
                    break;
                }
                if methodMap.hasKey(methodName) {
                    MethodInfo? method = methodMap[methodName];
                    if method is MethodInfo {
                        reordered.push(method);
                    }
                }
            }

            // Now fetch descriptions for the selected methods
            MethodInfo[] withDescriptions = check addMethodDescriptions(reordered);
            return withDescriptions;
        }
    }

    return error("Failed to rank methods using LLM");
}

# Fetch descriptions for selected methods from LLM (only for methods without descriptions)
#
# + methods - Selected methods to get descriptions for
# + return - Methods with descriptions added
function addMethodDescriptions(MethodInfo[] methods) returns MethodInfo[]|error {
    if methods.length() == 0 {
        return methods;
    }

    // Identify methods that need descriptions (don't have javadoc descriptions)
    MethodInfo[] needsDescription = [];
    int[] needsDescriptionIndices = [];
    foreach int i in 0 ..< methods.length() {
        if methods[i].description is () || methods[i].description == "" {
            needsDescription.push(methods[i]);
            needsDescriptionIndices.push(i);
        }
    }

    // If all methods have descriptions, return as-is
    if needsDescription.length() == 0 {
        return methods;
    }

    // If LLM not configured, return methods as-is
    if !utils:isAIServiceInitialized() {
        return methods;
    }

    // Build method list with signatures for methods needing descriptions
    string methodList = "";
    foreach int i in 0 ..< needsDescription.length() {
        MethodInfo m = needsDescription[i];
        string paramTypes = "";
        if m.parameters.length() > 0 {
            string[] pTypes = [];
            foreach ParameterInfo p in m.parameters {
                pTypes.push(p.typeName);
            }
            paramTypes = string:'join(", ", ...pTypes);
        }
        methodList = methodList + (i + 1).toString() + ". " + m.name + "(" + paramTypes + ") -> " + m.returnType + "\n";
    }

    string systemPrompt = "You are a Java SDK expert. Provide one-line descriptions for the given methods. " +
        "Each description should clearly explain what the method does in user-friendly language. " +
        "Return ONLY the descriptions, one per line, in the same order as the input methods. " +
        "Do not include method names or numbers, just pure descriptions.";

    string userPrompt = "Provide one-line descriptions for these methods:\n\n" + methodList +
        "\nDescriptions (one per line, in same order):";

    string|error responseResult = utils:callAIAdvanced(userPrompt, systemPrompt, 5000);

    if responseResult is string {
        string responseText = responseResult.trim();
        if responseText != "" {
            string[] descriptions = regex:split(responseText, "\n");
            descriptions = descriptions.map(d => d.trim()).filter(d => d.length() > 0);

            // Apply LLM descriptions only to methods that needed them
            MethodInfo[] result = methods.clone();
            foreach int i in 0 ..< needsDescriptionIndices.length() {
                if i < descriptions.length() {
                    int methodIndex = needsDescriptionIndices[i];
                    result[methodIndex].description = descriptions[i];
                }
            }
            return result;
        }
    }

    // Return methods without descriptions if LLM call fails
    return methods;
}

# Ask LLM to select the top-N most-used methods from the provided list.
#
# + methods - All methods 
# + n - Number of methods to select
# + return - Selected top-N methods or error
function selectTopNMethodsWithLLM(MethodInfo[] methods, int n) returns MethodInfo[]|error {
    if n <= 0 {
        return error("Invalid n passed to selectTopNMethodsWithLLM");
    }

    if methods.length() == 0 {
        return methods;
    }

    if !utils:isAIServiceInitialized() {
        return error("Anthropic LLM not configured: cannot select top-N methods");
    }

    string systemPrompt = getMethodRankingSystemPrompt();
    string methodsList = formatMethodsListForRanking(methods);
    string userPrompt = getMethodSelectionUserPrompt(methods.length(), methodsList, n);

    string|error responseResult = utils:callAIAdvanced(userPrompt, systemPrompt, 5000);
    if responseResult is string {
        string responseText = responseResult.trim();

        // Parse comma-separated method names
        string[] parts = regex:split(responseText, ",");
        string[] trimmed = parts.map(p => p.trim()).filter(p => p.length() > 0);

        if trimmed.length() == 0 {
            return error("LLM returned no method names for top-N selection");
        }

        // Map names to MethodInfo by exact match on name
        map<MethodInfo> methodMap = {};
        foreach MethodInfo m in methods {
            methodMap[m.name] = m;
        }

        MethodInfo[] selected = [];
        foreach string name in trimmed {
            if methodMap.hasKey(name) {
                MethodInfo? mm = methodMap[name];
                if mm is MethodInfo {
                    selected.push(mm);
                }
            }
            if selected.length() == n {
                break;
            }
        }

        // If LLM returned fewer valid names than n, fall back to filling from original list
        if selected.length() < n {
            foreach MethodInfo m in methods {
                // avoid duplicates
                boolean found = false;
                foreach MethodInfo s in selected {
                    if s.name == m.name {
                        found = true;
                        break;
                    }
                }
                if !found {
                    selected.push(m);
                }
                if selected.length() == n {
                    break;
                }
            }
        }

        return selected;
    }

    return error("Failed to call LLM for top-N method selection");
}

# Heuristic-based client initialization pattern detection
#
# + clientClass - The client class to analyze
# + return - Detected initialization pattern
function detectClientInitPatternHeuristically(ClassInfo clientClass) returns ClientInitPattern {
    foreach MethodInfo m in clientClass.methods {
        if m.isStatic {
            string nameLower = m.name.toLowerAscii();
            if nameLower == "builder" {
                return {
                    patternName: "builder",
                    initializationCode: clientClass.simpleName + " client = " + clientClass.simpleName + ".builder().build();",
                    explanation: "Detected static builder() method",
                    detectedBy: "heuristic"
                };
            }
            if nameLower == "newbuilder" {
                return {
                    patternName: "builder",
                    initializationCode: clientClass.simpleName + " client = " + clientClass.simpleName + ".newBuilder().build();",
                    explanation: "Detected static newBuilder() method",
                    detectedBy: "heuristic"
                };
            }
            if nameLower == "create" || nameLower.startsWith("create") {
                return {
                    patternName: "static-factory",
                    initializationCode: clientClass.simpleName + " client = " + clientClass.simpleName + ".create();",
                    explanation: "Detected static create() factory method",
                    detectedBy: "heuristic"
                };
            }
        }
    }

    string innerBuilderClassName = clientClass.className + "$Builder";
    boolean hasInnerBuilder = false;
    foreach ConstructorInfo ctor in clientClass.constructors {
        foreach ParameterInfo p in ctor.parameters {
            if p.typeName.endsWith("Builder") || p.typeName == innerBuilderClassName {
                hasInnerBuilder = true;
                break;
            }
        }
        if hasInnerBuilder {
            break;
        }
    }
    if hasInnerBuilder {
        return {
            patternName: "builder",
            initializationCode: "new " + clientClass.simpleName + ".Builder(...).build();",
            explanation: "Detected inner Builder class instantiated via constructor",
            detectedBy: "heuristic"
        };
    }

    // Fall back to constructors if present
    if clientClass.constructors.length() == 0 {
        return {
            patternName: "no-constructor",
            initializationCode: "// No public constructors found",
            explanation: "The class does not expose public constructors",
            detectedBy: "heuristic"
        };
    }

    string[] patterns = [];
    string[] codePatterns = [];
    foreach ConstructorInfo constructor in clientClass.constructors {
        if constructor.parameters.length() == 0 {
            patterns.push("Default constructor");
            codePatterns.push(string `new ${clientClass.simpleName}()`);
        } else {
            string[] paramTypes = constructor.parameters.map(p => p.typeName);
            patterns.push(string `Constructor(${string:'join(", ", ...paramTypes)})`);
            string[] paramNames = constructor.parameters.map(p => p.name);
            codePatterns.push(string `new ${clientClass.simpleName}(${string:'join(", ", ...paramNames)})`);
        }
    }

    return {
        patternName: "constructor",
        initializationCode: string:'join(" // OR\n", ...codePatterns),
        explanation: string:'join(" | ", ...patterns),
        detectedBy: "heuristic"
    };
}

# Analyze fields using LLM to determine if they are required or optional
#
# + methodName - Method name for context
# + parameterType - Parameter type name
# + fields - Array of request fields to analyze
# + config - Analyzer configuration
# + return - Updated fields with isRequired set by LLM
public function analyzeFieldRequirements(
        string methodName,
        string parameterType,
        RequestFieldInfo[] fields,
        AnalyzerConfig config
) returns RequestFieldInfo[]|error {

    if config.disableLLM || fields.length() == 0 {
        return fields;
    }

    // Build field list for prompt
    string fieldsList = "";
    foreach RequestFieldInfo fld in fields {
        fieldsList += string `- ${fld.name}: ${fld.typeName}\n`;
    }

    // Call LLM
    string sysPrompt = getFieldRequirementSystemPrompt();
    string userPrompt = getFieldRequirementUserPrompt(methodName, parameterType, fieldsList);
    string|error llmResult = utils:callAIAdvanced(userPrompt, sysPrompt, 5000);

    if llmResult is error {
        // If LLM fails, return original fields
        return fields;
    }

    // Parse LLM response
    string responseText = llmResult;

    // Extract JSON array from response (handle markdown code blocks)
    string jsonText = responseText.trim();
    if jsonText.startsWith("```json") {
        jsonText = jsonText.substring(7);
    }
    if jsonText.startsWith("```") {
        jsonText = jsonText.substring(3);
    }
    if jsonText.endsWith("```") {
        jsonText = jsonText.substring(0, jsonText.length() - 3);
    }
    jsonText = jsonText.trim();

    json|error parsedJson = jsonText.fromJsonString();
    if parsedJson is error {
        // If parsing fails, return original fields
        return fields;
    }

    // Parse the JSON array and update fields
    if parsedJson is json[] {
        map<boolean> requirementMap = {};

        foreach json item in parsedJson {
            if item is map<json> {
                string? fieldName = <string?>item["field"];
                boolean? required = <boolean?>item["required"];

                if fieldName is string && required is boolean {
                    requirementMap[fieldName] = required;
                }
            }
        }

        // Update fields with LLM results
        RequestFieldInfo[] updatedFields = [];
        foreach RequestFieldInfo fld in fields {
            RequestFieldInfo updated = fld;
            if requirementMap.hasKey(fld.name) {
                updated.isRequired = requirementMap.get(fld.name);
            }
            updatedFields.push(updated);
        }

        return updatedFields;
    }

    return fields;
}

# Check if a field is a redundant "AsString" variant of another field
#
# + fieldName - Field name to check
# + allFields - All fields in the same context
# + return - True if this field should be filtered out
function isRedundantAsStringField(string fieldName, RequestFieldInfo[] allFields) returns boolean {
    // Check if field name ends with "AsString" or "AsStrings"
    if !fieldName.endsWith("AsString") && !fieldName.endsWith("AsStrings") {
        return false;
    }

    // Extract the base field name (remove AsString/AsStrings suffix)
    string baseFieldName;
    if fieldName.endsWith("AsStrings") {
        baseFieldName = fieldName.substring(0, fieldName.length() - 9);
    } else {
        baseFieldName = fieldName.substring(0, fieldName.length() - 8);
    }

    // Check if the base field exists
    foreach RequestFieldInfo fld in allFields {
        if fld.name == baseFieldName {
            return true;
        }
    }

    return false;
}

# Extract member class information from cached member classes
#
# + memberClassCache - Map of class names to ClassInfo
# + allClasses - All parsed classes from the main analysis
# + dependencyJarPaths - Dependency JAR paths for resolving external types
# + enumCache - Mutable enum cache to record discovered nested enums
# + connectionConfigScope - Mutable set of class names that belong to connection-config recursion scope
# + return - Map of member class info with extracted fields
function extractMemberClassInfo(
        map<ClassInfo> memberClassCache,
        ClassInfo[] allClasses,
        string[] dependencyJarPaths,
    map<EnumMetadata> enumCache,
    map<boolean> connectionConfigScope
) returns map<MemberClassInfo> {
    map<MemberClassInfo> result = {};
    ClassInfo[] resolvedClasses = [...allClasses];

    string[] pending = memberClassCache.keys();
    int index = 0;

    while index < pending.length() {
        string className = pending[index];
        ClassInfo? classInfoOpt = memberClassCache[className];
        if classInfoOpt is () {
            index += 1;
            continue;
        }
        ClassInfo classInfo = classInfoOpt;

        if isDisallowedConfigTypeClass(classInfo.className) {
            index += 1;
            continue;
        }

        boolean isConnectionScoped = connectionConfigScope.hasKey(className);

        RequestFieldInfo[] extractedFields;
        if isConnectionScoped {
            extractedFields = extractClassAndAncestorFields(
                classInfo,
                resolvedClasses,
                dependencyJarPaths
            );
        } else if classInfo.isEnum {
            extractedFields = extractEnumConstants(classInfo);
        } else if classInfo.isInterface {
            extractedFields = extractClassAndAncestorFields(classInfo, resolvedClasses, dependencyJarPaths);
        } else {
            extractedFields = [];
            foreach FieldInfo fld in classInfo.fields {
                if fld.isStatic {
                    continue;
                }
                extractedFields.push({
                    name: fld.name,
                    typeName: extractSimpleTypeName(fld.typeName),
                    fullType: fld.typeName,
                    isRequired: true
                });
            }

            if extractedFields.length() == 0 {
                map<boolean> existingFieldNames = {};
                // A: Public constructors
                foreach ConstructorInfo ctor in classInfo.constructors {
                    if ctor.parameters.length() == 0 {
                        continue;
                    }
                    foreach ParameterInfo param in ctor.parameters {
                        if param.name == "" || param.name.startsWith("arg") {
                            continue;
                        }
                        if existingFieldNames.hasKey(param.name) {
                            continue;
                        }
                        existingFieldNames[param.name] = true;
                        extractedFields.push({
                            name: param.name,
                            typeName: extractSimpleTypeName(param.typeName),
                            fullType: param.typeName,
                            isRequired: true
                        });
                    }
                }
                // B: Static factory methods whose return type is this class
                foreach MethodInfo m in classInfo.methods {
                    if !m.isStatic || m.parameters.length() == 0 {
                        continue;
                    }
                    if extractSimpleTypeName(m.returnType) != classInfo.simpleName {
                        continue;
                    }
                    foreach ParameterInfo param in m.parameters {
                        if param.name == "" || param.name.startsWith("arg") {
                            continue;
                        }
                        if existingFieldNames.hasKey(param.name) {
                            continue;
                        }
                        existingFieldNames[param.name] = true;
                        extractedFields.push({
                            name: param.name,
                            typeName: extractSimpleTypeName(param.typeName),
                            fullType: param.typeName,
                            isRequired: true
                        });
                    }
                }
            }
        }

        // Filter redundant AsString fields from member class fields too
        RequestFieldInfo[] filteredFields = [];
        foreach RequestFieldInfo fld in extractedFields {
            if isRedundantAsStringField(fld.name, extractedFields) {
                continue;
            }

            RequestFieldInfo enhanced = fld;

            // Resolve collection generic member types (e.g., List<Foo>)
            if isCollectionType(fld.typeName) {
                string? genericParam = extractGenericTypeParameter(fld.fullType);
                if genericParam is string && genericParam.length() > 0 {
                    enhanced.memberReference = genericParam;

                    ClassInfo? memberClass = findClassByName(genericParam, allClasses);
                    if memberClass is () {
                        memberClass = resolveClassFromJars(genericParam, dependencyJarPaths);
                    }

                    if memberClass is ClassInfo {
                        if isDisallowedConfigTypeClass(memberClass.className) {
                            continue;
                        }

                        if memberClass.isEnum || hasEnumLikeConstants(memberClass) {
                            if memberClass.isEnum {
                                enhanced.enumReference = memberClass.className;
                            }
                            if !enumCache.hasKey(memberClass.className) {
                                enumCache[memberClass.className] = extractEnumMetadata(memberClass);
                            }
                        } else if memberClass.className != className &&
                                !memberClassCache.hasKey(memberClass.className) {
                            memberClassCache[memberClass.className] = memberClass;
                            pending.push(memberClass.className);
                            if isConnectionScoped {
                                connectionConfigScope[memberClass.className] = true;
                            }
                        }

                        enhanced.memberReference = memberClass.className;
                    }
                }
            } else if !isSimpleType(fld.fullType) && !isStandardJavaType(fld.fullType) {
                // Resolve nested object/enum fields recursively
                ClassInfo? nestedClass = findOrResolveClass(fld.fullType, resolvedClasses, dependencyJarPaths);

                if nestedClass is ClassInfo {
                    if isDisallowedConfigTypeClass(nestedClass.className) {
                        continue;
                    }

                    if nestedClass.isEnum || hasEnumLikeConstants(nestedClass) {
                        if nestedClass.isEnum {
                            enhanced.enumReference = nestedClass.className;
                        }
                        if !enumCache.hasKey(nestedClass.className) {
                            enumCache[nestedClass.className] = extractEnumMetadata(nestedClass);
                        }
                    } else {
                        enhanced.memberReference = nestedClass.className;
                        if nestedClass.className != className &&
                            !memberClassCache.hasKey(nestedClass.className) {
                            memberClassCache[nestedClass.className] = nestedClass;
                            pending.push(nestedClass.className);
                            if isConnectionScoped {
                                connectionConfigScope[nestedClass.className] = true;
                            }
                        }

                        if nestedClass.isInterface || nestedClass.isAbstract {
                            ClassInfo[] nestedImpls = findInterfaceImplementors(
                                nestedClass.className, resolvedClasses, dependencyJarPaths);
                            foreach ClassInfo implCls in nestedImpls {
                                if isDisallowedConfigTypeClass(implCls.className) ||
                                        memberClassCache.hasKey(implCls.className) {
                                    continue;
                                }
                                memberClassCache[implCls.className] = implCls;
                                pending.push(implCls.className);
                            }
                        }
                    }
                }
            }

            filteredFields.push(enhanced);
        }

        MemberClassInfo memberInfo = {
            simpleName: classInfo.simpleName,
            packageName: classInfo.packageName,
            fields: filteredFields
        };

        result[className] = memberInfo;

        index += 1;
    }

    return result;
}

function extractClassAndAncestorFields(
        ClassInfo classInfo,
        ClassInfo[] resolvedClasses,
        string[] dependencyJarPaths
) returns RequestFieldInfo[] {
    map<boolean> visited = {};
    RequestFieldInfo[] collected = [];

    collectClassHierarchyFields(classInfo, resolvedClasses, dependencyJarPaths, visited, collected);

    map<boolean> seen = {};
    RequestFieldInfo[] unique = [];
    foreach RequestFieldInfo fld in collected {
        string key = fld.name + "|" + fld.fullType;
        if seen.hasKey(key) {
            continue;
        }
        seen[key] = true;
        unique.push(fld);
    }

    return unique;
}

function collectClassHierarchyFields(
        ClassInfo classInfo,
        ClassInfo[] resolvedClasses,
        string[] dependencyJarPaths,
        map<boolean> visited,
        RequestFieldInfo[] collected
) {
    if visited.hasKey(classInfo.className) {
        return;
    }
    visited[classInfo.className] = true;
    log:printDebug("Collecting hierarchy fields", className = classInfo.className);

    RequestFieldInfo[] ownFields;
    if classInfo.isEnum {
        ownFields = extractEnumConstants(classInfo);
    } else {
        ownFields = extractResponseFields(classInfo);
    }

    foreach RequestFieldInfo ownField in ownFields {
        collected.push(ownField);
    }
    log:printDebug("Own fields collected", className = classInfo.className, count = ownFields.length());

    string? superClass = classInfo.superClass;
    if superClass is string && superClass != "" && superClass != "java.lang.Object" {
        log:printDebug("Traversing superclass for hierarchy fields", sourceClass = classInfo.className, superClass = superClass);
        ClassInfo? superInfo = findOrResolveClass(superClass, resolvedClasses, dependencyJarPaths);
        if superInfo is ClassInfo {
            collectClassHierarchyFields(superInfo, resolvedClasses, dependencyJarPaths, visited, collected);
        }
    }

    // Traverse own interfaces upward (not looking for implementers downward)
    foreach string iface in classInfo.interfaces {
        if iface == "" || iface == "java.lang.Object" {
            continue;
        }
        log:printDebug("Traversing interface for hierarchy fields", sourceClass = classInfo.className, iface = iface);
        ClassInfo? ifaceInfo = findOrResolveClass(iface, resolvedClasses, dependencyJarPaths);
        if ifaceInfo is ClassInfo {
            collectClassHierarchyFields(ifaceInfo, resolvedClasses, dependencyJarPaths, visited, collected);
        }
    }
}

function buildConnectionConfigScope(ConnectionFieldInfo[] connectionFields) returns map<boolean> {
    map<boolean> scope = {};

    foreach ConnectionFieldInfo connField in connectionFields {
        if connField.typeReference is string {
            string typeRef = <string>connField.typeReference;
            if typeRef.trim() != "" && !isDisallowedConfigTypeClass(typeRef) {
                scope[typeRef] = true;
            }
        }
        if connField.memberReference is string {
            string memberRef = <string>connField.memberReference;
            if memberRef.trim() != "" && !isDisallowedConfigTypeClass(memberRef) {
                scope[memberRef] = true;
            }
        }
        if connField.enumReference is string {
            string enumRef = <string>connField.enumReference;
            if enumRef.trim() != "" && !isDisallowedConfigTypeClass(enumRef) {
                scope[enumRef] = true;
            }
        }
    }

    return scope;
}

function isDisallowedConfigTypeClass(string className) returns boolean {
    string n = className.trim();
    if n == "" {
        return true;
    }

    string lower = n.toLowerAscii();

    // Builder classes
    if lower.includes("$builder") || lower.endsWith("builder") {
        return true;
    }

    // Internal/impl packages
    if lower.includes(".internal.") || lower.includes(".impl.") {
        return true;
    }

    // Inner classes (except $Type enums)
    if n.includes("$") && !n.endsWith("$Type") {
        return true;
    }

    // Native/CRT layer — never user-facing config
    if lower.includes(".crt.") {
        return true;
    }

    // Lifecycle sub-systems (waiters, signers, interceptors) — not connection config types
    if lower.includes(".waiters.") || lower.includes(".signer.") ||
        lower.includes(".interceptor.") || lower.includes(".handlers.") {
        return true;
    }

    // Generic internal framework package patterns.
    if lower.endsWith(".internal") || lower.endsWith(".impl") {
        return true;
    }

    return false;
}

# Resolve connection fields for builder pattern using LLM enrichment.
#
# + clientClass - The client ClassInfo for which to resolve builder connection fields 
# + allClasses - All classes available
# + dependencyJarPaths - Paths to dependency JARs for deeper analysis if needed
# + sdkPackage - The SDK package name
# + clientSimpleName - The simple name of the client class
# + return - The resolved connection fields and synthetic type metadata
function resolveBuilderConnectionFields(
        ClassInfo clientClass,
        ClassInfo[] allClasses,
        string[] dependencyJarPaths,
        string sdkPackage,
        string clientSimpleName
) returns [string?, ConnectionFieldInfo[], SyntheticTypeMetadata[]] {

    log:printInfo("Resolving builder connection fields", clientClass = clientClass.className);
    ClassInfo? builderClass = findBuilderClass(clientClass, allClasses, dependencyJarPaths);
    if builderClass is () {
        log:printInfo("No builder class found for client", clientClass = clientClass.className);
        return [(), [], []];
    }
    log:printInfo("Builder class found", clientClass = clientClass.className, builderClass = builderClass.className);

    ConnectionFieldInfo[] fields = [];
    map<boolean> visitedClasses = {};
        map<boolean> visitedFieldKeys = {};
    ClassInfo[] resolvedClasses = [...allClasses];

    collectBuilderSetters(
            builderClass, resolvedClasses, dependencyJarPaths,
            fields, visitedClasses, visitedFieldKeys, 0
    );
    log:printInfo("Raw builder setters collected", builderClass = builderClass.className, fieldCount = fields.length());

    if fields.length() == 0 {
        return [builderClass.className, [], []];
    }

    ConnectionFieldInfo[] clean = [];
    foreach ConnectionFieldInfo f in fields {
        ConnectionFieldInfo stripped = {
            name: f.name,
            typeName: f.typeName,
            fullType: f.fullType,
            isRequired: f.isRequired,
            enumReference: f.enumReference,
            memberReference: f.memberReference,
            typeReference: f.typeReference,
            description: f.description,
            interfaceImplementations: f.interfaceImplementations
        };
        clean.push(stripped);
    }

    return [builderClass.className, clean, []];
}

# Find the builder class for a client class.
#
# + clientClass - The client ClassInfo to find a builder for 
# + allClasses - All classes available (for hierarchy lookup)
# + dependencyJarPaths - Paths to dependency JARs for resolving external classes
# + return - The builder ClassInfo if found, otherwise ()
function findBuilderClass(ClassInfo clientClass, ClassInfo[] allClasses, string[] dependencyJarPaths) returns ClassInfo? {
    log:printInfo("Searching for builder class", clientClass = clientClass.className);
    ClassInfo[] candidates = [];

    // Strategy 0: direct inner-class builder lookup.
    foreach ClassInfo cls in allClasses {
        string sn = cls.simpleName;
        string cn = cls.className;
        if (sn == clientClass.simpleName + "Builder" || sn == "Builder") &&
            (cn == clientClass.className + "$Builder" ||
             cn.startsWith(clientClass.className + "$") && sn == "Builder") {
            candidates.push(cls);
        }
    }
    // Also try resolving from dependency JARs when not already found in allClasses
    if candidates.length() == 0 {
        string innerBuilderName = clientClass.className + "$Builder";
        ClassInfo? innerBuilderCls = resolveClassFromJars(innerBuilderName, dependencyJarPaths);
        if innerBuilderCls is ClassInfo {
            candidates.push(innerBuilderCls);
        }
    }
    log:printDebug("Strategy 0 (inner-class builder) candidates", clientClass = clientClass.className, count = candidates.length());

    // Strategy 1: static builder() method return type
    foreach MethodInfo m in clientClass.methods {
        if m.isStatic && m.name == "builder" && m.returnType != "void" {
            ClassInfo? found = findClassByName(m.returnType, allClasses);
            if found is ClassInfo {
                candidates.push(found);
            }
            // returnType may be a simple name, try qualifying with client package
            string qualified = clientClass.packageName + "." + m.returnType;
            found = findClassByName(qualified, allClasses);
            if found is ClassInfo {
                candidates.push(found);
            }
            // Try to resolve from dependency JARs
            found = resolveClassFromJars(m.returnType, dependencyJarPaths);
            if found is ClassInfo {
                candidates.push(found);
            }
            found = resolveClassFromJars(qualified, dependencyJarPaths);
            if found is ClassInfo {
                candidates.push(found);
            }
        }
    }

    log:printDebug("Strategy 1 (static builder() method) candidates", clientClass = clientClass.className, count = candidates.length());

    // Strategy 2: name-convention search for Builder in same package
    string clientSimple = clientClass.simpleName;
    foreach ClassInfo cls in allClasses {
        string sn = cls.simpleName;
        if (sn == clientSimple + "Builder" || sn == clientSimple + "$Builder") &&
            cls.packageName.startsWith(clientClass.packageName) {
            candidates.push(cls);
        }
    }

    log:printDebug("Strategy 2 (name-convention search) candidates", clientClass = clientClass.className, count = candidates.length());

    // Strategy 3: any Builder in same package whose name contains the client name
    foreach ClassInfo cls in allClasses {
        if cls.simpleName.endsWith("Builder") &&
            cls.packageName.startsWith(clientClass.packageName) &&
            cls.simpleName.includes(clientSimple) {
            candidates.push(cls);
        }
    }
    log:printDebug("Strategy 3 (contains-name Builder in package) candidates", clientClass = clientClass.className, count = candidates.length());

    if candidates.length() == 0 {
        log:printInfo("No builder candidates found", clientClass = clientClass.className);
        return ();
    }

    ClassInfo[] uniqueCandidates = [];
    foreach ClassInfo candidate in candidates {
        boolean exists = false;
        foreach ClassInfo existing in uniqueCandidates {
            if existing.className == candidate.className {
                exists = true;
                break;
            }
        }
        if !exists {
            uniqueCandidates.push(candidate);
        }
    }

    ClassInfo best = uniqueCandidates[0];
    int bestScore = scoreBuilderCandidate(best, clientClass);
    foreach int index in 1 ..< uniqueCandidates.length() {
        ClassInfo current = uniqueCandidates[index];
        int score = scoreBuilderCandidate(current, clientClass);
        if score > bestScore {
            best = current;
            bestScore = score;
        }
    }

    log:printInfo("Builder class selected", clientClass = clientClass.className, builderClass = best.className, score = bestScore);
    return best;
}

function scoreBuilderCandidate(ClassInfo candidate, ClassInfo clientClass) returns int {
    int score = 0;
    string candidateName = candidate.className.toLowerAscii();
    string clientSimple = clientClass.simpleName.toLowerAscii();

    if candidate.isInterface {
        score -= 20;
    } else {
        score += 10;
    }
    if candidate.isAbstract {
        score -= 10;
    }

    if candidateName.includes(clientSimple) {
        score += 8;
    }
    if candidateName.endsWith("builder") || candidateName.endsWith("$builder") {
        score += 6;
    }

    foreach MethodInfo method in candidate.methods {
        if !method.isStatic && method.parameters.length() == 1 {
            score += 1;
        }
    }

    foreach FieldInfo fld in candidate.fields {
        if !fld.isStatic {
            score += 1;
        }
    }

    return score;
}

# Recursively collect setter-style methods from a builder class and its ancestors.
#
# + builderClass - The current builder ClassInfo to analyze  
# + resolvedClasses - Mutable array of all resolved classes
# + dependencyJarPaths - Paths to dependency JARs for resolving external classes
# + fields - The collected ConnectionFieldInfo array
# + visitedClasses - Map of visited class names to prevent infinite loops
# + visitedFieldKeys - Map of visited field keys (name+type) to prevent exact duplicates
# + depth - The current recursion depth
function collectBuilderSetters(
        ClassInfo builderClass,
        ClassInfo[] resolvedClasses,
        string[] dependencyJarPaths,
        ConnectionFieldInfo[] fields,
        map<boolean> visitedClasses,
        map<boolean> visitedFieldKeys,
        int depth
) {
    if visitedClasses.hasKey(builderClass.className) {
        return;
    }
    visitedClasses[builderClass.className] = true;
    log:printDebug("Collecting builder setters", builderClass = builderClass.className, depth = depth);

    foreach FieldInfo fld in builderClass.fields {
        if fld.isStatic {
            continue;
        }
        string fieldName = fld.name;
        if fieldName.startsWith("$") || fieldName.startsWith("_") {
            continue;
        }
        if shouldFilterField(fieldName, fld.typeName) {
            continue;
        }

        string fieldKey = buildConnectionFieldDedupKey(fieldName, fld.typeName);
        if visitedFieldKeys.hasKey(fieldKey) {
            continue;
        }
        visitedFieldKeys[fieldKey] = true;

        string paramSimple = extractSimpleTypeName(fld.typeName);
        ClassInfo? resolvedClass = findOrResolveClass(fld.typeName, resolvedClasses, dependencyJarPaths);
        string level1Ctx = resolvedClass is ClassInfo ? buildLevel1Context(resolvedClass) : "";
        string[] implFqns = [];
        if resolvedClass is ClassInfo {
            if (resolvedClass.isInterface || resolvedClass.isAbstract) && !isStandardJavaType(fld.typeName) {
                log:printInfo("Instance field type is interface/abstract, searching for implementations",
                    fieldName = fieldName, interfaceType = fld.typeName,
                    isInterface = resolvedClass.isInterface, isAbstract = resolvedClass.isAbstract);
                ClassInfo[] implClasses = findInterfaceImplementors(fld.typeName, resolvedClasses, dependencyJarPaths);
                if implClasses.length() > 0 {
                    foreach ClassInfo implCls in implClasses {
                        implFqns.push(implCls.className);
                        boolean alreadyInResolved = false;
                        foreach ClassInfo rc in resolvedClasses {
                            if rc.className == implCls.className {
                                alreadyInResolved = true;
                                break;
                            }
                        }
                        if !alreadyInResolved {
                            resolvedClasses.push(implCls);
                        }
                    }
                    level1Ctx = buildInterfaceImplementationsContext(implClasses);
                    log:printInfo("Interface implementations found for instance field",
                        fieldName = fieldName, interfaceType = fld.typeName, implCount = implFqns.length(),
                        impls = string:'join(", ", ...implFqns));
                } else {
                    log:printInfo("No implementations found for interface instance field",
                        fieldName = fieldName, interfaceType = fld.typeName,
                        depJarCount = dependencyJarPaths.length());
                }
            }
        } else {
            log:printInfo("Instance field type not resolved from JARs",
                fieldName = fieldName, fullType = fld.typeName,
                depJarCount = dependencyJarPaths.length());
        }
        log:printInfo("Connection field extracted (instance field)",
            fieldName = fieldName, fullType = fld.typeName,
            typeResolved = resolvedClass is ClassInfo,
            builderClassName = builderClass.className);

        ConnectionFieldInfo info = {
            name: fieldName,
            typeName: paramSimple,
            fullType: fld.typeName,
            isRequired: false,
            description: fld.javadoc,
            level1Context: level1Ctx,
            interfaceImplementations: implFqns
        };

        if !isPrimitiveType(fld.typeName) {
            if isCollectionType(paramSimple) {
                string? genericParam = extractGenericTypeParameter(fld.typeName);
                if genericParam is string && genericParam.length() > 0 {
                    ClassInfo? memberClass = findOrResolveClass(genericParam, resolvedClasses, dependencyJarPaths);
                    if memberClass is ClassInfo {
                        info.memberReference = genericParam;
                    }
                }
            } else if !isStandardJavaType(fld.typeName) {
                if implFqns.length() > 0 {
                } else {
                    info.typeReference = fld.typeName;
                    if resolvedClass is ClassInfo &&
                        (resolvedClass.isEnum || hasEnumLikeConstants(resolvedClass)) {
                        info.enumReference = fld.typeName;
                        info.typeReference = ();
                    }
                }
            }
        }

        fields.push(info);
    }

    // Setter-style methods
    string[] utilityMethods = [
        "build",
        "tostring",
        "hashcode",
        "equals",
        "close",
        "copy",
        "applymutation",
        "sdkfields",
        "sdkfieldnameconstants",
        "get",
        "set",
        "create",
        "validate",
        "from",
        "of",
        "with"
    ];

    foreach MethodInfo m in builderClass.methods {
        if m.isStatic {
            continue;
        }
        if m.parameters.length() != 1 {
            continue;
        }

        string methodNameLower = m.name.toLowerAscii();
        boolean isUtility = false;
        foreach string util in utilityMethods {
            if methodNameLower == util || methodNameLower.startsWith("get") ||
                methodNameLower.startsWith("set") || methodNameLower.startsWith("on") {
                isUtility = true;
                break;
            }
        }
        if isUtility {
            continue;
        }

        string fieldName = m.name;
        if fieldName.startsWith("$") || fieldName.startsWith("_") {
            continue;
        }

        string paramFullType = m.parameters[0].typeName;
        string paramSimple = extractSimpleTypeName(paramFullType);

        // Consumer/Supplier functional interfaces cannot be represented as fields.
        if paramSimple == "Consumer" || paramSimple.endsWith("Consumer") || paramSimple == "Supplier" {
            continue;
        }

        if shouldFilterField(fieldName, paramFullType) {
            continue;
        }

        string fieldKey = buildConnectionFieldDedupKey(fieldName, paramFullType);
        if visitedFieldKeys.hasKey(fieldKey) {
            continue;
        }
        visitedFieldKeys[fieldKey] = true;

        ClassInfo? paramTypeClass = findOrResolveClass(paramFullType, resolvedClasses, dependencyJarPaths);
        string level1Ctx = paramTypeClass is ClassInfo ? buildLevel1Context(paramTypeClass) : "";
        string[] implFqns = [];
        if paramTypeClass is ClassInfo {
            if (paramTypeClass.isInterface || paramTypeClass.isAbstract) && !isStandardJavaType(paramFullType) {
                log:printInfo("Setter param type is interface/abstract, searching for implementations",
                    fieldName = fieldName, interfaceType = paramFullType,
                    isInterface = paramTypeClass.isInterface, isAbstract = paramTypeClass.isAbstract);
                ClassInfo[] implClasses = findInterfaceImplementors(paramFullType, resolvedClasses, dependencyJarPaths);
                if implClasses.length() > 0 {
                    foreach ClassInfo implCls in implClasses {
                        implFqns.push(implCls.className);
                        boolean alreadyInResolved = false;
                        foreach ClassInfo rc in resolvedClasses {
                            if rc.className == implCls.className {
                                alreadyInResolved = true;
                                break;
                            }
                        }
                        if !alreadyInResolved {
                            resolvedClasses.push(implCls);
                        }
                    }
                    level1Ctx = buildInterfaceImplementationsContext(implClasses);
                    log:printInfo("Interface implementations found for setter method",
                        fieldName = fieldName, interfaceType = paramFullType, implCount = implFqns.length(),
                        impls = string:'join(", ", ...implFqns));
                } else {
                    log:printInfo("No implementations found for interface setter param",
                        fieldName = fieldName, interfaceType = paramFullType,
                        depJarCount = dependencyJarPaths.length());
                }
            }
        } else {
            log:printInfo("Setter param type not resolved from JARs",
                fieldName = fieldName, fullType = paramFullType,
                depJarCount = dependencyJarPaths.length());
        }
        log:printInfo("Connection field extracted (setter method)",
            fieldName = fieldName, fullType = paramFullType,
            typeResolved = paramTypeClass is ClassInfo,
            builderClassName = builderClass.className);

        ConnectionFieldInfo info = {
            name: fieldName,
            typeName: paramSimple,
            fullType: paramFullType,
            isRequired: false,
            description: m.description,
            level1Context: level1Ctx,
            interfaceImplementations: implFqns
        };

        if !isPrimitiveType(paramFullType) {
            if isCollectionType(paramSimple) {
                string? genericParam = extractGenericTypeParameter(paramFullType);
                if genericParam is string && genericParam.length() > 0 {
                    ClassInfo? memberClass = findOrResolveClass(genericParam, resolvedClasses, dependencyJarPaths);
                    if memberClass is ClassInfo {
                        info.memberReference = genericParam;
                    }
                }
            } else if !isStandardJavaType(paramFullType) {
                if implFqns.length() > 0 {
                } else {
                    info.typeReference = paramFullType;
                    if paramTypeClass is ClassInfo &&
                        (paramTypeClass.isEnum || hasEnumLikeConstants(paramTypeClass)) {
                        info.enumReference = paramFullType;
                        info.typeReference = ();
                    }
                }
            }
        }

        fields.push(info);
    }

    // Superclass recursion
    string? superClass = builderClass.superClass;
    if superClass is string && superClass != "java.lang.Object" && superClass != "" {
        string[] superCandidates = normalizeCandidateTypeNames(superClass);
        if superCandidates.length() == 0 {
            superCandidates.push(superClass);
        }
        foreach string superCandidate in superCandidates {
            if superCandidate == "" || superCandidate == "java.lang.Object" {
                continue;
            }
            ClassInfo? superInfo = findOrResolveClass(superCandidate, resolvedClasses, dependencyJarPaths);
            if superInfo is ClassInfo {
                log:printDebug("Recursing into builder superclass", sourceClass = builderClass.className, superClass = superCandidate, depth = depth);
                collectBuilderSetters(superInfo, resolvedClasses, dependencyJarPaths,
                        fields, visitedClasses, visitedFieldKeys, depth + 1);
                break;
            }
        }
    }

    // Interface recursion
    foreach string iface in builderClass.interfaces {
        string[] interfaceCandidates = normalizeCandidateTypeNames(iface);
        if interfaceCandidates.length() == 0 {
            interfaceCandidates.push(iface);
        }
        foreach string ifaceCandidate in interfaceCandidates {
            if ifaceCandidate == "" || ifaceCandidate == "java.lang.Object" {
                continue;
            }
            ClassInfo? ifaceInfo = findOrResolveClass(ifaceCandidate, resolvedClasses, dependencyJarPaths);
            if ifaceInfo is ClassInfo {
                log:printDebug("Recursing into builder interface", sourceClass = builderClass.className, iface = ifaceCandidate, depth = depth);
                collectBuilderSetters(ifaceInfo, resolvedClasses, dependencyJarPaths,
                        fields, visitedClasses, visitedFieldKeys, depth + 1);
                break;
            }
        }
    }
}

function buildConnectionFieldDedupKey(string fieldName, string fullType) returns string {
    return fieldName + "|" + fullType;
}

# Find all concrete implementations of an interface or abstract class.
#
# + interfaceFqn - Fully qualified name of the interface/abstract class to find implementations for
# + resolvedClasses - Already-loaded class pool (mutated: newly resolved impls are added)
# + dependencyJarPaths - Dependency JAR paths for Phase 2 scanning
# + return - All concrete implementing ClassInfo records found
function findInterfaceImplementors(
        string interfaceFqn,
        ClassInfo[] resolvedClasses,
        string[] dependencyJarPaths
) returns ClassInfo[] {
    ClassInfo[] impls = [];
    string ifaceSimple = extractSimpleTypeName(interfaceFqn);
    log:printInfo("Finding interface implementors",
        interfaceFqn = interfaceFqn, resolvedClassCount = resolvedClasses.length(),
        depJarCount = dependencyJarPaths.length());

    // Phase 1: scan already-resolved classes
    foreach ClassInfo candidate in resolvedClasses {
        if candidate.isAbstract || candidate.isInterface || candidate.isEnum {
            continue;
        }
        if isDisallowedConfigTypeClass(candidate.className) {
            continue;
        }
        boolean isImpl = false;
        foreach string iface in candidate.interfaces {
            if iface == interfaceFqn || iface.endsWith("." + ifaceSimple) {
                isImpl = true;
                break;
            }
        }
        if !isImpl {
            string? sc = candidate.superClass;
            if sc is string && (sc == interfaceFqn || sc.endsWith("." + ifaceSimple)) {
                isImpl = true;
            }
        }
        if isImpl {
            impls.push(candidate);
            log:printInfo("Phase 1: found implementation in resolved classes",
                interfaceFqn = interfaceFqn, implClass = candidate.className);
        }
    }
    log:printInfo("Phase 1 complete", interfaceFqn = interfaceFqn, phase1ImplCount = impls.length());

    // Phase 2: scan dependency JARs for additional implementations
    log:printInfo("Phase 2: scanning dependency JARs for implementors",
        interfaceFqn = interfaceFqn, depJarCount = dependencyJarPaths.length());
    string[] depImplementors = findImplementorsInJars(interfaceFqn, dependencyJarPaths);
    log:printInfo("Phase 2: JAR scan returned implementor names",
        interfaceFqn = interfaceFqn, rawCount = depImplementors.length(),
        names = string:'join(", ", ...depImplementors));
    foreach string implName in depImplementors {
        if isDisallowedConfigTypeClass(implName) {
            continue;
        }
        boolean alreadyFound = false;
        foreach ClassInfo existing in impls {
            if existing.className == implName {
                alreadyFound = true;
                break;
            }
        }
        if alreadyFound {
            continue;
        }
        ClassInfo? implClass = resolveClassFromJars(implName, dependencyJarPaths);
        if implClass is ClassInfo && !implClass.isAbstract && !implClass.isInterface && !implClass.isEnum {
            impls.push(implClass);
            log:printInfo("Phase 2: resolved implementation from JARs",
                interfaceFqn = interfaceFqn, implClass = implName);
        } else {
            log:printInfo("Phase 2: skipped implementor (abstract/interface/enum or unresolvable)",
                interfaceFqn = interfaceFqn, implName = implName,
                resolved = implClass is ClassInfo);
        }
    }

    log:printInfo("Interface implementor discovery complete",
        interfaceFqn = interfaceFqn, totalFound = impls.length());
    return impls;
}
