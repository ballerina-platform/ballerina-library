import ballerina/io;
import ballerina/regex;
import ballerina/time;

import wso2/connector_automator.api_specification_generator as api;
import wso2/connector_automator.utils;
import wso2/connector_automator.code_fixer as fixer;
import wso2/connector_automator.sdkanalyzer as analyzer;

# Generate connector artifacts from metadata JSON, IR JSON, and API spec.
#
# + config - Connector generator configuration, including input paths and generation options.
# + return - Connector generation result with artifact paths and generation stats, or error on failure.
public function generateConnector(ConnectorGeneratorConfig config)
        returns ConnectorGeneratorResult|ConnectorGeneratorError {
    time:Utc startTime = time:utcNow();

    printConnectorPlan(config);

    error? aiInit = utils:initAIService(config.quietMode);
    if aiInit is error {
        return error ConnectorGeneratorError("ANTHROPIC_API_KEY environment variable not set. " +
            "LLM is mandatory for connector generation.");
    }

    ConnectorGenerationInputs|error loaded = loadInputs(config);
    if loaded is error {
        return error ConnectorGeneratorError(string `Failed to load inputs: ${loaded.message()}`, loaded);
    }

    printConnectorStep(1, "Generating connector bundle via LLM", config.quietMode);
    GeneratedConnectorBundle|error bundleResult = generateConnectorBundleViaLLM(loaded, config);
    if bundleResult is error {
        return error ConnectorGeneratorError(
            string `LLM connector generation failed: ${bundleResult.message()}`,
            bundleResult);
    }
    GeneratedConnectorBundle bundle = bundleResult;
    bundle.typesBal = buildTypesBal(loaded.parsedSpec);
    bundle.clientBal = normalizeClientInteropDeclarations(bundle.clientBal);
    bundle.clientBal = applyClientDocsFromApiSpec(bundle.clientBal, loaded.apiSpecText);
    bundle.nativeAdaptorJava = normalizeNativeAdaptorWarnings(bundle.nativeAdaptorJava);

    printConnectorStep(2, "Validating generated connector bundle", config.quietMode);
    string[] validationFailures = [];
    error? validationError = validateGeneratedBundle(bundle, loaded);
    if validationError is error {
        validationFailures.push(validationError.message());
        if !config.quietMode {
            io:println("  → Validation reported issues. Artifacts will still be written for inspection.");
        }
    }

    string clientFileName = "client.bal";
    string typesFileName = "types.bal";
    string nativeSourcePath = normalizeNativeSourcePath(bundle.nativeAdaptorFilePath, bundle.nativeAdaptorClassName,
            "NativeAdaptor");

    printConnectorStep(3, "Writing generated connector artifacts", config.quietMode);
    record {|string clientPath; string typesPath; string nativePath;|}|error writeResult =
        writeConnectorArtifactsWithNames(
            bundle.clientBal,
            bundle.typesBal,
            bundle.nativeAdaptorJava,
            clientFileName,
            typesFileName,
            nativeSourcePath,
            config.outputDir);
    if writeResult is error {
        return error ConnectorGeneratorError(string `Failed to write connector artifacts: ${writeResult.message()}`,
            writeResult);
    }

    if validationFailures.length() > 0 {
        string validationSummary = "";
        foreach string failure in validationFailures {
            validationSummary += string `\n- ${failure}`;
        }
        return error ConnectorGeneratorError(
            string `Generated connector failed validation: Validation failures:${validationSummary}
Artifacts written for inspection:
  client: ${writeResult.clientPath}
  types:  ${writeResult.typesPath}
  native: ${writeResult.nativePath}`);
    }

    int mapped = countResolvedMappings(bundle.methodMappings, loaded.metadata.rootClient.methods);

    time:Utc endTime = time:utcNow();
    int durationMs = <int>(time:utcDiffSeconds(endTime, startTime) * 1000);

    printConnectorStep(4, "Connector generation completed successfully", config.quietMode);

    boolean codeFixingRan = false;
    boolean codeFixingSuccess = false;

    if config.enableCodeFixing {
        codeFixingRan = true;
        if !config.quietMode {
            io:println("Running post-generation native adaptor code fixing...");
        }

        boolean autoYes = config.fixMode != "report-only";
        string nativeProjectPath = string `${config.outputDir}/native`;
        fixer:FixResult|fixer:BallerinaFixerError fixResult = fixer:fixJavaNativeAdaptorErrors(nativeProjectPath,
                config.quietMode, autoYes, config.maxFixIterations);
        if fixResult is fixer:BallerinaFixerError {
            return error ConnectorGeneratorError(string `Code fixing failed: ${fixResult.message()}`, fixResult);
        }
        codeFixingSuccess = fixResult.success;
    }

    if !config.quietMode {
        printConnectorSummary(writeResult.clientPath, writeResult.typesPath, writeResult.nativePath, mapped, durationMs,
            codeFixingRan, codeFixingSuccess);
    }

    return {
        success: true,
        clientPath: writeResult.clientPath,
        typesPath: writeResult.typesPath,
        nativeAdaptorPath: writeResult.nativePath,
        mappedMethodCount: mapped,
        specMethodCount: loaded.parsedSpec.clientMethods.length(),
        durationMs: durationMs,
        codeFixingRan: codeFixingRan,
        codeFixingSuccess: codeFixingSuccess
    };
}

