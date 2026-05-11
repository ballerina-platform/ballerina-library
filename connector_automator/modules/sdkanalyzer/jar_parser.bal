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
import ballerina/jballerina.java;
import ballerina/log;
import ballerina/regex;

# Resolve Maven coordinate or local JAR path
#
# + sdkRef - Maven coordinate (e.g., "s3:2.25.16") or local JAR path
# + config - Optional analyzer config for resolution options
# + return - Resolved JAR information or error
public function resolveSDKReference(string sdkRef, AnalyzerConfig? config = ()) returns map<json>|error {
    string refKind = (sdkRef.includes(":") && !sdkRef.includes("/") && !sdkRef.includes("\\")) ? "maven" : "local";
    log:printInfo("Resolving SDK reference", refType = refKind, sdkRef = sdkRef);
    if sdkRef.includes(":") && !sdkRef.includes("/") && !sdkRef.includes("\\") {
        map<json> options = {
            maxDepth: 3,
            offlineMode: false,
            resolveDependencies: true
        };

        if config is AnalyzerConfig {
            options["maxDepth"] = config.maxDependencyDepth;
            options["offlineMode"] = config.offlineMode;
            options["resolveDependencies"] = config.resolveDependencies;
        }

        if regex:split(sdkRef, ":").length() < 3 {
            return error(string `Maven coordinate must be in groupId:artifactId:version format (e.g. 'software.amazon.awssdk:s3:2.31.66'), got: '${sdkRef}'`);
        }
        json result = check resolveMavenArtifactWithOptions(sdkRef, options);
        map<json> resolved = <map<json>>result;
        int depCount = resolved.hasKey("allJars") ? (<json[]>resolved["allJars"]).length() : 0;
        log:printInfo("Maven artifact resolved", mainJar = resolved.hasKey("mainJar") ? resolved["mainJar"].toString() : sdkRef, totalJars = depCount);
        return resolved;
    } else {
        string[] allJars = [sdkRef];

        map<boolean> knownFilenames = {[getJarFilename(sdkRef)]: true};

        string? parentDir = getParentDirectory(sdkRef);
        if parentDir is string {
            string[]|error jarFiles = findJarsInDirectory(parentDir);
            if jarFiles is string[] {
                foreach string jarPath in jarFiles {
                    string lowerPath = jarPath.toLowerAscii();
                    if jarPath != sdkRef &&
                        !lowerPath.includes("javadoc") &&
                        !lowerPath.includes("sources") {
                        allJars.push(jarPath);
                        knownFilenames[getJarFilename(jarPath)] = true;
                    }
                }
            }
        }

        log:printDebug("Local JARs collected from directory", jarCount = allJars.length(), mainJar = sdkRef);
        boolean resolveTransitive = true;
        int maxDepth = 3;
        if config is AnalyzerConfig {
            resolveTransitive = config.resolveDependencies && !config.offlineMode;
            maxDepth = config.maxDependencyDepth;
        }

        if resolveTransitive {
            string? inferredCoord = extractMavenCoordinateFromJar(sdkRef) ?: inferMavenCoordinateFromJarPath(sdkRef);
            if inferredCoord is string {
                string[] transitiveJars = resolveTransitiveJarPaths(inferredCoord, maxDepth);
                foreach string transitiveJar in transitiveJars {
                    string fname = getJarFilename(transitiveJar);
                    string lowerFname = fname.toLowerAscii();
                    if !knownFilenames.hasKey(fname) &&
                        !lowerFname.includes("javadoc") &&
                        !lowerFname.includes("sources") {
                        allJars.push(transitiveJar);
                        knownFilenames[fname] = true;
                    }
                }
            }
        }

        log:printInfo("Local JAR resolved with all dependencies", mainJar = sdkRef, totalJars = allJars.length());
        return {
            "mainJar": sdkRef,
            "allJars": allJars,
            "groupId": "",
            "artifactId": "",
            "version": "",
            "cacheDir": ""
        };
    }
}

