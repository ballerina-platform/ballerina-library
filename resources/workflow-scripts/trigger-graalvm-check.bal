import ballerina/http;
import ballerina/os;
import ballerina/lang.runtime;
import ballerina/log;
import ballerina/io;

string GITHUB_TOKEN = os:getEnv("GITHUB_TOKEN");
string LANG_TAG = os:getEnv("LANG_TAG");
string LANG_VERSION = os:getEnv("LANG_VERSION");
string NATIVE_IMAGE_OPTIONS = os:getEnv("NATIVE_IMAGE_OPTIONS");

string ORG_NAME = "ballerina-platform";
string WORKFLOW_FILE_NAME = "build-with-bal-test-graalvm.yml";
string STDLIB_MODULES = "./release/resources/stdlib_modules.json";

map<string> headers = {
    "Authorization": "token " + GITHUB_TOKEN,
    "Accept": "application/vnd.github.v3+json"
};

type GraalVMCheckInputs record {|
    string lang_tag;
    string lang_version;
    string native_image_options;
|};

final http:Client gitHubClient = check new ("https://api.github.com/repos");

function triggerWorkflow(string module_name, string branch, *GraalVMCheckInputs inputs) returns error? {
    http:Response res = check gitHubClient->/[ORG_NAME]/[module_name]/actions/workflows/[WORKFLOW_FILE_NAME]/dispatches.post(
        {
            "ref": branch,
            "inputs": inputs
        },
        headers
    );

    if res.statusCode != http:STATUS_NO_CONTENT {
        return error("workflow trigger failed with status code: " + res.statusCode.toString());
    }
}

type GetWorkflowRunResponse record {
    int total_count;
    record {int id;}[] workflow_runs;
};

function getWorkflow(string module_name) returns [int, string]|error {
    GetWorkflowRunResponse res = check gitHubClient->/[ORG_NAME]/[module_name]/actions/runs(headers);
    if res.total_count > 0 {
        return [
            res.workflow_runs[0].id,
            string `https://github.com/${ORG_NAME}/${module_name}/actions/runs/${res.workflow_runs[0].id}`
        ];
    }
    return error("failed to get the workflow ID");
}

type GetWorkflowRunStatusResponse record {
    STATUS status;
    CONCLUSION? conclusion;
};

function getWorkflowRunStatus(string module_name, int workflow_id) returns [STATUS, CONCLUSION?]|error {
    GetWorkflowRunStatusResponse res = check gitHubClient->/[ORG_NAME]/[module_name]/actions/runs/[workflow_id](headers);
    return [res.status, res.conclusion];
}

type Module record {
    string name;
    int level;
    string default_branch;
};

type Data record {|
    Module[] modules;
|};

enum STATUS {
    PENDING = "pending",
    IN_PROGRESS = "in_progress",
    COMPLETED = "completed",
    QUEUED = "queued"
};

enum CONCLUSION {
    SUCCESS = "success",
    FAILURE = "failure",
    NEUTRAL = "neutral",
    CANCELLED = "cancelled",
    TIMED_OUT = "timed_out",
    ACTION_REQUIRED = "action_required",
    NOT_APPLICABLE = "N/A"
}

type ModuleStatus record {|
    STATUS status;
    CONCLUSION conclusion = NOT_APPLICABLE;
    string link;
    int workflow_id;
|};

type LevelStatus record {|
    STATUS status;
    map<ModuleStatus>[] modules;
|};

public function main() returns error? {
    json jsonData = check io:fileReadJson(STDLIB_MODULES);
    Data data = check jsonData.cloneWithType();

    map<LevelStatus> result = triggerGraalVMChecks(data);
    checkStatus(result);
    check createReport(result);
}

