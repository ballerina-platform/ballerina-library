import ballerina/file;
import ballerina/io;

# Write generated connector files into the pre-existing template output directories.
#
# + clientCode - generated Ballerina client class code
# + typesCode - generated Ballerina types code
# + javaAdaptorCode - generated Java native adaptor code
# + sdkToken - root client name from SDK metadata, used for naming files and classes
# + outputDir - root output directory for generated artifacts
# + return - paths of the written files or an error if writing fails
public function writeConnectorArtifacts(string clientCode, string typesCode, string javaAdaptorCode,
        string sdkToken, string outputDir = "modules/connector_generator/output")
        returns record {|string clientPath; string typesPath; string nativePath;|}|error {
    return writeConnectorArtifactsWithNames(
            clientCode,
            typesCode,
            javaAdaptorCode,
            string `${sdkToken}_client.bal`,
            string `${sdkToken}_types.bal`,
            string `src/main/java/Native${sdkToken}Adaptor.java`,
            outputDir
    );
}

# Write generated connector files into the pre-existing template output directories with explicit file names.
#
# + clientCode - generated Ballerina client class code
# + typesCode - generated Ballerina types code
# + javaAdaptorCode - generated Java native adaptor code
# + clientFileName - output client file name
# + typesFileName - output types file name
# + nativeRelativePath - native adaptor path relative to output root
# + outputDir - root output directory for generated artifacts
# + return - paths of the written files or an error if writing fails
public function writeConnectorArtifactsWithNames(string clientCode, string typesCode, string javaAdaptorCode,
        string clientFileName, string typesFileName,
        string nativeRelativePath, string outputDir = "modules/connector_generator/output")
        returns record {|string clientPath; string typesPath; string nativePath;|}|error {
    string rootDir = outputDir.trim().length() == 0 ? "modules/connector_generator/output" : outputDir;
    string ballerinaDir = string `${rootDir}/ballerina`;
    string nativeRootDir = string `${rootDir}/native`;
    string nativePath = check resolveNativeJavaFilePath(nativeRootDir, nativeRelativePath);

    check ensureDir(ballerinaDir);
    check injectSdkDependency(nativeRootDir, rootDir, javaAdaptorCode);
    check injectBallerinaGradleDependency(ballerinaDir, rootDir, javaAdaptorCode);

    string clientPath = string `${ballerinaDir}/${clientFileName}`;
    string typesPath = string `${ballerinaDir}/${typesFileName}`;

    // Derive the correct fully-qualified class name from the actual Java file path.
    string? fqClassName = deriveJavaFqClassName(nativePath);
    string finalClientCode = fqClassName is string ? fixJavaMethodClassReferences(clientCode, fqClassName) : clientCode;
    string finalJavaCode = fqClassName is string ? fixJavaPackageDeclaration(javaAdaptorCode, fqClassName) : javaAdaptorCode;

    check io:fileWriteString(clientPath, finalClientCode);
    check io:fileWriteString(typesPath, typesCode);
    check io:fileWriteString(nativePath, finalJavaCode);

    return {
        clientPath: clientPath,
        typesPath: typesPath,
        nativePath: nativePath
    };
}

function ensureDir(string dirPath) returns error? {
    boolean exists = check file:test(dirPath, file:EXISTS);
    if !exists {
        check file:createDir(dirPath, file:RECURSIVE);
    }
}

function resolveNativeJavaFilePath(string nativeRootDir, string nativeRelativePath) returns string|error {
    string srcMainJava = string `${nativeRootDir}/src/main/java`;
    boolean srcExists = check file:test(srcMainJava, file:EXISTS);
    if srcExists {
        string leafDir = check findLeafDirectory(srcMainJava);
        string javaFileName = extractJavaFileName(nativeRelativePath);
        return string `${leafDir}/${javaFileName}`;
    }
    string fallback = toNativeSourcePath(nativeRootDir, nativeRelativePath);
    check ensureDir(parentDir(fallback));
    return fallback;
}

