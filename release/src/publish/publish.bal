import ballerina/config;
import ballerina/http;
import ballerina/log;
import ballerina/runtime;
import ballerina/stringutils;
import ballerina_stdlib/commons;

http:ClientConfiguration clientConfig = {
    retryConfig: {
        count: commons:RETRY_COUNT,
		intervalInMillis: commons:RETRY_INTERVAL,
		backOffFactor: commons:RETRY_BRACKOFF_FACTOR,
		maxWaitIntervalInMillis: commons:RETRY_MAX_WAIT_TIME
    }
};
http:Client httpClient = new (commons:API_PATH, clientConfig);
string accessToken = config:getAsString(commons:ACCESS_TOKEN_ENV);
string accessTokenHeaderValue = "Bearer " + accessToken;

public function main() {
    string eventType = config:getAsString(CONFIG_EVENT_TYPE);
    json[] modulesJson = commons:getModuleJsonArray();
    commons:Module[] modules = commons:getModuleArray(modulesJson);
    addDependentModules(modules);

    if (eventType == EVENT_TYPE_MODULE_PUSH) {
        string moduleFullName = config:getAsString(CONFIG_SOURCE_MODULE);
        string moduleName = stringutils:split(moduleFullName, "/")[1];
        log:printInfo("Publishing snapshots of the dependents of the module: " + moduleName);
        commons:Module? module = commons:getModuleFromModuleArray(modules, moduleName);
        if (module is commons:Module) {
            commons:Module[] toBePublished = getModulesToBePublished(module);
            handlePublish(toBePublished);
        } else {
            log:printWarn("Module '" + moduleName + "' not found in module array");
        }
    } else if (eventType == EVENT_TYPE_LANG_PUSH) {
        log:printInfo("Publishing all the standard library snapshots");
        handlePublish(modules);
    }
}

function handlePublish(commons:Module[] modules) {
    int currentLevel = -1;
    commons:Module[] currentModules = [];
    foreach commons:Module module in modules {
        int nextLevel = module.level;
        if (nextLevel > currentLevel) {
            waitForCurrentLevelModuleBuild(currentModules, currentLevel);
            currentModules.removeAll();
        }
        boolean inProgress = publishModule(module);
        if (inProgress) {
            module.inProgress = inProgress;
            currentModules.push(module);
            log:printInfo("Module " + module.name + " publish workflow triggerred successfully.");
        } else {
            log:printWarn("Module " + module.name + " publish workflow did not triggerred successfully.");
        }
        currentLevel = nextLevel;
    }
    waitForCurrentLevelModuleBuild(currentModules, currentLevel);
}

function waitForCurrentLevelModuleBuild(commons:Module[] modules, int level) {
    if (modules.length() == 0) {
        return;
    }
    commons:logNewLine();
    log:printInfo("Waiting for level " + level.toString() + " module builds");
    runtime:sleep(commons:SLEEP_INTERVAL); // sleep first to make sure we get the latest workflow triggered by this job
    commons:Module[] unpublishedModules = modules.filter(
        function (commons:Module m) returns boolean {
            return m.inProgress;
        }
    );
    commons:Module[] publishedModules = [];

    boolean allModulesPublished = false;
    int waitCycles = 0;
    while (!allModulesPublished) {
        foreach commons:Module module in modules {
            if (module.inProgress) {
                checkInProgressModules(module, unpublishedModules, publishedModules);
            }
        }
        if (publishedModules.length() == modules.length()) {
            allModulesPublished = true;
        } else if (waitCycles < commons:MAX_WAIT_CYCLES) {
            runtime:sleep(commons:SLEEP_INTERVAL);
            waitCycles += 1;
        } else {
            break;
        }
    }
    if (unpublishedModules.length() > 0) {
        log:printWarn("Following modules not published after the max wait time");
        commons:printModules(unpublishedModules);
        error err = error("Unpublished", message = "There are modules not published after max wait time");
        commons:logAndPanicError("Release Failed.", err);
    }
}

function checkInProgressModules(commons:Module module, commons:Module[] unpublished, commons:Module[] published) {
    boolean publishCompleted = checkModulePublish(module);
    if (publishCompleted) {
        module.inProgress = !publishCompleted;
        var moduleIndex = unpublished.indexOf(module);
        if (moduleIndex is int) {
            commons:Module publishedModule = unpublished.remove(moduleIndex);
            published.push(publishedModule);
            log:printInfo(publishedModule.name + " is published");
        }
    }
}