# Get parent directory from a file path
#
# + filePath - Input file path
# + return - Parent directory path or null if not found
function getParentDirectory(string filePath) returns string? {
    // Find last path separator
    int? lastSlash = filePath.lastIndexOf("/");
    int? lastBackSlash = filePath.lastIndexOf("\\");

    int separatorIdx = -1;
    if lastSlash is int && lastSlash >= 0 {
        separatorIdx = lastSlash;
    }
    if lastBackSlash is int && lastBackSlash > separatorIdx {
        separatorIdx = lastBackSlash;
    }

    if separatorIdx > 0 {
        return filePath.substring(0, separatorIdx);
    }
    return ();
}

# Find all JAR files in a directory
#
# + dirPath - Directory path to search for JAR files
# + return - Array of JAR file paths or error
function findJarsInDirectory(string dirPath) returns string[]|error {
    string[] jars = [];

    file:MetaData[] entries = check file:readDir(dirPath);
    foreach file:MetaData entry in entries {
        string name = entry.absPath;
        if name.toLowerAscii().endsWith(".jar") && !entry.dir {
            jars.push(name);
        }
    }

    return jars;
}

# Parse JAR file and extract class information.
# Supports both local JAR paths and Maven resolution results.
#
# + sdkRef - Maven coordinate or local JAR path
# + config - Analyzer configuration (includes optional javadocPath)
# + return - Array of class information or error
public function parseJarFromReference(string sdkRef, AnalyzerConfig config) returns ClassInfo[]|error {
    map<json>|error resolvedResult = resolveSDKReference(sdkRef, config);
    if resolvedResult is error {
        return resolvedResult;
    }
    return parseClassesFromResolved(resolvedResult, config);
}

