import ballerina/io;
import ballerina/os;

public function executeDocGen(string... args) returns error? {
    if args.length() == 0 {
        printUsage();
        return;
    }

    if args.length() < 2 {
        io:println("✗ Missing connector path");
        printUsage();
        return;
    }

    string command = args[0];
    string connectorPath = args[1];

    boolean autoYes = false;
    boolean quietMode = false;
    foreach string arg in args {
        if arg == "yes" {
            autoYes = true;
        } else if arg == "quiet" {
            quietMode = true;
        }
    }

    if autoYes && !quietMode {
        io:println("ℹ  Auto-confirm mode enabled");
    }
    if quietMode {
        io:println("ℹ  Quiet mode enabled");
    }

    match command {
        "generate-all" => {
            check generateAllReadmes(connectorPath, autoYes, quietMode);
        }
        "generate-ballerina" => {
            check genBallerinaReadme(connectorPath, autoYes, quietMode);
        }
        "generate-tests" => {
            check genTestsReadme(connectorPath, autoYes, quietMode);
        }
        "generate-examples" => {
            check genExamplesReadme(connectorPath, autoYes, quietMode);
        }
        "generate-individual-examples" => {
            check genIndividualExampleReadmes(connectorPath, autoYes, quietMode);
        }
        "generate-main" => {
            check genMainReadme(connectorPath, autoYes, quietMode);
        }
        _ => {
            io:println(string `✗ Unknown command: '${command}'`);
            printUsage();
        }
    }
}

function generateAllReadmes(string connectorPath, boolean autoYes, boolean quietMode) returns error? {
    printDocumentationPlan(connectorPath, quietMode);

    if !quietMode {
        io:println("");
        io:println("⚠  AI-Generated Content Notice:");
        io:println("   All documentation is AI-generated and requires review");
        io:println("   Verify links, credentials, and technical accuracy");
    }

    if !getUserConfirmation("\nProceed with documentation generation?", autoYes) {
        io:println("✗ Operation cancelled");
        return;
    }

    check validateApiKey();

    error? initResult = initDocumentationGenerator();
    if initResult is error {
        io:println(string `✗ AI initialization failed: ${initResult.message()}`);
        if !getUserConfirmation("Continue despite failure?", autoYes) {
            return initResult;
        }
    } else {
        io:println("✓ AI generator initialized");
    }

    io:println("");
    io:println("Generating documentation files...");

    error? result = generateAllDocumentation(connectorPath);
    if result is error {
        io:println(string `✗ Generation failed: ${result.message()}`);
        if !getUserConfirmation("Continue despite failure?", autoYes) {
            return result;
        }
    }

    printDocCompletionSummary(connectorPath, quietMode);
}

function genBallerinaReadme(string connectorPath, boolean autoYes, boolean quietMode) returns error? {
    printDocTypeHeader("Ballerina Module README", connectorPath, quietMode);

    if !getUserConfirmation("Proceed with generation?", autoYes) {
        io:println("✗ Operation cancelled");
        return;
    }

    check validateApiKey();
    check initDocumentationGenerator();

    io:println("Generating README...");
    error? result = generateBallerinaReadme(connectorPath);
    if result is error {
        io:println(string `✗ Generation failed: ${result.message()}`);
        return result;
    }

    io:println("");
    io:println("✓ README generated successfully");
    io:println(string `  Output: ${connectorPath}/ballerina/README.md`);

    if !quietMode {
        io:println("");
        io:println("⚠  Review required: API URLs, setup steps, code examples");
    }
}

function genTestsReadme(string connectorPath, boolean autoYes, boolean quietMode) returns error? {
    printDocTypeHeader("Tests README", connectorPath, quietMode);

    if !getUserConfirmation("Proceed with generation?", autoYes) {
        io:println("✗ Operation cancelled");
        return;
    }

    check validateApiKey();
    check initDocumentationGenerator();

    io:println("Generating README...");
    error? result = generateTestsReadme(connectorPath);
    if result is error {
        io:println(string `✗ Generation failed: ${result.message()}`);
        return result;
    }

    io:println("");
    io:println("✓ README generated successfully");
    io:println(string `  Output: ${connectorPath}/tests/README.md`);

    if !quietMode {
        io:println("");
        io:println("⚠  Review required: Environment variables, test commands");
    }
}

function genExamplesReadme(string connectorPath, boolean autoYes, boolean quietMode) returns error? {
    printDocTypeHeader("Examples README", connectorPath, quietMode);

    if !getUserConfirmation("Proceed with generation?", autoYes) {
        io:println("✗ Operation cancelled");
        return;
    }

    check validateApiKey();
    check initDocumentationGenerator();

    io:println("Generating README...");
    error? result = generateExamplesReadme(connectorPath);
    if result is error {
        io:println(string `✗ Generation failed: ${result.message()}`);
        return result;
    }

    io:println("");
    io:println("✓ README generated successfully");
    io:println(string `  Output: ${connectorPath}/examples/README.md`);

    if !quietMode {
        io:println("");
        io:println("⚠  Review required: Example descriptions, GitHub links");
    }
}