function checkModulePublish(commons:Module module) returns boolean {
    http:Request request = commons:createRequest(accessTokenHeaderValue);
    string moduleName = module.name.toString();
    string apiPath = "/" + moduleName + "/" + commons:WORKFLOW_STATUS_PATH;
    // Hack for type casting error in HTTP Client
    // https://github.com/ballerina-platform/ballerina-standard-library/issues/566
    var result = trap httpClient->get(apiPath, request);
    if (result is http:ClientError) {
        commons:logAndPanicError("Error occurred while releasing the module: " + moduleName, result);
    } else if (result is error) {
        log:printWarn("HTTP Client panicked while checking the publish status for module: " + moduleName);
        return false;
    }
    http:Response response = <http:Response>result;
    boolean isValid = commons:validateResponse(response);
    if (isValid) {
        map<json> payload = commons:getJsonPayload(response);
        if (isWorkflowCompleted(payload)) {
            return isWorkflowRunSuccess(payload, module);
        }
    }
    return false;
}

function isWorkflowCompleted(map<json> payload) returns boolean {
    map<json> workflowRun = getWorkflowJsonObject(payload);
    string status = workflowRun.status.toString();
    return status == STATUS_COMPLETED;
}

function isWorkflowRunSuccess(map<json> payload, commons:Module module) returns boolean {
    map<json> workflowRun = getWorkflowJsonObject(payload);
    string conclusion = workflowRun.conclusion.toString();
    if (conclusion == CONCLUSION_SUCCSESS) {
        return true;
    }
    string message = "Module " + module.name + " build did not successfully completed.";
    error e = error("Unsuccessfull", message = "Workflow run conclusion: " + conclusion);
    if (module.dependentModules.length() > 0) {
        commons:logAndPanicError(message, e);
    } else {
        log:printWarn(message + " Conclusion: " + conclusion);
    }
    return false;
}

function getWorkflowJsonObject(map<json> payload) returns map<json> {
    json[] workflows = <json[]>payload[WORKFLOW_RUNS];
    return <map<json>>workflows[0];
}

function publishModule(commons:Module module) returns boolean {
    commons:logNewLine();
    log:printInfo("Publishing " + module.name + " Version " + module.'version);
    http:Request request = commons:createRequest(accessTokenHeaderValue);
    string moduleName = module.name.toString();
    string 'version = module.'version.toString();
    string apiPath = "/" + moduleName + commons:DISPATCHES;

    json payload = {
        event_type: PUBLISH_SNAPSHOT_EVENT,
        client_payload: {
            'version: 'version
        }
    };
    request.setJsonPayload(payload);
    var result = httpClient->post(apiPath, request);
    if (result is error) {
        commons:logAndPanicError("Error occurred while releasing the module: " + moduleName, result);
    }
    http:Response response = <http:Response>result;
    return commons:validateResponse(response);
}

function getModulesToBePublished(commons:Module module) returns commons:Module[] {
    commons:Module[] toBePublished = [];
    populteToBePublishedModules(module, toBePublished);
    toBePublished = commons:sortModules(toBePublished);
    toBePublished = commons:removeDuplicates(toBePublished);
    // Removing the parent module
    int parentModuleIndex = <int>toBePublished.indexOf(module);
    _ = toBePublished.remove(parentModuleIndex);
    return toBePublished;
}

function populteToBePublishedModules(commons:Module module, commons:Module[] toBePublished) {
    toBePublished.push(module);
    foreach commons:Module dependentModule in module.dependentModules {
        populteToBePublishedModules(dependentModule, toBePublished);
    }
}

function addDependentModules(commons:Module[] modules) {
    foreach commons:Module module in modules {
        commons:Module[] dependentModules = [];
        string[] dependentModuleNames = module.dependents;
        foreach string dependentModuleName in dependentModuleNames {
            commons:Module? dependentModule = commons:getModuleFromModuleArray(modules, dependentModuleName);
            if (dependentModule is commons:Module) {
                dependentModules.push(dependentModule);
            }
        }
        dependentModules = commons:sortModules(dependentModules);
        module.dependentModules = dependentModules;
    }
}
