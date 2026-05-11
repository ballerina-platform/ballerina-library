import ballerina/file;
import ballerina/io;
import ballerina/lang.regexp;
import ballerina/os;
import ballerina/regex;

import wso2/connector_automator.api_specification_generator as generator;
import wso2/connector_automator.client_generator as client_generator;
import wso2/connector_automator.code_fixer as fixer;
import wso2/connector_automator.connector_generator as connector;
import wso2/connector_automator.document_generator as document_generator;
import wso2/connector_automator.example_generator as example_generator;
import wso2/connector_automator.sanitizor as sanitizor;
import wso2/connector_automator.sdkanalyzer as analyzer;
import wso2/connector_automator.test_generator as test_generator;
import wso2/connector_automator.utils as oautils;

const string TEST_JARS_DIR = "test-jars";
const string ANALYZER_OUTPUT_DIR = "modules/sdkanalyzer/output";
const string IR_OUTPUT_DIR = "modules/api_specification_generator/IR-output";
const string SPEC_OUTPUT_DIR = "modules/api_specification_generator/spec-output";
const string CONNECTOR_OUTPUT_DIR = "modules/connector_generator/output";

public function main(string... args) returns error? {
    if args.length() == 0 {
        printMainUsage();
        return;
    }

    string command = args[0];

    match command {
        "sdk" => {
            return executeSdkCommand(args.slice(1));
        }
        "openapi" => {
            return executeOpenApiCommand(args.slice(1));
        }
        "analyze" => {
            return executeAnalyze(args.slice(1));
        }
        "generate" => {
            return executeGenerate(args.slice(1));
        }
        "connector" => {
            return executeConnector(args.slice(1));
        }
        "fix-code" => {
            return executeFixCode(args.slice(1));
        }
        "fix-report-only" => {
            return executeFixReportOnly(args.slice(1));
        }
        "pipeline" => {
            return executePipeline(args.slice(1));
        }
        "generate-tests" => {
            return executeGenerateTests(args.slice(1));
        }
        "generate-examples" => {
            return executeGenerateExamples(args.slice(1));
        }
        "generate-docs" => {
            return executeGenerateDocs(args.slice(1));
        }
        "help" => {
            printMainUsage();
        }
        _ => {
            printMainUsage();
            return error(string `Unknown command: ${command}`);
        }
    }
}

function executeAnalyze(string[] args) returns error? {
    if args.length() < 2 {
        printAnalyzeUsage();
        return;
    }

    string sdkRef = args[0].trim();
    if sdkRef.length() == 0 {
        return error("Dataset key cannot be empty");
    }

    string outputRoot = toAbsolutePath(args[1].trim());
    if outputRoot.length() == 0 {
        return error("Output directory cannot be empty");
    }

    string analyzerOutputDir = resolveAnalyzerOutputDir(outputRoot);
    string[] flagArgs = args.slice(2);

    AnalyzerFlags flags = parseAnalyzerFlags(flagArgs);

    if isMavenCoordinate(sdkRef) {
        analyzer:AnalyzerConfig analyzerConfig = buildAnalyzerConfig(flagArgs, "", flags.quietMode);

        analyzer:AnalysisResult|analyzer:AnalyzerError analysisResult = analyzer:analyzeJavaSDK(
                sdkRef,
                analyzerOutputDir,
                analyzerConfig
        );

        if analysisResult is analyzer:AnalyzerError {
            io:println(string `Analysis failed: ${analysisResult.message()}`);
            return analysisResult;
        }

        return;
    }

    string datasetKey = sdkRef;
    string sdkJarPath = resolveSdkJarPath(datasetKey);
    string javadocJarPath = resolveJavadocJarPath(datasetKey);

    check ensureFileExists(sdkJarPath, "SDK JAR");
    check ensureFileExists(javadocJarPath, "Javadoc JAR");

        analyzer:AnalyzerConfig analyzerConfig = buildAnalyzerConfig(flagArgs, javadocJarPath, flags.quietMode);

    analyzer:AnalysisResult|analyzer:AnalyzerError analysisResult = analyzer:analyzeJavaSDK(
            sdkJarPath,
            analyzerOutputDir,
            analyzerConfig
    );

    if analysisResult is analyzer:AnalyzerError {
        io:println(string `Analysis failed: ${analysisResult.message()}`);
        return analysisResult;
    }

}

function isMavenCoordinate(string sdkRef) returns boolean {
    if !sdkRef.includes(":") {
        return false;
    }

    if sdkRef.includes("/") || sdkRef.includes("\\") {
        return false;
    }

    string[] parts = regex:split(sdkRef, ":");
    return parts.length() == 2 || parts.length() == 3;
}

function executeGenerate(string[] args) returns error? {
    if args.length() < 1 {
        printGenerateUsage();
        return;
    }

    string outputRoot = toAbsolutePath(args[0].trim());
    if outputRoot.length() == 0 {
        return error("Output directory cannot be empty");
    }

    string analyzerOutputDir = resolveAnalyzerOutputDir(outputRoot);
    check ensureDirectoryExists(analyzerOutputDir, "Analyzer output directory");

    string[] datasetKeys = check listDatasetKeysFromMetadataDir(analyzerOutputDir);
    if datasetKeys.length() == 0 {
        return error(string `No metadata files found in: ${analyzerOutputDir}`);
    }

    string[] flagArgs = args.slice(1);
    boolean quietMode = false;
    boolean enableExtendedThinking = true;

    foreach string arg in flagArgs {
        match arg {
            "quiet"|"--quiet"|"-q" => {
                quietMode = true;
            }
            "no-thinking"|"--no-thinking" => {
                enableExtendedThinking = false;
            }
            _ => {
            }
        }
    }

    string apiSpecOutputRoot = resolveApiSpecOutputRoot(outputRoot);

    foreach string datasetKey in datasetKeys {
        string metadataPath = resolveMetadataPath(datasetKey, outputRoot);
        check ensureFileExists(metadataPath, "Metadata JSON");

        generator:GeneratorConfig config = {
            metadataPath: metadataPath,
            outputDir: apiSpecOutputRoot,
            datasetKey: datasetKey,
            quietMode: quietMode,
            enableExtendedThinking: enableExtendedThinking
        };

        generator:GeneratorResult|generator:GeneratorError result = generator:generateSpecification(config);
        if result is generator:GeneratorError {
            io:println(string `Generation failed for ${datasetKey}: ${result.message()}`);
            return result;
        }
    }
    
}

function executeConnector(string[] args) returns error? {
    if args.length() < 1 {
        printConnectorUsage();
        return;
    }

    string datasetKey = "";
    string outputRoot = "";
    int flagsStartIndex = 1;

    if looksLikePath(args[0]) {
        outputRoot = toAbsolutePath(args[0].trim());
        string[]|error keys = listDatasetKeysFromMetadataDir(resolveAnalyzerOutputDir(outputRoot));
        if keys is error {
            return error(string `Failed to locate metadata in ${resolveAnalyzerOutputDir(outputRoot)}: ${keys.message()}`);
        }
        if keys.length() == 0 {
            return error(string `Metadata JSON not found: ${resolveAnalyzerOutputDir(outputRoot)}`);
        }
        if keys.length() > 1 {
            return error(string `Multiple metadata files found in ${resolveAnalyzerOutputDir(outputRoot)}. ` +
                "Use: bal run -- connector <dataset-key> <output-dir>");
        }
        datasetKey = keys[0];
        flagsStartIndex = 1;
    } else {
        datasetKey = args[0].trim();
        if datasetKey.length() == 0 {
            return error("Dataset key cannot be empty");
        }
        if args.length() > 1 && looksLikePath(args[1]) {
            outputRoot = toAbsolutePath(args[1].trim());
            flagsStartIndex = 2;
        }
    }

    string metadataPath = resolveMetadataPath(datasetKey, outputRoot);
    string irPath = resolveIrPath(datasetKey, outputRoot);
    string specPath = resolveSpecPath(datasetKey, outputRoot);

    check ensureFileExists(metadataPath, "Metadata JSON");
    check ensureFileExists(irPath, "IR JSON");
    check ensureFileExists(specPath, "API specification");

    connector:ConnectorGeneratorConfig config = {
        metadataPath: metadataPath,
        irPath: irPath,
        apiSpecPath: specPath,
        outputDir: resolveConnectorOutputPath(datasetKey, outputRoot),
        sdkVersionHint: extractSdkVersionFromDatasetKey(datasetKey)
    };

    foreach string arg in args.slice(flagsStartIndex) {
        if arg == "quiet" || arg == "--quiet" || arg == "-q" {
            config.quietMode = true;
        }
    }

    connector:ConnectorGeneratorResult|connector:ConnectorGeneratorError result = connector:generateConnector(config);
    if result is connector:ConnectorGeneratorError {
        io:println(string `Connector generation failed: ${result.message()}`);
        return result;
    }



}

