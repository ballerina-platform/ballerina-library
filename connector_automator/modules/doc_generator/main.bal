import connector_automator.cost_calculator;

import ballerina/io;
import ballerina/os;

public function main(string... args) returns error? {
    io:println("Starting Ballerina Connector Documentation Generator...\n");

    if args.length() == 0 {
        printUsage();
        return;
    }

    if args.length() < 2 {
        io:println("Error: Missing connector path");
        printUsage();
        return;
    }

    string command = args[0];
    string connectorPath = args[1];

    // Check for auto flag and quiet mode
    boolean autoYes = false;
    boolean quietMode = false;
    foreach string arg in args {
        if arg == "yes" {
            autoYes = true;
        } else if arg == "quiet" {
            quietMode = true;
        }
    }

    if autoYes {
        if !quietMode {
            io:println("Running in automated mode - all prompts will be auto-confirmed");
        }
    }

    if quietMode {
        if !autoYes {
            io:println("Running in quiet mode - reduced logging output");
        }
        io:println("Quiet mode enabled - minimal logging output");
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
            io:println("Error: Unknown command '" + command + "'");
            printUsage();
        }
    }
}

function printUsage() {
    io:println("Ballerina Connector Documentation Generator");
    io:println("");
    io:println("Usage: bal run doc_generator -- <command> <connector-path> [options]");
    io:println("");
    io:println("Commands:");
    io:println("  generate-all                 Generate all README files");
    io:println("  generate-ballerina           Generate core module README");
    io:println("  generate-tests               Generate tests README");
    io:println("  generate-examples            Generate main examples README");
    io:println("  generate-individual-examples Generate individual example READMEs");
    io:println("  generate-main                Generate root README");
    io:println("");
    io:println("Options:");
    io:println("  yes                          Auto-confirm all prompts (for CI/CD)");
    io:println("  quiet                        Reduce logging output");
    io:println("");
    io:println("Examples:");
    io:println("  bal run doc_generator -- generate-all /path/to/connector");
    io:println("  bal run doc_generator -- generate-all /path/to/connector yes");
    io:println("  bal run doc_generator -- generate-all /path/to/connector yes quiet");
    io:println("");
    io:println("Environment Variables:");
    io:println("  ANTHROPIC_API_KEY            Required for AI-powered documentation generation");
    io:println("");
}

// Helper function to get user confirmation
function getUserConfirmation(string message, boolean autoYes = false) returns boolean {
    if autoYes {
        io:println(string `${message} (y/n): y [auto-confirmed]`);
        return true;
    }

    io:print(string `${message} (y/n): `);
    string|io:Error userInput = io:readln();
    if userInput is io:Error {
        io:println("Failed to read user input, defaulting to 'no'");
        return false;
    }
    string trimmedInput = userInput.trim().toLowerAscii();
    return trimmedInput == "y" || trimmedInput == "yes";
}

function generateAllReadmes(string connectorPath, boolean autoYes = false, boolean quietMode = false) returns error? {

    cost_calculator:resetCostTracking();

    io:println(string `Connector path: ${connectorPath}`);
    io:println("\nREADMEs to be generated:");
    io:println("1. Ballerina module README (/ballerina/README.md)");
    io:println("2. Tests README (/tests/README.md)");
    io:println("3. Main examples README (/examples/README.md)");
    io:println("4. Individual example READMEs (/examples/*/README.md)");
    io:println("5. Root module README (/README.md)");

    if !autoYes && !quietMode {
        io:println("\n  AI Generation Notice:");
        io:println("   These READMEs are generated using AI and may contain inaccuracies.");
        io:println("   Manual review and verification is strongly recommended.");
    }

    if !getUserConfirmation("\nProceed with generating all READMEs?", autoYes) {
        io:println("Operation cancelled by user.");
        return;
    }

    check validateApiKey();

    error? initResult = initDocumentationGenerator();
    if initResult is error {
        if !quietMode {
            io:println("Error initializing AI generator: " + initResult.message());
        }

        if !getUserConfirmation("Continue despite initialization failure?", autoYes) {
            return error("AI generator initialization failed: " + initResult.message());
        }
    } else {
        if !quietMode {
            io:println("✓ AI generator initialized successfully");
        }
    }

    error? result = generateAllDocumentation(connectorPath);
    if result is error {
        if !quietMode {
            io:println("Error generating documentation: " + result.message());
        }

        if !getUserConfirmation("Continue despite generation failure?", autoYes) {
            return error("Documentation generation failed: " + result.message());
        }
    } else {
        io:println("✓ All READMEs generated successfully!");

        decimal totalCost = cost_calculator:getTotalCost();
        io:println(string ` Total Documentation Generation Cost: $${totalCost.toString()}`);

        if !quietMode {
            io:println("Generated files can be found in the respective directories under: " + connectorPath);
            io:println("\n IMPORTANT: All content is AI-generated and requires manual review!");
            io:println(" Please verify across all generated READMEs:");
            io:println("   - All API URLs, documentation links, and setup guides");
            io:println("   - Authentication steps and credential formats");
            io:println("   - Code examples, Config.toml variables, and syntax");
            io:println("   - GitHub repository links and CI/CD badge URLs");
            io:println("   - Example descriptions matching actual functionality");
            io:println("   - Test commands and environment variable names");
        }
    }
}

