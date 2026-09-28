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
public type TemplateFileType "bal"|"md"|"json"|"yaml"|"yml"|"toml"|"gradle"|"properties"|"gitignore"|"gitattributes"
    |"txt"|"sh"|"bat"|"java"|"xml"|"LICENSE"|"CODEOWNERS";

const FILES_DIR = "files";
const FEATURES_DIR = "features";

// Local build outputs that may exist inside a template directory but must never be copied
final string[] SKIP_DIRS = [".git", ".gradle", "build", "target"];

# Optional arguments of the template generator.
#
# + name - The descriptive name of the module to be used in the generated files. Defaults to the capitalized module name
# + codeOwners - The code owners of the module to be used in the `CODEOWNERS` file
# + features - Comma-separated list of the template features to enable. Each feature is a directory in `<templateDir>/features`
public type Options record {|
    string name = "";
    string codeOwners = "";
    string features = "";
|};

# This function generates a module repository from the given template with the given metadata.
#
# + templateDir - The path to the template directory, which contains the `files` directory and optionally the `features` directory
# + targetDir - The path to the directory where the generated files should be written
# + moduleName - The name of the module to be used in the `Ballerina.toml` file and the Ballerina central
# + repoName - The name of the repository
# + moduleVersion - The version of the module to be used in the `Ballerina.toml` file
# + balVersion - The Ballerina version to be used
# + options - The optional arguments
# + return - An error if an error occurs while generating the files
public function main(string templateDir, string targetDir, string moduleName, string repoName, string moduleVersion,
        string balVersion, *Options options) returns error? {
    string[] features = from string feature in regexp:split(re `,`, options.features)
        let string trimmed = feature.trim()
        where trimmed != ""
        select trimmed;

    log:printInfo("Generating the module repository with the following metadata:");
    log:printInfo("Template: " + templateDir);
    log:printInfo("Module Name: " + moduleName);
    log:printInfo("Repository Name: " + repoName);
    log:printInfo("Module Version: " + moduleVersion);
    log:printInfo("Ballerina Version: " + balVersion);
    log:printInfo("Name: " + options.name);
    log:printInfo("Code Owners: " + options.codeOwners);
    log:printInfo("Features: " + features.toString());

    string filesDir = check file:joinPath(templateDir, FILES_DIR);
    if !check file:test(filesDir, file:IS_DIR) {
        return error(string `Template files directory not found: ${filesDir}`);
    }
    string[] featureDirs = check getFeatureDirs(templateDir, features);

    map<string> placeholders = {
        "MODULE_NAME_PC": options.name == "" ? capitalize(moduleName) : options.name,
        "MODULE_NAME_CC": moduleName[0].toLowerAscii() + moduleName.substring(1),
        "MODULE_PATH": re `\.`.replaceAll(moduleName, "/"),
        "MODULE_CLASS_PREFIX": "".'join(...from string segment in regexp:split(re `\.`, moduleName)
            select capitalize(segment)),
        "REPO_NAME": repoName,
        "MODULE_VERSION": moduleVersion,
        "BAL_VERSION": balVersion,
        "LICENSE_YEAR": time:utcToCivil(time:utcNow()).year.toString(),
        "CODEOWNERS": options.codeOwners
    };
    string[] enabledFlags = from string feature in features
        select re `-`.replaceAll(feature, "_").toUpperAscii();

    // Stage the output so that the pre-existing files in the target directory are never processed
    string stagingDir = check file:createTempDir();
    check copyDirectory(filesDir, stagingDir);
    foreach string featureDir in featureDirs {
        check copyDirectory(featureDir, stagingDir);
    }
    check processDirectory(stagingDir, placeholders, enabledFlags);
    check renamePaths(stagingDir, placeholders);
    check copyDirectory(stagingDir, targetDir);
    check file:remove(stagingDir, file:RECURSIVE);
    log:printInfo(string `Generated the module repository at: ${targetDir}`);
}

function getFeatureDirs(string templateDir, string[] features) returns string[]|error {
    string featuresDir = check file:joinPath(templateDir, FEATURES_DIR);
    string[] available = [];
    if check file:test(featuresDir, file:IS_DIR) {
        foreach file:MetaData meta in check file:readDir(featuresDir) {
            if meta.dir {
                available.push(check file:basename(meta.absPath));
            }
        }
    }
    string[] featureDirs = [];
    foreach string feature in features {
        if available.indexOf(feature) is () {
            return error(string `Unknown feature '${feature}' for template ${templateDir}. Available features: ${
                available.toString()}`);
        }
        featureDirs.push(check file:joinPath(featuresDir, feature));
    }
    return featureDirs;
}

