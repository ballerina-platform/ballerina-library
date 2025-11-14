import connector_automator.utils;

import ballerina/file;
import ballerina/io;
import ballerina/lang.regexp;

function setupMockServerModule(string connectorPath, boolean quietMode = false) returns error? {
    string ballerinaDir = connectorPath + "/ballerina";
    // cd into ballerina dir and add mock.server module using bal add cmd

    if !quietMode {
        io:println("Setting up mock.server module...");
    }

    string command = string `bal add mock.server`;

    utils:CommandResult addResult = utils:executeCommand(command, ballerinaDir, quietMode);
    if !addResult.success {
        return error("Failed to add mock.server module" + addResult.stderr);
    }

    if !quietMode {
        io:println("✓ Mock.server module added successfully");
    }

    // delete the auto generated tests directory
    string mockTestDir = ballerinaDir + "/modules/mock.server/tests";
    if check file:test(mockTestDir, file:EXISTS) {
        check file:remove(mockTestDir, file:RECURSIVE);
        if !quietMode {
            io:println("Removed auto generated tests directory");
        }
    }

    // delete auto generated mock.server.bal file
    string mockServerFile = ballerinaDir + "/modules/mock.server/mock.server.bal";
    if check file:test(mockServerFile, file:EXISTS) {
        check file:remove(mockServerFile, file:RECURSIVE);
        if !quietMode {
            io:println("Removed auto generated mock.server.bal file");
        }
    }

    return;
}

function generateMockServer(string connectorPath, string specPath, boolean quietMode = false) returns error? {
    string ballerinaDir = connectorPath + "/ballerina";
    string mockServerDir = ballerinaDir + "/modules/mock.server";
    int operationCount = check countOperationsInSpec(specPath);
    if !quietMode {
        io:println(string `Total operations found in spec: ${operationCount}`);
    }

    string command;

    if operationCount <= MAX_OPERATIONS {
        if !quietMode {
            io:println(string `Using all ${operationCount} operations`);
        }
        command = string `bal openapi -i ${specPath} -o ${mockServerDir}`;
    } else {
        if !quietMode {
            io:println(string `Filtering from ${operationCount} to ${MAX_OPERATIONS} most useful operations`);
        }
        string operationsList = check selectOperationsUsingAI(specPath);
        if !quietMode {
            io:println(string `Selected operations: ${operationsList}`);
        }
        command = string `bal openapi -i ${specPath} -o ${mockServerDir} --operations ${operationsList}`;
    }

    // generate mock service template using openapi tool
    utils:CommandResult result = utils:executeCommand(command, ballerinaDir, quietMode);
    if !result.success {
        return error("Failed to generate mock server using ballerina openAPI tool" + result.stderr);
    }

    // rename mock server
    string mockServerPathOld = mockServerDir + "/aligned_ballerina_openapi_service.bal";
    string mockServerPathNew = mockServerDir + "/mock_server.bal";
    if check file:test(mockServerPathOld, file:EXISTS) {
        check file:rename(mockServerPathOld, mockServerPathNew);
        if !quietMode {
            io:println("Renamed mock server file");
        }
    }

    // delete client.bal
    string clientPath = mockServerDir + "/client.bal";
    if check file:test(clientPath, file:EXISTS) {
        check file:remove(clientPath, file:RECURSIVE);
        if !quietMode {
            io:println("Removed client.bal");
        }
    }

    return;
}

function countOperationsInSpec(string specPath) returns int|error {
    string specContent = check io:fileReadString(specPath);

    // count operationId occurences in the spec
    regexp:RegExp operationIdPattern = re `"operationId"\s*:\s*"[^"]*"`;
    regexp:Span[] matches = operationIdPattern.findAll(specContent);
    return matches.length();

}