function printConnectorPlan(ConnectorGeneratorConfig config) {
    if config.quietMode {
        return;
    }
    string sep = createConnectorSeparator("=", 70);
    io:println(sep);
    io:println("Connector Generation Plan");
    io:println(sep);
    io:println(string `Metadata: ${config.metadataPath}`);
    io:println(string `IR: ${config.irPath}`);
    io:println(string `Spec: ${config.apiSpecPath}`);
    io:println(string `Output Dir: ${config.outputDir}`);
    io:println("");
    io:println("Operations:");
    io:println("  1. Generate connector bundle via LLM");
    io:println("  2. Validate generated artifacts");
    io:println("  3. Write Ballerina and Java outputs");
    io:println("  4. Optional post-generation code fixing");
    io:println(sep);
}

function printConnectorSummary(string clientPath, string typesPath, string nativePath, int mapped,
        int durationMs, boolean codeFixingRan, boolean codeFixingSuccess) {
    string sep = createConnectorSeparator("=", 70);
    io:println("");
    io:println(sep);
    io:println("✓ Connector Generation Complete");
    io:println(sep);
    io:println(string `  • client: ${clientPath}`);
    io:println(string `  • types: ${typesPath}`);
    io:println(string `  • native: ${nativePath}`);
    io:println(string `  • mapped methods: ${mapped}`);
    io:println(string `  • duration: ${durationMs}ms`);
    if codeFixingRan {
        io:println(string `  • code fixing: ${codeFixingSuccess ? "success" : "partial/failed"}`);
    }
    io:println(sep);
}

function printConnectorStep(int stepNum, string title, boolean quietMode) {
    if quietMode {
        return;
    }
    string sep = createConnectorSeparator("-", 50);
    io:println("");
    io:println(string `Step ${stepNum}: ${title}`);
    io:println(sep);
}

function createConnectorSeparator(string char, int length) returns string {
    string[] chars = [];
    int i = 0;
    while i < length {
        chars.push(char);
        i += 1;
    }
    return string:'join("", ...chars);
}

# CLI entrypoint for connector command.
#
# + args - Command-line arguments passed to the connector generator, including input paths and options.
# + return - Error on failure, or void on success.
public function executeConnectorGenerator(string[] args) returns error? {
    if args.length() < 4 {
        printConnectorUsage();
        return;
    }

    int idx = 1;
    if args[0] != "connector" {
        idx = 0;
    }

    if args.length() < idx + 3 {
        printConnectorUsage();
        return;
    }

    ConnectorGeneratorConfig config = {
        metadataPath: args[idx],
        irPath: args[idx + 1],
        apiSpecPath: args[idx + 2],
        outputDir: args.length() > idx + 3 ? args[idx + 3] : "./output"
    };

    int optionStart = args.length() > idx + 3 ? idx + 4 : idx + 3;
    foreach string arg in args.slice(optionStart) {
        if arg == "quiet" || arg == "--quiet" || arg == "-q" {
            config.quietMode = true;
        } else if arg == "--fix-code" {
            config.enableCodeFixing = true;
        } else if arg == "--fix-report-only" {
            config.enableCodeFixing = true;
            config.fixMode = "report-only";
        } else if arg.startsWith("--fix-iterations=") {
            string val = arg.substring(17);
            int|error parsed = int:fromString(val);
            if parsed is int {
                config.maxFixIterations = parsed;
            }
        }
    }

    ConnectorGeneratorResult|ConnectorGeneratorError result = generateConnector(config);
    if result is ConnectorGeneratorError {
        io:println(string `Connector generation failed: ${result.message()}`);
        return result;
    }

    io:println(string `Connector generated:`);
    io:println(string `  client: ${result.clientPath}`);
    io:println(string `  types:  ${result.typesPath}`);
    io:println(string `  native: ${result.nativeAdaptorPath}`);
    io:println(string `  mapped methods: ${result.mappedMethodCount}`);
    if result.codeFixingRan {
        io:println(string `  code fixing: ${result.codeFixingSuccess ? "success" : "partial/failed"}`);
    }
}

