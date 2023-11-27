// Copyright (c) 2022, WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
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

type List record {|
    Module[] modules;
    Module[] extendedModules;
    Module[] connectors;
    Module[] tools;
|};

type Module record {|
    string name;
    string module_version?;
    int level?;
    string default_branch?;
    string version_key?;
    boolean release?;
    string[] dependents?;
    string gradle_properties?;
|};

public function main() returns error? {
    List moduleNameList = check getSortedModuleNameList();
    List moduleDetails = check initializeModuleDetails(moduleNameList);

    check getImmediateDependencies(moduleDetails);
    check calculateLevels(moduleDetails);
    Module[] sortedModules = moduleDetails.modules.sort(array:ASCENDING, a => a.level);
    moduleDetails.modules = sortedModules;
    check writeToFile(STDLIB_MODULES_JSON, moduleDetails);
    check updateStdlibDashboard(moduleDetails);
}

//  Sorts the Ballerina library module list in ascending order
function getSortedModuleNameList() returns List|error {
    json moduleListJson = check io:fileReadJson(MODULE_LIST_JSON);
    List moduleList = check moduleListJson.cloneWithType();

    List sortedList = {
        modules: sortModuleArray(moduleList.modules, 2),
        extendedModules: sortModuleArray(moduleList.extendedModules, 2),
        connectors: sortModuleArray(moduleList.connectors, 2),
        tools: sortModuleArray(moduleList.tools, 0)
    };

    check writeToFile(MODULE_LIST_JSON, sortedList);
    return sortedList;
}

function sortModuleArray(Module[] moduleArray, int nameIndex) returns Module[] {
    Module[] sortedModuleArray = from Module module in moduleArray
        order by re `-`.split(module.name)[nameIndex] ascending
        select module;
    return sortedModuleArray;
}

function initializeModuleDetails(List moduleNameList) returns List|error {
    return {
        modules: check initializeModuleList(moduleNameList.modules),
        extendedModules: check initializeModuleList(moduleNameList.extendedModules),
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

    return {
        name: moduleName,
        module_version: moduleVersion,
        level: 1,
        default_branch: defaultBranch,
        version_key: versionKey,
        release: true,
        dependents: [],
        gradle_properties: gradleProperties
    };
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
function getImmediateDependencies(List moduleDetails) returns error? {
    foreach Module module in moduleDetails.modules {
        string[] dependees = check getDependencies(module, moduleDetails);

        // Get the dependecies modules which use module in there package
        foreach Module dependee in moduleDetails.modules {
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
function getDependencies(Module module, List moduleDetails) returns string[]|error {
    string[] propertiesFileArr = [];
    string moduleName = module.name;
    string? propertiesFile = module.gradle_properties;
    if propertiesFile is string {
        propertiesFileArr = re `\n`.split(propertiesFile);
    }
    string[] dependencies = [];

    foreach string line in propertiesFileArr {
        foreach Module item in moduleDetails.modules {
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
    _ = module.remove("gradle_properties");
    return dependencies;
}

function calculateLevels(List moduleDetails) returns error? {
    DiGraph dependencyGraph = new DiGraph();

    // Module names are used to create the nodes and the level attribute of the node is initialized to 1
    foreach Module module in moduleDetails.modules {
        dependencyGraph.addNode(module.name);
    }

    // Edges are created considering the dependents of each module
    foreach Module module in moduleDetails.modules {
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
            processCurrentLevel(dependencyGraph, processing, moduleDetails, currentLevel, n);
        }
        processedList = processing;
        currentLevel += 1;
    }

    foreach Module module in moduleDetails.modules {
        int? moduleLevel = dependencyGraph.getCurrentLevel(module.name);
        if moduleLevel is int {
            module.level = moduleLevel;
        }
    }
}

function processCurrentLevel(DiGraph dependencyGraph, string[] processing, List moduleDetails,
        int currentLevel, string node) {
    string[]? successorsOfNode = dependencyGraph.successor(node);
    string[] successors = [];

    if successorsOfNode is string[] {
        successors = successorsOfNode;
    }

    foreach string successor in successors {
        removeModulesInIntermediatePaths(dependencyGraph, node, successor, successors, moduleDetails);
        dependencyGraph.setCurrentLevel(successor, currentLevel);
        if !(processing.indexOf(successor) is int) {
            processing.push(successor);
        }
    }
}

function removeModulesInIntermediatePaths(DiGraph dependencyGraph, string sourceNode,
        string destinationNode, string[] successors, List moduleDetails) {
    string[] longestPath = dependencyGraph.getLongestPath(sourceNode, destinationNode);
    foreach string n in longestPath.slice(1, longestPath.length() - 1) {
        if (successors.indexOf(n) is int) {
            foreach Module module in moduleDetails.modules {
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
    updatedReadmeFile += check getBallerinaExtendedDashboard(moduleDetails.extendedModules);
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

isolated function writeToFile(string fileName, anydata content) returns error? {
    string prettifiedContent = prettify:prettify(content.toJson());

    error? result = io:fileWriteString(fileName, prettifiedContent);
    if result is error {
        log:printError("Error occurred while writing to the file: " + result.message());
        return result;
    }
}