# Parse classes from an already-resolved SDK reference map.
# Shared by parseJarFromReference and parseJarWithDependencies to avoid double resolution.
#
# + resolved - Already-resolved reference map (from resolveSDKReference)
# + config - Analyzer configuration
# + return - Array of class information or error
function parseClassesFromResolved(map<json> resolved, AnalyzerConfig config) returns ClassInfo[]|error {
    if config.javadocPath is string {
        resolved["javadocPath"] = config.javadocPath;
    }

    json result = analyzeJarWithJavaParserExternal(resolved);

    json[] classArray = <json[]>result;

    ClassInfo[] classes = [];

    foreach json item in classArray {
        map<json> classMap = <map<json>>item;

        // Compute packageName if missing
        if !classMap.hasKey("packageName") {
            string className = classMap["className"].toString();
            classMap["packageName"] = computePackageName(className);
        }

        // Compute simpleName if missing
        if !classMap.hasKey("simpleName") {
            string className = classMap["className"].toString();
            classMap["simpleName"] = computeSimpleName(className);
        }

        // Ensure class-level defaults
        if !classMap.hasKey("isInterface") {
            classMap["isInterface"] = false;
        }
        if !classMap.hasKey("isAbstract") {
            classMap["isAbstract"] = false;
        }
        if !classMap.hasKey("isEnum") {
            classMap["isEnum"] = false;
        }
        if !classMap.hasKey("isDeprecated") {
            classMap["isDeprecated"] = false;
        }
        if !classMap.hasKey("interfaces") {
            classMap["interfaces"] = [];
        }
        if !classMap.hasKey("annotations") {
            classMap["annotations"] = [];
        }

        // Normalize methods
        if classMap.hasKey("methods") {
            json[] methods = <json[]>classMap["methods"];
            foreach json m in methods {
                map<json> mMap = <map<json>>m;
                if !mMap.hasKey("returnType") {
                    mMap["returnType"] = "";
                }
                if !mMap.hasKey("exceptions") {
                    mMap["exceptions"] = [];
                }
                if !mMap.hasKey("isStatic") {
                    mMap["isStatic"] = false;
                }
                if !mMap.hasKey("isFinal") {
                    mMap["isFinal"] = false;
                }
                if !mMap.hasKey("isAbstract") {
                    mMap["isAbstract"] = false;
                }
                if !mMap.hasKey("signature") {
                    if mMap.hasKey("name") {
                        mMap["signature"] = mMap["name"];
                    } else {
                        mMap["signature"] = "";
                    }
                }
                if !mMap.hasKey("typeParameters") {
                    mMap["typeParameters"] = [];
                }
                if !mMap.hasKey("annotations") {
                    mMap["annotations"] = [];
                }

                // Normalize parameters
                if mMap.hasKey("parameters") {
                    json[] params = <json[]>mMap["parameters"];
                    foreach json p in params {
                        map<json> pMap = <map<json>>p;
                        if pMap.hasKey("type") && !pMap.hasKey("typeName") {
                            pMap["typeName"] = pMap["type"];
                        }
                        if !pMap.hasKey("typeName") {
                            pMap["typeName"] = "";
                        }
                        if !pMap.hasKey("name") {
                            pMap["name"] = "";
                        }
                        if !pMap.hasKey("isVarArgs") {
                            pMap["isVarArgs"] = false;
                        }
                        if !pMap.hasKey("typeArguments") {
                            pMap["typeArguments"] = [];
                        }
                        if !pMap.hasKey("requestFields") {
                            pMap["requestFields"] = [];
                        }
                    }
                } else {
                    mMap["parameters"] = [];
                }
            }
        } else {
            classMap["methods"] = [];
        }

        // Normalize fields
        if classMap.hasKey("fields") {
            json[] flds = <json[]>classMap["fields"];
            foreach json f in flds {
                map<json> fMap = <map<json>>f;
                if fMap.hasKey("type") && !fMap.hasKey("typeName") {
                    fMap["typeName"] = fMap["type"];
                }
                if !fMap.hasKey("typeName") {
                    fMap["typeName"] = "";
                }
                if !fMap.hasKey("name") {
                    fMap["name"] = "";
                }
                if !fMap.hasKey("isStatic") {
                    fMap["isStatic"] = false;
                }
                if !fMap.hasKey("isFinal") {
                    fMap["isFinal"] = false;
                }
                if !fMap.hasKey("isDeprecated") {
                    fMap["isDeprecated"] = false;
                }
            }
        } else {
            classMap["fields"] = [];
        }

        // Normalize constructors
        if classMap.hasKey("constructors") {
            json[] ctors = <json[]>classMap["constructors"];
            foreach json c in ctors {
                map<json> cMap = <map<json>>c;
                if !cMap.hasKey("isDeprecated") {
                    cMap["isDeprecated"] = false;
                }
                if !cMap.hasKey("javadoc") {
                    cMap["javadoc"] = null;
                }
                if cMap.hasKey("parameters") {
                    json[] params = <json[]>cMap["parameters"];
                    foreach json p in params {
                        map<json> pMap = <map<json>>p;
                        if pMap.hasKey("type") && !pMap.hasKey("typeName") {
                            pMap["typeName"] = pMap["type"];
                        }
                        if !pMap.hasKey("typeName") {
                            pMap["typeName"] = "";
                        }
                        if !pMap.hasKey("name") {
                            pMap["name"] = "";
                        }
                        if !pMap.hasKey("isVarArgs") {
                            pMap["isVarArgs"] = false;
                        }
                    }
                } else {
                    cMap["parameters"] = [];
                }
                if !cMap.hasKey("exceptions") {
                    cMap["exceptions"] = [];
                }
            }
        } else {
            classMap["constructors"] = [];
        }

        // Ensure unresolved flag present
        if !classMap.hasKey("unresolved") {
            classMap["unresolved"] = false;
        }

        // Manually construct ClassInfo to avoid cloneWithType conversion issues
        ClassInfo cls = {
            className: classMap.hasKey("className") ? classMap["className"].toString() : "",
            packageName: classMap.hasKey("packageName") ? classMap["packageName"].toString() : "",
            isInterface: <boolean>classMap["isInterface"],
            isAbstract: <boolean>classMap["isAbstract"],
            isEnum: <boolean>classMap["isEnum"],
            simpleName: classMap.hasKey("simpleName") ? classMap["simpleName"].toString() : "",
            superClass: classMap.hasKey("superClass") && classMap["superClass"] != () ? classMap["superClass"].toString() : (),
            interfaces: toStringArray(classMap.hasKey("interfaces") ? <json[]>classMap["interfaces"] : ()),
            methods: convertMethods(classMap.hasKey("methods") ? <json[]>classMap["methods"] : ()),
            fields: convertFields(classMap.hasKey("fields") ? <json[]>classMap["fields"] : ()),
            constructors: convertConstructors(classMap.hasKey("constructors") ? <json[]>classMap["constructors"] : ()),
            isDeprecated: classMap.hasKey("isDeprecated") ? <boolean>classMap["isDeprecated"] : false,
            annotations: toStringArray(classMap.hasKey("annotations") ? <json[]>classMap["annotations"] : ()),
            genericSuperClass: classMap.hasKey("genericSuperClass") && classMap["genericSuperClass"] != () ? classMap["genericSuperClass"].toString() : "",
            unresolved: classMap.hasKey("unresolved") ? <boolean>classMap["unresolved"] : false
        };
        classes.push(cls);
    }

    return classes;
}