function loadInputs(ConnectorGeneratorConfig config) returns ConnectorGenerationInputs|error {
    string metadataText = check io:fileReadString(config.metadataPath);
    json|error metadataJson = metadataText.fromJsonString();
    if metadataJson is error {
        return error(string `Invalid metadata JSON: ${metadataJson.message()}`, metadataJson);
    }
    analyzer:StructuredSDKMetadata|error metadata = metadataJson.cloneWithType(analyzer:StructuredSDKMetadata);
    if metadata is error {
        return error(string `Metadata JSON does not match schema: ${metadata.message()}`, metadata);
    }

    string irText = check io:fileReadString(config.irPath);
    json|error irJson = irText.fromJsonString();
    if irJson is error {
        return error(string `Invalid IR JSON: ${irJson.message()}`, irJson);
    }
    api:IntermediateRepresentation|error ir = irJson.cloneWithType(api:IntermediateRepresentation);
    if ir is error {
        return error(string `IR JSON does not match schema: ${ir.message()}`, ir);
    }

    ParsedApiSpec|error parsedSpec = parseApiSpec(config.apiSpecPath);
    if parsedSpec is error {
        return error(string `Failed to parse API spec: ${parsedSpec.message()}`, parsedSpec);
    }

    string apiSpecText = check io:fileReadString(config.apiSpecPath);

    return {
        metadata: metadata,
        ir: ir,
        parsedSpec: parsedSpec,
        metadataJsonText: metadataText,
        irJsonText: irText,
        apiSpecText: apiSpecText
    };
}

function generateConnectorBundleViaLLM(ConnectorGenerationInputs loaded,
        ConnectorGeneratorConfig config) returns GeneratedConnectorBundle|error {
    string systemPrompt = getConnectorGenerationSystemPrompt();
    string userPrompt = getConnectorGenerationUserPrompt(
            loaded.metadataJsonText,
            loaded.irJsonText,
            loaded.apiSpecText,
            config.sdkVersionHint
    );

    string responseText = check utils:callAIAdvanced(userPrompt, systemPrompt, config.maxTokens,
            config.enableExtendedThinking, config.thinkingBudgetTokens);
    string bundleJsonText = check utils:extractJsonFromLLMResponse(responseText);

    json|error parsed = bundleJsonText.fromJsonString();
    if parsed is error {
        return error(string `LLM bundle JSON parse failed: ${parsed.message()}`);
    }
    GeneratedConnectorBundle|error bundle = parsed.cloneWithType(GeneratedConnectorBundle);
    if bundle is error {
        return error(string `LLM bundle schema mismatch: ${bundle.message()}`);
    }
    return bundle;
}

