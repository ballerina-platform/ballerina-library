// Copyright (c) 2024 WSO2 LLC. (http://www.wso2.com).
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
import ballerina/lang.regexp;
import ballerina/lang.runtime;
import ballerina/os;
import ballerinax/github;

const string ACCESS_TOKEN_ENV = "BALLERINA_BOT_TOKEN";
const string RELEASE_LIBS = "RELEASE_LIBS";
const string RELEASE_EXTENSIONS = "RELEASE_EXTENSIONS";
const string RELEASE_TOOLS = "RELEASE_TOOLS";
const string RELEASE_DRIVER_MODULES = "RELEASE_DRIVER_MODULES";
const string RELEASE_HANDWRITTEN_CONNECTORS = "RELEASE_HANDWRITTEN_CONNECTORS";
const string RELEASE_GENERATED_CONNECTORS = "RELEASE_GENERATED_CONNECTORS";

const string MODULE_LIST_JSON = "./resources/stdlib_modules.json";
const string GITHUB_ORG = "ballerina-platform";

const decimal WORKFLOW_START_WAIT_TIME = 2;
const decimal WORKFLOW_POLL_INTERVAL = 5;

configurable string token = os:getEnv(ACCESS_TOKEN_ENV);

configurable boolean releaseLibs = check boolean:fromString(os:getEnv(RELEASE_LIBS));
configurable boolean releaseExtensions = check boolean:fromString(os:getEnv(RELEASE_EXTENSIONS));
configurable boolean releaseTools = check boolean:fromString(os:getEnv(RELEASE_TOOLS));
configurable boolean releaseDriverModules = check boolean:fromString(os:getEnv(RELEASE_DRIVER_MODULES));
configurable boolean releaseHandwrittenConnectors = check boolean:fromString(os:getEnv(RELEASE_HANDWRITTEN_CONNECTORS));
configurable boolean releaseGeneratedConnectors = check boolean:fromString(os:getEnv(RELEASE_GENERATED_CONNECTORS));

// Provide the correct workflow as a configurable variable.
configurable string workflow = ?;

final github:Client github = check new ({
    retryConfig: {
        count: 3,
        interval: 1,
        backOffFactor: 2.0,
        maxWaitInterval: 3
    },
    auth: {
        token
    }
});

public function main() returns error? {

    Module[]|error modules = getModuleList();
    if modules is error {
        printError(modules);
        return modules;
    }
    modules.forEach((m) => io:println(m.name));
    [Module[], int]|error filterResult = filterModules(modules);
    if filterResult is error {
        printError(filterResult);
        return filterResult;
    }
    Module[] filteredModules = filterResult[0];
    int maxLevel = filterResult[1];
    check handleRelease(filteredModules, maxLevel);
}

public function getModuleList() returns Module[]|error {
    List moduleList = check (check io:fileReadJson(MODULE_LIST_JSON)).fromJsonWithType();
    Module[] result = [];
    if releaseLibs {
        result.push(...moduleList.library_modules);
    }
    if releaseExtensions {
        result.push(...moduleList.extended_modules);
    }
    if releaseTools {
        result.push(...moduleList.tools);
    }
    if releaseDriverModules {
        result.push(...moduleList.driver_modules);
    }
    if releaseHandwrittenConnectors {
        result.push(...moduleList.handwritten_connectors);
    }
    if releaseGeneratedConnectors {
        result.push(...moduleList.generated_connectors);
    }
    return result;
}

isolated function filterModules(Module[] modules) returns [Module[], int]|error {
    regexp:RegExp snapshotRegex = check regexp:fromString("-SNAPSHOT");
    int maxLevel = 1;
    Module[] result = [];
    foreach Module m in modules {
        if m.level > maxLevel {
            maxLevel = m.level;
        }
        if !m.release {
            continue;
        }
        result.push({
            name: m.name,
            module_version: regexp:replaceAll(snapshotRegex, m.module_version, ""),
            level: m.level,
            default_branch: m.default_branch,
            release: m.release,
            version_key: m.version_key,
            inProgress: false
        });
    }
    return [result, maxLevel];
}

isolated function handleRelease(Module[] modules, int maxLevel) returns error? {
    int currentLevel = 1;
    while currentLevel <= maxLevel {
        Module[] currentLevelModules = from Module m in modules
            where m.level == currentLevel
            select m;
        check releaseLevel(currentLevelModules, currentLevel);
        currentLevel = currentLevel + 1;
    }
}

