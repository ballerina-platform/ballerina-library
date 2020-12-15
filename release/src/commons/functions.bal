import ballerina/config;
import ballerina/http;
import ballerina/io;
import ballerina/lang.'string;
import ballerina/log;
import ballerina/runtime;
import ballerina/stringutils;

http:ClientConfiguration clientConfig = {
    retryConfig: {
        count: RETRY_COUNT,
		intervalInMillis: RETRY_INTERVAL,
		backOffFactor: RETRY_BACKOFF_FACTOR,
		maxWaitIntervalInMillis: RETRY_MAX_WAIT_TIME
    }
};
http:Client httpClient = new (API_PATH, clientConfig);
string accessToken = config:getAsString(ACCESS_TOKEN_ENV);
string accessTokenHeaderValue = "Bearer " + accessToken;

public function handlePublish(Module[] modules, WorkflowStatus workflowStatus) {
    int currentLevel = -1;
    Module[] currentModules = [];
    foreach Module module in modules {
        int nextLevel = module.level;
        if (nextLevel > currentLevel) {
            waitForCurrentLevelModuleBuild(currentModules, currentLevel, workflowStatus);
            logNewLine();
            log:printInfo("Publishing level " + nextLevel.toString() + " modules");
            currentModules.removeAll();
        }
        boolean inProgress = publishModule(module, accessTokenHeaderValue, httpClient);
        if (inProgress) {
            module.inProgress = inProgress;
            currentModules.push(module);
            log:printInfo("Successfully triggerred the module \"" + getModuleName(module) + "\"");
        } else {
            log:printWarn("Failed to trigger the module \"" + getModuleName(module) + "\"");
        }
        currentLevel = nextLevel;
    }
    waitForCurrentLevelModuleBuild(currentModules, currentLevel, workflowStatus);
}

function waitForCurrentLevelModuleBuild(Module[] modules, int level, WorkflowStatus workflowStatus) {
    if (modules.length() == 0) {
        return;
    }
    logNewLine();
    log:printInfo("Waiting for level " + level.toString() + " module builds");
    runtime:sleep(SLEEP_INTERVAL); // sleep first to make sure we get the latest workflow triggered by this job
    Module[] unpublishedModules = modules.filter(
        function (Module m) returns boolean {
            return m.inProgress;
        }
    );
    Module[] publishedModules = [];

    boolean allModulesPublished = false;
    int waitCycles = 0;
    while (!allModulesPublished) {
        foreach Module module in modules {
            if (module.inProgress) {
                checkInProgressModules(module, unpublishedModules, publishedModules, workflowStatus);
            }
        }
        if (publishedModules.length() == modules.length()) {
            allModulesPublished = true;
        } else if (waitCycles < MAX_WAIT_CYCLES) {
            runtime:sleep(SLEEP_INTERVAL);
            waitCycles += 1;
        } else {
            break;
        }
    }
    if (unpublishedModules.length() > 0) {
        log:printWarn("Following modules not published after the max wait time");
        printModules(unpublishedModules);
        error err = error("Unpublished", message = "There are modules not published after max wait time");
        logAndPanicError("Publishing Failed.", err);
    }
}

function checkInProgressModules(Module module, Module[] unpublished, Module[] published, WorkflowStatus status) {
    boolean publishCompleted = checkModulePublish(module, status);
    if (publishCompleted) {
        module.inProgress = !publishCompleted;
        var moduleIndex = unpublished.indexOf(module);
        if (moduleIndex is int) {
            Module publishedModule = unpublished.remove(moduleIndex);
            published.push(publishedModule);
        }
    }
}

function checkModulePublish(Module module, WorkflowStatus workflowStatus) returns boolean {
    http:Request request = createRequest(accessTokenHeaderValue);
    string moduleName = module.name.toString();
    string apiPath = "/" + moduleName + "/" + WORKFLOW_STATUS_PATH;
    // Hack for type casting error in HTTP Client
    // https://github.com/ballerina-platform/ballerina-standard-library/issues/566
    var result = trap httpClient->get(apiPath, request);
    if (result is error) {
        log:printWarn("Error occurred while checking the publish status for module: " + getModuleName(module));
        return false;
    }
    http:Response response = <http:Response>result;
    boolean isValid = validateResponse(response);
    if (isValid) {
        map<json> payload = getJsonPayload(response);
        if (isWorkflowCompleted(payload)) {
            workflowStatus.isFailure = !isRunSuccess(payload, module);
            workflowStatus.failedModules[workflowStatus.failedModules.length()] = module.name;
            return true;
        }
    }
    return false;
}

public function isWorkflowCompleted(map<json> payload) returns boolean {
    map<json> workflowRun = getWorkflowJsonObject(payload);
    string status = workflowRun.status.toString();
    return status == STATUS_COMPLETED;
}

function isRunSuccess(map<json> payload, Module module) returns boolean {
    map<json> workflowRun = getWorkflowJsonObject(payload);
    string status = workflowRun.conclusion.toString();
    if (status == CONCLUSION_SUCCSESS) {
        log:printInfo("Succcessfully published the module \"" + getModuleName(module) + "\"");
        return true;
    } else {
        log:printWarn("Failed to publish the module \"" + getModuleName(module) + "\". Conclusion: " + status);
        return false;
    }
}

