import connector_automator.cost_calculator;
import connector_automator.utils;

import ballerina/io;
import ballerina/lang.runtime;
import ballerina/log;

public function executeExampleGen(string... args) returns error? {
    if args.length() < 1 {
        io:println("Please provide the path to the connector module.");
        return;
    }

    cost_calculator:resetCostTracking();

    string connectorPath = args[0];
    // 1. analyze the connector
    ConnectorDetails|error details = analyzeConnector(connectorPath);
    if details is error {
        io:println("Failed to analyze connector: ", details.message());
        return;
    }

    // Initialize ai_generator
    error? initResult = initExampleGenerator();
    if initResult is error {

        io:println("Error initializing AI generator: " + initResult.message());

        return error("AI generator initialization failed: " + initResult.message());
    }

    // 2. Pack and push connector to local repository BEFORE generating examples
    io:println("Packing and pushing connector to local repository...");
    error? packResult = packAndPushConnector(connectorPath);
    if packResult is error {
        io:println("Failed to pack and push connector: ", packResult.message());
        io:println("This is required for examples to resolve the connector dependency.");
        return packResult;
    }
    io:println("✓ Connector successfully packed and pushed to local repository");

    // 3. Determine the number of examples

    int numExamples = numberOfExamples(details.apiCount);
    // io:println("Number of Examples to generate: ", numberOfExamples.toString());

    // array to keep track of functions used in generated examples. 
    string[] usedFunctionaNames = [];

    // 4. Loop to generate each example
    foreach int i in 1 ... numExamples {
        io:println("Generating use case ", i.toString(), "...");
        io:println("Generating example name for use case ", i.toString(), "...");

        json|error useCaseResponse = generateUseCaseAndFunctions(details, usedFunctionaNames);
        if useCaseResponse is error {
            log:printError("Failed to generate use case", useCaseResponse);
            continue;
        }

        string useCase = check useCaseResponse.useCase.ensureType();
        json functionNamesJson = check useCaseResponse.requiredFunctions.ensureType();
        string[] functionNames = [];

        // Convert json array to string array
        if functionNamesJson is json[] {
            foreach json item in functionNamesJson {
                if item is string {
                    functionNames.push(item);
                }
            }
        } else {
            log:printError("requiredFunctions is not a JSON array");
            continue;
        }

        // adding the newly used function to the tacking list
        usedFunctionaNames.push(...functionNames);

        //io:println("Generated use case: " + useCase);
        //io:println("Required functions: " + functionNames.toString());

        // Step 2: Extract the targeted context based on the required functions
        string|error targetedContext = extractTargetedContext(details, functionNames);
        // io:Error? targeted_context = io:fileWriteString("targeted_context.txt", check targetedContext);
        if targetedContext is error {
            log:printError("Failed to extract targeted context", targetedContext);
            continue;
        }

        // io:println("\n", "=========TARGETED CONTEXT==========", targetedContext);
        string|error generatedCode = generateExampleCode(details, useCase, targetedContext);
        if generatedCode is error {
            log:printError("Failed to generate example code", generatedCode);
            continue;
        }
        // Generate AI-powered example name
        string|error exampleNameResult = generateExampleName(useCase);
        string exampleName;
        if exampleNameResult is error {
            log:printError("Failed to generate example name, using fallback", exampleNameResult);
            exampleName = "example_" + i.toString();
        } else {
            exampleName = exampleNameResult;
        }

        //io:println("Generated example name: ", exampleName);
        //io:println("Generating example code for use case ", i.toString(), "...");
        //io:println("Generated Example Code for Use Case ", i.toString(), ":\n", generatedCode);

        // Write the generated example to file
        //io:println("Writing example ", i.toString(), " to file...");
        error? writeResult = writeExampleToFile(connectorPath, exampleName, useCase, generatedCode, details.connectorName);
        if writeResult is error {
            // io:println("Failed to write example to file: ", writeResult.message());
            continue;
        }
        //io:println("Successfully wrote example ", i.toString(), " to file system.");

        runtime:sleep(10);

        // Fix compilation errors in the generated example
        string exampleDir = connectorPath + "/examples/" + exampleName;
        error? fixResult = fixExampleCode(exampleDir, exampleName);
        if fixResult is error {
            io:println("Warning: Failed to fix compilation errors for example ", i.toString(), ": ", fixResult.message());
            io:println("Example may require manual intervention.");
            // Continue with other examples even if one fails to fix
        }

        // Show individual example cost
        decimal exampleCost = cost_calculator:getStageCost("example_generator_usecase") +
                            cost_calculator:getStageCost("example_generator_code") +
                            cost_calculator:getStageCost("example_generator_name");
        io:println(string `✓ Example ${i} (${exampleName}) completed! Cost: $${(exampleCost / <decimal>i).toString()}`);
    }

    // Show final cost summary
    utils:repeat();
    io:println("EXAMPLE GENERATION COST SUMMARY");
    utils:repeat();

    decimal usecaseCost = cost_calculator:getStageCost("example_generator_usecase");
    decimal codeCost = cost_calculator:getStageCost("example_generator_code");
    decimal nameCost = cost_calculator:getStageCost("example_generator_name");
    decimal totalCost = cost_calculator:getTotalCost();

    io:println(string `Use Case Generation: $${usecaseCost.toString()}`);
    io:println(string `Code Generation: $${codeCost.toString()}`);
    io:println(string `Name Generation: $${nameCost.toString()}`);
    utils:repeat();
    io:println(string `Total Cost: $${totalCost.toString()}`);
    io:println(string `Average per Example: $${(totalCost / <decimal>numExamples).toString()}`);
    utils:repeat();

    io:println(string ` Generated ${numExamples} examples successfully!`);

    //io:println("Example generation completed successfully!");
}