# Parse JAR file and extract class information along with dependency JAR paths.
# This variant is useful when you need to resolve external classes from dependencies.
#
# + sdkRef - Maven coordinate or local JAR path
# + config - Analyzer configuration (includes optional javadocPath)
# + return - ParsedJarResult containing classes and dependency JAR paths, or error
public function parseJarWithDependencies(string sdkRef, AnalyzerConfig config) returns ParsedJarResult|error {
    map<json>|error resolvedResult = resolveSDKReference(sdkRef, config);

    if resolvedResult is error {
        return resolvedResult;
    }

    map<json> resolved = resolvedResult;

    // Extract dependency JAR paths
    string[] depJarPaths = [];
    if resolved.hasKey("allJars") {
        json[]? allJarsJson = <json[]?>resolved["allJars"];
        if allJarsJson is json[] {
            foreach json jarPath in allJarsJson {
                depJarPaths.push(jarPath.toString());
            }
        }
    }
    log:printDebug("Dependency JARs extracted", sdkRef = sdkRef, depJarCount = depJarPaths.length());

    ClassInfo[]|error classesResult = parseClassesFromResolved(resolved, config);
    if classesResult is error {
        return classesResult;
    }
    log:printInfo("JAR parsed successfully", sdkRef = sdkRef, classCount = classesResult.length());

    return {
        classes: classesResult,
        dependencyJarPaths: depJarPaths
    };
}

# Parse JAR file and extract class information (legacy method for backward compatibility).
#
# + jarPath - Path to JAR file
# + return - Array of class information or error
public function parseJar(string jarPath) returns ClassInfo[]|error {
    AnalyzerConfig defaultConfig = {};
    return parseJarFromReference(jarPath, defaultConfig);
}

# Compute package name from fully qualified class name
#
# + className - Fully qualified class name
# + return - Package name
function computePackageName(string className) returns string {
    int? idx = className.lastIndexOf(".");
    return (idx is int && idx > 0) ? className.substring(0, idx) : "";
}

# Compute simple name from fully qualified class name
#
# + className - Fully qualified class name
# + return - Simple name
function computeSimpleName(string className) returns string {
    int? idx = className.lastIndexOf(".");
    return (idx is int && idx > 0) ? className.substring(idx + 1) : className;
}

function toStringArray(json[]? arr) returns string[] {
    if arr is json[] {
        string[] out = [];
        foreach json v in arr {
            out.push(v.toString());
        }
        return out;
    }
    return [];
}

function jpExtractSimpleTypeName(string fullType) returns string {
    if fullType == "" {
        return "arg";
    }
    int? idx = fullType.lastIndexOf(".");
    if idx is int {
        if idx >= 0 {
            return fullType.substring(idx + 1);
        }
    }
    return fullType;
}

function jpGenerateParamNameFromType(string fullType, int index) returns string {
    string simple = jpExtractSimpleTypeName(fullType);
    // make camelCase
    if simple.length() == 0 {
        return string `arg${index}`;
    }
    string first = simple.substring(0, 1).toLowerAscii();
    string rest = simple.substring(1);
    return string `${first}${rest}`;
}

