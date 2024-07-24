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

// Define the file extensions that are considered as template files
public type TemplateFileExt "bal"|"md"|"json"|"yaml"|"yml"|"toml"|"gradle"|"properties";

public function main(string path, string moduleName, string repoName, string moduleVersion, string balVersion) returns error? {
    log:printInfo("Generating connector template with the following metadata:");
    log:printInfo("Module Name: " + moduleName);
    log:printInfo("Repository Name: " + repoName);
    log:printInfo("Module Version: " + moduleVersion);
    log:printInfo("Ballerina Version: " + balVersion);

    map<string> placeholders = {
        "MODULE_NAME_PC": moduleName[0].toUpperAscii() + moduleName.substring(1),
        "MODULE_NAME_CC": moduleName[0].toLowerAscii() + moduleName.substring(1),
        "REPO_NAME": repoName,
        "MODULE_VERSION": moduleVersion,
        "BAL_VERSION": balVersion,
        "LICENSE_YEAR": time:utcToCivil(time:utcNow()).year.toString()
    };

    // Recursively process all files in the target directory
    check processDirectory(path, placeholders);
}

function processDirectory(string dir, map<string> placeholders) returns error? {
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
    string ext = getExtension(filePath);
    if ext !is TemplateFileExt {
        log:printInfo("Skipping file: " + filePath);
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

    check io:fileWriteString(filePath, content);
}

function getExtension(string filePath) returns string {
    string[] nameParts = regexp:split(re `\.`, filePath);
    return nameParts[nameParts.length() - 1];
}