function genIndividualExampleReadmes(string connectorPath, boolean autoYes, boolean quietMode) returns error? {
    printDocTypeHeader("Individual Example READMEs", connectorPath, quietMode);

    if !getUserConfirmation("Proceed with generation?", autoYes) {
        io:println("✗ Operation cancelled");
        return;
    }

    check validateApiKey();
    check initDocumentationGenerator();

    io:println("Generating READMEs...");
    error? result = generateIndividualExampleReadmes(connectorPath);
    if result is error {
        io:println(string `✗ Generation failed: ${result.message()}`);
        return result;
    }

    io:println("");
    io:println("✓ READMEs generated successfully");
    io:println(string `  Output: ${connectorPath}/examples/*/README.md`);

    if !quietMode {
        io:println("");
        io:println("⚠  Review required: Config.toml values, curl commands");
    }
}

function genMainReadme(string connectorPath, boolean autoYes, boolean quietMode) returns error? {
    printDocTypeHeader("Root README", connectorPath, quietMode);

    if !getUserConfirmation("Proceed with generation?", autoYes) {
        io:println("✗ Operation cancelled");
        return;
    }

    check validateApiKey();
    check initDocumentationGenerator();

    io:println("Generating README...");
    error? result = generateMainReadme(connectorPath);
    if result is error {
        io:println(string `✗ Generation failed: ${result.message()}`);
        return result;
    }

    io:println("");
    io:println("✓ README generated successfully");
    io:println(string `  Output: ${connectorPath}/README.md`);

    if !quietMode {
        io:println("");
        io:println("⚠  Review required: CI/CD badges, package links");
    }
}

function printDocumentationPlan(string connectorPath, boolean quietMode) {
    if quietMode {
        return;
    }

    string sep = createSeparator("=", 70);
    io:println(sep);
    io:println("Documentation Generation");
    io:println(sep);
    io:println(string `Connector: ${connectorPath}`);
    io:println("");
    io:println("Documentation Files:");
    io:println("  1. Ballerina module README");
    io:println("  2. Tests README");
    io:println("  3. Main examples README");
    io:println("  4. Individual example READMEs");
    io:println("  5. Root module README");
    io:println(sep);
}

function printDocTypeHeader(string docType, string connectorPath, boolean quietMode) {
    if quietMode {
        return;
    }

    string sep = createSeparator("-", 60);
    io:println("");
    io:println(docType);
    io:println(sep);
    io:println(string `Connector: ${connectorPath}`);
    io:println(sep);
}

function printDocCompletionSummary(string connectorPath, boolean quietMode) {
    string sep = createSeparator("=", 70);

    io:println("");
    io:println(sep);
    io:println("Documentation Generation Complete");
    io:println(sep);
    io:println("");
    io:println("Generated Files:");
    io:println(string `  • ${connectorPath}/README.md`);
    io:println(string `  • ${connectorPath}/ballerina/README.md`);
    io:println(string `  • ${connectorPath}/tests/README.md`);
    io:println(string `  • ${connectorPath}/examples/README.md`);
    io:println(string `  • ${connectorPath}/examples/*/README.md`);

    if !quietMode {
        io:println("");
        io:println("⚠  Manual Review Required:");
        io:println("   • API URLs and documentation links");
        io:println("   • Authentication steps and credentials");
        io:println("   • Code examples and Config.toml variables");
        io:println("   • GitHub repository links and CI/CD badges");
        io:println("   • Example descriptions and functionality");
    }

    io:println("");
    io:println("Next Steps:");
    io:println("  • Review generated READMEs for accuracy");
    io:println("  • Test example commands and configurations");
    io:println("  • Update links and badges as needed");
    io:println(sep);
}

function getUserConfirmation(string message, boolean autoYes) returns boolean {
    if autoYes {
        return true;
    }
    io:print(string `${message} (y/n): `);
    string|io:Error userInput = io:readln();
    if userInput is io:Error {
        return false;
    }
    return userInput.trim().toLowerAscii() is "y"|"yes";
}

function validateApiKey() returns error? {
    string|error apiKey = os:getEnv("ANTHROPIC_API_KEY");
    if apiKey is error {
        return error("ANTHROPIC_API_KEY not configured");
    }
}

function createSeparator(string char, int length) returns string {
    string[] chars = [];
    int i = 0;
    while i < length {
        chars.push(char);
        i += 1;
    }
    return string:'join("", ...chars);
}

function printUsage() {
    io:println("Documentation Generator");
    io:println("");
    io:println("USAGE");
    io:println("  bal run -- generate-docs <command> <connector-path> [options]");
    io:println("");
    io:println("COMMANDS");
    io:println("  generate-all                 Generate all READMEs");
    io:println("  generate-ballerina           Generate module README");
    io:println("  generate-tests               Generate tests README");
    io:println("  generate-examples            Generate examples README");
    io:println("  generate-individual-examples Generate example READMEs");
    io:println("  generate-main                Generate root README");
    io:println("");
    io:println("OPTIONS");
    io:println("  yes      Auto-confirm all prompts");
    io:println("  quiet    Minimal logging output");
    io:println("");
    io:println("EXAMPLES");
    io:println("  bal run -- generate-docs generate-all ./connector");
    io:println("  bal run -- generate-docs generate-ballerina ./connector yes");
    io:println("  bal run -- generate-docs generate-all ./connector yes quiet");
    io:println("");
    io:println("ENVIRONMENT");
    io:println("  ANTHROPIC_API_KEY    Required for AI-powered documentation");
    io:println("");
    io:println("FEATURES");
    io:println("  • AI-generated documentation with templates");
    io:println("  • Multiple README types for different audiences");
    io:println("  • Interactive confirmation prompts");
    io:println("  • CI/CD friendly with auto-confirm mode");
    io:println("  • Comprehensive review guidelines");
    io:println("");
}