function executeFixCode(string[] args) returns error? {
    return executeFixCommand(args, "auto-apply");
}

function executeGenerateTests(string[] args) returns error? {
    if args.length() < 1 {
        printGenerateTestsUsage();
        return;
    }

    string datasetKey = "";
    string outputRoot = "";
    int flagsStartIndex = 1;

    if looksLikePath(args[0]) {
        outputRoot = toAbsolutePath(args[0].trim());
        string[]|error keys = listDatasetKeysFromMetadataDir(resolveAnalyzerOutputDir(outputRoot));
        if keys is error {
            return error(string `Failed to locate metadata in ${resolveAnalyzerOutputDir(outputRoot)}: ${keys.message()}`);
        }
        if keys.length() == 0 {
            return error(string `Metadata JSON not found: ${resolveAnalyzerOutputDir(outputRoot)}`);
        }
        if keys.length() > 1 {
            return error(string `Multiple metadata files found in ${resolveAnalyzerOutputDir(outputRoot)}. ` +
                "Use: bal run -- generate-tests <dataset-key> <output-dir>");
        }
        datasetKey = keys[0];
        flagsStartIndex = 1;
    } else {
        datasetKey = args[0].trim();
        if datasetKey.length() == 0 {
            return error("Dataset key cannot be empty");
        }
        if args.length() > 1 && looksLikePath(args[1]) {
            outputRoot = toAbsolutePath(args[1].trim());
            flagsStartIndex = 2;
        }
    }

    string specPath = toAbsolutePath(resolveSpecPath(datasetKey, outputRoot));
    check ensureFileExists(specPath, "API specification");

    string connectorOutputPath = resolveConnectorOutputPath(datasetKey, outputRoot);
    string connectorBallerinaToml = string `${connectorOutputPath}/ballerina/Ballerina.toml`;
    check ensureFileExists(connectorBallerinaToml, "Generated connector output");

    string[] forwardedArgs = [connectorOutputPath, specPath, ...args.slice(flagsStartIndex)];
    error? genResult = test_generator:executeTestGen("sdk", ...forwardedArgs);

    return genResult;
}

function executeGenerateExamples(string[] args) returns error? {
    if args.length() < 1 {
        printGenerateExamplesUsage();
        return;
    }

    string datasetKey = "";
    string outputRoot = "";
    int flagsStartIndex = 1;

    if looksLikePath(args[0]) {
        outputRoot = toAbsolutePath(args[0].trim());
        string[]|error keys = listDatasetKeysFromMetadataDir(resolveAnalyzerOutputDir(outputRoot));
        if keys is error {
            return error(string `Failed to locate metadata in ${resolveAnalyzerOutputDir(outputRoot)}: ${keys.message()}`);
        }
        if keys.length() == 0 {
            return error(string `Metadata JSON not found: ${resolveAnalyzerOutputDir(outputRoot)}`);
        }
        if keys.length() > 1 {
            return error(string `Multiple metadata files found in ${resolveAnalyzerOutputDir(outputRoot)}. ` +
                "Use: bal run -- generate-examples <dataset-key> <output-dir>");
        }
        datasetKey = keys[0];
        flagsStartIndex = 1;
    } else {
        datasetKey = args[0].trim();
        if datasetKey.length() == 0 {
            return error("Dataset key cannot be empty");
        }
        if args.length() > 1 && looksLikePath(args[1]) {
            outputRoot = toAbsolutePath(args[1].trim());
            flagsStartIndex = 2;
        }
    }

    string connectorOutputPath = resolveConnectorOutputPath(datasetKey, outputRoot);
    string connectorBallerinaToml = string `${connectorOutputPath}/ballerina/Ballerina.toml`;
    check ensureFileExists(connectorBallerinaToml, "Generated connector output");

    string[] forwardedArgs = [connectorOutputPath, ...args.slice(flagsStartIndex)];
    error? exResult = example_generator:executeExampleGen(...forwardedArgs);

    return exResult;
}

function executeGenerateDocs(string[] args) returns error? {
    if args.length() < 2 {
        printGenerateDocsUsage();
        return;
    }

    string docCommand = args[0].trim();
    string datasetKey = "";
    string outputRoot = "";
    int flagsStartIndex = 2;

    if looksLikePath(args[1]) {
        outputRoot = toAbsolutePath(args[1].trim());
        string[]|error keys = listDatasetKeysFromMetadataDir(resolveAnalyzerOutputDir(outputRoot));
        if keys is error {
            return error(string `Failed to locate metadata in ${resolveAnalyzerOutputDir(outputRoot)}: ${keys.message()}`);
        }
        if keys.length() == 0 {
            return error(string `Metadata JSON not found: ${resolveAnalyzerOutputDir(outputRoot)}`);
        }
        if keys.length() > 1 {
            return error(string `Multiple metadata files found in ${resolveAnalyzerOutputDir(outputRoot)}. ` +
                "Use: bal run -- generate-docs <doc-command> <dataset-key> <output-dir>");
        }
        datasetKey = keys[0];
        flagsStartIndex = 2;
    } else {
        datasetKey = args[1].trim();
        if datasetKey.length() == 0 {
            return error("Dataset key cannot be empty");
        }

        if args.length() > 2 && looksLikePath(args[2]) {
            outputRoot = toAbsolutePath(args[2].trim());
            flagsStartIndex = 3;
        }
    }

    string connectorOutputPath = resolveConnectorOutputPath(datasetKey, outputRoot);
    string connectorBallerinaToml = string `${connectorOutputPath}/ballerina/Ballerina.toml`;
    check ensureFileExists(connectorBallerinaToml, "Generated connector output");

    string[] forwardedArgs = [docCommand, connectorOutputPath, ...args.slice(flagsStartIndex)];
    error? docResult = document_generator:executeDocGen(...forwardedArgs);

    return docResult;
}

function printGenerateTestsUsage() {
    io:println();
    io:println("Generate connector tests from dataset key");
    io:println();
    io:println("USAGE:");
    io:println("  bal run -- generate-tests <dataset-key> [yes] [quiet]");
    io:println();
    io:println("INPUTS:");
    io:println("  <output-dir>/docs/spec/<dataset-key>_spec.bal");
    io:println("  <output-dir>/ballerina/... (generated connector)");
    io:println();
    io:println("EXAMPLE:");
    io:println("  bal run -- generate-tests sqs-2.31.66 /home/user/SDK-auto-generated-connectors yes quiet");
    io:println();
}

function printGenerateExamplesUsage() {
    io:println();
    io:println("Generate connector examples from dataset key");
    io:println();
    io:println("USAGE:");
    io:println("  bal run -- generate-examples <dataset-key> [yes] [quiet]");
    io:println();
    io:println("INPUTS:");
    io:println("  <output-dir>/ballerina/... (generated connector)");
    io:println();
    io:println("OUTPUT:");
    io:println("  <output-dir>/examples/");
    io:println();
    io:println("EXAMPLE:");
    io:println("  bal run -- generate-examples sqs-2.31.66 /home/user/SDK-auto-generated-connectors yes quiet");
    io:println();
}