// Recursively descend into the single-child subdirectory chain until a leaf (no subdirs) is reached.
function findLeafDirectory(string dirPath) returns string|error {
    file:MetaData[] entries = check file:readDir(dirPath);
    string[] subDirs = [];
    foreach file:MetaData entry in entries {
        if entry.dir {
            subDirs.push(entry.absPath);
        }
    }
    if subDirs.length() == 1 {
        return findLeafDirectory(subDirs[0]);
    }
    return dirPath;
}

// Extract just the .java filename from a relative path.
function extractJavaFileName(string nativeRelativePath) returns string {
    string trimmed = nativeRelativePath.trim();
    int? idx = trimmed.lastIndexOf("/");
    string baseName = idx is int ? trimmed.substring(<int>idx + 1) : trimmed;
    if baseName.endsWith(".java") {
        return baseName;
    }
    return string `${baseName}.java`;
}

function toNativeSourcePath(string nativeRootDir, string nativeRelativePath) returns string {
    string trimmed = nativeRelativePath.trim();
    if trimmed.length() == 0 {
        return string `${nativeRootDir}/src/main/java/NativeAdaptor.java`;
    }
    if trimmed.startsWith("src/main/java/") {
        return string `${nativeRootDir}/${trimmed}`;
    }
    if trimmed.endsWith(".java") {
        return string `${nativeRootDir}/src/main/java/${trimmed}`;
    }
    return string `${nativeRootDir}/src/main/java/${trimmed}.java`;
}

function parentDir(string path) returns string {
    int? idx = path.lastIndexOf("/");
    if idx is int && idx > 0 {
        return path.substring(0, idx);
    }
    return ".";
}

// Inject the SDK implementation dependency.
function injectSdkDependency(string nativeRootDir, string rootDir, string javaAdaptorCode) returns error? {
    string buildGradlePath = string `${nativeRootDir}/build.gradle`;
    boolean buildExists = check file:test(buildGradlePath, file:EXISTS);
    if !buildExists {
        return;
    }

    string? sdkVersion = inferSdkVersionFromRootDir(rootDir);
    string? sdkArtifact = inferSdkArtifactFromRootDir(rootDir);
    string? sdkGroupId = inferSdkGroupIdFromImports(javaAdaptorCode, sdkArtifact);

    if !(sdkGroupId is string && sdkArtifact is string && sdkVersion is string) {
        return;
    }

    // Idempotency: skip if artifact already present in the file
    string buildGradleContent = check io:fileReadString(buildGradlePath);
    if buildGradleContent.includes(string `name: '${sdkArtifact}'`) {
        return;
    }

    // Write version property into root gradle.properties
    string propName = deriveSdkVersionPropertyName(<string>sdkArtifact);
    check ensureGradleProperty(rootDir, propName, <string>sdkVersion);

    // Inject implementation line inside the existing dependencies {} block.
    string sdkLine = "    implementation group: '" + <string>sdkGroupId + "', name: '" + <string>sdkArtifact + "', version: \"${" + propName + "}\"";

    int? depsStart = buildGradleContent.indexOf("dependencies {");
    if depsStart is int {
        int? depsEnd = buildGradleContent.indexOf("\n}", <int>depsStart);
        if depsEnd is int {
            string updated = buildGradleContent.substring(0, <int>depsEnd)
                + string `
${sdkLine}
`
                + buildGradleContent.substring(<int>depsEnd);
            check io:fileWriteString(buildGradlePath, updated);
            return;
        }
    }
}

