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
    json[] modulesJson = commons:getModuleJsonArray();
    commons:Module[] modules = commons:getModuleArray(modulesJson);
    removeSnapshotVersions(modules);
    handleRelease(modules);
}

function handleRelease(commons:Module[] modules) {
    int currentLevel = -1;
    commons:Module[] currentModules = [];
    foreach commons:Module module in modules {
        int nextLevel = module.level;
        if (nextLevel > currentLevel && currentModules.length() > 0) {
            waitForCurrentModuleReleases(currentModules, currentLevel);
            currentModules.removeAll();
        }
        if (module.release) {
            boolean inProgress = releaseModule(module);
            if (inProgress) {
                module.inProgress = inProgress;
                currentModules.push(module);
                log:printInfo("Module " + module.name + " release triggerred successfully.");
            } else {
                log:printWarn("Module " + module.name + " release did not triggerred successfully.");
            }
        }
        currentLevel = nextLevel;
    }
    waitForCurrentModuleReleases(currentModules, currentLevel);
}

function releaseModule(commons:Module module) returns boolean {
    commons:logNewLine();
    log:printInfo("Releasing " + module.name + " Version " + module.'version);
    http:Request request = commons:createRequest(accessTokenHeaderValue);
    string moduleName = module.name.toString();
    string 'version = module.'version.toString();
    string apiPath = "/" + moduleName + commons:DISPATCHES;

    json payload = {
        event_type: RELEASE_EVENT,
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

function waitForCurrentModuleReleases(commons:Module[] modules, int level) {
    if (modules.length() == 0) {
        return;
    }
    commons:logNewLine();
    log:printInfo("Waiting for level " + level.toString() + " module builds");
    commons:Module[] unreleasedModules = modules.filter(
        function (commons:Module m) returns boolean {
            return m.inProgress;
        }
    );
    commons:Module[] releasedModules = [];

    boolean allModulesReleased = false;
    int waitCycles = 0;
    while (!allModulesReleased) {
        foreach commons:Module module in modules {
            if (module.inProgress) {
                checkInProgressModules(module, unreleasedModules, releasedModules);
            }
        }
        if (releasedModules.length() == modules.length()) {
            allModulesReleased = true;
        } else if (waitCycles < commons:MAX_WAIT_CYCLES) {
            runtime:sleep(commons:SLEEP_INTERVAL);
            waitCycles += 1;
        } else {
            break;
        }
    }
    if (unreleasedModules.length() > 0) {
        log:printWarn("Following modules not released after the max wait time");
        commons:printModules(unreleasedModules);
        error err = error("Unreleased", message = "There are modules not released after max wait time");
        commons:logAndPanicError("Release Failed.", err);
    }
}

function checkInProgressModules(commons:Module module, commons:Module[] unreleased, commons:Module[] released) {
    boolean releaseCompleted = checkModuleRelease(module);
    if (releaseCompleted) {
        module.inProgress = !releaseCompleted;
        var moduleIndex = unreleased.indexOf(module);
        if (moduleIndex is int) {
            commons:Module releasedModule = unreleased.remove(moduleIndex);
            released.push(releasedModule);
            log:printInfo(releasedModule.name + " " + releasedModule.'version + " is released");
        }
    }
}

function checkModuleRelease(commons:Module module) returns boolean {
    // Don't wait for level 0 modules
    if (!module.inProgress || module.level < 1) {
        return true;
    }
    http:Request request = commons:createRequest(accessTokenHeaderValue);
    string moduleName = module.name.toString();
    string 'version = module.'version.toString();
    string expectedReleaseTag = "v" + 'version;

    string modulePath = "/" + moduleName + RELEASES + TAGS + "/v" + 'version;
    // Hack for type casting error in HTTP Client
    // https://github.com/ballerina-platform/ballerina-standard-library/issues/566
    var result = trap httpClient->get(modulePath, request);
    if (result is http:ClientError) {
        commons:logAndPanicError("Error occurred while checking the release status for module: " + moduleName, result);
    } else if (result is error) {
        log:printWarn("HTTP Client panicked while checking the release status for module: " + moduleName);
        return false;
    }
    http:Response response = <http:Response>result;

    if(!commons:validateResponse(response)) {
        return false;
    } else {
        map<json> payload = <map<json>>response.getJsonPayload();
        string releaseTag = payload[FIELD_TAG_NAME].toString();
        return <@untainted>releaseTag == expectedReleaseTag;
    }
}

function removeSnapshotVersions(commons:Module[] modules) {
    foreach commons:Module module in modules {
        string moduleVersion = module.'version;
        if (stringutils:contains(moduleVersion, SNAPSHOT)) {
            module.'version = stringutils:replace(moduleVersion, SNAPSHOT, "");
        }
    }
}