function validateGeneratedBundle(GeneratedConnectorBundle bundle,
        ConnectorGenerationInputs loaded) returns error? {
    if bundle.clientBal.trim().length() == 0 || bundle.typesBal.trim().length() == 0 ||
            bundle.nativeAdaptorJava.trim().length() == 0 {
        return error("Generated artifact code blocks must not be empty");
    }

    string[] specMethodNames = [];
    foreach SpecMethodSignature method in loaded.parsedSpec.clientMethods {
        specMethodNames.push(method.name);
    }

    foreach string specMethodName in specMethodNames {
        int occurrences = 0;
        foreach GeneratedMethodMapping mapping in bundle.methodMappings {
            if mapping.specMethod == specMethodName {
                occurrences += 1;
            }
        }
        if occurrences != 1 {
            return error(string `Expected exactly one mapping for '${specMethodName}', found ${occurrences}`);
        }
    }

    foreach GeneratedMethodMapping mapping in bundle.methodMappings {
        if !hasMethodByName(mapping.javaMethod, loaded.metadata.rootClient.methods) {
            return error(string `Mapped Java method not found in metadata root client: ${mapping.javaMethod}`);
        }
        if mapping.confidence < 0.0d || mapping.confidence > 1.0d {
            return error(string `Invalid mapping confidence for '${mapping.specMethod}': ${mapping.confidence}`);
        }
        foreach ParameterBinding binding in mapping.parameterBindings {
            if binding.specParam.trim().length() == 0 || binding.javaParam.trim().length() == 0 {
                return error(string `Invalid empty parameter binding in mapping '${mapping.specMethod}'`);
            }
        }
    }

    foreach string methodName in specMethodNames {
        if !bundle.clientBal.includes(string `function ${methodName}(`) {
            return error(string `Generated clientBal is missing method signature for '${methodName}'`);
        }
        if !bundle.nativeAdaptorJava.includes(string ` ${methodName}(`) {
            return error(string `Generated nativeAdaptorJava is missing method '${methodName}'`);
        }
    }

    string[] referencedTypeNames = collectReferencedTypeNamesFromSpec(loaded.parsedSpec);
    foreach string typeName in referencedTypeNames {
        if !hasDeclaredTypeOrEnum(bundle.typesBal, typeName) {
            return error(string `Generated typesBal is missing type declaration for '${typeName}' referenced by API spec signatures`);
        }
    }

    string expectedNativePath = deriveNativeSourcePathFromClass(bundle.nativeAdaptorClassName);
    if bundle.nativeAdaptorFilePath.trim() != expectedNativePath {
        return error(string `nativeAdaptorFilePath must be '${expectedNativePath}', found '${bundle.nativeAdaptorFilePath}'`);
    }

    string[] requiredNativeImports = [
        "import io.ballerina.runtime.api.Environment;",
        "import io.ballerina.runtime.api.creators.ErrorCreator;",
        "import io.ballerina.runtime.api.creators.ValueCreator;",
        "import io.ballerina.runtime.api.utils.StringUtils;",
        "import io.ballerina.runtime.api.values.BObject;"
    ];
    foreach string requiredImport in requiredNativeImports {
        if !bundle.nativeAdaptorJava.includes(requiredImport) {
            return error(string `Generated nativeAdaptorJava missing required import/prefix: ${requiredImport}`);
        }
    }

    error? interopValidationError = validateClientInteropDeclarations(bundle.clientBal);
    if interopValidationError is error {
        return interopValidationError;
    }

    error? nativeTypeImportValidationError = validateNativeTypeImports(bundle.nativeAdaptorJava);
    if nativeTypeImportValidationError is error {
        return nativeTypeImportValidationError;
    }

    error? nativeWarningValidationError = validateNativeWarningPatterns(bundle.nativeAdaptorJava);
    if nativeWarningValidationError is error {
        return nativeWarningValidationError;
    }

    if !bundle.validation.allSpecMethodsMapped || bundle.validation.unmappedSpecMethods.length() > 0 {
        return error("LLM validation indicates unmapped API spec methods");
    }
    if bundle.validation.signatureMismatches.length() > 0 {
        return error("LLM validation indicates signature mismatches");
    }
    if bundle.validation.typeReferenceErrors.length() > 0 {
        io:println(string `  ⚠  Type reference warnings (non-fatal): ${string:'join(", ", ...bundle.validation.typeReferenceErrors)}`);
    }
}

function validateClientInteropDeclarations(string clientBal) returns error? {
    int? classStartMaybe = clientBal.indexOf("public isolated client class Client {");
    int classStart = classStartMaybe is int ? classStartMaybe : -1;
    if classStart >= 0 {
        int depth = 0;
        boolean opened = false;
        int classEnd = -1;
        foreach int i in classStart ..< clientBal.length() {
            string ch = clientBal.substring(i, i + 1);
            if ch == "{" {
                depth += 1;
                opened = true;
            } else if ch == "}" {
                depth -= 1;
                if opened && depth == 0 {
                    classEnd = i;
                    break;
                }
            }
        }

        if classEnd > classStart {
            string classBlock = clientBal.substring(classStart, classEnd + 1);
            if classBlock.includes("= @java:Method") {
                return error("clientBal contains @java:Method external declarations inside Client class; move them to module-level functions outside the class");
            }
        }
    }

    boolean callsNativeInit = clientBal.includes("nativeInit(self, ") ||
        clientBal.includes("nativeInit(self,") ||
        clientBal.includes(" return nativeInit(");

    if callsNativeInit {
        boolean hasNativeInitDecl = clientBal.includes("function nativeInit(");
        boolean nativeInitBoundToJavaInit = clientBal.includes("name: \"init\"");
        if !hasNativeInitDecl || !nativeInitBoundToJavaInit {
            return error("clientBal has native init call but is missing matching external nativeInit declaration bound to Java method 'init'");
        }
    }
}

