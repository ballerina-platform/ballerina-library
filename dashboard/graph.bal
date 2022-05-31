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
import ballerina/regex;
import ballerina/lang.array;
import ballerina/log;

type List record {|
    Module[] modules;
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
    List moduleDetails = check initializeModuleDteails(moduleNameList);
    check getImmediateDependencies(moduleDetails);
    check calculateLevels(moduleDetails);
    Module[] sortedModules = moduleDetails.modules.sort(array:ASCENDING, a => a.level);
    moduleDetails = {modules: sortedModules};
    updateModulesJsonFile(moduleDetails);
    List[] seperateModulesResult = seperateModules(moduleDetails);
    check updateStdlibDashboard(seperateModulesResult[0], seperateModulesResult[1]);
}

//  Sorts the ballerina standard library module list in ascending order
function getSortedModuleNameList() returns List|error {

    json nameListJson = check io:fileReadJson(MODULE_LIST_JSON);
    List nameList = check nameListJson.cloneWithType();

    Module[] sortedModules = from var e in nameList.modules
        order by regex:split(e.name, "-")[2] ascending
        select e;
    List sortedNameList = {modules: sortedModules};

    check io:fileWriteJson(MODULE_LIST_JSON, sortedNameList.toJson());

    return sortedNameList;
}

function initializeModuleDteails(List moduleNameList) returns List|error {
    log:printInfo("Initializing the module information");
    List moduleDetails = {modules: []};

    foreach var module in moduleNameList.modules {
        Module initialModule = check initializeModuleInfo(module);
        moduleDetails.modules.push(initialModule);
    }
    return moduleDetails;
}

function initializeModuleInfo(Module module) returns Module|error {
    string moduleName = module.name;
    string defaultBranch = check getDefaultBranch(moduleName);
    string gradleProperties =
        check git->get(string `/${BALLERINA_ORG_NAME}/${moduleName}/${defaultBranch}/${GRADLE_PROPERTIES}`);
    string nameInVesrsionKey = capitalize(getModuleShortName(moduleName));
    string defaultVersionKey = string `stdlib${nameInVesrsionKey}Version`;
    string? versionKey = module.version_key;
    if versionKey is string {
        defaultVersionKey = versionKey;
    }
    string moduleVersion = check getVersion(moduleName, gradleProperties);

    return {
        name: moduleName,
        module_version: moduleVersion,
        level: 1,
        default_branch: defaultBranch,
        version_key: defaultVersionKey,
        release: true,
        dependents: [],
        gradle_properties: gradleProperties
    };
}

function getVersion(string moduleName, string gradleProperties) returns string|error {
    string[] gradlePropertiesLines = regex:split(gradleProperties, "\n");
    string moduleVersion = "";
    foreach var line in gradlePropertiesLines {
        if line.startsWith("version") {
            moduleVersion = regex:split(line, "=")[1];
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
        log:printInfo(string `Finding dependents of module ${module.name}`);
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
        propertiesFileArr = regex:split(propertiesFile, "\n");
    }
    string[] dependencies = [];

    foreach string line in propertiesFileArr {
        foreach Module item in moduleDetails.modules {
            string dependentName = item.name;
            if dependentName == moduleName {
                continue;
            }
            string? versionKey = item.version_key;
            if versionKey is string && regex:matches(line, "^.*" + versionKey + ".*$") {
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
        removeModulesInIntermediatePaths(
            dependencyGraph, node, successor, successors, moduleDetails);
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

function updateModulesJsonFile(List updatedJson) {
    io:Error? fileWriteJson = io:fileWriteJson(STDLIB_MODULES_JSON, updatedJson.toJson());
    if fileWriteJson is io:Error {
        log:printError(string `Failed to write to the ${STDLIB_MODULES_JSON}`);
    }
}

function seperateModules(List moduleDetails) returns List[] {
    Module[] ballerinaxSorted = from var e in moduleDetails.modules
        where regex:split(e.name, "-")[1] == "ballerinax"
        order by e.level ascending
        select e;
    Module[] ballerinaSorted = from var e in moduleDetails.modules
        where regex:split(e.name, "-")[1] == "ballerina"
        order by e.level ascending
        select e;
    List sortedNameListX = {"modules": ballerinaxSorted};
    List sortedNameList = {"modules": ballerinaSorted};

    return [sortedNameListX, sortedNameList];
}

// Updates the stdlib dashboard in README.md
function updateStdlibDashboard(List moduleDetailsBalX, List moduleDetailsBal) returns error? {
    string[] readmeFile = regex:split(check io:fileReadString(README_FILE), "\n");
    string updatedReadmeFile = "";
    foreach string line in readmeFile {
        updatedReadmeFile += line + "\n";
        if regex:matches(line, "^.*" + DASHBOARD_TITLE + ".*$") {
            updatedReadmeFile += "\n" + BAL_TITLE + "\n";
            updatedReadmeFile += README_HEADER;
            updatedReadmeFile += README_HEADER_SEPARATOR;
            break;
        }
    }
    // Modules in levels 0 and 1 are categorized under level 1
    // A single row in the table is created for each module in the module list
    string levelColumn = "1";
    int currentLevel = 1;

    foreach Module module in moduleDetailsBal.modules {
        int? moduleLevel = module.level;
        if moduleLevel is int && moduleLevel > currentLevel {
            currentLevel = moduleLevel;
            levelColumn = currentLevel.toString();
        }
        string row = check getDashboardRow(module, levelColumn);
        updatedReadmeFile += row;
        updatedReadmeFile += "\n";
        levelColumn = "";
    }

    levelColumn = "";
    updatedReadmeFile += "\n" + BALX_TITLE + "\n";
    updatedReadmeFile += README_HEADER;
    updatedReadmeFile += README_HEADER_SEPARATOR;

    foreach Module module in moduleDetailsBalX.modules {
        string row = check getDashboardRow(module, levelColumn);
        updatedReadmeFile += row;
        updatedReadmeFile += "\n";
    }

    io:Error? fileWriteString = io:fileWriteString(README_FILE, updatedReadmeFile);
    if fileWriteString is io:Error {
        log:printError(string `Failed to write to the ${README_FILE}`);
    }
    log:printInfo("Dashboard Updated");
}