function printGenerateDocsUsage() {
    io:println();
    io:println("Generate connector documentation from dataset key");
    io:println();
    io:println("USAGE:");
    io:println("  bal run -- generate-docs <doc-command> <dataset-key> [yes] [quiet]");
    io:println();
    io:println("DOC COMMANDS:");
    io:println("  generate-all");
    io:println("  generate-ballerina");
    io:println("  generate-tests");
    io:println("  generate-examples");
    io:println("  generate-individual-examples");
    io:println("  generate-main");
    io:println();
    io:println("EXAMPLE:");
    io:println("  bal run -- generate-docs generate-all sqs-2.31.66 /home/user/SDK-auto-generated-connectors yes quiet");
    io:println();
}

function executeFixReportOnly(string[] args) returns error? {
    return executeFixCommand(args, "report-only");
}

function executeFixCommand(string[] args, string fixMode) returns error? {
    if args.length() < 1 {
        printFixUsage(fixMode);
        return;
    }

    string datasetKey = "";
    string outputRoot = "";
    int flagsStartIndex = 1;

    if looksLikePath(args[0]) {
        outputRoot = toAbsolutePath(args[0].trim());
        string[]|error keys = listDatasetKeysFromMetadataDir(resolveAnalyzerOutputDir(outputRoot));
        if keys is error {
            return error(string `Failed to locate metadata in ${resolveAnalyzerOutputDir(outputRoot)}: ${keys.message()}`);
        }
        if keys.length() == 0 {
            return error(string `Metadata JSON not found: ${resolveAnalyzerOutputDir(outputRoot)}`);
        }
        if keys.length() > 1 {
            return error(string `Multiple metadata files found in ${resolveAnalyzerOutputDir(outputRoot)}. ` +
                string `Use: bal run -- ${fixMode == "report-only" ? "fix-report-only" : "fix-code"} <dataset-key> <output-dir>`);
        }
        datasetKey = keys[0];
        flagsStartIndex = 1;
    } else {
        datasetKey = args[0].trim();
        if datasetKey.length() == 0 {
            return error("Dataset key cannot be empty");
        }
        if args.length() > 1 && looksLikePath(args[1]) {
            outputRoot = toAbsolutePath(args[1].trim());
            flagsStartIndex = 2;
        }
    }

    string metadataPath = resolveMetadataPath(datasetKey, outputRoot);
    string irPath = resolveIrPath(datasetKey, outputRoot);
    string specPath = resolveSpecPath(datasetKey, outputRoot);

    check ensureFileExists(metadataPath, "Metadata JSON");
    check ensureFileExists(irPath, "IR JSON");
    check ensureFileExists(specPath, "API specification");

    boolean quietMode = false;
    int maxFixIterations = 3;
    boolean autoYes = fixMode != "report-only";
    string connectorOutputPath = resolveConnectorOutputPath(datasetKey, outputRoot);
    string nativeOutputPath = resolveNativeOutputPath(datasetKey, outputRoot);
    string ballerinaOutputPath = string `${connectorOutputPath}/ballerina`;

    check ensureFileExists(string `${nativeOutputPath}/build.gradle`, "Generated connector build.gradle");

    foreach string arg in args.slice(flagsStartIndex) {
        if arg == "quiet" || arg == "--quiet" || arg == "-q" {
            quietMode = true;
        } else if arg.startsWith("--fix-iterations=") {
            string val = arg.substring(17);
            int|error parsed = int:fromString(val);
            if parsed is int {
                maxFixIterations = parsed;
            }
        }
    }

    string[] planOperations = fixMode == "report-only"
        ? [
            "Run Java native fixer",
            "Collect Java/native fix status",
            "Report consolidated fix status"
        ]
        : [
            "Run Java native fixer",
            "Run Ballerina client/types fixer",
            "Report consolidated fix status"
        ];

    printCommandPlan(fixMode == "report-only" ? "Fix Report" : "Fix Code", datasetKey,
        planOperations, quietMode);

    fixer:FixResult|fixer:BallerinaFixerError javaFixResultOrError = fixer:fixJavaNativeAdaptorErrors(
            nativeOutputPath,
            quietMode,
            autoYes,
            maxFixIterations
    );

    if javaFixResultOrError is fixer:BallerinaFixerError {
        io:println(string `Code fix failed (Java native): ${javaFixResultOrError.message()}`);
        return javaFixResultOrError;
    }

    fixer:FixResult javaFixResult = javaFixResultOrError;

    fixer:FixResult ballerinaFixResult = {
        success: true,
        errorsFixed: 0,
        errorsRemaining: 0,
        appliedFixes: [],
        remainingFixes: []
    };

    if fixMode != "report-only" {
        check ensureFileExists(string `${ballerinaOutputPath}/Ballerina.toml`, "Generated connector Ballerina.toml");
        fixer:FixResult|fixer:BallerinaFixerError ballerinaFixResultOrError = fixer:fixAllErrors(
                ballerinaOutputPath,
                quietMode,
                autoYes
        );

        if ballerinaFixResultOrError is fixer:BallerinaFixerError {
            io:println(string `Code fix failed (Ballerina client): ${ballerinaFixResultOrError.message()}`);
            return ballerinaFixResultOrError;
        }
        ballerinaFixResult = ballerinaFixResultOrError;
    }

    boolean overallSuccess = javaFixResult.success && ballerinaFixResult.success;
    int totalFixed = javaFixResult.errorsFixed + ballerinaFixResult.errorsFixed;
    int totalRemaining = javaFixResult.errorsRemaining + ballerinaFixResult.errorsRemaining;

    string[] combinedIssues = [];
    foreach string issue in javaFixResult.remainingFixes {
        combinedIssues.push(string `java: ${issue}`);
    }
    foreach string issue in ballerinaFixResult.remainingFixes {
        combinedIssues.push(string `ballerina: ${issue}`);
    }

    string[] details = [
        string `success: ${overallSuccess}`,
        string `fixed: ${totalFixed}`,
        string `remaining: ${totalRemaining}`,
        string `java_remaining: ${javaFixResult.errorsRemaining}`
    ];
    if fixMode != "report-only" {
        details.push(string `ballerina_remaining: ${ballerinaFixResult.errorsRemaining}`);
    }
    if !overallSuccess && combinedIssues.length() > 0 {
        foreach string issue in combinedIssues {
            details.push(string `issue: ${issue}`);
        }
    }
    printCommandSummary(fixMode == "report-only" ? "Fix Report" : "Fix Code", overallSuccess, details, quietMode);
}

function printCommandPlan(string title, string target, string[] operations, boolean quietMode) {
    if quietMode {
        return;
    }

    string sep = createMainSeparator("=", 70);
    io:println(sep);
    io:println(string `${title} Plan`);
    io:println(sep);
    io:println(string `Target: ${target}`);
    io:println("");
    io:println("Operations:");
    int i = 0;
    while i < operations.length() {
        io:println(string `  ${i + 1}. ${operations[i]}`);
        i += 1;
    }
    io:println(sep);
}

function printCommandSummary(string title, boolean success, string[] details, boolean quietMode) {
    string sep = createMainSeparator("=", 70);
    io:println("");
    io:println(sep);
    io:println(string `${success ? "✓" : "⚠"} ${title} Complete`);
    io:println(sep);
    foreach string detail in details {
        io:println(string `  • ${detail}`);
    }
    if !quietMode {
        io:println(sep);
    }
}

function createMainSeparator(string char, int length) returns string {
    string[] chars = [];
    int i = 0;
    while i < length {
        chars.push(char);
        i += 1;
    }
    return string:'join("", ...chars);
}