function normalizeClientInteropDeclarations(string clientBal) returns string {
    string[] lines = regex:split(clientBal, "\n");
    string[] normalizedLines = [];
    string[] moduleLevelExterns = [];

    boolean inClientClass = false;
    int classDepth = 0;
    int i = 0;
    while i < lines.length() {
        string line = lines[i];
        string trimmed = line.trim();

        if !inClientClass && trimmed.includes("client class Client") && trimmed.endsWith("{") {
            inClientClass = true;
            classDepth = 1;
            normalizedLines.push(line);
            i += 1;
            continue;
        }

        if inClientClass && trimmed.includes("= @java:Method") && trimmed.includes("function ") {
            string signature = line.substring(0, <int>line.indexOf("= @java:Method")).trim();
            string methodName = extractFunctionName(signature);
            string nativeFunctionName = methodName == "init" ? "nativeInit" : string `native${capitalizeFirst(methodName)}`;
            string paramSegment = extractParamSegment(signature);
            string returnType = extractReturnType(signature);
            string[] paramDecls = splitSignatureParameters(paramSegment);

            string[] wrapperArgNames = [];
            string[] moduleParamDecls = ["Client bClient"];
            foreach string paramDeclRaw in paramDecls {
                string paramDecl = paramDeclRaw.trim();
                if paramDecl.length() == 0 {
                    continue;
                }
                wrapperArgNames.push(extractParamName(paramDecl));
                moduleParamDecls.push(normalizeExternalParamDecl(paramDecl));
            }

            string indent = extractIndent(line);
            string wrapperArgs = wrapperArgNames.length() > 0
                ? string `self, ${string:'join(", ", ...wrapperArgNames)}`
                : "self";
            normalizedLines.push(string `${indent}${signature} {`);
            if returnType == "()" {
                normalizedLines.push(string `${indent}    ${nativeFunctionName}(${wrapperArgs});`);
                normalizedLines.push(string `${indent}    return;`);
            } else {
                normalizedLines.push(string `${indent}    return ${nativeFunctionName}(${wrapperArgs});`);
            }
            normalizedLines.push(string `${indent}}`);

            string[] annotationBlock = [];
            int j = i;
            while j < lines.length() {
                string annLine = lines[j];
                annotationBlock.push(annLine.trim());
                if annLine.trim().endsWith("} external;") {
                    break;
                }
                j += 1;
            }

            string annotationInline = string:'join(" ", ...annotationBlock);
            if annotationInline.startsWith(signature) {
                annotationInline = annotationInline.substring(signature.length()).trim();
            }
            if !annotationInline.startsWith("= @java:Method") {
                annotationInline = string `= @java:Method {${annotationInline}`;
            }
            // Ensure the @java:Method annotation binds to the original method name
            // (no native prefix) so Java adaptor methods match the spec method names.
            annotationInline = ensureJavaMethodName(annotationInline, methodName);

            string moduleSignature = string `function ${nativeFunctionName}(${string:'join(", ", ...moduleParamDecls)}) returns ${returnType}`;
            moduleLevelExterns.push(string `${moduleSignature} ${annotationInline}`);

            i = j + 1;
            continue;
        }

        normalizedLines.push(line);

        if inClientClass {
            classDepth += countChar(line, "{");
            classDepth -= countChar(line, "}");
            if classDepth <= 0 {
                inClientClass = false;
            }
        }

        i += 1;
    }

    string normalized = string:'join("\n", ...normalizedLines);
    if moduleLevelExterns.length() == 0 {
        return normalized;
    }

    return string `${normalized}\n\n${string:'join("\n\n", ...moduleLevelExterns)}\n`;
}

type ClientDocMap record {| 
    string[] classDoc;
    map<string[]> methodDocs;
|};

function applyClientDocsFromApiSpec(string clientBal, string apiSpecText) returns string {
    ClientDocMap docs = extractClientDocsFromApiSpec(apiSpecText);
    if docs.classDoc.length() == 0 && docs.methodDocs.keys().length() == 0 {
        return clientBal;
    }

    string[] lines = regex:split(clientBal, "\n");
    string[] output = [];
    boolean inClientClass = false;
    int classDepth = 0;
    int i = 0;

    while i < lines.length() {
        string line = lines[i];
        string trimmed = line.trim();

        if !inClientClass {
            if trimmed.startsWith("#") {
                int? nextIndex = nextNonEmptyLineIndex(lines, i + 1);
                if nextIndex is int {
                    string nextTrimmed = lines[<int>nextIndex].trim();
                    if nextTrimmed == "public isolated client class Client {" {
                        i += 1;
                        continue;
                    }
                }
            }

            if trimmed == "public isolated client class Client {" {
                foreach string docLine in docs.classDoc {
                    output.push(docLine);
                }
                output.push(line);
                inClientClass = true;
                classDepth = 1;
                i += 1;
                continue;
            }

            output.push(line);
            i += 1;
            continue;
        }

        if trimmed.startsWith("#") {
            i += 1;
            continue;
        }

        string? methodName = extractClientMethodName(trimmed);
        if methodName is string {
            string[]? methodDoc = docs.methodDocs.get(<string>methodName);
            if methodDoc is string[] {
                string indent = extractIndent(line);
                foreach string docLine in <string[]>methodDoc {
                    output.push(string `${indent}${docLine}`);
                }
            }
        }

        output.push(line);

        classDepth += countChar(line, "{");
        classDepth -= countChar(line, "}");
        if classDepth <= 0 {
            inClientClass = false;
            classDepth = 0;
        }

        i += 1;
    }

    return string:'join("\n", ...output);
}