function copyDirectory(string sourceDir, string targetDir) returns error? {
    if !check file:test(targetDir, file:EXISTS) {
        check file:createDir(targetDir, file:RECURSIVE);
    }
    foreach file:MetaData meta in check file:readDir(sourceDir) {
        string name = check file:basename(meta.absPath);
        string targetPath = check file:joinPath(targetDir, name);
        if meta.dir {
            if SKIP_DIRS.indexOf(name) is int {
                continue;
            }
            check copyDirectory(meta.absPath, targetPath);
        } else {
            check file:copy(meta.absPath, targetPath, file:REPLACE_EXISTING, file:COPY_ATTRIBUTES);
        }
    }
}

function processDirectory(string dir, map<string> placeholders, string[] enabledFlags) returns error? {
    foreach file:MetaData meta in check file:readDir(dir) {
        if meta.dir {
            check processDirectory(meta.absPath, placeholders, enabledFlags);
        } else {
            check processFile(meta.absPath, placeholders, enabledFlags);
        }
    }
}

function processFile(string filePath, map<string> placeholders, string[] enabledFlags) returns error? {
    string fileName = check file:basename(filePath);
    int? lastDotIndex = fileName.lastIndexOf(".");
    string ext = lastDotIndex is int ? fileName.substring(lastDotIndex + 1) : fileName;
    if ext !is TemplateFileType {
        log:printInfo(string `Skipping file: ${fileName}`);
        return;
    }

    string content = check resolveFeatureBlocks(check io:fileReadString(filePath), enabledFlags, filePath);
    foreach [string, string] [placeholder, value] in placeholders.entries() {
        content = re `\{\{${placeholder}\}\}`.replaceAll(content, value);
    }
    regexp:Span? unresolved = re `\{\{[#/]?[A-Z_]+\}\}`.find(content);
    if unresolved is regexp:Span {
        return error(string `Unresolved placeholder '${unresolved.substring()}' in ${filePath}`);
    }

    check io:fileWriteString(filePath, content + "\n");
    log:printInfo(string `Added file: ${fileName}`);
}

# Keeps the lines between `{{#FLAG}}` and `{{/FLAG}}` marker lines when the flag is enabled and drops them otherwise.
# The marker lines are always removed. Blocks can be nested.
#
# + content - The file content
# + enabledFlags - The enabled feature flags
# + filePath - The path of the file, used in error messages
# + return - The content with the feature blocks resolved, or an error if the blocks are malformed
function resolveFeatureBlocks(string content, string[] enabledFlags, string filePath) returns string|error {
    string[] lines = [];
    string[] openFlags = [];
    int disabledDepth = 0;
    foreach string line in regexp:split(re `\n`, content) {
        regexp:Groups? marker = re `^\s*(?:#|//|<!--)?\s*\{\{([#/])([A-Z_]+)\}\}\s*(?:-->)?\s*$`.findGroups(line);
        if marker is () {
            if disabledDepth == 0 {
                lines.push(line);
            }
            continue;
        }
        string kind = (<regexp:Span>marker[1]).substring();
        string flag = (<regexp:Span>marker[2]).substring();
        if kind == "#" {
            openFlags.push(flag);
            if disabledDepth > 0 || enabledFlags.indexOf(flag) is () {
                disabledDepth += 1;
            }
        } else {
            if openFlags.length() == 0 || openFlags.pop() != flag {
                return error(string `Mismatched feature block end '{{/${flag}}}' in ${filePath}`);
            }
            if disabledDepth > 0 {
                disabledDepth -= 1;
            }
        }
    }
    if openFlags.length() > 0 {
        return error(string `Unclosed feature block '{{#${openFlags.pop()}}}' in ${filePath}`);
    }
    return "\n".'join(...lines);
}

# Renames the files and directories whose names contain placeholders. A value containing `/` creates nested directories.
#
# + dir - The directory to process
# + placeholders - The placeholders and their values
# + return - An error if an error occurs while renaming
function renamePaths(string dir, map<string> placeholders) returns error? {
    foreach file:MetaData meta in check file:readDir(dir) {
        if meta.dir {
            check renamePaths(meta.absPath, placeholders);
        }
        string name = check file:basename(meta.absPath);
        if !name.includes("{{") {
            continue;
        }
        string newName = name;
        foreach [string, string] [placeholder, value] in placeholders.entries() {
            newName = re `\{\{${placeholder}\}\}`.replaceAll(newName, value);
        }
        string newPath = check file:joinPath(dir, ...regexp:split(re `/`, newName));
        string newParent = check file:parentPath(newPath);
        if !check file:test(newParent, file:EXISTS) {
            check file:createDir(newParent, file:RECURSIVE);
        }
        if meta.dir && check file:test(newPath, file:EXISTS) {
            check copyDirectory(meta.absPath, newPath);
            check file:remove(meta.absPath, file:RECURSIVE);
        } else {
            check file:rename(meta.absPath, newPath);
        }
        log:printInfo(string `Renamed: ${name} -> ${newName}`);
    }
}

function capitalize(string value) returns string {
    return value.length() == 0 ? value : value[0].toUpperAscii() + value.substring(1);
}