function printConnectorUsage() {
    io:println();
    io:println("Generate connector artifacts from fixed metadata/IR/spec locations");
    io:println();
    io:println("USAGE:");
    io:println("  bal run -- connector <dataset-key> [options]");
    io:println();
    io:println("INPUTS:");
    io:println("  modules/sdkanalyzer/output/<dataset-key>-metadata.json");
    io:println("  modules/api_specification_generator/IR-output/<dataset-key>-ir.json");
    io:println("  modules/api_specification_generator/spec-output/<dataset-key>_spec.bal");
    io:println();
    io:println("OUTPUT:");
    io:println("  <output-dir>/ballerina/client.bal");
    io:println("  <output-dir>/ballerina/types.bal");
    io:println("  <output-dir>/native/... (native adaptor)");
    io:println();
    io:println("OPTIONS:");
    io:println("  quiet                   Minimal logging output");
    io:println();
    io:println("EXAMPLE:");
    io:println("  bal run -- connector s3-2.4.0 /home/user/SDK-auto-generated-connectors");
    io:println();
}

function printFixUsage(string fixMode) {
    io:println();
    io:println("Run code fixer on generated connector output (Java native + Ballerina client)");
    io:println();
    io:println("USAGE:");
    if fixMode == "report-only" {
        io:println("  bal run -- fix-report-only <dataset-key> [options]");
    } else {
        io:println("  bal run -- fix-code <dataset-key> [options]");
    }
    io:println();
    io:println("INPUTS:");
    io:println("  <output-dir>/docs/spec/<dataset-key>-metadata.json");
    io:println("  <output-dir>/docs/spec/<dataset-key>-ir.json");
    io:println("  <output-dir>/docs/spec/<dataset-key>_spec.bal");
    io:println();
    io:println("OUTPUT:");
    io:println("  <output-dir>/ballerina/client.bal");
    io:println("  <output-dir>/ballerina/types.bal");
    io:println("  <output-dir>/native/... (native adaptor)");
    io:println();
    io:println("OPTIONS:");
    io:println("  --fix-iterations=<n>    Maximum fixer iterations (default: 3)");
    io:println("  quiet                   Minimal logging output");
    io:println();
    io:println("EXAMPLES:");
    io:println("  bal run -- fix-code s3-2.4.0 /home/user/SDK-auto-generated-connectors");
    io:println("  bal run -- fix-report-only s3-2.4.0 /home/user/SDK-auto-generated-connectors");
    io:println();
}

function executePipeline(string[] args) returns error? {
    if args.length() < 2 {
        printPipelineUsage();
        return;
    }

    string datasetKey = args[0].trim();
    if datasetKey.length() == 0 {
        return error("Dataset key cannot be empty");
    }

    string outputRoot = toAbsolutePath(args[1].trim());
    if outputRoot.length() == 0 {
        return error("Output directory cannot be empty");
    }

    string sdkJarPath = resolveSdkJarPath(datasetKey);
    string javadocJarPath = resolveJavadocJarPath(datasetKey);

    check ensureFileExists(sdkJarPath, "SDK JAR");
    check ensureFileExists(javadocJarPath, "Javadoc JAR");

    boolean quietMode = false;
    boolean autoYes = false;
    boolean runFixCode = true;
    boolean runGenerateTests = true;
    boolean runGenerateExamples = true;
    boolean runGenerateDocs = true;
    string fixMode = "auto-apply";
    int maxFixIterations = 3;
    foreach string arg in args.slice(2) {
        if arg == "quiet" || arg == "--quiet" || arg == "-q" {
            quietMode = true;
        } else if arg == "yes" || arg == "--yes" || arg == "-y" {
            autoYes = true;
        } else if arg == "--fix-code" {
            runFixCode = true;
        } else if arg == "--fix-report-only" {
            runFixCode = true;
            fixMode = "report-only";
        } else if arg == "--skip-fix" {
            runFixCode = false;
        } else if arg == "--skip-tests" {
            runGenerateTests = false;
        } else if arg == "--generate-examples" {
            runGenerateExamples = true;
        } else if arg == "--skip-examples" {
            runGenerateExamples = false;
        } else if arg == "--generate-docs" {
            runGenerateDocs = true;
        } else if arg == "--skip-docs" {
            runGenerateDocs = false;
        } else if arg.startsWith("--fix-iterations=") {
            string value = arg.substring(17);
            int|error parsed = int:fromString(value);
            if parsed is int {
                maxFixIterations = parsed;
            }
        }
    }

    printPipelineModuleHeader("SDK Analyzer", quietMode);
    if !quietMode {
        io:println(string `  → SDK JAR: ${sdkJarPath}`);
        io:println(string `  → Javadoc JAR: ${javadocJarPath}`);
    }

        analyzer:AnalyzerConfig analyzerConfig = buildAnalyzerConfig(args.slice(2), javadocJarPath, quietMode);
    analyzer:AnalysisResult|analyzer:AnalyzerError analysisResult = analyzer:analyzeJavaSDK(
            sdkJarPath,
            resolveAnalyzerOutputDir(outputRoot),
            analyzerConfig
    );
    if analysisResult is analyzer:AnalyzerError {
        io:println(string `Analysis failed: ${analysisResult.message()}`);
        return analysisResult;
    }

    string metadataPath = resolveMetadataPath(datasetKey, outputRoot);
    check ensureFileExists(metadataPath, "Metadata JSON");

    check runPipelineStagesForDataset(datasetKey, outputRoot, analysisResult.methodsExtracted, autoYes, quietMode,
        runFixCode, runGenerateTests, runGenerateExamples, runGenerateDocs, fixMode, maxFixIterations);
}

function runPipelineStagesForDataset(string datasetKey, string outputRoot, int extractedMethods,
        boolean autoYes, boolean quietMode,
        boolean runFixCode, boolean runGenerateTests, boolean runGenerateExamples, boolean runGenerateDocs,
        string fixMode, int maxFixIterations) returns error? {
    string metadataPath = resolveMetadataPath(datasetKey, outputRoot);
    check ensureFileExists(metadataPath, "Metadata JSON");

    printPipelineModuleHeader("API Specification Generator", quietMode);
    if !quietMode {
        io:println(string `  → Metadata: ${metadataPath}`);
    }

    generator:GeneratorConfig genConfig = {
        metadataPath: metadataPath,
        outputDir: resolveApiSpecOutputRoot(outputRoot),
        quietMode: quietMode,
        datasetKey: datasetKey
    };

    generator:GeneratorResult|generator:GeneratorError genResult = generator:generateSpecification(genConfig);
    if genResult is generator:GeneratorError {
        io:println(string `Specification generation failed: ${genResult.message()}`);
        return genResult;
    }

    string irPath = resolveIrPath(datasetKey, outputRoot);
    string specPath = resolveSpecPath(datasetKey, outputRoot);
    check ensureFileExists(irPath, "IR JSON");
    check ensureFileExists(specPath, "API specification");

    if !confirmPipelineAfterSpec(datasetKey, metadataPath, irPath, specPath, autoYes, quietMode) {
        return error("Pipeline cancelled by user after API specification generation.");
    }

    printPipelineModuleHeader("Connector Generator", quietMode);
    if !quietMode {
        io:println(string `  → IR: ${irPath}`);
        io:println(string `  → API Spec: ${specPath}`);
    }

    connector:ConnectorGeneratorConfig connectorConfig = {
        metadataPath: metadataPath,
        irPath: irPath,
        apiSpecPath: specPath,
        outputDir: resolveConnectorOutputPath(datasetKey, outputRoot),
        quietMode: quietMode,
        enableCodeFixing: false,
        fixMode: fixMode,
        maxFixIterations: maxFixIterations,
        sdkVersionHint: extractSdkVersionFromDatasetKey(datasetKey)
    };

    connector:ConnectorGeneratorResult|connector:ConnectorGeneratorError connectorResult =
        connector:generateConnector(connectorConfig);

    if connectorResult is connector:ConnectorGeneratorError {
        io:println(string `Connector generation failed: ${connectorResult.message()}`);
        return connectorResult;
    }

    boolean fixCompleted = false;
    if runFixCode {
        printPipelineModuleHeader("Code Fixer", quietMode);

        string[] fixArgs = [datasetKey, outputRoot];
        if quietMode {
            fixArgs.push("quiet");
        }
        if autoYes {
            fixArgs.push("yes");
        }
        error? fixError = executeFixCommand(fixArgs, fixMode);
        if fixError is error {
            return fixError;
        }
        fixCompleted = true;
    }

    boolean examplesCompleted = false;
    if runGenerateExamples {
        printPipelineModuleHeader("Example Generator", quietMode);

        string[] exampleArgs = [datasetKey, outputRoot];
        if autoYes {
            exampleArgs.push("yes");
        }
        if quietMode {
            exampleArgs.push("quiet");
        }

        error? exampleError = executeGenerateExamples(exampleArgs);
        if exampleError is error {
            return exampleError;
        }
        examplesCompleted = true;
    }

    boolean testsCompleted = false;
    if runGenerateTests {
        printPipelineModuleHeader("Test Generator", quietMode);

        string[] testArgs = [datasetKey, outputRoot, "yes"];
        if quietMode {
            testArgs.push("quiet");
        }
        error? testError = executeGenerateTests(testArgs);
        if testError is error {
            return testError;
        }
        testsCompleted = true;
    }

    boolean docsCompleted = false;
    if runGenerateDocs {
        printPipelineModuleHeader("Document Generator", quietMode);

        string[] docArgs = ["generate-all", datasetKey, outputRoot];
        if autoYes {
            docArgs.push("yes");
        }
        if quietMode {
            docArgs.push("quiet");
        }

        error? docsError = executeGenerateDocs(docArgs);
        if docsError is error {
            return docsError;
        }
        docsCompleted = true;
    }

    printPipelineFinalSummary(datasetKey, metadataPath, irPath, genResult.specificationPath,
        connectorResult.clientPath, connectorResult.typesPath, connectorResult.nativeAdaptorPath,
        extractedMethods, connectorResult.mappedMethodCount,
        runFixCode, fixCompleted, runGenerateTests, testsCompleted, runGenerateExamples, examplesCompleted,
        runGenerateDocs, docsCompleted,
        connectorResult.codeFixingRan, connectorResult.codeFixingSuccess, quietMode);
}

