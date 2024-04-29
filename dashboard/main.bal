// Copyright (c) 2024, WSO2 LLC. (http://www.wso2.org).
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

import ballerina/io;
import ballerina/lang.array;
import ballerina/log;

import thisarug/prettify;

public function main() returns error? {
    List moduleNameList = check getSortedModuleNameList();
    List moduleDetails = check initializeModuleDetails(moduleNameList);

    Module[] libraryModules = moduleDetails.modules;
    Module[] modules = [...libraryModules, ...moduleDetails.extended_modules, ...moduleDetails.tools];

    check getImmediateDependencies(modules);
    check calculateLevels(modules);
    moduleDetails.forEach(function(Module[] moduleList) {
        removePropertiesFile(moduleList);
    });
    moduleDetails.modules = libraryModules.sort(array:ASCENDING, a => a.level);

    check writeToFile(STDLIB_MODULES_JSON, moduleDetails);
    check updateStdlibDashboard(moduleDetails);
}

//  Sorts the Ballerina library module list in ascending order
function getSortedModuleNameList() returns List|error {
    List moduleList = check (check io:fileReadJson(MODULE_LIST_JSON)).fromJsonWithType();

    List sortedList = {
        modules: sortModuleArray(moduleList.modules),
        extended_modules: sortModuleArray(moduleList.extended_modules),
        connectors: sortModuleArray(moduleList.connectors),
        tools: sortModuleArray(moduleList.tools)
    };

    check writeToFile(MODULE_LIST_JSON, sortedList);
    return sortedList;
}

function sortModuleArray(Module[] moduleArray) returns Module[] {
    return from Module module in moduleArray
        order by getModuleShortName(module.name) ascending
        select module;
}

function initializeModuleDetails(List moduleNameList) returns List|error {
    return {
        modules: check initializeModuleList(moduleNameList.modules),
        extended_modules: check initializeModuleList(moduleNameList.extended_modules),
        connectors: check initializeModuleList(moduleNameList.connectors),
        tools: check initializeModuleList(moduleNameList.tools)
    };
}

function initializeModuleList(Module[] modules) returns Module[]|error {
    Module[] moduleList = [];
    foreach Module module in modules {
        Module initialModule = check initializeModuleInfo(module);
        moduleList.push(initialModule);
    }
    return moduleList;
}

function initializeModuleInfo(Module module) returns Module|error {
    string moduleName = module.name;
    string defaultBranch = check getDefaultBranch(moduleName);
    string gradleProperties =
        check git->get(string `/${BALLERINA_ORG_NAME}/${moduleName}/${defaultBranch}/${GRADLE_PROPERTIES}`);
    string versionKey = getVersionKey(module);
    string moduleVersion = check getVersion(moduleName, gradleProperties);
    boolean displayCodeCovBadge = getDisplayCodeCovBadge(module);
    return {
        name: moduleName,
        module_version: moduleVersion,
        level: 1,
        default_branch: defaultBranch,
        version_key: versionKey,
        release: true,
        display_code_cov_badge: displayCodeCovBadge,
        dependents: [],
        gradle_properties: gradleProperties
    };
}

function getDisplayCodeCovBadge(Module module) returns boolean {
    boolean? displayCodeCovBadge = module.display_code_cov_badge;
    if displayCodeCovBadge is boolean {
        return displayCodeCovBadge;
    }
    return true;
}

function getVersionKey(Module module) returns string {
    string? versionKey = module.version_key;
    if versionKey is string {
        return versionKey;
    }
    string nameInVesrsionKey = capitalize(getModuleShortName(module.name));
    return string `stdlib${nameInVesrsionKey}Version`;
}

function getVersion(string moduleName, string gradleProperties) returns string|error {
    string[] gradlePropertiesLines = re `\n`.split(gradleProperties);
    string moduleVersion = "";
    foreach string line in gradlePropertiesLines {
        if line.startsWith("version") {
            moduleVersion = re `=`.split(line)[1];
            break;
        }
    }
    if moduleVersion == "" {
        log:printWarn(string `Version not found for the module: ${moduleName}`);
    }
    return moduleVersion;
}

