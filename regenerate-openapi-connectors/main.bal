//  Copyright (c) 2025, WSO2 LLC. (http://www.wso2.com).
//
//  WSO2 LLC. licenses this file to you under the Apache License,
//  Version 2.0 (the "License"); you may not use this file except
//  in compliance with the License.
//  You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing,
//  software distributed under the License is distributed on an
//  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
//  KIND, either express or implied. See the License for the
//  specific language governing permissions and limitations
//  under the License.

import ballerina/io;
import ballerina/lang.runtime;
import ballerina/os;
import ballerinax/github;

const string ACCESS_TOKEN_ENV = "BALLERINA_BOT_TOKEN";
const string FLATTEN_OPENAPI = "FLATTEN_OPENAPI";
const string ADDITIONAL_FLATTEN_FLAGS = "ADDITIONAL_FLATTEN_FLAGS";
const string ALIGN_OPENAPI = "ALIGN_OPENAPI";
const string ADDITIONAL_ALIGN_FLAGS = "ADDITIONAL_ALIGN_FLAGS";
const string ADDITIONAL_GENERATION_FLAGS = "ADDITIONAL_GENERATION_FLAGS";
const string DISTRIBUTION_ZIP = "DISTRIBUTION_ZIP";
const string AUTO_MERGE = "AUTO_MERGE";
const string BALLERINA_VERSION = "BALLERINA_VERSION";

const string MODULE_LIST_JSON = "./resources/stdlib_modules.json";
const string GITHUB_ORG = "chathushkaayash";

const decimal WORKFLOW_START_WAIT_TIME = 2;
const decimal WORKFLOW_POLL_INTERVAL = 5;

configurable string token = os:getEnv(ACCESS_TOKEN_ENV);

configurable boolean flattenOpenAPI = check boolean:fromString(os:getEnv(FLATTEN_OPENAPI));
configurable string additionalFlattenFlags = os:getEnv(ADDITIONAL_FLATTEN_FLAGS);
configurable boolean alignOpenAPI = check boolean:fromString(os:getEnv(ALIGN_OPENAPI));
configurable string additionalAlignFlags = os:getEnv(ADDITIONAL_ALIGN_FLAGS);
configurable string additionalGenerationFlags = os:getEnv(ADDITIONAL_GENERATION_FLAGS);
configurable string distributionZip = os:getEnv(DISTRIBUTION_ZIP);
configurable boolean autoMerge = check boolean:fromString(os:getEnv(AUTO_MERGE));
configurable string ballerinaVersion = os:getEnv(BALLERINA_VERSION);

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

    Module[]|error modules = getGeneratedModuleList();
    if modules is error {
        printError(modules);
        return modules;
    }
    modules.forEach((m) => io:println(m.name));
    ProcessingModule[] processingModules = [];
    if modules.length() == 0 {
        return;
    }
    foreach Module m in modules {
        int|error workflowId = triggerModuleRegeneration(m);
        if workflowId is error {
            continue;
        }
        processingModules.push({
            workflowId,
            m
        });
    }
    check waitForRegeneration(processingModules);
}

public function getGeneratedModuleList() returns Module[]|error {
    List moduleList = check (check io:fileReadJson(MODULE_LIST_JSON)).fromJsonWithType();
    return moduleList.generated_connectors;
}

isolated function waitForRegeneration(ProcessingModule[] processingModules) returns error? {
    printInfo(string `Waiting for module regeneration to complete`);
    int processedCount = 0;
    int totalModules = processingModules.length();
    (Module|error)[] regeneratedModules = [];
    while processedCount < totalModules {
        runtime:sleep(WORKFLOW_POLL_INTERVAL);
        // Cloning the array to avoid concurrent modification
        ProcessingModule[] newProcessingModules = processingModules.clone();
        foreach ProcessingModule processingModule in newProcessingModules {
            boolean|error result = isModuleRegenerated(processingModule);
            if result is error {
                regeneratedModules.push(result);
                processedCount += 1;
                _ = removeModule(processingModules, processingModule);
                continue;
            }
            if result {
                regeneratedModules.push(processingModule.m);
                _ = removeModule(processingModules, processingModule);
                processedCount += 1;
            }
        }
    }
    check logProcessedModules(regeneratedModules);
}

isolated function triggerModuleRegeneration(Module m) returns int|error {
    printInfo(string `Regenerating module: ${m.name}`);
    m.inProgress = true;
    github:Workflow_id_dispatches_body payload = {
        ref: m.default_branch,
        inputs: {
            "flatten-openapi": flattenOpenAPI,
            "additional-flatten-flags": additionalFlattenFlags,
            "align-openapi": alignOpenAPI,
            "additional-align-flags": additionalAlignFlags,
            "distribution-zip": distributionZip,
            "auto-merge": autoMerge,
            "ballerina-version": ballerinaVersion,
            "additional-generation-flags": additionalGenerationFlags
        }
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

isolated function isModuleRegenerated(ProcessingModule processingModule) returns boolean|error {
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
            return error(string `Failed to regenerate module: ${processingModule.m.name}`);
        }
    }
    return false;
}

isolated function removeModule(ProcessingModule[] modules, ProcessingModule m) returns ProcessingModule? {
    int? index = modules.indexOf(m);
    if index is () {
        return;
    }
    return modules.remove(index);
}

isolated function logProcessedModules((Module|error)[] regeneratedModules) returns error? {
    boolean hasErrors = false;
    foreach Module|error m in regeneratedModules {
        if m is error {
            printError(m);
            hasErrors = true;
            continue;
        }
        printInfo(string `Module ${m.name} regenerated successfully`);
    }

    if hasErrors {
        return error(string `Some modules failed to regenerate`);
    }
    printInfo(string `All modules regenerated successfully`);
}

isolated function printInfo(string message) {
    io:println(string `[INFO] ${message}`);
}

isolated function printError(error e) {
    io:println(string `[ERROR] ${e.message()}`);
}
