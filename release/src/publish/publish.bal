import ballerina/config;
import ballerina/http;
import ballerina/log;
import ballerina_stdlib/commons;

import ballerina/io;

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
        error err = error("PublishFailed", message = "Some module builds are failing");
        commons:logAndPanicError("Publishing Failed.", err);
    }
}

function checkCurrentPublishWorkflows() {
    io:println("Checking for already running workflows");
    http:Request request = commons:createRequest(accessTokenHeaderValue);
    string apiPath = "/ballerina-standard-library/actions/workflows/publish_snapshots.yml/runs?per_page=1";
    var result = trap httpClient->get(apiPath, request);
    if (result is error) {
        log:printWarn("Error occurred while checking the current workflow status");
    }
    io:println("Response Received");
    http:Response response = <http:Response>result;
    boolean isValid = commons:validateResponse(response);
    if (isValid) {
        map<json> payload = commons:getJsonPayload(response);
        if (!commons:isWorkflowCompleted(payload)) {
            map<json> workflow = commons:getWorkflowJsonObject(payload);
            io:println(workflow.id);
            string cancelPath = "/ballerina-standard-library/actions/runs/" + workflow.id.toString() + "/cancel";
            var cancelResult = trap httpClient->post(cancelPath, request);
            if (cancelResult is error) {
                log:printWarn("Error occurred while cancelling the current workflow status");
            } else {
                io:println(cancelResult.getJsonPayload());
                io:println(cancelResult.statusCode);
                log:printInfo("Cancelled the already running job.");
            }
        } else {
            io:println("No workflows running");
        }
    }
}