function convertParameters(json[]? params) returns ParameterInfo[] {
    ParameterInfo[] out = [];
    if params is json[] {
        foreach json p in params {
            map<json> pMap = <map<json>>p;
            string tname = pMap.hasKey("typeName") ? pMap["typeName"].toString() : (pMap.hasKey("type") ? pMap["type"].toString() : "");
            string pname = pMap.hasKey("name") ? pMap["name"].toString() : "";
            if pname == "" || pname.startsWith("arg") {
                pname = jpGenerateParamNameFromType(tname, out.length() + 1);
            }

            RequestFieldInfo[] providedFields = [];
            if pMap.hasKey("requestFields") {
                json[] rf = <json[]>pMap["requestFields"];
                foreach json rfj in rf {
                    map<json> rfMap = <map<json>>rfj;
                    RequestFieldInfo rfi = {
                        name: rfMap.hasKey("name") ? rfMap["name"].toString() : "",
                        typeName: rfMap.hasKey("type") ? rfMap["type"].toString() : (rfMap.hasKey("typeName") ? rfMap["typeName"].toString() : ""),
                        fullType: rfMap.hasKey("fullType") ? rfMap["fullType"].toString() : (rfMap.hasKey("fullType") ? rfMap["fullType"].toString() : ""),
                        isRequired: rfMap.hasKey("isRequired") ? <boolean>rfMap["isRequired"] : false
                    };
                    if rfMap.hasKey("enumReference") {
                        rfi.enumReference = rfMap["enumReference"].toString();
                    }
                    if rfMap.hasKey("javadoc") && rfMap["javadoc"] != () {
                        rfi.description = rfMap["javadoc"].toString();
                    } else if rfMap.hasKey("description") && rfMap["description"] != () {
                        rfi.description = rfMap["description"].toString();
                    }
                    providedFields.push(rfi);
                }
            }

            ParameterInfo param = {
                name: pname,
                typeName: tname,
                requestFields: providedFields
            };
            out.push(param);
        }
    }
    return out;
}

// Convert methods array to MethodInfo[]
function convertMethods(json[]? methods) returns MethodInfo[] {
    MethodInfo[] out = [];
    if methods is json[] {
        foreach json m in methods {
            map<json> mMap = <map<json>>m;
            MethodInfo mi = {
                name: mMap.hasKey("name") ? mMap["name"].toString() : "",
                parameters: convertParameters(mMap.hasKey("parameters") ? <json[]>mMap["parameters"] : ()),
                returnType: mMap.hasKey("returnType") ? mMap["returnType"].toString() : "",
                description: mMap.hasKey("javadoc") && mMap["javadoc"] != () ? mMap["javadoc"].toString() : (),
                exceptions: toStringArray(mMap.hasKey("exceptions") ? <json[]>mMap["exceptions"] : ()),
                isStatic: mMap.hasKey("isStatic") ? <boolean>mMap["isStatic"] : false,
                isFinal: mMap.hasKey("isFinal") ? <boolean>mMap["isFinal"] : false,
                isAbstract: mMap.hasKey("isAbstract") ? <boolean>mMap["isAbstract"] : false,
                signature: mMap.hasKey("signature") ? mMap["signature"].toString() : (mMap.hasKey("name") ? mMap["name"].toString() : ""),
                isDeprecated: mMap.hasKey("isDeprecated") ? <boolean>mMap["isDeprecated"] : false,
                typeParameters: toStringArray(mMap.hasKey("typeParameters") ? <json[]>mMap["typeParameters"] : ()),
                annotations: toStringArray(mMap.hasKey("annotations") ? <json[]>mMap["annotations"] : ())
            };
            out.push(mi);
        }
    }
    return out;
}

// Convert fields array to FieldInfo[]
function convertFields(json[]? fields) returns FieldInfo[] {
    FieldInfo[] out = [];
    if fields is json[] {
        foreach json f in fields {
            map<json> fMap = <map<json>>f;
            FieldInfo fi = {
                name: fMap.hasKey("name") ? fMap["name"].toString() : "",
                typeName: fMap.hasKey("typeName") ? fMap["typeName"].toString() : (fMap.hasKey("type") ? fMap["type"].toString() : ""),
                isStatic: fMap.hasKey("isStatic") ? <boolean>fMap["isStatic"] : false,
                isFinal: fMap.hasKey("isFinal") ? <boolean>fMap["isFinal"] : false,
                javadoc: fMap.hasKey("javadoc") && fMap["javadoc"] != () ? fMap["javadoc"].toString() : (),
                literalValue: fMap.hasKey("literalValue") && fMap["literalValue"] != () ? fMap["literalValue"].toString() : (),
                isDeprecated: fMap.hasKey("isDeprecated") ? <boolean>fMap["isDeprecated"] : false
            };
            out.push(fi);
        }
    }
    return out;
}

