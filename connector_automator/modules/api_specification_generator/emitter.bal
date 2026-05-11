// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/file;
import ballerina/io;
import wso2/connector_automator.utils;

# Write the Ballerina specification source to a .bal file.
#
# + code - Ballerina source code string
# + outputDir - Output root directory
# + fileName - Target file name (e.g. "sqs_spec.bal")
# + return - Full path of the written file or error
public function writeBallerinaSpec(string code, string outputDir, string fileName) returns string|error {
    string specOutputDir = resolveSpecOutputDir(outputDir);
    boolean dirExists = check file:test(specOutputDir, file:EXISTS);
    if !dirExists {
        check file:createDir(specOutputDir, file:RECURSIVE);
    }

    string filePath = string `${specOutputDir}/${fileName}`;
    check io:fileWriteString(filePath, code);
    return filePath;
}

# Write a text or JSON content string to a file for reference / debugging.
#
# + content - File content string
# + outputDir - Target directory
# + fileName - Target file name (e.g. "sqsclient-ir.json")
# + return - Full path of the written file or error
public function writeIRFile(string content, string outputDir, string fileName) returns string|error {
    boolean dirExists = check file:test(outputDir, file:EXISTS);
    if !dirExists {
        check file:createDir(outputDir, file:RECURSIVE);
    }

    string filePath = string `${outputDir}/${fileName}`;
    check io:fileWriteString(filePath, content);
    return filePath;
}

# Write a JSON value directly to a file (used for the IR JSON reference file).
#
# + irJson - JSON value to write
# + outputDir - Output root directory
# + fileName - Target file name (e.g. "sqsclient-ir.json")
# + return - Full path of the written file or error
public function writeIRJsonFile(json irJson, string outputDir, string fileName) returns string|error {
    string irOutputDir = resolveIrOutputDir(outputDir);
    boolean dirExists = check file:test(irOutputDir, file:EXISTS);
    if !dirExists {
        check file:createDir(irOutputDir, file:RECURSIVE);
    }

    string filePath = string `${irOutputDir}/${fileName}`;
    check io:fileWriteJson(filePath, irJson);
    return filePath;
}

function resolveSpecOutputDir(string outputDir) returns string {
    string normalized = outputDir.trim();
    if normalized.length() == 0 {
        return "modules/api_specification_generator/spec-output";
    }
    return normalized;
}

function resolveIrOutputDir(string outputDir) returns string {
    string normalized = outputDir.trim();
    if normalized.length() == 0 {
        return "modules/api_specification_generator/IR-output";
    }
    return normalized;
}

# Run `bal format` on a Ballerina source file for final cleanup.
#
# + filePath - Path to the .bal file to format
# + return - Error if formatting fails (non-fatal)
public function runBalFormat(string filePath) returns error? {
    utils:CommandResult result = utils:executeCommand(string `bal format ${filePath}`,
            utils:getDirectoryPath(filePath), true);
    if !result.success {
        io:println(string `Warning: bal format exited with code ${result.exitCode} for ${filePath}`);
    }
}