// Get the modules list which use the specific module
function getImmediateDependencies(Module[] modules) returns error? {
    foreach Module module in modules {
        string[] dependees = check getDependencies(module, modules);

        // Get the dependecies modules which use module in there package
        foreach Module dependee in modules {
            string dependeeName = dependee.name;
            string[]? dependeeDependents = dependee.dependents;
            if dependees.indexOf(dependeeName) is int && dependeeDependents is string[] {
                dependeeDependents.push(module.name);
                dependee.dependents = dependeeDependents;
            }
        }
    }
}

// Get dependecies of specific module
function getDependencies(Module module, Module[] modules) returns string[]|error {
    string[] propertiesFileArr = [];
    string moduleName = module.name;
    string? propertiesFile = module.gradle_properties;
    if propertiesFile is string {
        propertiesFileArr = re `\n`.split(propertiesFile);
    }
    string[] dependencies = [];

    foreach string line in propertiesFileArr {
        foreach Module item in modules {
            string dependentName = item.name;
            if dependentName == moduleName {
                continue;
            }
            string? versionKey = item.version_key;
            if versionKey is string && re `^.*${versionKey}.*$`.isFullMatch(line) {
                dependencies.push(dependentName);
                break;
            }
        }
    }
    return dependencies;
}

function calculateLevels(Module[] modules) returns error? {
    DiGraph dependencyGraph = new;

    // Module names are used to create the nodes and the level attribute of the node is initialized to 1
    foreach Module module in modules {
        dependencyGraph.addNode(module.name);
    }

    // Edges are created considering the dependents of each module
    foreach Module module in modules {
        string[]? moduleDependents = module.dependents;
        if moduleDependents is string[] {
            foreach var dependent in moduleDependents {
                dependencyGraph.addEdge(module.name, dependent);
            }
        }
    }

    string[] processedList = [];
    foreach Node n in dependencyGraph.getGraph() {
        if dependencyGraph.inDegree(n.vertex) == 0 {
            processedList.push(n.vertex);
        }
    }

    // While the processing list is not empty, successors of each node in the current level are determined
    // For each successor of the node,
    //    - Longest path from node to successor is considered and intermediate nodes are removed from dependent list
    //   - The level is updated and the successor is appended to a temporary array
    // After all nodes are processed in the current level the processing list is updated with the temporary array
    int currentLevel = 2;
    while processedList.length() > 0 {
        string[] processing = [];

        foreach string n in processedList {
            processCurrentLevel(dependencyGraph, processing, modules, currentLevel, n);
        }
        processedList = processing;
        currentLevel += 1;
    }

    foreach Module module in modules {
        int? moduleLevel = dependencyGraph.getCurrentLevel(module.name);
        if moduleLevel is int {
            module.level = moduleLevel;
        }
    }
}

function processCurrentLevel(DiGraph dependencyGraph, string[] processing, Module[] modules,
        int currentLevel, string node) {
    string[]? successorsOfNode = dependencyGraph.successor(node);
    string[] successors = [];

    if successorsOfNode is string[] {
        successors = successorsOfNode;
    }

    foreach string successor in successors {
        removeModulesInIntermediatePaths(dependencyGraph, node, successor, successors, modules);
        dependencyGraph.setCurrentLevel(successor, currentLevel);
        if !(processing.indexOf(successor) is int) {
            processing.push(successor);
        }
    }
}