function triggerGraalVMChecks(Data data) returns map<LevelStatus> {
    map<LevelStatus> result = {};

    foreach Module module in data.modules {
        do {
            check triggerWorkflow(module.name, module.default_branch,
                lang_tag = LANG_TAG, lang_version = LANG_VERSION, native_image_options = NATIVE_IMAGE_OPTIONS);
            runtime:sleep(10);
            [int, string] [id, link] = check getWorkflow(module.name);
            log:printInfo("Successfully triggered the GraalVM check", module = module.name, link = link);

            ModuleStatus moduleStatus = {
                status: IN_PROGRESS,
                link: link,
                workflow_id: id
            };

            if !result.hasKey(module.level.toString()) {
                LevelStatus levelStatus = {
                    status: IN_PROGRESS,
                    modules: [{[module.name] : moduleStatus}]
                };
                result[module.level.toString()] = levelStatus;
            } else {
                LevelStatus levelStatus = result.get(module.level.toString());
                levelStatus.modules.push({[module.name] : moduleStatus});
            }
        } on fail error err {
            log:printError("Failed to trigger the GraalVM check", module = module.name, 'error = err);
        }
    }

    return result;
}

function checkStatus(map<LevelStatus> result) {
    while !isComplete(result) {
        runtime:sleep(300);
        foreach [string, LevelStatus] [level, levelStatus] in result.entries() {
            if levelStatus.status == COMPLETED {
                continue;
            }
            if isLevelComplete(levelStatus) {
                log:printInfo("Level " + level + " is completed");
                levelStatus.status = COMPLETED;
                continue;
            }
            foreach map<ModuleStatus> moduleStatusMap in levelStatus.modules {
                foreach [string, ModuleStatus] [module_name, moduleStatus] in moduleStatusMap.entries() {
                    if moduleStatus.status != COMPLETED {
                        checkModuleStatus(moduleStatus, module_name);
                    }
                }
            }
        }
    }
}

function checkModuleStatus(ModuleStatus moduleStatus, string module_name) {
    do {
        [STATUS, CONCLUSION?] [status, conclusion] = check getWorkflowRunStatus(module_name, moduleStatus.workflow_id);
        if status == COMPLETED {
            moduleStatus.status = COMPLETED;
            match conclusion {
                SUCCESS => {
                    moduleStatus.conclusion = SUCCESS;
                    log:printInfo("GraalVM check passed", module = module_name, link = moduleStatus.link);
                }
                _ => {
                    if conclusion !is () {
                        moduleStatus.conclusion = conclusion;
                    }
                    log:printError("GraalVM check failed", module = module_name, status = conclusion ?: status, link = moduleStatus.link);
                }
            }
        } else {
            log:printInfo("GraalVM check is in progress", module = module_name, link = moduleStatus.link);
        }
    } on fail error err {
        log:printError("Failed to get the GraalVM check status", module = module_name, 'error = err);
    }
}

function isComplete(map<LevelStatus> result) returns boolean {
    foreach LevelStatus levelStatus in result {
        if levelStatus.status != COMPLETED {
            return false;
        }
    }
    return true;
}

function isLevelComplete(LevelStatus levelStatus) returns boolean {
    foreach map<ModuleStatus> moduleStatusMap in levelStatus.modules {
        foreach [string, ModuleStatus] [_, moduleStatus] in moduleStatusMap.entries() {
            if moduleStatus.status != COMPLETED {
                return false;
            }
        }
    }
    return true;
}

type ReportRecord record {|
    string level;
    string module;
    string status;
|};

function createReport(map<LevelStatus> result) returns error? {
    table<ReportRecord> resultTable = table [];
    foreach [string, LevelStatus] [level, levelStatus] in result.entries() {
        foreach map<ModuleStatus> moduleStatusMap in levelStatus.modules {
            foreach [string, ModuleStatus] [module, moduleStatus] in moduleStatusMap.entries() {
                ReportRecord rec = {
                    level: "Level " + level,
                    module: module,
                    status: string `[${moduleStatus.conclusion}](${moduleStatus.link})`
                };
                resultTable.add(rec);
            }
        }
    }

    string title = "GraalVM Check Report";
    string tableTitle = "| Level | Module | Status |";
    string tableTitleSeparator = "| ----- | ------ | ---- |";
    string[] rows = from ReportRecord reportRecord in resultTable
        select
        "| " + string:'join(" | ", reportRecord.level, reportRecord.module, reportRecord.status) + " |";
    string[] summary = ["## " + title + " :rocket:", tableTitle, tableTitleSeparator, ...rows];
    string summaryString = string:'join("\n", ...summary);
    check io:fileWriteString("graalvm_check_summary.md", summaryString);
}