function genBallerinaReadme(string connectorPath, boolean autoYes = false, boolean quietMode = false) returns error? {
    cost_calculator:resetCostTracking();

    io:println("=== Ballerina Module README Generation ===");
    io:println(string `Connector path: ${connectorPath}`);
    io:println("This will generate the core Ballerina module README file with:");
    io:println("• Service overview with official links");
    io:println("• Step-by-step setup guide with credentials");
    io:println("• Quickstart code example with authentication");
    io:println("• List of available examples with descriptions");

    if !getUserConfirmation("\nProceed with Ballerina README generation?", autoYes) {
        io:println("Operation cancelled by user.");
        return;
    }

    check validateApiKey();

    error? initResult = initDocumentationGenerator();
    if initResult is error {
        if !quietMode {
            io:println("Error initializing AI generator: " + initResult.message());
        }
        return error("AI generator initialization failed: " + initResult.message());
    }

    if !quietMode {
        io:println("✓ AI generator initialized successfully");
        io:println("Generating Ballerina module README...");
    }

    error? result = generateBallerinaReadme(connectorPath);
    if result is error {
        if !quietMode {
            io:println("Error generating Ballerina README: " + result.message());
        }
        return error("Ballerina README generation failed: " + result.message());
    }

    decimal totalCost = cost_calculator:getTotalCost();
    io:println("✓ Ballerina README generated successfully!");
    io:println(string ` Cost: $${totalCost.toString()}`);

    if !quietMode {
        io:println(string `Generated file: ${connectorPath}/ballerina/README.md`);
        io:println(" Note: This is AI-generated content. Please review and verify all information, especially:");
        io:println("   - API URLs and documentation links");
        io:println("   - Authentication setup steps");
        io:println("   - Code examples and syntax");
    }
}

function genTestsReadme(string connectorPath, boolean autoYes = false, boolean quietMode = false) returns error? {
    cost_calculator:resetCostTracking();

    io:println("=== Tests README Generation ===");
    io:println(string `Connector path: ${connectorPath}`);
    io:println("This will generate the Tests README file with:");
    io:println("• Prerequisites for running tests");
    io:println("• Mock server vs live API test environments");
    io:println("• Configuration setup (Config.toml and environment variables)");
    io:println("• Commands to execute tests");

    if !getUserConfirmation("\nProceed with Tests README generation?", autoYes) {
        io:println("Operation cancelled by user.");
        return;
    }

    check validateApiKey();

    error? initResult = initDocumentationGenerator();
    if initResult is error {
        if !quietMode {
            io:println("Error initializing AI generator: " + initResult.message());
        }
        return error("AI generator initialization failed: " + initResult.message());
    }

    if !quietMode {
        io:println("✓ AI generator initialized successfully");
        io:println("Generating Tests README...");
    }

    error? result = generateTestsReadme(connectorPath);
    if result is error {
        if !quietMode {
            io:println("Error generating Tests README: " + result.message());
        }
        return error("Tests README generation failed: " + result.message());
    }

    decimal totalCost = cost_calculator:getTotalCost();
    io:println("✓ Tests README generated successfully!");
    io:println(string ` Cost: $${totalCost.toString()}`);
    if !quietMode {
        io:println(string `Generated file: ${connectorPath}/tests/README.md`);
        io:println(" Note: This is AI-generated content. Please review and verify:");
        io:println("   - Environment variable names and values");
        io:println("   - Test execution commands");
        io:println("   - Configuration file formats");
    }
}

