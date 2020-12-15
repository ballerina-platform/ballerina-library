import ballerina/config;
import ballerina/http;
import ballerina/log;
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

boolean isFailure = false;

public function main() {
    json[] modulesJson = commons:getModuleJsonArray();
    commons:Module[] modules = commons:getModuleArray(modulesJson);
    commons:addDependentModules(modules);

    commons:WorkflowStatus workflowStatus = {
        isFailure: false,
        failedModules: []
    };

    log:printInfo("Publishing all the standard library snapshots");
    checkCurrentPublishWorkflows();
    commons:handlePublish(modules, workflowStatus);

    if (isFailure) {
        commons:logNewLine();
        log:printWarn("Following module builds failed");
        foreach string name in workflowStatus.failedModules {
            log:printWarn(name);
        }
        error err = error("Failed", message = "Some module builds are failing");
        panic err;
    }
}

function checkCurrentPublishWorkflows() {
    log:printInfo("Checking for already running workflows");
    http:Request request = commons:createRequest();
    string apiPath = "/ballerina-standard-library/actions/workflows/publish_snapshots.yml/runs?per_page=1";
    var result = trap httpClient->get(apiPath, request);
    if (result is error) {
        log:printWarn("Error occurred while checking the current workflow status");
    }
    http:Response response = <http:Response>result;
    boolean isValid = commons:validateResponse(response);
    if (isValid) {
        map<json> payload = commons:getJsonPayload(response);
        if (!commons:isWorkflowCompleted(payload)) {
            map<json> workflow = commons:getWorkflowJsonObject(payload);
            cancelWorkflow(workflow.id.toString());
        } else {
            log:printInfo("No workflows running");
        }
    }
}

function cancelWorkflow(string id) {
    string path = "/ballerina-standard-library/actions/runs/" + id + "/cancel";
    http:Request request = commons:createRequest();
    var result = trap httpClient->post(path, request);
    if (result is error) {
        log:printWarn("Error occurred while cancelling the current workflow status");
    } else {
        log:printInfo("Cancelled the already running job.");
    }
}
