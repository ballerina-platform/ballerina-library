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

import ballerina/data.jsondata;
import ballerina/io;
import ballerina/lang.array;
import ballerina/log;

public function main() returns error? {
    List moduleNameList = check getSortedModuleNameList();
    List moduleDetails = check initializeModuleDetails(moduleNameList);

    Module[] libraryModules = moduleDetails.library_modules;
    Module[] extendedModules = moduleDetails.extended_modules;
    Module[] handwrittenConnectors = moduleDetails.handwritten_connectors;
    Module[] generatedConnectors = moduleDetails.generated_connectors;
    Module[] tools = moduleDetails.tools;

    Module[] modules = [
        ...libraryModules,
        ...extendedModules,
        ...handwrittenConnectors,
        ...generatedConnectors,
        ...tools
    ];

    check getImmediateDependencies(modules);
    check calculateLevels(modules);
    moduleDetails.forEach(function(Module[] moduleList) {
        removePropertiesFile(moduleList);
    });

    moduleDetails.library_modules = libraryModules.sort(array:ASCENDING, a => a.level);

    check writeToFile(STDLIB_MODULES_JSON, moduleDetails);
    check updateDashboard(moduleDetails);
}

//  Sorts the Ballerina library module list in ascending order
function getSortedModuleNameList() returns List|error {
    List moduleList = check (check io:fileReadJson(MODULE_LIST_JSON)).fromJsonWithType();

    List sortedList = {
        library_modules: sortModuleArray(moduleList.library_modules),
        extended_modules: sortModuleArray(moduleList.extended_modules),
        handwritten_connectors: sortModuleArray(moduleList.handwritten_connectors),
        generated_connectors: sortModuleArray(moduleList.generated_connectors),
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
        library_modules: check initializeModuleList(moduleNameList.library_modules),
        extended_modules: check initializeModuleList(moduleNameList.extended_modules),
        handwritten_connectors: check initializeModuleList(moduleNameList.handwritten_connectors, MAX_LEVEL),
        generated_connectors: check initializeModuleList(moduleNameList.generated_connectors, MAX_LEVEL),
        tools: check initializeModuleList(moduleNameList.tools)
    };
}

function initializeModuleList(Module[] modules, int defaultModuleLevel = 1) returns Module[]|error {
    Module[] moduleList = [];
    foreach Module module in modules {
        Module initialModule = check initializeModuleInfo(module, defaultModuleLevel);
        moduleList.push(initialModule);
    }
    return moduleList;
}

function initializeModuleInfo(Module module, int defaultModuleLevel = 1) returns Module|error {
    string moduleName = module.name;
    string defaultBranch = check getDefaultBranch(moduleName);
    string gradleProperties = check getGradlePropertiesFile(moduleName);
    string moduleVersion = check getVersion(moduleName, gradleProperties);
    return {
        name: moduleName,
        module_version: moduleVersion,
        level: defaultModuleLevel,
        default_branch: defaultBranch,
        version_key: getVersionKey(module),
        release: true,
        dependents: [],
        gradle_properties: gradleProperties,
        is_multiple_connectors: module.is_multiple_connectors ?: false
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
        if module.level == MAX_LEVEL {
            continue;
        }
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
        if successors.indexOf(n) is int {
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
function updateDashboard(List moduleDetails) returns error? {
    string readmeFile = check io:fileReadString(README_FILE);
    string[] readmeFileLines = re `\n`.split(readmeFile);
    string updatedReadmeFile = "";

    foreach string line in readmeFileLines {
        updatedReadmeFile += line + "\n";
        if line == DASHBOARD_TITLE {
            break;
        }
    }

    updatedReadmeFile += check getLibraryModulesDashboard(moduleDetails.library_modules);
    updatedReadmeFile += check getExtendedModulesDashboard(moduleDetails.extended_modules);
    updatedReadmeFile += check getHandwrittenConnectorDashboard(moduleDetails.handwritten_connectors);
    updatedReadmeFile += check getGeneratedConnectorDashboard(moduleDetails.generated_connectors);
    updatedReadmeFile += check getBallerinaToolsDashboard(moduleDetails.tools);

    io:Error? fileWriteString = io:fileWriteString(README_FILE, updatedReadmeFile);
    if fileWriteString is io:Error {
        log:printError(string `Failed to write to the ${README_FILE}`);
    }
    log:printInfo("Dashboard Updated");
}

isolated function getLibraryModulesDashboard(Module[] modules) returns string|error {
    string data = "";
    string levelColumn = "1";
    int currentLevel = 1;
    foreach Module module in modules {
        int? moduleLevel = module.level;
        if moduleLevel is int && moduleLevel > currentLevel {
            currentLevel = moduleLevel;
            levelColumn = currentLevel.toString();
        }
        data += check getLibraryDashboardRow(module, levelColumn) + "\n";
        levelColumn = "";
    }
    return getDashboard(TITLE_LIBRARY_MODULES, DESCRIPTION_LIBRARY_MODULES, HEADER_LIBRARY_MODULES_DASHBOARD,
            HEADER_SEPARATOR_LIBRARY_MODULES, data);
}

isolated function getExtendedModulesDashboard(Module[] modules) returns string|error {
    string data = "";
    foreach Module module in modules {
        data += check getDashboardRow(module) + "\n";
    }
    return getDashboard(TITLE_EXTENDED_MODULES, DESCRIPTION_EXTENDED_MODULES, HEADER_EXTENDED_MODULES_DASHBOARD,
            HEADER_SEPARATOR_EXTENDED_MODULES, data);
}

isolated function getHandwrittenConnectorDashboard(Module[] modules) returns string|error {
    string data = "";

    foreach Module module in modules {
        data += check getDashboardRow(module) + "\n";
    }
    return getDashboard(TITLE_HANDWRITTEN_CONNECTORS, DESCRIPTION_HANDWRITTEN_CONNECTORS,
            HEADER_HANDWRITTEN_CONNECTOR_DASHBOARD, HEADER_SEPARATOR_HANDWRITTEN_CONNECTORS, data);
}

isolated function getGeneratedConnectorDashboard(Module[] modules) returns string|error {
    string data = "";

    foreach Module module in modules {
        data += check getGeneratedConnectorDashboardRow(module) + "\n";
    }
    return getDashboard(TITLE_GENERATED_CONNECTORS, DESCRIPTION_GENERATED_CONNECTORS,
            HEADER_GENERATED_CONNECTOR_DASHBOARD, HEADER_SEPARATOR_GENERATED_CONNECTORS, data);
}

isolated function getBallerinaToolsDashboard(Module[] modules) returns string|error {
    string data = "";

    foreach Module module in modules {
        data += check getToolsDashboardRow(module) + "\n";
    }
    return getDashboard(TITLE_TOOLS, DESCRIPTION_TOOLS, HEADER_TOOLS_DASHBOARD, HEADER_SEPARATOR_TOOLS, data);
}

isolated function getDashboard(string title, string description, string header, string separator, string data) returns string {
    return string `
${title}

${description}

${header}
${separator}
${data}`;
}

isolated function writeToFile(string fileName, json content) returns error? {
    string prettifiedContent = jsondata:prettify(content);

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