function printPipelineModuleHeader(string moduleName, boolean quietMode) {
    if quietMode {
        return;
    }

    string sep = createMainSeparator("-", 60);
    io:println("");
    io:println(sep);
    io:println(string `Executing module: ${moduleName}`);
    io:println(sep);
}

function confirmPipelineAfterSpec(string datasetKey, string metadataPath, string irPath, string specPath,
        boolean autoYes, boolean quietMode) returns boolean {
    if quietMode || autoYes {
        return true;
    }

    string sep = createMainSeparator("-", 60);
    io:println("");
    io:println(sep);
    io:println("Generated artifacts after API specification generation");
    io:println(sep);
    io:println(string `Dataset: ${datasetKey}`);
    io:println(string `Metadata: ${metadataPath}`);
    io:println(string `IR: ${irPath}`);
    io:println(string `Specification: ${specPath}`);
    io:println(sep);

    return getPipelineUserConfirmation("Continue pipeline with these generated artifacts?");
}

function getPipelineUserConfirmation(string message) returns boolean {
    io:print(string `${message} (y/n): `);
    string|io:Error userInput = io:readln();
    if userInput is io:Error {
        return false;
    }
    return userInput.trim().toLowerAscii() is "y"|"yes";
}

function printPipelineFinalSummary(string datasetKey, string metadataPath, string irPath, string specPath,
        string clientPath, string typesPath, string nativePath, int extractedMethods, int mappedMethods,
    boolean runFixCode, boolean fixCompleted, boolean runGenerateTests, boolean testsCompleted,
    boolean runGenerateExamples, boolean examplesCompleted,
    boolean runGenerateDocs, boolean docsCompleted,
        boolean connectorInternalFixRan, boolean connectorInternalFixSuccess, boolean quietMode) {
    string sep = createMainSeparator("=", 70);
    io:println("");
    io:println(sep);
    io:println("Pipeline Summary");
    io:println(sep);
    io:println(string `Dataset: ${datasetKey}`);
    io:println(string `Metadata: ${metadataPath}`);
    io:println(string `IR: ${irPath}`);
    io:println(string `Specification: ${specPath}`);
    io:println(string `Connector client: ${clientPath}`);
    io:println(string `Connector types: ${typesPath}`);
    io:println(string `Native adaptor: ${nativePath}`);
    io:println(string `Methods extracted: ${extractedMethods}`);
    io:println(string `Methods mapped: ${mappedMethods}`);
    io:println(string `Code fixing: ${runFixCode ? (fixCompleted ? "completed" : "failed") : "skipped"}`);
    io:println(string `Example generation: ${runGenerateExamples ? (examplesCompleted ? "completed" : "failed") : "skipped"}`);
    io:println(string `Test generation: ${runGenerateTests ? (testsCompleted ? "completed" : "failed") : "skipped"}`);
    io:println(string `Documentation generation: ${runGenerateDocs ? (docsCompleted ? "completed" : "failed") : "skipped"}`);
    if connectorInternalFixRan {
        io:println(string `Connector-internal code fixing: ${connectorInternalFixSuccess ? "success" : "partial/failed"}`);
    }

    if !quietMode {
        io:println(sep);
    }
}

type AnalyzerFlags record {|
    boolean quietMode;
|};

function parseAnalyzerFlags(string[] args) returns AnalyzerFlags {
    AnalyzerFlags flags = {
        quietMode: false
    };

    foreach string arg in args {
        if arg == "quiet" || arg == "--quiet" || arg == "-q" {
            flags.quietMode = true;
        }
    }

    return flags;
}

function buildAnalyzerConfig(string[] args, string javadocJar, boolean quietMode) returns analyzer:AnalyzerConfig {
    analyzer:AnalyzerConfig config = {
        quietMode: quietMode
    };

    if javadocJar.trim().length() > 0 {
        config.javadocPath = javadocJar;
    }

    int i = 0;
    while i < args.length() {
        string arg = args[i];
        match arg {
            "yes"|"--yes"|"-y" => {
                config.autoYes = true;
            }
            "quiet"|"--quiet"|"-q" => {
                config.quietMode = true;
            }
            "include-deprecated"|"--include-deprecated" => {
                config.includeDeprecated = true;
            }
            "include-internal"|"--include-internal" => {
                config.filterInternal = false;
            }
            "include-non-public"|"--include-non-public" => {
                config.includeNonPublic = true;
            }
            "--sources" => {
                if i + 1 < args.length() {
                    config.sourcesPath = args[i + 1];
                    i = i + 1;
                }
            }
            _ => {
                if arg.includes("=") {
                    string[] parts = regex:split(arg, "=");
                    if parts.length() == 2 {
                        string key = parts[0].trim();
                        string value = parts[1].trim();

                        match key {
                            "exclude-packages"|"--exclude-packages" => {
                                if value.length() > 0 {
                                    config.excludePackages = regex:split(value, ",")
                                        .map(pkg => pkg.trim())
                                        .filter(pkg => pkg.length() > 0);
                                }
                            }
                            "include-packages"|"--include-packages" => {
                                if value.length() > 0 {
                                    config.includePackages = regex:split(value, ",")
                                        .map(pkg => pkg.trim())
                                        .filter(pkg => pkg.length() > 0);
                                }
                            }
                            "max-depth"|"--max-depth" => {
                                int|error depth = int:fromString(value);
                                if depth is int {
                                    config.maxDependencyDepth = depth;
                                }
                            }
                            "methods-to-list"|"--methods-to-list" => {
                                int|error methods = int:fromString(value);
                                if methods is int {
                                    config.methodsToList = methods;
                                }
                            }
                            "sources"|"--sources" => {
                                if value.length() > 0 {
                                    config.sourcesPath = value;
                                }
                            }
                            _ => {
                            }
                        }
                    }
                }
            }
        }
        i = i + 1;
    }

    return config;
}

function resolveSdkJarPath(string datasetKey) returns string {
    return string `${TEST_JARS_DIR}/${datasetKey}.jar`;
}

function resolveJavadocJarPath(string datasetKey) returns string {
    return string `${TEST_JARS_DIR}/${datasetKey}-javadoc.jar`;
}