// Convert constructors array to ConstructorInfo[]
function convertConstructors(json[]? ctors) returns ConstructorInfo[] {
    ConstructorInfo[] out = [];
    if ctors is json[] {
        foreach json c in ctors {
            map<json> cMap = <map<json>>c;
            ConstructorInfo ci = {
                parameters: convertParameters(cMap.hasKey("parameters") ? <json[]>cMap["parameters"] : ()),
                exceptions: toStringArray(cMap.hasKey("exceptions") ? <json[]>cMap["exceptions"] : ()),
                javadoc: cMap.hasKey("javadoc") && cMap["javadoc"] != () ? cMap["javadoc"].toString() : (),
                isDeprecated: cMap.hasKey("isDeprecated") ? <boolean>cMap["isDeprecated"] : false
            };
            out.push(ci);
        }
    }
    return out;
}

# External function to analyze JAR using JavaParser approach.
#
# + jarPathOrResolved - JAR file path or Maven resolution map
# + return - JSON array
function analyzeJarWithJavaParserExternal(string|map<json> jarPathOrResolved) returns json = @java:Method {
    'class: "io.ballerina.connector.automator.sdkanalyzer.JavaParserAnalyzer",
    name: "analyzeJarWithJavaParser",
    paramTypes: ["java.lang.Object"]
} external;

# External function to resolve a single class from JAR files.
# Used for lazy resolution of external dependency classes.
#
# + className - Fully qualified class name
# + jarPaths - Array of JAR file paths to search
# + return - Class info JSON or null if not found
function resolveClassFromJarsExternal(string className, string[] jarPaths) returns json? = @java:Method {
    'class: "io.ballerina.connector.automator.sdkanalyzer.JavaParserAnalyzer",
    name: "resolveClassFromJars",
    paramTypes: ["io.ballerina.runtime.api.values.BString", "io.ballerina.runtime.api.values.BArray"]
} external;

# Find all concrete classes in the given JAR files that directly implement or extend
# the specified interface or abstract class.
# Operates in metadata-only mode (no method-body parsing) for efficiency.
#
# + interfaceFqn - Fully qualified name of the target interface or abstract class
# + jarPaths - Array of JAR file paths to scan
# + return - Array of fully qualified class names that are concrete implementations
public function findImplementorsInJars(string interfaceFqn, string[] jarPaths) returns string[] {
    json result = findImplementorsInJarsExternal(interfaceFqn, jarPaths);
    json[] resultArr = result is json[] ? result : [];
    string[] names = [];
    foreach json item in resultArr {
        names.push(item.toString());
    }
    return names;
}

function findImplementorsInJarsExternal(string interfaceFqn, string[] jarPaths) returns json = @java:Method {
    'class: "io.ballerina.connector.automator.sdkanalyzer.JavaParserAnalyzer",
    name: "findImplementorsInJars",
    paramTypes: ["io.ballerina.runtime.api.values.BString", "io.ballerina.runtime.api.values.BArray"]
} external;

