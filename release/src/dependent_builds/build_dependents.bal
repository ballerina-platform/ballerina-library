import ballerina/config;
import ballerina/http;
import ballerina/log;
import ballerina/stringutils;
import ballerina_stdlib/commons;

http:ClientConfiguration clientConfig = {
    retryConfig: {
        count: commons:RETRY_COUNT,
		intervalInMillis: commons:RETRY_INTERVAL,
		backOffFactor: commons:RETRY_BACKOFF_FACTOR,
		maxWaitIntervalInMillis: commons:RETRY_MAX_WAIT_TIME
    }
};
http:Client httpClient = new (commons:API_PATH, clientConfig);
string accessToken = config:getAsString(commons:ACCESS_TOKEN_ENV);
string accessTokenHeaderValue = "Bearer " + accessToken;

public function main() {
    string moduleFullName = stringutils:split(config:getAsString(CONFIG_SOURCE_MODULE), "/")[1];
    string moduleName = stringutils:split(moduleFullName, "-")[2];
    log:printInfo("Publishing snapshots of the dependents of the module \"" + moduleName + "\"");

    commons:Module[] modules = commons:getModuleArray(commons:getModuleJsonArray());
    commons:addDependentModules(modules);

    commons:WorkflowStatus workflowStatus = {
        isFailure: false,
        failedModules: []
    };

    commons:Module? module = commons:getModuleFromModuleArray(modules, moduleFullName);
    if (module is commons:Module) {
        commons:Module[] toBePublished = getModulesToBePublished(module);
        commons:handlePublish(toBePublished, workflowStatus);
    } else {
        log:printWarn("Module '" + moduleName + "' not found in module array");
    }

    if (workflowStatus.isFailure) {
        commons:logNewLine();
        log:printWarn("Following module builds failed");
        foreach string name in workflowStatus.failedModules {
            log:printWarn(name);
        }
        error err = error("Failed", message = "Some module builds are failing");
        panic err;
    }
}

function getModulesToBePublished(commons:Module module) returns commons:Module[] {
    commons:Module[] toBePublished = [];
    commons:populteToBePublishedModules(module, toBePublished);
    toBePublished = commons:sortModules(toBePublished);
    toBePublished = commons:removeDuplicates(toBePublished);
    // Removing the parent module
    int parentModuleIndex = <int>toBePublished.indexOf(module);
    _ = toBePublished.remove(parentModuleIndex);
    return toBePublished;
}