function extractClientDocsFromApiSpec(string apiSpecText) returns ClientDocMap {
    ClientDocMap out = {
        classDoc: [],
        methodDocs: {}
    };

    string[] lines = regex:split(apiSpecText, "\n");
    int classLineIndex = -1;
    foreach int idx in 0 ..< lines.length() {
        if lines[idx].trim() == "public isolated client class Client {" {
            classLineIndex = idx;
            break;
        }
    }

    if classLineIndex < 0 {
        return out;
    }

    string[] classDoc = collectDocBlockAbove(lines, classLineIndex);
    if classDoc.length() > 0 {
        out.classDoc = classDoc;
    }

    int depth = 0;
    boolean entered = false;
    int i = classLineIndex;
    while i < lines.length() {
        string line = lines[i];
        string trimmed = line.trim();

        depth += countChar(line, "{");
        if countChar(line, "{") > 0 {
            entered = true;
        }

        if entered && depth == 0 {
            break;
        }

        string? methodName = extractClientMethodName(trimmed);
        if methodName is string {
            string[] methodDoc = collectDocBlockAbove(lines, i);
            if methodDoc.length() > 0 {
                out.methodDocs[<string>methodName] = methodDoc;
            }
        }

        depth -= countChar(line, "}");
        i += 1;
    }

    return out;
}

function collectDocBlockAbove(string[] lines, int lineIndex) returns string[] {
    string[] reversed = [];
    int i = lineIndex - 1;
    boolean started = false;

    while i >= 0 {
        string trimmed = lines[i].trim();
        if trimmed.startsWith("#") {
            reversed.push(trimmed);
            started = true;
            i -= 1;
            continue;
        }

        if started && trimmed.length() == 0 {
            i -= 1;
            continue;
        }
        break;
    }

    if reversed.length() == 0 {
        return [];
    }

    return reversed.reverse();
}

function extractClientMethodName(string trimmedLine) returns string? {
    if trimmedLine.startsWith("public isolated function init(") {
        return "init";
    }
    if !trimmedLine.startsWith("remote isolated function ") {
        return;
    }

    int nameStart = 25;
    int? paren = trimmedLine.indexOf("(");
    if paren is () || <int>paren <= nameStart {
        return;
    }

    return trimmedLine.substring(nameStart, <int>paren).trim();
}

function nextNonEmptyLineIndex(string[] lines, int fromIndex) returns int? {
    int i = fromIndex;
    while i < lines.length() {
        if lines[i].trim().length() > 0 {
            return i;
        }
        i += 1;
    }
    return;
}

function extractIndent(string line) returns string {
    int i = 0;
    while i < line.length() {
        string ch = line.substring(i, i + 1);
        if ch != " " && ch != "\t" {
            return line.substring(0, i);
        }
        i += 1;
    }
    return "";
}

function extractFunctionName(string signature) returns string {
    int? fnIndex = signature.indexOf("function ");
    if fnIndex is () {
        return "native";
    }
    int startIndex = <int>fnIndex + 9;
    int? end = signature.indexOf("(");
    if end is () || <int>end <= startIndex {
        return "native";
    }
    return signature.substring(startIndex, <int>end).trim();
}

function extractParamSegment(string signature) returns string {
    int? startIndex = signature.indexOf("(");
    int? end = signature.indexOf(") returns ");
    if startIndex is () || end is () || <int>end <= <int>startIndex {
        return "";
    }
    return signature.substring(<int>startIndex + 1, <int>end).trim();
}

function extractReturnType(string signature) returns string {
    int? returnsIndex = signature.indexOf(") returns ");
    if returnsIndex is () {
        return "error?";
    }
    return signature.substring(<int>returnsIndex + 10).trim();
}

function extractParamName(string paramDecl) returns string {
    string p = paramDecl.trim();
    if p.startsWith("*") {
        p = p.substring(1).trim();
    }
    int? eqIndex = p.indexOf("=");
    if eqIndex is int {
        p = p.substring(0, eqIndex).trim();
    }
    int? lastSpace = p.lastIndexOf(" ");
    if lastSpace is () {
        return p;
    }
    return p.substring(<int>lastSpace + 1).trim();
}

function normalizeExternalParamDecl(string paramDecl) returns string {
    string p = paramDecl.trim();
    if p.startsWith("*") {
        p = p.substring(1).trim();
    }
    int? eqIndex = p.indexOf("=");
    if eqIndex is int {
        p = p.substring(0, eqIndex).trim();
    }
    return p;
}

