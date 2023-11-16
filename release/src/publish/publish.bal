import ballerina/log;
import ballerina_stdlib/commons;

public function main() {
    json[] modulesJson = commons:getModuleJsonArray();
    commons:Module[] modules = commons:getModuleArray(modulesJson);
    commons:addDependentModules(modules);

    commons:WorkflowStatus workflowStatus = {
        isFailure: false,
        failedModules: []
    };

    log:printInfo("Publishing all the Ballerina library snapshots");
    commons:checkCurrentPublishWorkflows();
    commons:handlePublish(modules, workflowStatus);

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
