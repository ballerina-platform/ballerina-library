// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/file;
import ballerina/io;
import ballerina/os;
import ballerina/time;

const string DEFAULT_CONFIG = "batch_items.json";
const string ARTIFACTS_DIR = "./artifacts";
const string ARCHIVE_DIR = "./artifacts_archive";
const int DEFAULT_TIMEOUT_SECONDS = 7200;

type BatchConfig record {|
    BatchItem[] items;
|};

type BatchItem record {|
    string name?;
    string 'type?;
    string instructions?;
|};

type BatchResult record {|
    string name;
    string 'type;
    string slug;
    string status;
    decimal duration;
    decimal? cost;
    string? projectPath;
    string archiveDir;
|};

type RunCost record {|
    decimal? totalCombinedCostUsd?;
    decimal? durationSeconds?;
|};

public function runBatch(string arg1 = "", string arg2 = "", string arg3 = "") returns error? {
    string configPath = DEFAULT_CONFIG;
    int timeoutSeconds = DEFAULT_TIMEOUT_SECONDS;

    foreach string arg in [arg1, arg2, arg3] {
        string trimmed = arg.trim();
        if trimmed == "" {
            continue;
        }
        if trimmed.startsWith("config=") {
            configPath = trimmed.substring(7);
        } else if trimmed.startsWith("timeout=") {
            int|error parsedTimeout = int:fromString(trimmed.substring(8));
            if parsedTimeout is error || parsedTimeout <= 0 {
                return error("Invalid batch timeout. Use timeout=<positive seconds>.");
            }
            timeoutSeconds = parsedTimeout;
        } else {
            return error("Unsupported batch option: " + trimmed +
                ". Supported options: config=<path>, timeout=<seconds>.");
        }
    }

    string|io:Error configContent = io:fileReadString(configPath);
    if configContent is io:Error {
        return error("Config not found: " + configPath +
            ". Copy batch_items.json.example to " + configPath + " and fill it in.");
    }

    json|error configJson = configContent.fromJsonString();
    if configJson is error {
        return error("Invalid JSON in " + configPath + ": " + configJson.message());
    }
    BatchConfig|error config = configJson.cloneWithType(BatchConfig);
    if config is error {
        return error("Batch config must contain an items array.");
    }
    if config.items.length() == 0 {
        return error("Batch items list is empty.");
    }

    check validateItems(config.items);
    check prepareBatchArtifacts();
    BatchResult[] results = [];

    io:println("======================================================================");
    io:println("BATCH RUN — " + config.items.length().toString() + " items queued");
    io:println("Config: " + configPath);
    io:println("Timeout: " + timeoutSeconds.toString() + "s per item");
    io:println("======================================================================");

    foreach int i in 0 ..< config.items.length() {
        BatchItem item = config.items[i];
        string kind = itemKind(item);
        string name = itemName(item);
        string slug = artifactSlug(name, kind);
        string instructions = item.instructions ?: "";

        io:println("\n======================================================================");
        io:println("[" + (i + 1).toString() + "/" + config.items.length().toString() +
            "] Processing " + kind + ": " + name);
        if instructions != "" {
            io:println("         Instructions: " + instructions);
        }
        io:println("======================================================================");

        time:Utc itemStart = time:utcNow();
        boolean success = runPipeline(item, timeoutSeconds);
        time:Utc itemEnd = time:utcNow();
        decimal duration = time:utcDiffSeconds(itemEnd, itemStart);

        RunCost? costData = parseRunCost(slug, kind);
        string? projectPath = readCreatedProjectPath();
        string status = success ? "OK" : "FAILED";
        string archivePath = check archiveArtifacts(slug, status);

        BatchResult result = {
            name: name,
            'type: kind,
            slug: slug,
            status: status,
            duration: duration,
            cost: costData is RunCost ? costData?.totalCombinedCostUsd : (),
            projectPath: projectPath,
            archiveDir: archivePath
        };
        results.push(result);

        if success {
            io:println("\n[OK] " + name + " completed in " + duration.toString() + "s");
        } else {
            io:println("\n[FAILED] " + name + " failed after " + duration.toString() + "s");
        }
    }

    string summary = check buildSummary(results);
    io:println("\n\n" + summary);
    check file:createDir(ARCHIVE_DIR, file:RECURSIVE);
    string summaryPath = ARCHIVE_DIR + "/batch_summary_" + timestampSlug(time:utcNow()) + ".txt";
    check io:fileWriteString(summaryPath, summary);
    io:println("\nSummary saved to: " + summaryPath);

    if hasFailed(results) {
        return error("One or more batch items failed.");
    }
}