isolated function releaseLevel(Module[] modules, int level) returns error? {
    ProcessingModule[] processingModules = [];
    if modules.length() == 0 {
        return;
    }
    printInfo(string `Releasing modules in level: ${level}`);
    foreach Module m in modules {
        int workflowId = check triggerModuleRelease(m);
        processingModules.push({
            workflowId,
            m
        });
    }
    check waitForLevelRelease(processingModules, level);
    printInfo(string `All modules in level ${level} released successfully`);
}

isolated function waitForLevelRelease(ProcessingModule[] processingModules, int level) returns error? {
    printInfo(string `Waiting for level ${level} module releases to complete`);
    int processedCount = 0;
    int totalModules = processingModules.length();
    (Module|error)[] releasedModules = [];
    while processedCount < totalModules {
        runtime:sleep(WORKFLOW_POLL_INTERVAL);
        // Clonning the array to avoid concurrent modification
        ProcessingModule[] newProcessingModules = processingModules.clone();
        foreach ProcessingModule processingModule in newProcessingModules {
            boolean|error result = isModuleReleased(processingModule);
            if result is error {
                releasedModules.push(result);
                processedCount += 1;
                _ = removeModule(processingModules, processingModule);
                continue;
            }
            if result {
                releasedModules.push(processingModule.m);
                _ = removeModule(processingModules, processingModule);
                processedCount += 1;
            }
        }
    }
    check logProcessedModules(releasedModules, level);
}

isolated function triggerModuleRelease(Module m) returns int|error {
    printInfo(string `Releasing module: ${m.name}`);
    boolean versionAvailable = isVersionAlreadyAvailable(m);
    if versionAvailable {
        printInfo(string `Version ${m.module_version} already available for module: ${m.name}`);
        return 0;
    }
    m.inProgress = true;
    github:Workflow_id_dispatches_body payload = {
        ref: m.default_branch
    };

    error? dispatchResult = github->/repos/[GITHUB_ORG]/[m.name]/actions/workflows/[workflow]/dispatches.post(payload);
    if dispatchResult is error {
        printError(dispatchResult);
        return dispatchResult;
    }

    // Wait for the workflow to start
    runtime:sleep(WORKFLOW_START_WAIT_TIME);

    // Retrieve the workflow run ID
    github:WorkflowRunResponse|error result = github->/repos/[GITHUB_ORG]/[m.name]/actions/workflows/[workflow]/runs(per_page = 1);
    if result is error {
        printError(result);
        return result;
    }
    return result.workflow_runs[0].id;
}

isolated function isModuleReleased(ProcessingModule processingModule) returns boolean|error {
    int workflowId = processingModule.workflowId;
    if workflowId == 0 {
        return true;
    }
    github:WorkflowRun workflow = check github->/repos/[GITHUB_ORG]/[processingModule.m.name]/actions/runs/[workflowId];
    string? status = workflow.status;
    string? conclusion = workflow.conclusion;

    if status == "completed" {
        if conclusion == "success" {
            return true;
        } else {
            return error(string `Failed to release module: ${processingModule.m.name}`);
        }
    }
    return false;
}

isolated function isVersionAlreadyAvailable(Module m) returns boolean {
    // Check if the version is already available in the central repository
    github:Release|error release = github->/repos/[GITHUB_ORG]/[m.name]/releases/tags/[string `v${m.module_version}`];
    if release is error {
        return false;
    }
    return true;
}

isolated function removeModule(ProcessingModule[] modules, ProcessingModule m) returns ProcessingModule? {
    int? index = modules.indexOf(m);
    if index is () {
        return;
    }
    return modules.remove(index);
}

isolated function logProcessedModules((Module|error)[] releasedModules, int level) returns error? {
    boolean hasErrors = false;
    foreach Module|error m in releasedModules {
        if m is error {
            printError(m);
            hasErrors = true;
            continue;
        }
        printInfo(string `Module ${m.name} released successfully`);
    }

    if hasErrors {
        return error(string `Failed to release modules in level ${level}`);
    }
    printInfo(string `All modules in level ${level} released successfully`);
}

isolated function printInfo(string message) {
    io:println(string `[INFO] ${message}`);
}

isolated function printError(error e) {
    io:println(string `[ERROR] ${e.message()}`);
}
