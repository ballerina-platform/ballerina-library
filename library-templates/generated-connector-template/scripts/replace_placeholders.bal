// Copyright (c) 2024, WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/file;
import ballerina/io;
import ballerina/lang.regexp;
import ballerina/log;
import ballerina/time;

// Define file extensions to be accepted as template files
public type TemplateFileType "bal"|"md"|"json"|"yaml"|"yml"|"toml"|"gradle"|"properties"|"gitignore"|"txt"|"sh"|"bat"|"LICENSE"|"CODEOWNERS";

final string[] SKIP_DIRS = [".git", ".gradle"];

# This function generates a connector template with the given metadata.
#
# + path - The relative path to the directory where the connector template is located
# + moduleName - The name of the module to be used the `Ballerina.toml` file and the Ballerina central
# + repoName - The name of the repository to be used in the `Ballerina.toml` file
# + moduleVersion - The version of the module to be used in the `Ballerina.toml` file
# + balVersion - The Ballerina version to be used
# + connectorName - The descriptive name of the connector to be used in the generated files
# + codeOwners - The code owners of the connector to be used in the `CODEOWNERS` file
# + return - An error if an error occurs while generating the connector template
public function main(string path, string moduleName, string repoName, string moduleVersion, string balVersion, string connectorName, string codeOwners) returns error? {
    log:printInfo("Generating connector template with the following metadata:");
    log:printInfo("Module Name: " + moduleName);
    log:printInfo("Repository Name: " + repoName);
    log:printInfo("Module Version: " + moduleVersion);
    log:printInfo("Ballerina Version: " + balVersion);
    log:printInfo("Connector Name: " + connectorName);
    log:printInfo("Code Owners: " + codeOwners);

    map<string> placeholders = {
        "MODULE_NAME_PC": connectorName == "" ? moduleName[0].toUpperAscii() + moduleName.substring(1) : connectorName,
        "MODULE_NAME_CC": moduleName[0].toLowerAscii() + moduleName.substring(1),
        "REPO_NAME": repoName,
        "MODULE_VERSION": moduleVersion,
        "BAL_VERSION": balVersion,
        "LICENSE_YEAR": time:utcToCivil(time:utcNow()).year.toString(),
        "CODEOWNERS": codeOwners
    };

    // Recursively process all files in the target directory
    check processDirectory(path, placeholders);
}

function processDirectory(string dir, map<string> placeholders) returns error? {
    string name = check file:basename(dir);
    if SKIP_DIRS.indexOf(name) is int {
        log:printInfo(string `Skipping directory: ${name}`);
        return;
    }

    file:MetaData[] files = check file:readDir(dir);
    foreach file:MetaData file in files {
        if file.dir {
            check processDirectory(file.absPath, placeholders);
        } else {
            check processFile(file.absPath, placeholders);
        }
    }
}

function processFile(string filePath, map<string> placeholders) returns error? {
    string fileName = check file:basename(filePath);
    int? lastDotIndex = fileName.lastIndexOf(".");
    string ext = lastDotIndex is int ? fileName.substring(lastDotIndex + 1) : fileName;
    if ext !is TemplateFileType {
        log:printInfo(string `Skipping file: ${fileName}`);
        return;
    }

    string|error readResult = check io:fileReadString(filePath);
    if readResult is error {
        return error(string `Error reading file ${filePath}: ${readResult.message()}`);
    }

    string content = readResult;
    foreach [string, string] [placeholder, value] in placeholders.entries() {
        content = re `\{\{${placeholder}\}\}`.replaceAll(content, value);
    }

    check io:fileWriteString(filePath, content + "\n");
    log:printInfo(string `Added file: ${fileName}`);
}

# Returns the name and the extension of a given file path.
#
# + filePath - The path of the file to get the extension of
# + return - The name and the extension of the file, as a tuple. The first element is the name and the second element is the extension.
function getFileInfo(string filePath) returns [string, string]|error {
    string fileName = check file:basename(filePath);
    string[] nameParts = regexp:split(re `\.`, fileName);
    return [nameParts[0], nameParts[nameParts.length() - 1]];
}