function prepareBatchArtifacts() returns error? {
    boolean|file:Error exists = file:test(ARTIFACTS_DIR, file:EXISTS);
    if exists is file:Error {
        return error("Could not check artifacts directory: " + exists.message());
    }
    if exists {
        return error("Existing artifacts/ directory found. Move or delete it before running batch mode.");
    }
}

function validateItems(BatchItem[] items) returns error? {
    foreach int i in 0 ..< items.length() {
        BatchItem item = items[i];
        if itemName(item) == "" {
            return error("items[" + i.toString() + "] must include a non-empty name.");
        }
        string? rawKind = item.'type;
        if rawKind is () || rawKind.trim() == "" {
            return error("items[" + i.toString() + "] must include type: connector or trigger.");
        }
        string kind = itemKind(item);
        if kind != "connector" && kind != "trigger" {
            return error("items[" + i.toString() + "] has unsupported type '" + kind +
                "'. Use 'connector' or 'trigger'.");
        }
    }
}

function itemKind(BatchItem item) returns string {
    string? kind = item.'type;
    return kind is string ? kind.trim().toLowerAscii() : "";
}

function itemName(BatchItem item) returns string {
    string? name = item.name;
    return name is string ? name.trim() : "";
}

function slugify(string name) returns string {
    string slug = name.trim().toLowerAscii();
    slug = re `\s+`.replaceAll(slug, "-");
    slug = re `[^a-z0-9\-\.]`.replaceAll(slug, "");
    return slug;
}

function artifactSlug(string name, string kind) returns string {
    string slug = slugify(name);
    if kind == "trigger" {
        return re `\.`.replaceAll(slug, "_");
    }
    return slug;
}