function capitalizeFirst(string value) returns string {
    if value.length() == 0 {
        return value;
    }
    string first = value.substring(0, 1).toUpperAscii();
    return value.length() == 1 ? first : string `${first}${value.substring(1)}`;
}

function countChar(string value, string ch) returns int {
    int count = 0;
    foreach int i in 0 ..< value.length() {
        if value.substring(i, i + 1) == ch {
            count += 1;
        }
    }
    return count;
}

function normalizeNativeAdaptorWarnings(string nativeAdaptorJava) returns string {
    string normalized = nativeAdaptorJava;
    normalized = replaceAllLiteral(normalized, "WithStrings(", "(");
    normalized = replaceAllLiteral(normalized, "catch (Exception e)", "catch (RuntimeException e)");
    return normalized;
}

function validateNativeWarningPatterns(string nativeAdaptorJava) returns error? {
    if nativeAdaptorJava.includes("WithStrings(") {
        return error("nativeAdaptorJava contains potentially deprecated '*WithStrings(...)' method usage; use non-deprecated alternatives");
    }
    if nativeAdaptorJava.includes("catch (Exception e)") {
        return error("nativeAdaptorJava contains broad catch(Exception e); use more specific catches or multi-catch");
    }
}

function replaceAllLiteral(string inputText, string needle, string replacement) returns string {
    if needle.length() == 0 || !inputText.includes(needle) {
        return inputText;
    }

    string out = "";
    int cursor = 0;
    while cursor < inputText.length() {
        int? hit = inputText.substring(cursor).indexOf(needle);
        if hit is () {
            out += inputText.substring(cursor);
            break;
        }
        int absolute = cursor + <int>hit;
        out += inputText.substring(cursor, absolute);
        out += replacement;
        cursor = absolute + needle.length();
    }
    return out;
}

function validateNativeTypeImports(string nativeAdaptorJava) returns error? {
    boolean hasRuntimeTypeImport = nativeAdaptorJava.includes("import io.ballerina.runtime.api.types.Type;");
    boolean hasModelTypeImport = false;
    string[] lines = regex:split(nativeAdaptorJava, "\n");
    foreach string line in lines {
        string trimmed = line.trim();
        if trimmed.startsWith("import ") && trimmed.endsWith(".model.Type;") {
            hasModelTypeImport = true;
            break;
        }
    }

    if hasRuntimeTypeImport && hasModelTypeImport {
        return error("nativeAdaptorJava has ambiguous Type imports: runtime Type and model.Type imported together");
    }
}

function countResolvedMappings(GeneratedMethodMapping[] mappings,
        analyzer:MethodInfo[] methods) returns int {
    int count = 0;
    foreach GeneratedMethodMapping mapping in mappings {
        if hasMethodByName(mapping.javaMethod, methods) {
            count += 1;
        }
    }
    return count;
}

function hasMethodByName(string methodName, analyzer:MethodInfo[] methods) returns boolean {
    foreach analyzer:MethodInfo method in methods {
        if method.name == methodName {
            return true;
        }
    }
    return false;
}

function normalizeBallerinaFileName(string suggestedName, string suffix) returns string {
    string trimmed = suggestedName.trim();
    if trimmed.length() == 0 {
        return string `generated_${suffix}`;
    }
    if trimmed.endsWith(".bal") {
        return trimmed;
    }
    return string `${trimmed}.bal`;
}

function normalizeJavaFileName(string className, string fallbackBaseName) returns string {
    string trimmed = className.trim();
    string base = trimmed.length() > 0 ? trimmed : fallbackBaseName;
    if base.endsWith(".java") {
        return base;
    }
    return string `${base}.java`;
}

function deriveNativeSourcePathFromClass(string nativeAdaptorClassName) returns string {
    string className = nativeAdaptorClassName.trim();
    if className.length() == 0 {
        return "src/main/java/NativeAdaptor.java";
    }
    string path = "";
    string remaining = className;
    while true {
        int? idx = remaining.indexOf(".");
        if idx is int {
            string token = remaining.substring(0, idx);
            path = path.length() == 0 ? token : string `${path}/${token}`;
            remaining = remaining.substring(idx + 1);
        } else {
            path = path.length() == 0 ? remaining : string `${path}/${remaining}`;
            break;
        }
    }
    return string `src/main/java/${path}.java`;
}