function genIndividualExampleReadmes(string connectorPath, boolean autoYes = false, boolean quietMode = false) returns error? {
    cost_calculator:resetCostTracking();

    io:println("=== Individual Example READMEs Generation ===");
    io:println(string `Connector path: ${connectorPath}`);
    io:println("This will generate individual README files for each example with:");
    io:println("• Human-readable titles and use case descriptions");
    io:println("• Connector-specific setup guides with links");
    io:println("• Accurate Config.toml examples matching configurable variables");
    io:println("• Appropriate run instructions (with/without curl commands)");

    if !getUserConfirmation("\nProceed with Individual Example READMEs generation?", autoYes) {
        io:println("Operation cancelled by user.");
        return;
    }

    check validateApiKey();

    error? initResult = initDocumentationGenerator();
    if initResult is error {
        if !quietMode {
            io:println("Error initializing AI generator: " + initResult.message());
        }
        return error("AI generator initialization failed: " + initResult.message());
    }

    if !quietMode {
        io:println("✓ AI generator initialized successfully");
        io:println("Generating Individual Example READMEs...");
    }

    error? result = generateIndividualExampleReadmes(connectorPath);
    if result is error {
        if !quietMode {
            io:println("Error generating Individual Example READMEs: " + result.message());
        }
        return error("Individual Example READMEs generation failed: " + result.message());
    }

    decimal totalCost = cost_calculator:getTotalCost();
    io:println("✓ Individual Example READMEs generated successfully!");
    io:println(string ` Cost: $${totalCost.toString()}`);

    if !quietMode {
        io:println(string `Generated files in: ${connectorPath}/examples/*/README.md`);
        io:println(" Note: This is AI-generated content. Please review each example README for:");
        io:println("   - Correct Config.toml variable names and formats");
        io:println("   - Accurate setup guide links");
        io:println("   - Proper curl commands for HTTP services");
        io:println("   - Example descriptions matching actual functionality");
    }
}

function genExamplesReadme(string connectorPath, boolean autoYes = false, boolean quietMode = false) returns error? {
    cost_calculator:resetCostTracking();

    io:println("=== Main Examples README Generation ===");
    io:println(string `Connector path: ${connectorPath}`);
    io:println("This will generate the main Examples README file with:");
    io:println("• Connector overview with example scenarios");
    io:println("• Numbered list of examples with GitHub links");
    io:println("• Prerequisites and credential setup");
    io:println("• Build and run instructions");

    if !getUserConfirmation("\nProceed with Examples README generation?", autoYes) {
        io:println("Operation cancelled by user.");
        return;
    }

    check validateApiKey();

    error? initResult = initDocumentationGenerator();
    if initResult is error {
        if !quietMode {
            io:println("Error initializing AI generator: " + initResult.message());
        }
        return error("AI generator initialization failed: " + initResult.message());
    }

    if !quietMode {
        io:println("✓ AI generator initialized successfully");
        io:println("Generating Examples README...");
    }

    error? result = generateExamplesReadme(connectorPath);
    if result is error {
        if !quietMode {
            io:println("Error generating Examples README: " + result.message());
        }
        return error("Examples README generation failed: " + result.message());
    }

    decimal totalCost = cost_calculator:getTotalCost();
    io:println("✓ Examples README generated successfully!");
    io:println(string ` Cost: $${totalCost.toString()}`);
    if !quietMode {
        io:println(string `Generated file: ${connectorPath}/examples/README.md`);
        io:println(" Note: This is AI-generated content. Please verify:");
        io:println("   - Example names and descriptions");
        io:println("   - GitHub repository links");
        io:println("   - Build commands and prerequisites");
    }
}

function genMainReadme(string connectorPath, boolean autoYes = false, boolean quietMode = false) returns error? {
    cost_calculator:resetCostTracking();

    io:println("=== Root Module README Generation ===");
    io:println(string `Connector path: ${connectorPath}`);
    io:println("This will generate the root README file with:");
    io:println("• Header with connector name and CI/CD badges");
    io:println("• Complete overview, setup guide, and quickstart");
    io:println("• Examples section with GitHub links");
    io:println("• Useful links to Ballerina Central and community resources");

    if !getUserConfirmation("\nProceed with Main README generation?", autoYes) {
        io:println("Operation cancelled by user.");
        return;
    }

    check validateApiKey();

    error? initResult = initDocumentationGenerator();
    if initResult is error {
        if !quietMode {
            io:println("Error initializing AI generator: " + initResult.message());
        }
        return error("AI generator initialization failed: " + initResult.message());
    }

    if !quietMode {
        io:println("✓ AI generator initialized successfully");
        io:println("Generating Main README...");
    }

    error? result = generateMainReadme(connectorPath);
    if result is error {
        if !quietMode {
            io:println("Error generating Main README: " + result.message());
        }
        return error("Main README generation failed: " + result.message());
    }

    decimal totalCost = cost_calculator:getTotalCost();
    io:println("✓ Main README generated successfully!");
    io:println(string ` Cost: $${totalCost.toString()}`);

    if !quietMode {
        io:println(string `Generated file: ${connectorPath}/README.md`);
        io:println(" Note: This is AI-generated content. Please review and verify:");
        io:println("   - CI/CD badge URLs and status");
        io:println("   - Ballerina Central package links");
        io:println("   - All GitHub repository references");
        io:println("   - Community and documentation links");
    }
}

function validateApiKey() returns error? {
    string|error apiKey = os:getEnv("ANTHROPIC_API_KEY");
    if apiKey is error {
        return error("ANTHROPIC_API_KEY environment variable is not set");
    }

}
