// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/file;
import ballerina/io;
import ballerina/regex;
import ballerina/time;
import wso2/connector_automator.utils;

# Main function that analyzes a Java SDK JAR file using JavaParser approach.
#
# + jarPath - Path to the JAR file (local filesystem path)
# + outputDir - Output directory for metadata and reports
# + config - Analyzer configuration
# + return - Analysis result or error
public function analyzeJavaSDK(string jarPath, string outputDir, AnalyzerConfig config)
        returns AnalysisResult|AnalyzerError {

    error? aiInitErr = utils:initAIService(config.quietMode);
    if aiInitErr is error {
        return error AnalyzerError(aiInitErr.message(), aiInitErr);
    }

    time:Utc startTime = time:utcNow();
    string[] warnings = [];

    printAnalyzerPlan(jarPath, outputDir, config.quietMode);

    // Step 1: Check if it's a Maven coordinate or local JAR
    boolean isMavenCoordinate = jarPath.includes(":") && !jarPath.includes("/") && !jarPath.includes("\\");

    if !isMavenCoordinate {
        // Validate local JAR file exists
        boolean jarExists = check file:test(jarPath, file:EXISTS);
        if !jarExists {
            return error AnalyzerError(string `JAR file not found: ${jarPath}`);
        }

    } else {
    }

    // Step 2: Create output directory if it doesn't exist
    boolean outputExists = check file:test(outputDir, file:EXISTS);
    if !outputExists {
        check file:createDir(outputDir, file:RECURSIVE);
    }

    // Step 3: Extract and analyze classes using JavaParser
    printAnalyzerStep(1, "Extracting classes", config.quietMode);

    ParsedJarResult|AnalyzerError analysisResult = analyzeJarWithDependencies(jarPath, config);
    if analysisResult is AnalyzerError {
        return analysisResult;
    }
    ClassInfo[] rawClasses = analysisResult.classes;
    string[] dependencyJarPaths = analysisResult.dependencyJarPaths;

    if !config.quietMode {
        io:println(string `  → Found ${rawClasses.length()} classes`);
        if dependencyJarPaths.length() > 1 {
            io:println(string `  → ${dependencyJarPaths.length()} dependency JARs available for class resolution`);
        }
    }

    check writeClassList(outputDir, rawClasses);

    // Step 4: Filter relevant classes for client identification

    ClassInfo[] filteredClasses = [];
    foreach ClassInfo cls in rawClasses {
        if isRelevantClientClass(cls) {
            filteredClasses.push(cls);
        }
    }

    if !config.quietMode {
        io:println(string `  → ${filteredClasses.length()} relevant client classes`);
    }

    if filteredClasses.length() == 0 {
        return error AnalyzerError("No relevant client classes found in the JAR");
    }

    // Write filtered class list
    check writeFilteredClassList(outputDir, filteredClasses);

    // Step 5: Identify root client class using LLM with weighted scoring
    printAnalyzerStep(2, "Identifying root client", config.quietMode);

    // Increase candidate shortlist to give the LLM more options for side-by-side comparison
        [ClassInfo, LLMClientScore][]|AnalyzerError clientResult = identifyClientClassWithLLM(filteredClasses, 20);
    if clientResult is AnalyzerError {
        return clientResult;
    }

    // Get top 5 candidates with scores
    [ClassInfo, LLMClientScore][] topCandidates = clientResult;

    ClassInfo rootClient = selectRootClientCandidate(topCandidates);

    if !config.quietMode {
        io:println(string `  → Root client: ${rootClient.simpleName}`);
    }

    // Step 6: Detect client initialization pattern (LLM-only)
    printAnalyzerStep(3, "Detecting init pattern", config.quietMode);

    ClientInitPattern|AnalyzerError clientInitResult = detectClientInitPatternWithLLM(rootClient, rawClasses, dependencyJarPaths);
    if clientInitResult is AnalyzerError {
        return clientInitResult;
    }
    ClientInitPattern clientInitPattern = clientInitResult;

    // Step 7: Extract public methods from root client
    printAnalyzerStep(4, "Extracting and ranking methods", config.quietMode);

    // Pass rawClasses so delegate traversal can resolve sub-client return types
    MethodInfo[] publicMethods = extractPublicMethods(rootClient, rawClasses);
    int totalPublicMethods = publicMethods.length();

    if !config.quietMode {
        io:println(string `  → ${totalPublicMethods} methods`);
    }

    // Step 8: Rank methods by usage using LLM
    MethodInfo[]|AnalyzerError rankedResult = rankMethodsByUsageWithLLM(publicMethods);
    if rankedResult is AnalyzerError {
        return rankedResult;
    }
    MethodInfo[] selectedMethods = rankedResult;

    if !config.quietMode {
        io:println(string `  → ${selectedMethods.length()} methods selected`);
    }

    // Step 9: Generate structured metadata
    printAnalyzerStep(5, "Generating metadata", config.quietMode);

    // Pass the full set of extracted classes
    StructuredSDKMetadata structuredMetadata = generateStructuredMetadata(
            rootClient,
            clientInitPattern,
            selectedMethods,
            rawClasses,
            dependencyJarPaths,
            config
    );
    // Step 10: Create final metadata object
    time:Utc endTime = time:utcNow();
    decimal duration = time:utcDiffSeconds(endTime, startTime);
    int durationMs = <int>(duration * 1000);

    // Step 11: Write outputs
    // Write structured metadata JSON with SDK simple name
    string sdkSimpleName = extractDatasetKeyFromJarPath(jarPath);
    check writeStructuredMetadata(structuredMetadata, outputDir, sdkSimpleName);
    string metadataPath = string `${outputDir}/${sdkSimpleName}-metadata.json`;

    if !config.quietMode {
        io:println(string `  → Output: ${metadataPath}`);
    }

    // Clean up intermediate class listing files
    do { check file:remove(string `${outputDir}/classes.txt`); } on fail { }
    do { check file:remove(string `${outputDir}/filtered-classes.txt`); } on fail { }

    // Calculate final duration
    time:Utc finalEndTime = time:utcNow();
    decimal finalDuration = time:utcDiffSeconds(finalEndTime, startTime);

    if !config.quietMode {
        printAnalyzerSummary(metadataPath, selectedMethods.length(), finalDuration);
    }

    return {
        success: true,
        metadataPath: metadataPath,
        classesAnalyzed: 1,
        methodsExtracted: selectedMethods.length(),
        durationMs: durationMs,
        warnings: warnings
    };
}