function removeModulesInIntermediatePaths(DiGraph dependencyGraph, string sourceNode,
        string destinationNode, string[] successors, Module[] modules) {
    string[] longestPath = dependencyGraph.getLongestPath(sourceNode, destinationNode);
    foreach string n in longestPath.slice(1, longestPath.length() - 1) {
        if (successors.indexOf(n) is int) {
            foreach Module module in modules {
                string[]? moduleDependents = module.dependents;
                if module.name == sourceNode && moduleDependents is string[] {
                    int? indexOfDestinationNode = moduleDependents.indexOf(destinationNode);
                    if indexOfDestinationNode is int {
                        _ = moduleDependents.remove(indexOfDestinationNode);
                        module.dependents = moduleDependents;
                    }
                    break;
                }
            }
        }
    }
}

// Updates the stdlib dashboard in README.md
function updateStdlibDashboard(List moduleDetails) returns error? {
    string readmeFile = check io:fileReadString(README_FILE);
    string[] readmeFileLines = re `\n`.split(readmeFile);
    string updatedReadmeFile = "";

    foreach string line in readmeFileLines {
        updatedReadmeFile += line + "\n";
        if line == DASHBOARD_TITLE {
            break;
        }
    }

    updatedReadmeFile += check getBallerinaDashboard(moduleDetails.modules);
    updatedReadmeFile += "\n";
    updatedReadmeFile += check getBallerinaExtendedDashboard(moduleDetails.extended_modules);
    updatedReadmeFile += "\n";
    updatedReadmeFile += check getBallerinaConnectorDashboard(moduleDetails.connectors);
    updatedReadmeFile += "\n";
    updatedReadmeFile += check getBallerinaToolsDashboard(moduleDetails.tools);

    io:Error? fileWriteString = io:fileWriteString(README_FILE, updatedReadmeFile);
    if fileWriteString is io:Error {
        log:printError(string `Failed to write to the ${README_FILE}`);
    }
    log:printInfo("Dashboard Updated");
}

isolated function getBallerinaDashboard(Module[] modules) returns string|error {
    string dashboard = string `
${BAL_TITLE}

${LIBRARY_DASHBOARD_HEDER}
${LIBRARY_HEADER_SEPARATOR}`;
    string levelColumn = "1";
    int currentLevel = 1;

    foreach Module module in modules {
        int? moduleLevel = module.level;
        if moduleLevel is int && moduleLevel > currentLevel {
            currentLevel = moduleLevel;
            levelColumn = currentLevel.toString();
        }
        string row = check getLibraryDashboardRow(module, levelColumn);
        dashboard += row;
        dashboard += "\n";
        levelColumn = "";
    }
    return dashboard;
}

isolated function getBallerinaExtendedDashboard(Module[] modules) returns string|error {
    string dashboard = string `
${BALX_TITLE}

${EXTENDED_DASHBOARD_HEDER}
${HEADER_SEPARATOR}`;

    foreach Module module in modules {
        string row = check getDashboardRow(module);
        dashboard += row + "\n";
    }
    return dashboard;
}

isolated function getBallerinaConnectorDashboard(Module[] modules) returns string|error {
    string dashboard = string `
${CONNECTOR_TITLE}

${CONNECTOR_DASHBOARD_HEDER}
${HEADER_SEPARATOR}`;

    foreach Module module in modules {
        string row = check getDashboardRow(module);
        dashboard += row + "\n";
    }
    return dashboard;
}

isolated function getBallerinaToolsDashboard(Module[] modules) returns string|error {
    string dashboard = string `
${TOOLS_TITLE}

${TOOLS_DASHBOARD_HEDER}
${TOOLS_HEADER_SEPARATOR}`;

    foreach Module module in modules {
        string row = check getToolsDashboardRow(module);
        dashboard += row + "\n";
    }
    return dashboard;
}

isolated function writeToFile(string fileName, json content) returns error? {
    string prettifiedContent = prettify:prettify(content);

    error? result = io:fileWriteString(fileName, prettifiedContent);
    if result is error {
        log:printError("Error occurred while writing to the file: " + result.message());
        return result;
    }
}

isolated function removePropertiesFile(Module[] modules) {
    foreach Module module in modules {
        module.gradle_properties = ();
    }
}