public function getWorkflowJsonObject(map<json> payload) returns map<json> {
    json[] workflows = <json[]>payload[WORKFLOW_RUNS];
    return <map<json>>workflows[0];
}

public function addDependentModules(Module[] modules) {
    foreach Module module in modules {
        Module[] dependentModules = [];
        string[] dependentModuleNames = module.dependents;
        foreach string dependentModuleName in dependentModuleNames {
            Module? dependentModule = getModuleFromModuleArray(modules, dependentModuleName);
            if (dependentModule is Module) {
                dependentModules.push(dependentModule);
            }
        }
        dependentModules = sortModules(dependentModules);
        module.dependentModules = dependentModules;
    }
}

public function populteToBePublishedModules(Module module, Module[] toBePublished) {
    toBePublished.push(module);
    foreach Module dependentModule in module.dependentModules {
        populteToBePublishedModules(dependentModule, toBePublished);
    }
}

public function publishModule(Module module, string accessToken, http:Client httpClient) returns boolean {
    http:Request request = createRequest(accessToken);
    string moduleName = module.name.toString();
    string 'version = module.'version.toString();
    string apiPath = "/" + moduleName + DISPATCHES;

    json payload = {
        event_type: PUBLISH_SNAPSHOT_EVENT,
        client_payload: {
            'version: 'version
        }
    };
    request.setJsonPayload(payload);
    var result = httpClient->post(apiPath, request);
    if (result is error) {
        logAndPanicError("Failed to publish the module \"" + getModuleName(module) + "\"", result);
    }
    http:Response response = <http:Response>result;
    return validateResponse(response);
}

public function sortModules(Module[] modules) returns Module[] {
    return modules.sort(compareModules);
}

public function getJsonPayload(http:Response response) returns map<json> {
    var result = response.getJsonPayload();
    if (result is error) {
        logAndPanicError("Error occurred while retriving the JSON payload", result);
    }
    return <@untainted map<json>>result;
}

public function removeDuplicates(Module[] modules) returns Module[] {
    int length = modules.length();
    if (length < 2) {
        return modules;
    }
    Module[] newModules = [];
    int i = 0;
    int j = 0;
    while (i < length) {
        if (i < length -1 && modules[i] == modules[i + 1]) {
            i += 1;
            continue;
        }
        newModules[j] = modules[i];
        i += 1;
        j += 1;
    }
    return newModules;
}

function compareModules(Module m1, Module m2) returns int {
    if (m1.level > m2.level) {
        return 1;
    } else if (m1.level < m2.level) {
        return -1;
    } else {
        return 'string:codePointCompare(m1.name, m2.name);
    }
}

public function getModuleJsonArray() returns json[] {
    var result = readFileAndGetJson(CONFIG_FILE_PATH);
    if (result is error) {
        logAndPanicError("Error occurred while reading the config file", result);
    }
    json jsonFile = <json>result;
    return <json[]>jsonFile.modules;
}

public function getModuleArray(json[] modulesJson) returns Module[] {
    Module[] modules = [];
    foreach json moduleJson in modulesJson {
        Module|error result = Module.constructFrom(moduleJson);
        if (result is error) {
            logAndPanicError("Error building the module record", result);
        }
        Module module = <Module>result;
        modules.push(module);
    }
    return sortModules(modules);
}

public function createRequest(string accessTokenHeaderValue) returns http:Request {
    http:Request request = new;
    request.setHeader(ACCEPT_HEADER_KEY, ACCEPT_HEADER_VALUE);
    request.setHeader(AUTH_HEADER_KEY, accessTokenHeaderValue);
    return request;
}

function readFileAndGetJson(string path) returns json|error {
    io:ReadableByteChannel rbc = check <@untainted>io:openReadableFile(path);
    io:ReadableCharacterChannel rch = new (rbc, "UTF8");
    var result = <@untainted>rch.readJson();
    closeReadChannel(rch);
    return result;
}

function closeReadChannel(io:ReadableCharacterChannel rc) {
    var result = rc.close();
    if (result is error) {
        log:printError("Error occurred while closing character stream", result);
    }
}

public function validateResponse(http:Response response) returns boolean {
    int statusCode = response.statusCode;
    if (statusCode != 200 && statusCode != 201 && statusCode != 202 && statusCode != 204) {
        return false;
    }
    return true;
}

public function logAndPanicError(string message, error e) {
    log:printError(message, e);
    panic e;
}

public function getModuleName(Module module) returns string {
    string moduleFullName = module.name;
    return stringutils:split(moduleFullName, "-")[2];
}

public function printModules(Module[] modules) {
    foreach Module module in modules {
        printModule(module);
    }
}

public function printModule (Module module) {
    log:printInfo(getModuleName(module) + " " + module.'version);
}

public function logNewLine() {
    log:printInfo("------------------------------");
}

public function getModuleFromModuleArray(Module[] modules, string name) returns Module? {
    foreach Module module in modules {
        if (module.name == name) {
            return module;
        }
    }
}