// Inject all SDK-specific entries into ballerina/build.gradle.
function injectBallerinaGradleDependency(string ballerinaDir, string rootDir, string javaAdaptorCode) returns error? {
    string buildGradlePath = string `${ballerinaDir}/build.gradle`;
    boolean buildExists = check file:test(buildGradlePath, file:EXISTS);
    if !buildExists {
        return;
    }

    string? sdkVersion = inferSdkVersionFromRootDir(rootDir);
    string? sdkArtifact = inferSdkArtifactFromRootDir(rootDir);
    string? sdkGroupId = inferSdkGroupIdFromImports(javaAdaptorCode, sdkArtifact);

    if !(sdkGroupId is string && sdkArtifact is string && sdkVersion is string) {
        return;
    }

    string propName = deriveSdkVersionPropertyName(<string>sdkArtifact);
    string content = check io:fileReadString(buildGradlePath);
    boolean changed = false;

    string? packageName = readValueFromBallerinaGradle(ballerinaDir, "packageName");

    if !content.includes(string `name: '${sdkArtifact}'`) {
        string externalJarsLine = "    externalJars(group: '" + <string>sdkGroupId + "', name: '" + <string>sdkArtifact + "', version: \"${" + propName + "}\") {\n    }";
        int? depsStart = content.indexOf("dependencies {");
        if depsStart is int {
            int? depsEnd = content.indexOf("\n}", <int>depsStart);
            if depsEnd is int {
                content = content.substring(0, <int>depsEnd)
                    + string `
${externalJarsLine}
`
                    + content.substring(<int>depsEnd);
                changed = true;
            }
        }
    }

    if packageName is string {
        int? lastDot = (<string>packageName).lastIndexOf(".");
        string packagePrefix = lastDot is int ? (<string>packageName).substring(0, <int>lastDot) : <string>packageName;
        string sdkVersionPlaceholder = string `@${packagePrefix}.sdk.version@`;
        string tomlAssignLine = "        ballerinaTomlFile.text = newBallerinaToml";
        if !content.includes(string `newBallerinaToml.replace("${sdkVersionPlaceholder}"`) && content.includes(tomlAssignLine) {
            content = content.substring(0, <int>content.indexOf(tomlAssignLine))
                + string `        newBallerinaToml = newBallerinaToml.replace("${sdkVersionPlaceholder}", project.${propName})
`
                + content.substring(<int>content.indexOf(tomlAssignLine));
            changed = true;
        }
    }

    if changed {
        check io:fileWriteString(buildGradlePath, content);
    }
}

function readValueFromBallerinaGradle(string ballerinaDir, string varName) returns string? {
    string buildGradlePath = string `${ballerinaDir}/build.gradle`;
    string|error content = io:fileReadString(buildGradlePath);
    if content is error {
        return;
    }
    string pattern = string `def ${varName} = "`;
    int? idx = (<string>content).indexOf(pattern);
    if !(idx is int) {
        return;
    }
    int valueStart = <int>idx + pattern.length();
    int? quoteEnd = (<string>content).indexOf("\"", valueStart);
    if !(quoteEnd is int) {
        return;
    }
    return (<string>content).substring(valueStart, <int>quoteEnd);
}

function deriveSdkVersionPropertyName(string artifactId) returns string {
    return string `${artifactId}SdkVersion`;
}

function ensureGradleProperty(string rootDir, string propKey, string propValue) returns error? {
    string propsPath = string `${rootDir}/gradle.properties`;

    boolean exists = check file:test(propsPath, file:EXISTS);
    if !exists {
        check io:fileWriteString(propsPath, string `${propKey}=${propValue}\n`);
        return;
    }

    string content = check io:fileReadString(propsPath);
    if content.includes(string `${propKey}=`) {
        return;
    }

    check io:fileWriteString(propsPath, content.trim() + string `
${propKey}=${propValue}
`);
}