function resolveAnalyzerOutputDir(string outputRoot = "") returns string {
    string root = outputRoot.trim();
    if root.length() == 0 {
        return ANALYZER_OUTPUT_DIR;
    }
    return string `${root}/docs/spec`;
}

function resolveApiSpecOutputRoot(string outputRoot = "") returns string {
    string root = outputRoot.trim();
    if root.length() == 0 {
        return "modules/api_specification_generator/spec-output";
    }
    return string `${root}/docs/spec`;
}

function resolveMetadataPath(string datasetKey, string outputRoot = "") returns string {
    return string `${resolveAnalyzerOutputDir(outputRoot)}/${datasetKey}-metadata.json`;
}

function resolveIrPath(string datasetKey, string outputRoot = "") returns string {
    string specOutputDir = resolveApiSpecOutputRoot(outputRoot);
    return string `${specOutputDir}/${datasetKey}-ir.json`;
}

function resolveSpecPath(string datasetKey, string outputRoot = "") returns string {
    string specOutputDir = resolveApiSpecOutputRoot(outputRoot);
    return string `${specOutputDir}/${datasetKey}_spec.bal`;
}

function extractSdkVersionFromDatasetKey(string datasetKey) returns string {
    string[] parts = regex:split(datasetKey, "-");
    foreach string part in parts.reverse() {
        if regex:matches(part, "^[0-9]+\\.[0-9]+.*") {
            return part;
        }
    }

    return "";
}

function resolveConnectorOutputPath(string datasetKey, string outputRoot = "") returns string {
    string root = outputRoot.trim();
    if root.length() > 0 {
        return root;
    }

    if CONNECTOR_OUTPUT_DIR.startsWith("/") {
        return string `${CONNECTOR_OUTPUT_DIR}/${datasetKey}`;
    }
    string cwd = os:getEnv("PWD");
    return string `${cwd}/${CONNECTOR_OUTPUT_DIR}/${datasetKey}`;
}

function resolveNativeOutputPath(string datasetKey, string outputRoot = "") returns string {
    string connectorOutputPath = resolveConnectorOutputPath(datasetKey, outputRoot);
    return string `${connectorOutputPath}/native`;
}

function ensureDirectoryExists(string dirPath, string dirLabel) returns error? {
    boolean exists = check file:test(dirPath, file:EXISTS);
    if !exists {
        return error(string `${dirLabel} not found: ${dirPath}`);
    }
}

function listDatasetKeysFromMetadataDir(string metadataDir) returns string[]|error {
    file:MetaData[] entries = check file:readDir(metadataDir);
    string[] datasetKeys = [];

    foreach file:MetaData entry in entries {
        if entry.dir {
            continue;
        }

        string fileName = extractFileName(entry.absPath);
        if fileName.endsWith("-metadata.json") {
            datasetKeys.push(fileName.substring(0, fileName.length() - 14));
        }
    }

    return datasetKeys;
}

function extractFileName(string absPath) returns string {
    regexp:RegExp sepPattern = re `/|\\`;
    string[] segments = regexp:split(sepPattern, absPath);
    if segments.length() == 0 {
        return absPath;
    }
    return segments[segments.length() - 1];
}

function looksLikePath(string value) returns boolean {
    string v = value.trim();
    if v.length() == 0 {
        return false;
    }

    if v.startsWith("/") || v.startsWith("./") || v.startsWith("../") || v.startsWith("~") {
        return true;
    }

    return v.includes("/") || v.includes("\\");
}

function toAbsolutePath(string path) returns string {
    string trimmed = path.trim();
    if trimmed.startsWith("/") {
        return trimmed;
    }
    string cwd = os:getEnv("PWD");
    return string `${cwd}/${trimmed}`;
}

function ensureFileExists(string filePath, string fileLabel) returns error? {
    boolean exists = check file:test(filePath, file:EXISTS);
    if !exists {
        return error(string `${fileLabel} not found: ${filePath}`);
    }
}

function executeSdkCommand(string[] args) returns error? {
    if args.length() == 0 {
        printSdkUsage();
        return;
    }

    if os:getEnv("ANTHROPIC_API_KEY").length() == 0 {
        return error("ANTHROPIC_API_KEY is not set. The SDK workflow requires an Anthropic API key.");
    }

    string subCommand = args[0];
    string[] subArgs = args.slice(1);

    match subCommand {
        "analyze" => {
            return executeAnalyze(subArgs);
        }
        "generate" => {
            return executeGenerate(subArgs);
        }
        "connector" => {
            return executeConnector(subArgs);
        }
        "fix-code" => {
            return executeFixCode(subArgs);
        }
        "fix-report-only" => {
            return executeFixReportOnly(subArgs);
        }
        "pipeline" => {
            return executePipeline(subArgs);
        }
        "generate-tests" => {
            return executeGenerateTests(subArgs);
        }
        "generate-examples" => {
            return executeGenerateExamples(subArgs);
        }
        "generate-docs" => {
            return executeSdkGenerateDocs(subArgs);
        }
        "generate-all" => {
            return executeSdkGenerateAll(subArgs);
        }
        _ => {
            printSdkUsage();
            return error(string `Unknown SDK command: ${subCommand}`);
        }
    }
}

function executeSdkGenerateDocs(string[] args) returns error? {
    if args.length() < 1 {
        io:println("Usage: bal run -- sdk generate-docs <output-dir> [options]");
        return;
    }

    string outputRoot = toAbsolutePath(args[0].trim());
    string[]|error keys = listDatasetKeysFromMetadataDir(resolveAnalyzerOutputDir(outputRoot));
    if keys is error {
        return error(string `Failed to locate metadata in ${resolveAnalyzerOutputDir(outputRoot)}: ${keys.message()}`);
    }
    if keys.length() == 0 {
        return error(string `Metadata JSON not found in: ${resolveAnalyzerOutputDir(outputRoot)}`);
    }
    if keys.length() > 1 {
        return error(string `Multiple metadata files found. Use: bal run -- generate-docs <doc-command> <dataset-key> <output-dir>`);
    }

    string[] docArgs = ["generate-all", keys[0], outputRoot, ...args.slice(1)];
    return executeGenerateDocs(docArgs);
}

function executeSdkGenerateAll(string[] args) returns error? {
    if args.length() < 1 {
        io:println("Usage: bal run -- sdk generate-all <output-dir> [options]");
        return;
    }

    string outputRoot = toAbsolutePath(args[0].trim());
    string[]|error keys = listDatasetKeysFromMetadataDir(resolveAnalyzerOutputDir(outputRoot));
    if keys is error {
        return error(string `Failed to locate metadata in ${resolveAnalyzerOutputDir(outputRoot)}: ${keys.message()}`);
    }
    if keys.length() == 0 {
        return error(string `Metadata JSON not found in: ${resolveAnalyzerOutputDir(outputRoot)}`);
    }
    if keys.length() > 1 {
        return error(string `Multiple metadata files found. Use: bal run -- generate-docs generate-all <dataset-key> <output-dir>`);
    }

    string[] docArgs = ["generate-all", keys[0], outputRoot, ...args.slice(1)];
    return executeGenerateDocs(docArgs);
}