function normalizeNativeSourcePath(string suggestedPath, string nativeAdaptorClassName,
        string fallbackBaseName) returns string {
    string trimmed = suggestedPath.trim();
    if trimmed.length() > 0 {
        if trimmed.startsWith("src/main/java/") {
            if trimmed.endsWith(".java") {
                return trimmed;
            }
            return string `${trimmed}.java`;
        }
        if trimmed.endsWith(".java") {
            return string `src/main/java/${trimmed}`;
        }
        return string `src/main/java/${trimmed}.java`;
    }

    string className = nativeAdaptorClassName.trim();
    if className.length() > 0 {
        return deriveNativeSourcePathFromClass(className);
    }

    string fallbackName = normalizeJavaFileName(fallbackBaseName, fallbackBaseName);
    return string `src/main/java/${fallbackName}`;
}

function collectReferencedTypeNamesFromSpec(ParsedApiSpec parsedSpec) returns string[] {
    string[] names = [];
    foreach SpecMethodSignature method in parsedSpec.clientMethods {
        foreach SpecMethodParameter specParameter in method.parameters {
            addIdentifierTypes(specParameter.'type, names);
        }
        addIdentifierTypes(method.returnType, names);
    }
    return names;
}

function addIdentifierTypes(string typeExpr, string[] names) {
    string token = "";
    foreach int i in 0 ..< typeExpr.length() {
        string ch = typeExpr.substring(i, i + 1);
        if isIdentifierChar(ch) {
            token += ch;
        } else {
            pushTypeToken(token, names);
            token = "";
        }
    }
    pushTypeToken(token, names);
}

function isIdentifierChar(string ch) returns boolean {
    if ch.length() != 1 {
        return false;
    }
    byte b = ch.toBytes()[0];
    return (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 95;
}

function pushTypeToken(string token, string[] names) {
    string trimmed = token.trim();
    if trimmed.length() == 0 {
        return;
    }
    if isBuiltInTypeToken(trimmed) {
        return;
    }
    int codePoint = <int>trimmed.toCodePointInts()[0];
    if !(codePoint >= 65 && codePoint <= 90) {
        return;
    }
    if !containsString(names, trimmed) {
        names.push(trimmed);
    }
}

function containsString(string[] values, string target) returns boolean {
    foreach string value in values {
        if value == target {
            return true;
        }
    }
    return false;
}

function isBuiltInTypeToken(string token) returns boolean {
    return token == "string" || token == "int" || token == "boolean" || token == "decimal" || token == "float" ||
        token == "byte" || token == "xml" || token == "json" || token == "map" || token == "record" ||
        token == "error" || token == "readonly" || token == "future" || token == "stream" || token == "table" ||
        token == "typedesc" || token == "any" || token == "anydata" || token == "never" || token == "object";
}

function hasDeclaredTypeOrEnum(string typesBal, string typeName) returns boolean {
    return typesBal.includes(string `type ${typeName} `) ||
        typesBal.includes(string `type ${typeName} record`) ||
        typesBal.includes(string `enum ${typeName} `) ||
        typesBal.includes(string `enum ${typeName} {`);
}

function ensureJavaMethodName(string annotationStr, string methodName) returns string {
    string namePrefix = "name: \"";
    int? namePosOpt =  annotationStr.indexOf(namePrefix);
    if namePosOpt is int {
        int valueStart = <int>namePosOpt + namePrefix.length();
        int? valueEndOpt = annotationStr.indexOf("\"", valueStart);
        if valueEndOpt is int {
            return annotationStr.substring(0, valueStart) + methodName + annotationStr.substring(<int>valueEndOpt);
        }
    }
    int? closingIdx = annotationStr.indexOf("} external;");
    if closingIdx is int {
        string before = annotationStr.substring(0, <int>closingIdx).trim();
        if before.endsWith("{") {
            return before + " name: \"" + methodName + "\" } external;";
        }
        return before + ", name: \"" + methodName + "\" } external;";
    }
    return annotationStr;
}

public function printConnectorUsage() {
    io:println();
    io:println("Generate connector artifacts from metadata, IR and API spec");
    io:println();
    io:println("USAGE:");
    io:println("  bal run -- connector <metadata-json> <ir-json> <api-spec-bal> [output-dir] [options]");
    io:println();
    io:println("OPTIONS:");
    io:println("  --fix-code              Enable post-generation code fixing for native adaptor Java");
    io:println("  --fix-report-only       Run fixer diagnostics but do not apply changes");
    io:println("  --fix-iterations=<n>    Maximum fixer iterations (default: 3)");
    io:println("  --quiet, -q             Minimal logging");
    io:println();
    io:println("EXAMPLE:");
    io:println("  bal run -- connector path/to/metadata.json " +
            "path/to/ir.json " +
            "path/to/api_spec.bal ./output --fix-code");
    io:println();
}
