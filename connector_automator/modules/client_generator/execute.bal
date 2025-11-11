import connector_automator.utils;

import ballerina/io;
import ballerina/log;
import ballerina/regex;

public function executeClientGen(string... args) returns error? {
    if args.length() < 2 {
        printUsage();
        return;
    }

    string inputSpecPath = args[0]; // Path to OpenAPI spec (aligned)
    string outputDir = args[1]; // Output directory for client

    ClientGeneratorConfig config = parseCommandLineArgs(args.slice(2));

    if !config.quietMode {
        log:printInfo("Starting Ballerina client generation",
                inputSpec = inputSpecPath,
                outputDir = outputDir,
                config = config
        );
    }

    return generateBallerinaClient(inputSpecPath, outputDir, config);
}

# Parse command line arguments into configuration
#
# + args - Command line arguments after input and output paths
# + return - Parsed configuration
function parseCommandLineArgs(string[] args) returns ClientGeneratorConfig {
    ClientGeneratorConfig config = {};
    OpenAPIToolOptions toolOptions = {};
    boolean hasToolOptions = false;

    foreach string arg in args {
        match arg {
            "yes" => {
                config.autoYes = true;
            }
            "quiet" => {
                config.quietMode = true;
            }
            "remote-methods" => {
                toolOptions.clientMethod = "remote";
                hasToolOptions = true;
            }
            "resource-methods" => {
                toolOptions.clientMethod = "resource";
                hasToolOptions = true;
            }
            _ => {
                // Handle key=value pairs
                if arg.includes("=") {
                    string[] parts = regex:split(arg, "=");
                    if parts.length() == 2 {
                        string key = parts[0].trim();
                        string value = parts[1].trim();

                        match key {
                            "license" => {
                                toolOptions.license = value;
                                hasToolOptions = true;
                            }
                            "tags" => {
                                toolOptions.tags = regex:split(value, ",").map(tag => tag.trim());
                                hasToolOptions = true;
                            }
                            "operations" => {
                                toolOptions.operations = regex:split(value, ",").map(op => op.trim());
                                hasToolOptions = true;
                            }
                            "client-method" => {
                                if value == "resource" || value == "remote" {
                                    toolOptions.clientMethod = <"resource"|"remote">value;
                                    hasToolOptions = true;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if hasToolOptions {
        config.toolOptions = toolOptions;
    }

    return config;
}

# Generate Ballerina client from OpenAPI specification
#
# + specPath - Path to the OpenAPI specification file
# + outputDir - Output directory for generated client
# + config - Configuration for client generation
# + return - Error if generation fails, () if successful
public function generateBallerinaClient(string specPath, string outputDir, ClientGeneratorConfig config) returns error? {
    io:println("\n=== Ballerina Client Generation ===");
    io:println(string `Input OpenAPI spec: ${specPath}`);
    io:println(string `Output directory: ${outputDir}`);
    io:println("\nOperations to be performed:");
    io:println("• Generate Ballerina client code from OpenAPI specification");
    io:println("• Create project structure with proper dependencies");
    io:println("• Validate generated code structure");

    // Show configuration if tool options are provided
    if config.toolOptions is OpenAPIToolOptions {
        OpenAPIToolOptions options = <OpenAPIToolOptions>config.toolOptions;
        io:println("\nConfiguration Options:");
        io:println(string `• Client method type: ${options.clientMethod}`);
        // if options.license is string {
        //     io:println(string `• License file: ${options.license}`);
        // }
        if options.tags is string[] {
            io:println(string `• Filtered tags: ${string:'join(", ", ...options.tags ?: [])}`);
        }
        if options.operations is string[] {
            io:println(string `• Specific operations: ${string:'join(", ", ...options.operations ?: [])}`);
        }
    }
    io:println("");

    if !getUserConfirmation("Proceed with Ballerina client generation?", config.autoYes) {
        io:println("⚠ Skipping client generation.");
        return;
    }

    io:println("Generating Ballerina client code...");

    utils:CommandResult generateResult = executeBalClientGenerate(specPath, outputDir, config.toolOptions);

    if !utils:isCommandSuccessfull(generateResult) {
        if !config.quietMode {
            log:printError("Client generation failed", result = generateResult);
        }
        io:println("Client generation failed:");
        io:println(generateResult.stderr);

        if generateResult.compilationErrors.length() > 0 {
            io:println("\nCompilation errors found:");
            foreach utils:CmdCompilationError err in generateResult.compilationErrors {
                io:println(string `  • ${err.fileName}:${err.line}:${err.column} - ${err.message}`);
            }
        }

        return error("Client generation failed: " + generateResult.stderr);
    } else {
        if !config.quietMode {
            log:printInfo("Ballerina client generated successfully", outputPath = outputDir);
        }
        io:println("Ballerina client generated successfully");

        io:println(string `Generated files are available in: ${outputDir}`);

        // Show next steps
        io:println("\nNext Steps:");
        io:println("• Review the generated client code");
        io:println("• Run 'bal build' to check for compilation errors");
        io:println("• Use the code fixer if there are any compilation issues");
        io:println("• Generate examples to test the client functionality");
    }

    return ();
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
        log:printError("Failed to read user input", 'error = userInput);
        return false;
    }
    string trimmedInput = userInput.trim().toLowerAscii();
    return trimmedInput == "y" || trimmedInput == "Y" || trimmedInput == "yes";
}

function printUsage() {
    io:println("Ballerina Client Generator");
    io:println("");
    io:println("Usage: bal run client_generator -- <openapi-spec> <output-directory> [options]");
    io:println("");
    io:println("Required Arguments:");
    io:println("  <openapi-spec>     Path to the OpenAPI specification file");
    io:println("  <output-directory> Directory where generated client will be stored");
    io:println("");
    io:println("General Options:");
    io:println("  yes                Automatically answer 'yes' to all prompts (for CI/CD)");
    io:println("  quiet              Reduce logging output (minimal logs for CI/CD)");
    io:println("");
    io:println("OpenAPI Tool Options:");
    io:println("  remote-methods     Use remote methods (default: resource methods)");
    io:println("  resource-methods   Use resource methods (default)");
    io:println("");
    io:println("Key-Value Options:");
    io:println("  license=<path>     License file path for copyright header");
    io:println("  tags=<tag1,tag2>   Comma-separated tags to filter operations");
    io:println("  operations=<op1,op2> Comma-separated operations to generate");
    io:println("  client-method=<resource|remote> Client method type");
    io:println("");
    io:println("Configuration File Options:");
    io:println("  You can also use Config.toml to set default options:");
    io:println("  [client_generator.options]");
    io:println("  license = \"./license.txt\"");
    io:println("  tags = [\"users\", \"orders\"]");
    io:println("  clientMethod = \"resource\"");
    io:println("");
    io:println("Examples:");
    io:println("  bal run client_generator -- ./spec.json ./client");
    io:println("  bal run client_generator -- ./spec.yaml ./client yes quiet");
    io:println("  bal run client_generator -- ./spec.json ./client license=./license.txt tags=users,orders");
    io:println("  bal run client_generator -- ./spec.json ./client remote-methods");
    io:println("");
    io:println("Configuration via CLI:");
    io:println("  bal run client_generator -- ./spec.json ./client -Cclient_generator.options.license=./license.txt -Cclient_generator.options.clientMethod=remote");
}