function printSdkUsage() {
    io:println();
    io:println("SDK Workflow – Java SDK → Ballerina Connector");
    io:println();
    io:println("USAGE:");
    io:println("  bal run -- sdk analyze <dataset-key> <output-dir> [options]");
    io:println("  bal run -- sdk pipeline <dataset-key> <output-dir> [options]");
    io:println("  bal run -- sdk generate <output-dir> [options]");
    io:println("  bal run -- sdk connector <output-dir> [options]");
    io:println("  bal run -- sdk fix-code <output-dir> [options]");
    io:println("  bal run -- sdk fix-report-only <output-dir> [options]");
    io:println("  bal run -- sdk generate-tests <output-dir> [options]");
    io:println("  bal run -- sdk generate-examples <output-dir> [options]");
    io:println("  bal run -- sdk generate-docs <output-dir> [options]");
    io:println("  bal run -- sdk generate-all <output-dir> [options]");
    io:println();
    io:println("COMMANDS:");
    io:println("  analyze          Analyze Java SDK and write metadata");
    io:println("  pipeline         Run full SDK pipeline end-to-end");
    io:println("  generate         Generate API spec + IR from metadata");
    io:println("  connector        Generate Ballerina connector artifacts");
    io:println("  fix-code         Fix Java native + Ballerina compilation errors");
    io:println("  fix-report-only  Run fixer diagnostics without applying fixes");
    io:println("  generate-tests   Generate live integration tests");
    io:println("  generate-examples Generate code examples");
    io:println("  generate-docs    Generate all documentation");
    io:println("  generate-all     Generate all documentation (shortcut)");
    io:println();
    io:println("EXAMPLE:");
    io:println("  bal run -- sdk analyze s3-2.4.0 /home/user/SDK-auto-generated-connectors");
    io:println("  bal run -- sdk pipeline s3-2.4.0 /home/user/SDK-auto-generated-connectors");
    io:println("  bal run -- sdk generate-tests /home/user/SDK-auto-generated-connectors/module-s3");
    io:println();
}

function executeOpenApiCommand(string[] args) returns error? {
    if args.length() == 0 {
        printOpenApiUsage();
        return;
    }

    if os:getEnv("ANTHROPIC_API_KEY").length() == 0 {
        io:println("WARNING: ANTHROPIC_API_KEY is not set. AI-powered steps (sanitize, generate-tests, generate-examples, generate-docs) will fail.");
    }

    string subCommand = args[0];
    string[] subArgs = args.slice(1);

    match subCommand {
        "sanitize" => {
            return sanitizor:executeSanitizor(...subArgs);
        }
        "generate-client" => {
            return client_generator:executeClientGen(...subArgs);
        }
        "generate-tests" => {
            return test_generator:executeTestGen("openapi", ...subArgs);
        }
        "generate-examples" => {
            return example_generator:executeExampleGen(...subArgs);
        }
        "generate-docs" => {
            return document_generator:executeDocGen(...subArgs);
        }
        "generate-all" => {
            string[] docArgs = ["generate-all", ...subArgs];
            return document_generator:executeDocGen(...docArgs);
        }
        "fix-code" => {
            return fixer:executeCodeFixer(...subArgs);
        }
        "pipeline" => {
            return runOpenApiPipeline(subArgs);
        }
        _ => {
            printOpenApiUsage();
            return error(string `Unknown OpenAPI command: ${subCommand}`);
        }
    }
}

function runOpenApiPipeline(string[] args) returns error? {
    if args.length() < 2 {
        io:println("Usage: bal run -- openapi pipeline <openapi-spec> <output-dir> [options]");
        return;
    }

    string openApiSpec = args[0];
    string outputDir = args[1];
    string[] pipelineOptions = args.slice(2);

    boolean quietMode = false;
    boolean autoYes = false;

    foreach string option in pipelineOptions {
        if option == "quiet" {
            quietMode = true;
        } else if option == "yes" {
            autoYes = true;
        }
    }

    printOpenApiPipelineHeader(openApiSpec, outputDir, quietMode);

    printOpenApiStepHeader(1, "Sanitizing OpenAPI Specification", quietMode);
    string[] sanitizeArgs = [openApiSpec, outputDir, ...pipelineOptions];
    error? sanitizeResult = sanitizor:executeSanitizor(...sanitizeArgs);
    if sanitizeResult is error {
        io:println(string `Sanitization failed: ${sanitizeResult.message()}`);
        return sanitizeResult;
    }
    if !quietMode {
        io:println("Sanitization completed successfully");
    }

    printOpenApiStepHeader(2, "Generating Ballerina Client", quietMode);
    string sanitizedSpec = string `${outputDir}/docs/spec/aligned_ballerina_openapi.json`;
    string clientPath = string `${outputDir}/ballerina`;
    string[] clientArgs = [sanitizedSpec, clientPath, ...pipelineOptions];
    error? clientResult = client_generator:executeClientGen(...clientArgs);
    if clientResult is error {
        io:println(string `Client generation failed: ${clientResult.message()}`);
        io:println("Continuing pipeline...");
    } else if !quietMode {
        io:println("Client generation completed successfully");
    }

    printOpenApiStepHeader(3, "Building and Validating Client", quietMode);
    oautils:CommandResult buildResult = oautils:executeBalBuild(clientPath, quietMode);
    if oautils:hasCompilationErrors(buildResult) {
        io:println("Build validation failed: client contains compilation errors");
        io:println("Run 'bal run -- openapi fix-code <connector-path>' to resolve, or fix manually");
        return error(string `Client build failed: ${buildResult.stderr}`);
    }
    if !quietMode {
        io:println("Client built and validated successfully");
    }

    printOpenApiStepHeader(4, "Generating Examples", quietMode);
    string[] exampleArgs = [outputDir, ...pipelineOptions];
    error? exampleResult = example_generator:executeExampleGen(...exampleArgs);
    if exampleResult is error {
        io:println(string `Example generation failed: ${exampleResult.message()}`);
        io:println("Continuing pipeline...");
    } else if !quietMode {
        io:println("Example generation completed successfully");
    }

    printOpenApiStepHeader(5, "Generating Tests", quietMode);
    string[] testArgs = [outputDir, sanitizedSpec, ...pipelineOptions];
    error? testResult = test_generator:executeTestGen("openapi", ...testArgs);
    if testResult is error {
        io:println(string `Test generation failed: ${testResult.message()}`);
        io:println("Continuing pipeline...");
    } else if !quietMode {
        io:println("Test generation completed successfully");
    }

    printOpenApiStepHeader(6, "Generating Documentation", quietMode);
    string[] docArgs = ["generate-all", outputDir, ...pipelineOptions];
    error? docResult = document_generator:executeDocGen(...docArgs);
    if docResult is error {
        io:println(string `Documentation generation failed: ${docResult.message()}`);
    } else if !quietMode {
        io:println("Documentation generation completed successfully");
    }

    printOpenApiPipelineCompletion(outputDir, quietMode);
}

function printOpenApiPipelineHeader(string openApiSpec, string outputDir, boolean quietMode) {
    if quietMode {
        return;
    }
    string sep = createMainSeparator("=", 70);
    io:println("");
    io:println(sep);
    io:println("OpenAPI Connector Automation Pipeline");
    io:println(sep);
    io:println(string `Input : ${openApiSpec}`);
    io:println(string `Output: ${outputDir}`);
    io:println("");
    io:println("Pipeline Steps:");
    io:println("  1. Sanitize OpenAPI specification");
    io:println("  2. Generate Ballerina client");
    io:println("  3. Build and validate client");
    io:println("  4. Generate examples");
    io:println("  5. Generate tests");
    io:println("  6. Generate documentation");
    io:println(sep);
}

function printOpenApiStepHeader(int stepNum, string title, boolean quietMode) {
    if quietMode {
        return;
    }
    string sep = createMainSeparator("-", 60);
    io:println("");
    io:println(string `[${stepNum}/6] ${title}`);
    io:println(sep);
}

function printOpenApiPipelineCompletion(string outputDir, boolean quietMode) {
    string sep = createMainSeparator("=", 70);
    io:println("");
    io:println(sep);
    io:println("OpenAPI Pipeline Completed");
    io:println(sep);
    io:println(string `  Sanitized specification : ${outputDir}/docs/spec/`);
    io:println(string `  Ballerina client        : ${outputDir}/ballerina/`);
    io:println(string `  Usage examples          : ${outputDir}/examples/`);
    io:println(string `  Test suite              : ${outputDir}/ballerina/tests/`);
    io:println(string `  Documentation           : ${outputDir}`);
    if !quietMode {
        io:println(sep);
    }
}