function selectRootClientCandidate([ClassInfo, LLMClientScore][] topCandidates) returns ClassInfo {

    int syncIndex = -1;
    foreach int i in 0 ..< topCandidates.length() {
        ClassInfo c = <ClassInfo>topCandidates[i][0];
        string lname = c.simpleName.toLowerAscii();
        if !lname.includes("async") {
            syncIndex = i;
            break;
        }
    }

    decimal topScore = 0.0;
    [ClassInfo, LLMClientScore][] tied = [];
    if syncIndex != -1 {
        topScore = <decimal>topCandidates[syncIndex][1].totalScore;
        foreach var t in topCandidates {
            ClassInfo c = <ClassInfo>t[0];
            LLMClientScore s = <LLMClientScore>t[1];
            string lname = c.simpleName.toLowerAscii();
            if s.totalScore == topScore && !lname.includes("async") {
                tied.push([c, s]);
            } else if s.totalScore < topScore {
                break;
            }
        }
    } else {
        topScore = <decimal>topCandidates[0][1].totalScore;
        foreach var t in topCandidates {
            ClassInfo c = <ClassInfo>t[0];
            LLMClientScore s = <LLMClientScore>t[1];
            if s.totalScore == topScore {
                tied.push([c, s]);
            } else {
                break;
            }
        }
    }

    if tied.length() == 1 {
        return tied[0][0];
    }

    int bestMethods = -1;
    ClassInfo? bestCls = null;
    foreach var t in tied {
        ClassInfo c = <ClassInfo>t[0];
        if c.methods.length() > bestMethods {
            bestMethods = c.methods.length();
            bestCls = c;
        }
    }
    if bestCls is ClassInfo {
        return bestCls;
    }
    return topCandidates[0][0];
}