# Resolve a single class from dependency JARs.
#
# + className - Fully qualified class name to resolve
# + jarPaths - Array of JAR file paths to search
# + return - ClassInfo if found, () if not found
public function resolveClassFromJars(string className, string[] jarPaths) returns ClassInfo? {
    log:printDebug("Resolving class from JARs", className = className, jarCount = jarPaths.length());
    json? result = resolveClassFromJarsExternal(className, jarPaths);
    if result is () {
        log:printDebug("Class not found in JARs", className = className);
        return ();
    }

    map<json> classMap = <map<json>>result;

    // Ensure class-level defaults
    if !classMap.hasKey("isInterface") {
        classMap["isInterface"] = false;
    }
    if !classMap.hasKey("isAbstract") {
        classMap["isAbstract"] = false;
    }
    if !classMap.hasKey("isEnum") {
        classMap["isEnum"] = false;
    }
    if !classMap.hasKey("isDeprecated") {
        classMap["isDeprecated"] = false;
    }
    if !classMap.hasKey("interfaces") {
        classMap["interfaces"] = [];
    }
    if !classMap.hasKey("annotations") {
        classMap["annotations"] = [];
    }
    if !classMap.hasKey("methods") {
        classMap["methods"] = [];
    }
    if !classMap.hasKey("fields") {
        classMap["fields"] = [];
    }
    if !classMap.hasKey("constructors") {
        classMap["constructors"] = [];
    }

    string[] ifaces = [];
    json[]? ifacesJson = <json[]?>classMap["interfaces"];
    if ifacesJson is json[] {
        foreach json iface in ifacesJson {
            ifaces.push(iface.toString());
        }
    }

    string[] annots = [];
    json[]? annotsJson = <json[]?>classMap["annotations"];
    if annotsJson is json[] {
        foreach json ann in annotsJson {
            annots.push(ann.toString());
        }
    }

    string? superClassStr = ();
    json? superClassVal = classMap["superClass"];
    if superClassVal is string && superClassVal.length() > 0 {
        superClassStr = superClassVal;
    }

    string genericSuperStr = "";
    json? genericSuperVal = classMap["genericSuperClass"];
    if genericSuperVal is string && genericSuperVal.length() > 0 {
        genericSuperStr = genericSuperVal;
    }

    ClassInfo classInfo = {
        className: classMap["className"].toString(),
        packageName: classMap["packageName"].toString(),
        simpleName: classMap["simpleName"].toString(),
        superClass: superClassStr,
        isInterface: <boolean>classMap["isInterface"],
        isAbstract: <boolean>classMap["isAbstract"],
        isEnum: <boolean>classMap["isEnum"],
        isDeprecated: <boolean>classMap["isDeprecated"],
        interfaces: ifaces,
        annotations: annots,
        methods: convertMethods(<json[]?>classMap["methods"]),
        fields: convertFields(<json[]?>classMap["fields"]),
        constructors: convertConstructors(<json[]?>classMap["constructors"]),
        genericSuperClass: genericSuperStr
    };

    log:printDebug("Class resolved from JAR", className = className);
    return classInfo;
}

# Extract filtered javadoc for specific classes and members.
# This is more efficient than loading all javadoc entries.
#
# + javadocPath - Path to javadoc JAR file
# + classNames - Array of fully-qualified class names to extract
# + memberNames - Array of member names to extract (optional; if null/empty, extract all)
# + return - Map of class FQNs to member descriptions (as JSON)
public function extractFilteredJavadoc(string javadocPath, string[] classNames, string[] memberNames) returns map<string>|error {
    json result = extractFilteredJavadocExternal(javadocPath, classNames, memberNames);
    return <map<string>>result;
}

# External function to extract filtered javadoc.
#
# + javadocPath - Path to javadoc JAR file
# + classNames - Array of fully-qualified class names to extract
# + memberNames - Array of member names to extract (optional)
# + return - JSON map
function extractFilteredJavadocExternal(string javadocPath, string[] classNames, string[] memberNames) returns json = @java:Method {
    'class: "io.ballerina.connector.automator.sdkanalyzer.JavaParserAnalyzer",
    name: "extractFilteredJavadoc",
    paramTypes: ["io.ballerina.runtime.api.values.BString", "io.ballerina.runtime.api.values.BArray", "io.ballerina.runtime.api.values.BArray"]
} external;

# External function to resolve Maven artifact.
#
# + coordinate - Maven coordinate
# + return - Resolution result map
function resolveMavenArtifact(string coordinate) returns json = @java:Method {
    'class: "io.ballerina.connector.automator.sdkanalyzer.MavenResolver",
    name: "resolveMavenArtifact",
    paramTypes: ["io.ballerina.runtime.api.values.BString"]
} external;

