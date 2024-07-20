import ballerina/file;
import ballerina/io;
import ballerina/lang.regexp;
import ballerina/log;

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
        "REPO_NAME": regexp:split(re `/`, repoName)[1],
        "MODULE_VERSION": moduleVersion,
        "BAL_VERSION": balVersion
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
