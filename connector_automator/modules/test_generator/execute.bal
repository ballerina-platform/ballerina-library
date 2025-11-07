import connector_automator.cost_calculator;
import connector_automator.utils;

import ballerina/io;

public function executeTestGen(string... args) returns error? {
    if args.length() < 2 {
        printUsage();
        return;
    }

    string connectorPath = args[0];
    string specPath = args[1];

    // Check for quiet mode flag
    boolean quietMode = false;
    if args.length() > 2 {
        foreach string arg in args {
            if arg == "quiet" || arg == "q" {
                quietMode = true;
                break;
            }
        }
    }

    if !quietMode {
        io:println("=== Test Generator ===");
        io:println(string `Processing connector: ${connectorPath}`);
    }

    check utils:initAIService(quietMode);

    // Step 1: Setup mock server module
    if !quietMode {
        io:println("Step 1: Setting up mock server module...");
    }
    check setupMockServerModule(connectorPath, quietMode);

    // Step 2: Generate mock server implementation
    if !quietMode {
        io:println("Step 2: Generating mock server implementation...");
    }
    check generateMockServer(connectorPath, specPath, quietMode);

    string mockServerPath = connectorPath + "/ballerina/modules/mock.server/mock_server.bal";
    string typesPath = connectorPath + "/ballerina/modules/mock.server/types.bal";

    // Step 3: Complete mock server template
    if !quietMode {
        io:println("Step 3: Completing mock server template...");
    }
    check completeMockServer(mockServerPath, typesPath, quietMode);

    // Step 4: Generate tests
    if !quietMode {
        io:println("Step 4: Generating test file...");
    }
    check generateTestFile(connectorPath, quietMode);

    // Step 5: Fix all compilation errors related to tests
    if !quietMode {
        io:println("Step 6: Building and fixing compilation errors...");
    }
    check fixTestFileErrors(connectorPath, quietMode);

    if !quietMode {
        io:println("✓ Test generation completed successfully!");
    }

    utils:repeat();
    io:println("COST SUMMARY");
    utils:repeat();
    io:println(string `Mock Server Generation: $${cost_calculator:getStageCost("test_generator_mock").toString()}`);
    io:println(string `Test Generation: $${cost_calculator:getStageCost("test_generator").toString()}`);
    io:println(string `Selection (if used): $${cost_calculator:getStageCost("test_generator_selection").toString()}`);
    utils:repeat();
    io:println(string `Total Test Generation Cost: $${cost_calculator:getTotalCost().toString()}`);
    utils:repeat();

}

function printUsage() {
    io:println("Usage: test_generator <connector_path> <spec_path> [options]");
    io:println("Options:");
    io:println("  --quiet, -q    Run in quiet mode (suppress verbose output)");
    io:println("");
    io:println("Examples:");
    io:println("  test_generator /path/to/connector /path/to/spec.yaml");
    io:println("  test_generator /path/to/connector /path/to/spec.yaml --quiet");
}

