import connector_automator.utils;

import ballerina/file;
import ballerina/log;

public function executeBalClientGenerate(string inputPath, string outputPath, OpenAPIToolOptions? customOptions = ()) returns utils:CommandResult {
    // Use custom options if provided, otherwise use configurable options
    OpenAPIToolOptions toolOptions = customOptions ?: options;

    // Build the base command
    string command = string `bal openapi -i ${inputPath} --mode client -o ${outputPath}`;

    // Add optional flags based on configuration
    if toolOptions.license is string {
        string licensePath = toolOptions.license;

        // If it's a relative path, resolve it relative to the working directory (parent of output)
        if !licensePath.startsWith("/") {
            // Get the working directory (parent directory of output path)
            string workingDir = utils:getDirectoryPath(outputPath);
            licensePath = string `${workingDir}/${licensePath}`;
        }

        // Check if license file exists before adding to command
        boolean|file:Error licenseExists = file:test(licensePath, file:EXISTS);
        if licenseExists is boolean && licenseExists {
            command += string ` --license ${licensePath}`;
        } else {
            log:printWarn("License file not found, skipping license option", licensePath = licensePath);
        }
    }

    if toolOptions.tags is string[] {
        string tagsList = string:'join(",", ...toolOptions.tags ?: []);
        command += string ` --tags ${tagsList}`;
    }

    if toolOptions.operations is string[] {
        string operationsList = string:'join(",", ...toolOptions.operations ?: []);
        command += string ` --operations ${operationsList}`;
    }

    command += string ` --client-methods ${toolOptions.clientMethod}`;

    return utils:executeCommand(command, utils:getDirectoryPath(outputPath));
}