function printAnalyzerPlan(string jarPath, string outputDir, boolean quietMode) {
    if quietMode {
        return;
    }

    string sep = createAnalyzerSeparator("=", 70);
    io:println(sep);
    io:println("SDK Analysis Plan");
    io:println(sep);
    io:println(string `Source: ${jarPath}`);
    io:println(string `Output Dir: ${outputDir}`);
    io:println("");
    io:println("Operations:");
    io:println("  1. Extract and filter SDK classes");
    io:println("  2. Identify root client and init pattern");
    io:println("  3. Rank methods and generate metadata");
    io:println(sep);
}

function printAnalyzerSummary(string metadataPath, int methods, decimal duration) {
    string sep = createAnalyzerSeparator("=", 70);
    io:println("");
    io:println(sep);
    io:println("✓ SDK Analysis Complete");
    io:println(sep);
    io:println(string `  • metadata: ${metadataPath}`);
    io:println(string `  • methods extracted: ${methods}`);
    io:println(string `  • duration: ${duration}s`);
    io:println(sep);
}

function printAnalyzerStep(int stepNum, string title, boolean quietMode) {
    if quietMode {
        return;
    }
    string sep = createAnalyzerSeparator("-", 50);
    io:println("");
    io:println(string `Step ${stepNum}: ${title}`);
    io:println(sep);
}

function createAnalyzerSeparator(string char, int length) returns string {
    string[] chars = [];
    int i = 0;
    while i < length {
        chars.push(char);
        i += 1;
    }
    return string:'join("", ...chars);
}

# Check if a class is relevant for client identification
#
# + cls - ClassInfo to evaluate
# + return - true if relevant, false otherwise
function isRelevantClientClass(ClassInfo cls) returns boolean {

    string packageNameLower = cls.packageName.toLowerAscii();

    // Model packages contain DTOs, not clients
    if packageNameLower == "model" || packageNameLower.endsWith(".model") || packageNameLower.includes(".model.") {
        return false;
    }

    // Internal and implementation packages are never root client candidates.
    if packageNameLower.includes(".internal.") || packageNameLower.includes(".impl.") ||
        packageNameLower.endsWith(".internal") || packageNameLower.endsWith(".impl") {
        return false;
    }

    return true;
}

# Detect the client initialization pattern from constructors
#
# + clientClass - Root client ClassInfo
# + return - Initialization pattern description
function detectClientInitPattern(ClassInfo clientClass) returns string {
    if clientClass.constructors.length() == 0 {
        return "No public constructors found";
    }

    string[] patterns = [];
    foreach ConstructorInfo constructor in clientClass.constructors {
        if constructor.parameters.length() == 0 {
            patterns.push("Default constructor");
        } else {
            string[] paramTypes = constructor.parameters.map(p => p.typeName);
            patterns.push(string `Constructor(${string:'join(", ", ...paramTypes)})`);
        }
    }

    return string:'join(" | ", ...patterns);
}