function runPipeline(BatchItem item, int timeoutSeconds) returns boolean {
    string kind = itemKind(item);
    string[] pipelineArgs = ["java", "-jar", "target/bin/example_doc_generator.jar"];
    if kind == "trigger" {
        pipelineArgs.push("trigger");
    }
    pipelineArgs.push(itemName(item));
    string? instructions = item.instructions;
    if instructions is string && instructions.trim() != "" {
        pipelineArgs.push(instructions);
    }

    io:println("[CMD] " + joinStrings(pipelineArgs, " "));

    string timeoutScript = "if [ -w /dev/tty ]; then\n" +
        "  exec >/dev/tty 2>&1\n" +
        "fi\n" +
        "timeout=\"$1\"\n" +
        "shift\n" +
        "kill_tree() {\n" +
        "  signal=\"$1\"\n" +
        "  parent=\"$2\"\n" +
        "  children=$(pgrep -P \"$parent\" 2>/dev/null || true)\n" +
        "  for child in $children; do\n" +
        "    kill_tree \"$signal\" \"$child\"\n" +
        "  done\n" +
        "  kill \"$signal\" \"$parent\" 2>/dev/null\n" +
        "}\n" +
        "cleanup_child() {\n" +
        "  if [ -z \"${pid:-}\" ]; then\n" +
        "    return\n" +
        "  fi\n" +
        "  if [ -n \"${group_pid:-}\" ]; then\n" +
        "    kill -TERM \"-$group_pid\" 2>/dev/null\n" +
        "    sleep 2\n" +
        "    kill -KILL \"-$group_pid\" 2>/dev/null\n" +
        "  else\n" +
        "    kill_tree -TERM \"$pid\"\n" +
        "    sleep 2\n" +
        "    kill_tree -KILL \"$pid\"\n" +
        "  fi\n" +
        "  wait \"$pid\" 2>/dev/null\n" +
        "}\n" +
        "handle_interrupt() {\n" +
        "  echo \"[INFO] Batch item interrupted. Stopping active pipeline...\" >&2\n" +
        "  cleanup_child\n" +
        "  exit 130\n" +
        "}\n" +
        "if command -v setsid >/dev/null 2>&1; then\n" +
        "  setsid \"$@\" &\n" +
        "  group_pid=$!\n" +
        "else\n" +
        "  \"$@\" &\n" +
        "  group_pid=\"\"\n" +
        "fi\n" +
        "pid=$!\n" +
        "trap handle_interrupt INT TERM HUP\n" +
        "elapsed=0\n" +
        "while kill -0 \"$pid\" 2>/dev/null; do\n" +
        "  if [ \"$elapsed\" -ge \"$timeout\" ]; then\n" +
        "    echo \"[ERROR] Pipeline timed out after ${timeout}s\" >&2\n" +
        "    cleanup_child\n" +
        "    exit 124\n" +
        "  fi\n" +
        "  sleep 1\n" +
        "  elapsed=$((elapsed + 1))\n" +
        "done\n" +
        "wait \"$pid\"";

    string[] args = ["-c", timeoutScript, "batch-runner", timeoutSeconds.toString()];
    foreach string pipelineArg in pipelineArgs {
        args.push(pipelineArg);
    }

    os:Process|error proc = os:exec({
        value: "sh",
        arguments: args
    });
    if proc is error {
        io:println("[ERROR] Failed to start pipeline: " + proc.message());
        return false;
    }
    int|error exitCode = proc.waitForExit();
    if exitCode is error {
        io:println("[ERROR] Pipeline process failed: " + exitCode.message());
        return false;
    }
    return exitCode == 0;
}

function parseRunCost(string slug, string kind) returns RunCost? {
    string runLogDir = ARTIFACTS_DIR + "/run-log";
    file:MetaData[]|file:Error entries = file:readDir(runLogDir);
    if entries is file:Error {
        return ();
    }

    string goalSlug = kind == "trigger" ? slug + "-trigger-example" : slug + "-connector-example";
    file:MetaData? latestEntry = ();
    foreach file:MetaData entry in entries {
        if entry.absPath.includes(goalSlug + "_") && entry.absPath.endsWith(".json") {
            if latestEntry is () || time:utcDiffSeconds(entry.modifiedTime, latestEntry.modifiedTime) > 0d {
                latestEntry = entry;
            }
        }
    }
    if latestEntry is () {
        return ();
    }

    string|io:Error content = io:fileReadString((<file:MetaData>latestEntry).absPath);
    if content is io:Error {
        return ();
    }
    json|error runJson = content.fromJsonString();
    if runJson is error {
        return ();
    }
    RunCost|error cost = runJson.cloneWithType(RunCost);
    if cost is error {
        return ();
    }
    return cost;
}

function readCreatedProjectPath() returns string? {
    string|io:Error path = io:fileReadString(ARTIFACTS_DIR + "/run-log/created-project.txt");
    if path is io:Error {
        return ();
    }
    string trimmed = path.trim();
    return trimmed == "" ? () : trimmed;
}