function printOpenApiUsage() {
    io:println();
    io:println("OpenAPI Workflow - OpenAPI Spec → Ballerina Connector");
    io:println();
    io:println("USAGE:");
    io:println("  bal run -- openapi pipeline <spec> <output-dir> [options]");
    io:println("  bal run -- openapi sanitize <spec> <output-dir> [options]");
    io:println("  bal run -- openapi generate-client <spec> <output-dir> [options]");
    io:println("  bal run -- openapi fix-code <connector-path> [options]");
    io:println("  bal run -- openapi generate-tests <connector-path> <spec-path> [options]");
    io:println("  bal run -- openapi generate-examples <connector-path> [options]");
    io:println("  bal run -- openapi generate-docs <doc-command> <connector-path> [options]");
    io:println();
    io:println("COMMANDS:");
    io:println("  pipeline          Run full OpenAPI pipeline end-to-end");
    io:println("  sanitize          Sanitize and enhance the OpenAPI specification");
    io:println("  generate-client   Generate Ballerina client from sanitized spec");
    io:println("  fix-code          Fix compilation errors in generated client");
    io:println("  generate-tests    Generate mock server + live integration tests");
    io:println("  generate-examples Generate code examples for the connector");
    io:println("  generate-docs     Generate documentation (specify doc-command)");
    io:println();
    io:println("DOC COMMANDS (for generate-docs):");
    io:println("  generate-all");
    io:println("  generate-ballerina");
    io:println("  generate-tests");
    io:println("  generate-examples");
    io:println("  generate-individual-examples");
    io:println("  generate-main");
    io:println();
    io:println("OPTIONS:");
    io:println("  yes      Auto-confirm all prompts");
    io:println("  quiet    Minimal logging output");
    io:println();
    io:println("EXAMPLES:");
    io:println("  bal run -- openapi pipeline /home/user/spec.yaml /home/user/my-connector");
    io:println("  bal run -- openapi sanitize /home/user/spec.yaml /home/user/my-connector");
    io:println("  bal run -- openapi generate-client /home/user/spec.yaml /home/user/my-connector");
    io:println("  bal run -- openapi fix-code /home/user/my-connector/ballerina");
    io:println("  bal run -- openapi generate-tests /home/user/my-connector /home/user/spec.yaml");
    io:println("  bal run -- openapi generate-docs /home/user/my-connector");
    io:println();
}

function printMainUsage() {
    io:println();
    io:println("Connector Automator");
    io:println();
    io:println("USAGE:");
    io:println("  bal run -- sdk <command> [args...]      SDK (Java SDK) workflow");
    io:println("  bal run -- openapi <command> [args...]  OpenAPI spec workflow");
    io:println();
    io:println("SDK COMMANDS:");
    io:println("  sdk analyze <dataset-key> <output-dir>     Analyze Java SDK");
    io:println("  sdk pipeline <dataset-key> <output-dir>    Run full SDK pipeline");
    io:println("  sdk generate <output-dir>                  Generate API spec + IR");
    io:println("  sdk connector <output-dir>                 Generate connector");
    io:println("  sdk fix-code <output-dir>                  Fix compilation errors");
    io:println("  sdk generate-tests <output-dir>            Generate live tests");
    io:println("  sdk generate-examples <output-dir>         Generate examples");
    io:println("  sdk generate-docs <output-dir>             Generate documentation");
    io:println();
    io:println("OPENAPI COMMANDS:");
    io:println("  openapi pipeline <spec> <output-dir>       Run full OpenAPI pipeline");
    io:println("  openapi sanitize <spec> <output-dir>       Sanitize OpenAPI specification");
    io:println("  openapi generate-client <spec> <output>    Generate Ballerina client");
    io:println("  openapi fix-code <connector-path>          Fix compilation errors");
    io:println("  openapi generate-tests <path> <spec>       Generate mock + live tests");
    io:println("  openapi generate-examples <path>           Generate examples");
    io:println("  openapi generate-docs <cmd> <path>         Generate documentation");
    io:println();
    io:println("EXAMPLES:");
    io:println("  bal run -- sdk analyze s3-2.4.0 /home/user/SDK-auto-generated-connectors");
    io:println("  bal run -- sdk pipeline s3-2.4.0 /home/user/SDK-auto-generated-connectors");
    io:println("  bal run -- sdk generate-tests /home/user/SDK-auto-generated-connectors/module-s3");
    io:println("  bal run -- openapi generate-tests /home/user/my-connector /home/user/spec.yaml");
    io:println();
}

function printAnalyzeUsage() {
    io:println();
    io:println("Analyze Java SDK and write deterministic metadata output");
    io:println();
    io:println("USAGE:");
    io:println("  bal run -- analyze <dataset-key> <output-dir> [options]");
    io:println();
    io:println("INPUT RESOLUTION:");
    io:println("  SDK JAR      test-jars/<dataset-key>.jar");
    io:println("  Javadoc JAR  test-jars/<dataset-key>-javadoc.jar");
    io:println();
    io:println("OUTPUT:");
    io:println("  <output-dir>/docs/spec/<dataset-key>-metadata.json");
    io:println();
    io:println("OPTIONS:");
    io:println("  quiet                       Minimal logging output");
    io:println();
    io:println("EXAMPLE:");
    io:println("  bal run -- analyze s3-2.4.0 /home/user/SDK-auto-generated-connectors quiet");
    io:println("  bal run -- analyze kafka-clients-3.9.1 /home/user/SDK-auto-generated-connectors");
    io:println();
}

function printGenerateUsage() {
    io:println();
    io:println("Generate Ballerina API specification from fixed metadata output");
    io:println();
    io:println("USAGE:");
    io:println("  bal run -- generate <output-dir> [options]");
    io:println();
    io:println("INPUT:");
    io:println("  <output-dir>/docs/spec/*-metadata.json");
    io:println();
    io:println("OUTPUT:");
    io:println("  <output-dir>/docs/spec/<dataset-key>-ir.json");
    io:println("  <output-dir>/docs/spec/<dataset-key>_spec.bal");
    io:println();
    io:println("OPTIONS:");
    io:println("  quiet            Minimal logging output");
    io:println("  no-thinking      Disable LLM extended thinking");
    io:println();
    io:println("EXAMPLE:");
    io:println("  bal run -- generate /home/user/SDK-auto-generated-connectors");
    io:println();
}

function printPipelineUsage() {
    io:println();
    io:println("Full Pipeline: Analyze SDK → Generate API Spec → Generate Connector");
    io:println();
    io:println("USAGE:");
    io:println("  bal run -- pipeline <dataset-key> <output-dir> [options]");
    io:println();
    io:println("INPUT RESOLUTION:");
    io:println("  SDK JAR      test-jars/<dataset-key>.jar");
    io:println("  Javadoc JAR  test-jars/<dataset-key>-javadoc.jar");
    io:println();
    io:println("OUTPUTS:");
    io:println("  <output-dir>/docs/spec/<dataset-key>-metadata.json");
    io:println("  <output-dir>/docs/spec/<dataset-key>-ir.json");
    io:println("  <output-dir>/docs/spec/<dataset-key>_spec.bal");
    io:println("  <output-dir>/ballerina/... and <output-dir>/native/...");
    io:println();
    io:println("OPTIONS:");
    io:println("  yes                     Auto-confirm continuation prompts");
    io:println("  --fix-code              Run full code fixer phase (default: enabled)");
    io:println("  --fix-report-only       Run fixer in diagnostics mode");
    io:println("  --skip-fix              Skip code fixing phase");
    io:println("  --skip-tests            Skip test generation phase");
    io:println("  --generate-examples     Run example generation phase");
    io:println("  --skip-examples         Skip example generation phase");
    io:println("  --generate-docs         Run documentation generation phase");
    io:println("  --skip-docs             Skip documentation generation phase");
    io:println("  --fix-iterations=<n>    Maximum fixer iterations (default: 3)");
    io:println("  quiet                   Minimal logging output");
    io:println();
    io:println("EXAMPLE:");
    io:println("  bal run -- pipeline s3-2.4.0 /home/user/SDK-auto-generated-connectors --fix-code");
    io:println();
}
