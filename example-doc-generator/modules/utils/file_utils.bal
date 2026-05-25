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

import ballerina/io;
import ballerina/time;

public const OUTPUT_DIR = "./artifacts/execution-prompt";

# Saves the execution prompt content to a Markdown file in the output directory.
# The filename includes the goal slug and a timestamp.
#
# + content  - the full execution prompt content
# + goalSlug - a short hyphenated slug derived from the goal
# + return   - the absolute file path on success, or an error
public function saveExecutionPrompt(string content, string goalSlug) returns string|error {
    // Ensure output directory exists
    check io:fileWriteString(OUTPUT_DIR + "/.keep", "");

    // Generate filename with short goal + timestamp
    time:Utc now = time:utcNow();
    time:Civil civil = time:utcToCivil(now);
    string timestamp = string `${civil.year}-${civil.month < 10 ? "0" : ""}${civil.month}-${civil.day < 10 ? "0" : ""}${civil.day}_${civil.hour < 10 ? "0" : ""}${civil.hour}-${civil.minute < 10 ? "0" : ""}${civil.minute}-${civil.second < 10d ? "0" : ""}${civil.second.toString()}`;
    string filename = string `${goalSlug}_execution_prompt_${timestamp}.md`;
    string filePath = OUTPUT_DIR + "/" + filename;

    // Write the execution prompt to file
    check io:fileWriteString(filePath, content);
    return filePath;
}

# Injects the "## Try it yourself" section (description, Deploy to Devant button,
# and GitHub source link) into the workflow doc. The project name is read from
# artifacts/run-log/created-project.txt.
# Failures are logged as warnings; this function never blocks the pipeline.
#
# + docPath - absolute path to the workflow doc .md file to update
public function injectTryItYourselfSection(string docPath) {
    string projectPathFile = "artifacts/run-log/created-project.txt";
    string sectionHeading = "## Try it yourself";

    // Read project name from run-log
    string|error rawResult = io:fileReadString(projectPathFile);
    if rawResult is error {
        log("\t[WARN] created-project.txt not found — skipping 'Try it yourself' section injection");
        return;
    }
    string raw = rawResult.trim();
    if raw == "" {
        log("\t[WARN] created-project.txt is empty — skipping 'Try it yourself' section injection");
        return;
    }

    // Extract last path segment as project name
    string[] parts = re`[/\\]`.split(raw);
    string projectName = parts[parts.length() - 1];
    string description = "Try this sample in WSO2 Integration Platform.";
    string buttonLine = string `[![Deploy to Devant](https://openindevant.choreoapps.dev/images/DeployDevant-White.svg)](https://console.devant.dev/new?gh=wso2/integration-samples/tree/main/connectors/${projectName})`;
    string githubLink = string `[View source on GitHub](https://github.com/wso2/integration-samples/tree/main/connectors/${projectName})`;

    // Read doc content
    string|error contentResult = io:fileReadString(docPath);
    if contentResult is error {
        log("\t[WARN] Failed to read doc file — skipping 'Try it yourself' section injection");
        return;
    }
    string content = contentResult;

    // Idempotency check
    if content.includes(sectionHeading) {
        log("\t[INFO] '" + sectionHeading + "' already present — skipping 'Try it yourself' section injection");
        return;
    }

    // Build section block and append
    string sectionBlock = sectionHeading + "\n\n" + description + "\n\n" + buttonLine + "\n\n" + githubLink;
    string updated = content.trim() + "\n\n" + sectionBlock + "\n";

    // Write updated content
    error? writeErr = io:fileWriteString(docPath, updated);
    if writeErr is error {
        log("\t[WARN] Failed to write doc file — skipping 'Try it yourself' section injection");
        return;
    }

    log("\t[INFO] Injected 'Try it yourself' section for project '" + projectName + "' into " + docPath);
}