function archiveArtifacts(string slug, string status) returns string|error {
    boolean|file:Error artifactsExists = file:test(ARTIFACTS_DIR, file:EXISTS);
    if artifactsExists is file:Error || !artifactsExists {
        return check createNoArtifactsArchive(slug);
    }

    string suffix = status == "OK" ? "" : "_" + status;
    string baseDest = ARCHIVE_DIR + "/" + slug + suffix;
    string dest = baseDest;
    int attempt = 0;
    while check archivePathExists(dest) {
        attempt += 1;
        dest = baseDest + "_" + timestampSlug(time:utcNow()) + "_" + attempt.toString();
    }

    check file:createDir(ARCHIVE_DIR, file:RECURSIVE);
    check file:rename(ARTIFACTS_DIR, dest);
    io:println("[INFO] Archived artifacts to " + dest);
    return dest;
}

function createNoArtifactsArchive(string slug) returns string|error {
    string baseDest = ARCHIVE_DIR + "/" + slug + "_NO_ARTIFACTS";
    string dest = baseDest;
    int attempt = 0;
    while check archivePathExists(dest) {
        attempt += 1;
        dest = baseDest + "_" + timestampSlug(time:utcNow()) + "_" + attempt.toString();
    }

    check file:createDir(dest, file:RECURSIVE);
    check io:fileWriteString(dest + "/README.txt", "No artifacts were produced for this batch item.\n");
    io:println("[INFO] No artifacts produced. Wrote placeholder archive to " + dest);
    return dest;
}

function archivePathExists(string path) returns boolean|error {
    boolean|file:Error exists = file:test(path, file:EXISTS);
    if exists is file:Error {
        return error("Could not check archive path " + path + ": " + exists.message());
    }
    return exists;
}

function buildSummary(BatchResult[] results) returns string|error {
    string summary = "======================================================================\n" +
        "BATCH RUN SUMMARY\n" +
        "======================================================================\n" +
        " #   Type      Name                     Status     Duration     Cost       Archive\n" +
        " --- --------- ------------------------ ---------- ------------ ---------- ----------------\n";

    int okCount = 0;
    int failCount = 0;
    decimal totalCost = 0.0d;
    decimal totalDuration = 0.0d;

    foreach int i in 0 ..< results.length() {
        BatchResult result = results[i];
        string costText = "n/a";
        decimal? cost = result.cost;
        if cost is decimal {
            costText = "$" + cost.toString();
            totalCost += cost;
        }
        totalDuration += result.duration;
        if result.status == "OK" {
            okCount += 1;
        } else {
            failCount += 1;
        }
        summary += " " + (i + 1).toString() + "   " + result.'type + " " +
            result.name + " " + result.status + " " + result.duration.toString() +
            "s " + costText + " " + result.archiveDir + "\n";
    }

    summary += "----------------------------------------------------------------------\n" +
        "Total: " + results.length().toString() + " items | " + okCount.toString() +
        " OK | " + failCount.toString() + " failed\n" +
        "Total cost: $" + totalCost.toString() + " | Total time: " +
        totalDuration.toString() + "s\n" +
        "======================================================================\n";

    if results.length() > 0 {
        summary += "\nFOLLOW-UP INSTRUCTIONS\n" +
            "----------------------------------------------------------------------\n";
        foreach BatchResult result in results {
            if result.status == "OK" {
                summary += "# " + result.name + "\n" +
                    "Review generated artifacts in " + result.archiveDir + "\n";
                if result.'type == "connector" {
                    summary += "Publish connector docs/samples manually with the existing publish targets if needed.\n";
                } else {
                    summary += "Trigger publish helpers are not automated yet; publish trigger artifacts manually.\n";
                }
                summary += "\n";
            }
        }
    }
    return summary;
}

function hasFailed(BatchResult[] results) returns boolean {
    foreach BatchResult result in results {
        if result.status != "OK" {
            return true;
        }
    }
    return false;
}

function timestampSlug(time:Utc value) returns string {
    return re `[:\.]`.replaceAll(time:utcToString(value), "-");
}

function joinStrings(string[] values, string separator) returns string {
    string result = "";
    foreach int i in 0 ..< values.length() {
        if i > 0 {
            result += separator;
        }
        result += values[i];
    }
    return result;
}