# External function to resolve Maven artifact with options.
#
# + coordinate - Maven coordinate
# + options - Resolution options (e.g., maxDepth, offlineMode)
# + return - Resolution result map or error
function resolveMavenArtifactWithOptions(string coordinate, map<json> options) returns json|error = @java:Method {
    'class: "io.ballerina.connector.automator.sdkanalyzer.MavenResolver",
    name: "resolveMavenArtifactWithOptions",
    paramTypes: ["io.ballerina.runtime.api.values.BString", "io.ballerina.runtime.api.values.BMap"]
} external;

# Read the full Maven coordinate from the JAR's embedded META-INF/maven/*/pom.properties.
# Returns the full "groupId:artifactId:version" string, or () if the JAR has no Maven metadata.
#
# + jarPath - Path to the local JAR file
# + return - Full Maven coordinate string, or () if not found
function extractMavenCoordinateFromJar(string jarPath) returns string? = @java:Method {
    'class: "io.ballerina.connector.automator.sdkanalyzer.MavenResolver",
    name: "extractMavenCoordinateFromJar",
    paramTypes: ["io.ballerina.runtime.api.values.BString"]
} external;

# Extract the filename (last path component) from a file path.
#
# + filePath - Absolute or relative file path
# + return - Filename including extension
function getJarFilename(string filePath) returns string {
    int separatorIdx = -1;
    int? lastSlash = filePath.lastIndexOf("/");
    int? lastBackSlash = filePath.lastIndexOf("\\");
    if lastSlash is int && lastSlash > separatorIdx {
        separatorIdx = lastSlash;
    }
    if lastBackSlash is int && lastBackSlash > separatorIdx {
        separatorIdx = lastBackSlash;
    }
    if separatorIdx >= 0 && separatorIdx < filePath.length() - 1 {
        return filePath.substring(separatorIdx + 1);
    }
    return filePath;
}

# Infer a Maven coordinate from a JAR filename using the convention `<artifact>-<version>.jar`.
#
# + jarPath - Path to (or filename of) the JAR file
# + return - Maven coordinate string "artifact:version", or () if not parseable
function inferMavenCoordinateFromJarPath(string jarPath) returns string? {
    string filename = getJarFilename(jarPath);
    if !filename.endsWith(".jar") {
        return ();
    }
    string basename = filename.substring(0, filename.length() - 4);
    if basename.length() == 0 {
        return ();
    }

    string[] parts = regex:split(basename, "-");
    if parts.length() < 2 {
        return ();
    }

    int versionStartIdx = -1;
    foreach int i in 0 ..< parts.length() {
        string part = parts[i];
        if part.length() > 0 {
            string firstCh = part.substring(0, 1);
            if firstCh >= "0" && firstCh <= "9" {
                versionStartIdx = i;
                break;
            }
        }
    }

    if versionStartIdx <= 0 {
        return ();
    }

    string artifact = string:'join("-", ...parts.slice(0, versionStartIdx));
    string version = string:'join("-", ...parts.slice(versionStartIdx));
    if artifact.length() == 0 || version.length() == 0 {
        return ();
    }
    return string `${artifact}:${version}`;
}

# Attempt to resolve the transitive dependency JAR paths for the given Maven coordinate.
#
# + coordinate - Maven coordinate in the form "groupId:artifactId:version"
# + maxDepth - Maximum transitive dependency depth
# + return - List of resolved JAR file paths (may be empty)
function resolveTransitiveJarPaths(string coordinate, int maxDepth) returns string[] {
    map<json> options = {
        maxDepth: maxDepth,
        offlineMode: false,
        resolveDependencies: true
    };
    do {
        if regex:split(coordinate, ":").length() < 3 {
            return [];
        }
        json result = check resolveMavenArtifactWithOptions(coordinate, options);
        map<json> resolved = check result.ensureType();
        if !resolved.hasKey("allJars") {
            return [];
        }
        json[]? allJarsJson = <json[]?>resolved["allJars"];
        if allJarsJson is () {
            return [];
        }
        string[] jarPaths = [];
        foreach json j in allJarsJson {
            jarPaths.push(j.toString());
        }
        return jarPaths;
    } on fail {
        return [];
    }
}