function inferSdkInfoFromSpecDir(string rootDir) returns record {|string artifact; string 'version;|}? {
    string specDir = string `${rootDir}/docs/spec`;
    boolean|error specExists = file:test(specDir, file:EXISTS);
    if !(specExists is boolean && specExists) {
        return;
    }
    file:MetaData[]|error entries = file:readDir(specDir);
    if entries is error {
        return;
    }
    string suffix = "-metadata.json";
    foreach file:MetaData entry in entries {
        if !entry.dir && entry.absPath.endsWith(suffix) {
            int? lastSlash = entry.absPath.lastIndexOf("/");
            string fileName = lastSlash is int ? entry.absPath.substring(<int>lastSlash + 1) : entry.absPath;
            string stem = fileName.substring(0, fileName.length() - suffix.length());
            string[] parts = splitOnChar(stem, "-");
            foreach int i in 0 ..< parts.length() {
                if isLikelyVersion(parts[i]) && i > 0 {
                    string artifact = string:'join("-", ...parts.slice(0, i));
                    string ver = string:'join("-", ...parts.slice(i));
                    return {artifact: artifact, 'version: ver};
                }
            }
        }
    }
    return;
}

// Split a string on a single-character delimiter without requiring a regex import.
function splitOnChar(string value, string delimiter) returns string[] {
    string[] parts = [];
    string remaining = value;
    while true {
        int? idx = remaining.indexOf(delimiter);
        if !(idx is int) {
            parts.push(remaining);
            break;
        }
        parts.push(remaining.substring(0, <int>idx));
        remaining = remaining.substring(<int>idx + 1);
    }
    return parts;
}

function inferSdkArtifactFromRootDir(string rootDir) returns string? {
    // Primary: read from metadata filename in docs/spec/
    record {|string artifact; string 'version;|}? specInfo = inferSdkInfoFromSpecDir(rootDir);
    if specInfo is record {|string artifact; string 'version;|} {
        return specInfo.artifact;
    }
    string resolvedRootDir = rootDir.endsWith("/native") ? rootDir.substring(0, rootDir.length() - 7) : rootDir;
    int? slashIndex = resolvedRootDir.lastIndexOf("/");
    string dirName = slashIndex is int ? resolvedRootDir.substring(<int>slashIndex + 1) : resolvedRootDir;
    int? dashIndex = dirName.lastIndexOf("-");
    if !(dashIndex is int) || dashIndex <= 0 {
        return;
    }
    string versionCandidate = dirName.substring(<int>dashIndex + 1);
    if isLikelyVersion(versionCandidate) {
        return dirName.substring(0, <int>dashIndex);
    }
    return;
}

function inferSdkGroupIdFromImports(string javaAdaptorCode, string? sdkArtifact) returns string? {
    string[] imports = extractExternalImports(javaAdaptorCode);
    if imports.length() == 0 {
        return;
    }

    if sdkArtifact is string {
        string marker = string `.${sdkArtifact}.`;
        foreach string importPath in imports {
            int? markerIndex = importPath.indexOf(marker);
            if markerIndex is int && markerIndex > 0 {
                string group = importPath.substring(0, <int>markerIndex);
                if group.endsWith(".services") {
                    return group.substring(0, group.length() - 9);
                }
                return group;
            }
        }
    }

    return firstSegments(imports[0], 2);
}

function extractExternalImports(string javaAdaptorCode) returns string[] {
    string[] imports = [];
    string remaining = javaAdaptorCode;

    while true {
        int? importIndex = remaining.indexOf("import ");
        if !(importIndex is int) {
            break;
        }

        string afterImport = remaining.substring(<int>importIndex + 7);
        int? semiIndex = afterImport.indexOf(";");
        if !(semiIndex is int) {
            break;
        }

        string importPath = afterImport.substring(0, <int>semiIndex).trim();
        if isExternalImport(importPath) && !containsStringValue(imports, importPath) {
            imports.push(importPath);
        }

        remaining = afterImport.substring(<int>semiIndex + 1);
    }

    return imports;
}

function isExternalImport(string importPath) returns boolean {
    if importPath.startsWith("static ") {
        return false;
    }
    return !importPath.startsWith("java.") &&
        !importPath.startsWith("javax.") &&
        !importPath.startsWith("jakarta.") &&
        !importPath.startsWith("io.ballerina.") &&
        !importPath.startsWith("org.ballerinalang.");
}

function firstSegments(string value, int count) returns string {
    int segmentCount = 0;
    foreach int i in 0 ..< value.length() {
        string ch = value.substring(i, i + 1);
        if ch == "." {
            segmentCount += 1;
            if segmentCount == count {
                return value.substring(0, i);
            }
        }
    }
    return value;
}

function inferSdkVersionFromRootDir(string rootDir) returns string? {
    // Primary: read from metadata filename in docs/spec/
    record {|string artifact; string 'version;|}? specInfo = inferSdkInfoFromSpecDir(rootDir);
    if specInfo is record {|string artifact; string 'version;|} {
        return specInfo.'version;
    }
    string resolvedRootDir = rootDir.endsWith("/native") ? rootDir.substring(0, rootDir.length() - 7) : rootDir;
    int? slashIndex = resolvedRootDir.lastIndexOf("/");
    string dirName = slashIndex is int ? resolvedRootDir.substring(<int>slashIndex + 1) : resolvedRootDir;
    int? dashIndex = dirName.lastIndexOf("-");
    if !(dashIndex is int) || dashIndex <= 0 || (<int>dashIndex + 1) >= dirName.length() {
        return;
    }
    string ver = dirName.substring(<int>dashIndex + 1);
    return isLikelyVersion(ver) ? ver : ();
}

function containsStringValue(string[] items, string expected) returns boolean {
    foreach string item in items {
        if item == expected {
            return true;
        }
    }
    return false;
}

function isLikelyVersion(string value) returns boolean {
    if value.length() == 0 {
        return false;
    }
    foreach int i in 0 ..< value.length() {
        string ch = value.substring(i, i + 1);
        if !"0123456789.".includes(ch) {
            return false;
        }
    }
    return true;
}

function deriveJavaFqClassName(string filePath) returns string? {
    string marker = "src/main/java/";
    int? markerIdx = filePath.indexOf(marker);
    if !(markerIdx is int) {
        return;
    }
    string relative = filePath.substring(<int>markerIdx + marker.length());
    if relative.endsWith(".java") {
        relative = relative.substring(0, relative.length() - 5);
    }
    // Replace all path separators with dots
    string fq = "";
    foreach int i in 0 ..< relative.length() {
        string ch = relative.substring(i, i + 1);
        fq = fq + (ch == "/" ? "." : ch);
    }
    return fq.length() > 0 ? fq : ();
}

function fixJavaMethodClassReferences(string clientCode, string fqClassName) returns string {
    string result = "";
    string remaining = clientCode;
    string classPrefix = "'class: \"";
    while true {
        int? prefixIdx = remaining.indexOf(classPrefix);
        if !(prefixIdx is int) {
            result = result + remaining;
            break;
        }
        int valueStart = <int>prefixIdx + classPrefix.length();
        int? quoteEnd = remaining.indexOf("\"", valueStart);
        if !(quoteEnd is int) {
            result = result + remaining;
            break;
        }
        result = result + remaining.substring(0, valueStart) + fqClassName;
        remaining = remaining.substring(<int>quoteEnd);
    }
    return result;
}

function fixJavaPackageDeclaration(string javaCode, string fqClassName) returns string {
    int? lastDot = fqClassName.lastIndexOf(".");
    if !(lastDot is int) {
        return javaCode;
    }
    string correctPackage = fqClassName.substring(0, <int>lastDot);
    string packageKeyword = "package ";
    int? pkgIdx = javaCode.indexOf(packageKeyword);
    if !(pkgIdx is int) {
        return javaCode;
    }
    int? semiIdx = javaCode.indexOf(";", <int>pkgIdx);
    if !(semiIdx is int) {
        return javaCode;
    }
    return javaCode.substring(0, <int>pkgIdx + packageKeyword.length())
        + correctPackage
        + javaCode.substring(<int>semiIdx);
}
