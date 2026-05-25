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

import ballerina/http;
import ballerina/io;
import ballerina/lang.regexp;

const string CENTRAL_API_BASE = "https://api.central.ballerina.io";

// Open record — only readme is needed; extra fields are silently ignored
type CentralPackageMetadata record {
    string readme?;
};

// Finds the Examples section (any heading level, case-insensitive) in a readme,
// and returns its body up to the next same-or-higher-level heading, or nil if not found.
isolated function extractExamplesSection(string readme) returns string? {
    string[] lines = re `\r?\n`.split(readme);

    int startIdx = -1;
    int headingLevel = 0;
    foreach int i in 0 ..< lines.length() {
        // Match case-insensitively by lowercasing the trimmed line
        regexp:Groups? hg = re `^(#{1,6})\s+examples?\s*$`.findGroups(lines[i].trim().toLowerAscii());
        if hg is regexp:Groups {
            regexp:Span? lvlSpan = hg[1];
            if lvlSpan is regexp:Span {
                startIdx = i;
                headingLevel = lvlSpan.substring().length();
                break;
            }
        }
    }
    if startIdx == -1 {
        return ();
    }

    string[] bodyLines = [];
    foreach int i in (startIdx + 1) ..< lines.length() {
        regexp:Groups? nextHg = re `^(#{1,6})\s`.findGroups(lines[i]);
        if nextHg is regexp:Groups {
            regexp:Span? lvlSpan = nextHg[1];
            if lvlSpan is regexp:Span && lvlSpan.substring().length() <= headingLevel {
                break;
            }
        }
        bodyLines.push(lines[i]);
    }

    string body = string:'join("\n", ...bodyLines).trim();
    return body.length() > 0 ? body : ();
}

# Fetches the Examples section from the connector's Ballerina Central readme and
# appends it to the workflow doc under '## More code examples'.
# All failures are logged as warnings — this function never propagates errors.
#
# + docPath - path to the workflow doc markdown file to update
public function appendExamplesSection(string docPath) {
    string|io:Error contentResult = io:fileReadString(docPath);
    if contentResult is io:Error {
        log("\t[WARN] appendExamplesSection: could not read doc file — skipping.");
        return;
    }
    string content = contentResult;

    if content.includes("## More code examples") {
        log("\t[INFO] appendExamplesSection: 'More code examples' already present — skipping.");
        return;
    }

    // connector-name.txt written by pipeline at startup is the authoritative source
    string|io:Error savedName = io:fileReadString("./artifacts/run-log/connector-name.txt");
    if savedName is io:Error || savedName.trim().length() == 0 {
        log("\t[WARN] appendExamplesSection: connector-name.txt missing or empty — skipping.");
        return;
    }
    string connectorName = savedName.trim().toLowerAscii();
    log("\t[INFO] appendExamplesSection: connector name from file: '" + connectorName + "'");

    log("\t[INFO] appendExamplesSection: fetching metadata for '" + connectorName + "' from Ballerina Central...");

    http:Client|error clientResult = new (CENTRAL_API_BASE, timeout = 15);
    if clientResult is error {
        log("\t[WARN] appendExamplesSection: could not create HTTP client — skipping.");
        return;
    }
    http:Client centralClient = clientResult;

    string apiPath = "/2.0/registry/packages/ballerinax/" + connectorName + "/latest";
    http:Response|error resp = centralClient->get(apiPath);
    if resp is error {
        log("\t[INFO] appendExamplesSection: HTTP request failed for '" + connectorName + "' — skipping.");
        return;
    }
    if resp.statusCode != 200 {
        log("\t[INFO] appendExamplesSection: package 'ballerinax/" + connectorName + "' not found (HTTP " + resp.statusCode.toString() + ") — skipping.");
        return;
    }

    json|error respJson = resp.getJsonPayload();
    if respJson is error {
        log("\t[WARN] appendExamplesSection: could not parse JSON response — skipping.");
        return;
    }
    CentralPackageMetadata|error metadata = respJson.cloneWithType(CentralPackageMetadata);
    if metadata is error {
        log("\t[WARN] appendExamplesSection: unexpected response shape — skipping.");
        return;
    }

    string? readmeField = metadata.readme;
    if readmeField is () || readmeField.trim().length() == 0 {
        log("\t[INFO] appendExamplesSection: readme field is empty in package metadata — skipping.");
        return;
    }

    string? examplesBody = extractExamplesSection(readmeField);
    if examplesBody is () {
        log("\t[INFO] appendExamplesSection: no Examples section found for '" + connectorName + "' — skipping.");
        return;
    }

    log("\t[INFO] appendExamplesSection: found Examples section — appending as '## More code examples'.");
    string updated = content.trim() + "\n\n## More code examples\n\n" + examplesBody + "\n";
    io:Error? writeErr = io:fileWriteString(docPath, updated);
    if writeErr is io:Error {
        log("\t[WARN] appendExamplesSection: failed to write updated doc — skipping.");
        return;
    }
    log("\t[INFO] appendExamplesSection: done.");
}