# Detect the client initialization pattern from constructors returning ClientInitPattern record
#
# + clientClass - Root client ClassInfo
# + return - ClientInitPattern record
function detectClientInitPatternRecord(ClassInfo clientClass) returns ClientInitPattern {
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

# Build constructor signature
#
# + constructor - Constructor info
# + return - Constructor signature string
function buildConstructorSignature(ConstructorInfo constructor) returns string {
    string[] paramStrings = constructor.parameters.map(p => string `${p.typeName} ${p.name}`);
    return string `(${string:'join(", ", ...paramStrings)})`;
}

# Extract SDK version from JAR path
#
# + jarPath - Path to JAR file
# + return - Extracted version string
function extractSdkVersion(string jarPath) returns string {
    string[] pathParts = regex:split(jarPath, "/");
    string filename = pathParts[pathParts.length() - 1];

    // Remove .jar extension
    if filename.endsWith(".jar") {
        filename = filename.substring(0, filename.length() - 4);
    }

    // Look for version pattern (numbers with dots/dashes)
    string[] parts = regex:split(filename, "-");
    foreach string part in parts.reverse() {
        if regex:matches(part, "^[0-9]+\\.[0-9]+.*") {
            return part;
        }
    }

    return "unknown";
}

# Extract simple name from full class name
#
# + fullName - Full class name
# + return - Simple class name
function extractSimpleName(string fullName) returns string {
    string[] parts = regex:split(fullName, "\\.");
    return parts[parts.length() - 1];
}

function extractDatasetKeyFromJarPath(string jarPath) returns string {
    string[] pathParts = regex:split(jarPath, "/");
    string fileName = pathParts[pathParts.length() - 1];

    if fileName.toLowerAscii().endsWith(".jar") {
        fileName = fileName.substring(0, fileName.length() - 4);
    }

    if fileName.toLowerAscii().endsWith("-javadoc") {
        fileName = fileName.substring(0, fileName.length() - 8);
    }

    return fileName;
}

# Wrapper function for JavaParser analysis
#
# + jarPath - Path to JAR file  
# + config - Analyzer configuration (e.g., javadocPath) to pass to the Java interop layer
# + return - Array of ClassInfo or error
public function analyzeJarWithJavaParserWrapper(string jarPath, AnalyzerConfig config) returns ClassInfo[]|AnalyzerError {
    ClassInfo[]|error res = parseJarFromReference(jarPath, config);
    if res is error {
        return <AnalyzerError>res;
    }
    return res;
}

# Wrapper function for JavaParser analysis that also returns dependency JAR paths.
# This is useful for resolving external classes from dependency JARs.
#
# + jarPath - Path to JAR file  
# + config - Analyzer configuration to pass to the Java interop layer
# + return - ParsedJarResult containing classes and dependency paths, or error
public function analyzeJarWithDependencies(string jarPath, AnalyzerConfig config) returns ParsedJarResult|AnalyzerError {
    ParsedJarResult|error res = parseJarWithDependencies(jarPath, config);
    if res is error {
        return <AnalyzerError>res;
    }
    return res;
}

# Write structured metadata to file - stub implementation
#
# + metadata - Structured metadata to write
# + outputDir - Output directory for metadata JSON
# + sdkSimpleName - Simple name of the SDK for filename (default: "sdk")
# + return - Error if writing fails
function writeStructuredMetadata(StructuredSDKMetadata metadata, string outputDir, string sdkSimpleName = "sdk") returns error? {
    string metadataOutputDir = outputDir;
    string path = string `${metadataOutputDir}/${sdkSimpleName}-metadata.json`;
    json j = metadata;
    string content = prettyPrintJson(j, 0);
    boolean ok = check file:test(metadataOutputDir, file:EXISTS);
    if !ok {
        check file:createDir(metadataOutputDir, file:RECURSIVE);
    }
    check io:fileWriteString(path, content);
    return;
}

// Escape a string for inclusion in JSON
function escapeJsonString(string s) returns string {
    string out = "";
    int i = 0;
    while i < s.length() {
        string ch = s.substring(i, i + 1);
        if ch == "\\" {
            out += "\\\\";
        } else if ch == "\"" {
            out += "\\\"";
        } else if ch == "\n" {
            out += "\\n";
        } else if ch == "\r" {
            out += "\\r";
        } else if ch == "\t" {
            out += "\\t";
        } else {
            out += ch;
        }
        i += 1;
    }
    return out;
}

// Create indentation string (2 spaces per level)
function indentString(int level) returns string {
    int spaces = level * 2;
    string s = "";
    foreach int i in 0 ..< spaces {
        s += " ";
    }
    return s;
}

// Pretty-print JSON value recursively
function prettyPrintJson(json v, int indent) returns string {
    // Handle nil
    if v is () {
        return "null";
    }
    // Arrays
    if v is json[] {
        json[] arr = <json[]>v;
        if arr.length() == 0 {
            return "[]";
        }
        string out = "[\n";
        foreach int i in 0 ..< arr.length() {
            out += indentString(indent + 1) + prettyPrintJson(arr[i], indent + 1);
            if i < arr.length() - 1 {
                out += ",\n";
            } else {
                out += "\n";
            }
        }
        out += indentString(indent) + "]";
        return out;
    }

    // Objects (maps)
    if v is map<json> {
        map<json> m = <map<json>>v;
        string[] keys = m.keys();
        if keys.length() == 0 {
            return "{}";
        }

        string[] filteredKeys = [];
        foreach string k in keys {
            json val = m[k];
            boolean shouldOmit = false;
            if val is () {
                shouldOmit = true;
            } else if val is json[] {
                json[] arr = <json[]>val;
                if arr.length() == 0 {
                    shouldOmit = true;
                }
            }
            if !shouldOmit {
                filteredKeys.push(k);
            }
        }

        if filteredKeys.length() == 0 {
            return "{}";
        }

        string out = "{\n";
        foreach int i in 0 ..< filteredKeys.length() {
            string k = filteredKeys[i];
            json val = m[k];
            out += indentString(indent + 1) + "\"" + k + "\": " + prettyPrintJson(val, indent + 1);
            if i < filteredKeys.length() - 1 {
                out += ",\n";
            } else {
                out += "\n";
            }
        }
        out += indentString(indent) + "}";
        return out;
    }

    // Primitives
    if v is string {
        return "\"" + escapeJsonString(<string>v) + "\"";
    }
    if v is boolean {
        return v.toString();
    }
    if v is int {
        return v.toString();
    }
    if v is decimal {
        return v.toString();
    }

    // Fallback: use toString
    return v.toString();
}

# Write the list of all extracted classes to a text file for offline inspection
#
# + outputDir - Output directory to write the class list file
# + rawClasses - Array of ClassInfo representing all extracted classes from the JAR
# + return - Error if writing fails, otherwise nil
function writeClassList(string outputDir, ClassInfo[] rawClasses) returns error? {
    string path = string `${outputDir}/classes.txt`;
    string[] lines = [];
    foreach int i in 0 ..< rawClasses.length() {
        ClassInfo rc = rawClasses[i];
        lines.push(string `${i + 1}. ${rc.simpleName} - ${rc.packageName}`);
    }
    string content = string:'join("\n", ...lines);

    boolean ok = check file:test(outputDir, file:EXISTS);
    if !ok {
        check file:createDir(outputDir, file:RECURSIVE);
    }
    check io:fileWriteString(path, content);
    return;
}

# Write the list of filtered classes (those considered for client identification)
#
# + outputDir - Output directory to write the class list file  
# + filteredClasses - Array of ClassInfo representing filtered classes
# + return - return value description
function writeFilteredClassList(string outputDir, ClassInfo[] filteredClasses) returns error? {
    string path = string `${outputDir}/filtered-classes.txt`;
    string[] lines = [];
    foreach int i in 0 ..< filteredClasses.length() {
        ClassInfo rc = filteredClasses[i];
        lines.push(string `${i + 1}. ${rc.simpleName} - ${rc.packageName} | methods: ${rc.methods.length()} | interface: ${rc.isInterface}`);
    }
    string content = string:'join("\n", ...lines);

    boolean ok = check file:test(outputDir, file:EXISTS);
    if !ok {
        check file:createDir(outputDir, file:RECURSIVE);
    }
    check io:fileWriteString(path, content);
    return;
}
