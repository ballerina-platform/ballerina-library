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

const string DEFAULT_MODEL = "opus";
public const string FAST_MODEL = "sonnet";
public const int MAX_TURNS_PHASE1 = 15;   // overview + setup + triggers: read several files + examples
public const int MAX_TURNS_PHASE2A = 8;   // discovery only: glob + skim a few files
public const int MAX_TURNS_PHASE2B = 15;  // per-client: read client + types + examples

# Result of a Claude Code CLI invocation.
public type ClaudeResult record {|
    # The generated text content
    string text;
    # Model used (from JSON output)
    string? model;
    # Duration in milliseconds
    decimal? durationMs;
    # Total input tokens (direct + cache_creation + cache_read)
    int? inputTokens;
    # Total output tokens
    int? outputTokens;
    # Total cost in USD
    decimal? costUsd;
|};

# Check whether the Claude Code CLI is available on PATH.
#
# + return - true if `claude` is found, false otherwise
public function isClaudeInstalled() returns boolean {
    os:Process|error proc = os:exec({value: "sh", arguments: ["-c", "which claude > /dev/null 2>&1"]});
    if proc is error {
        return false;
    }
    int|error exitCode = proc.waitForExit();
    return exitCode is int && exitCode == 0;
}

# Invoke the Claude Code CLI in non-interactive (`-p`) mode with local file
# tools enabled (Read, Glob, Grep). Output is captured as stream-json for
# token count extraction.
#
# + promptText - Full prompt string to send to Claude
# + model      - Model alias: "opus" or "sonnet"
# + maxTurns   - Maximum tool-use turns (use phase-specific constants)
# + return     - ClaudeResult with the generated text, or an error
public function callClaude(string promptText, string model = DEFAULT_MODEL, int maxTurns = MAX_TURNS_PHASE1) returns ClaudeResult|error {
    time:Utc now = time:utcNow();
    string uid = string `${now[0]}_${now[1]}`;
    string promptFile = string `/tmp/conn_doc_prompt_${uid}.md`;
    string outputFile = string `/tmp/conn_doc_output_${uid}.jsonl`;
    string stderrFile = string `/tmp/conn_doc_stderr_${uid}.txt`;

    check io:fileWriteString(promptFile, promptText);

    string shellCmd = string `unset CLAUDECODE && claude -p` +
        string ` --model ${model}` +
        string ` --output-format stream-json` +
        string ` --verbose` +
        string ` --max-turns ${maxTurns}` +
        string ` --allowedTools Read` +
        string ` --allowedTools Glob` +
        string ` --allowedTools Grep` +
        string ` --allowedTools WebFetch` +
        string ` < "${promptFile}"` +
        string ` > "${outputFile}"` +
        string ` 2> "${stderrFile}"`;

    os:Process|error proc = os:exec({value: "sh", arguments: ["-c", shellCmd]});

    if proc is error {
        cleanupFile(promptFile);
        return error("Failed to start Claude Code CLI: " + proc.message());
    }

    int|error exitCode = proc.waitForExit();
    cleanupFile(promptFile);

    if exitCode is error {
        cleanupFile(stderrFile);
        cleanupFile(outputFile);
        return error("Error waiting for Claude: " + exitCode.message());
    }

    if exitCode != 0 {
        string|io:Error stderr = io:fileReadString(stderrFile);
        string stderrMsg = stderr is string ? stderr.substring(0, stderr.length().min(500)) : "";
        cleanupFile(stderrFile);
        cleanupFile(outputFile);
        return error(string `Claude Code CLI exited with code ${exitCode}. stderr: ${stderrMsg}`);
    }

    cleanupFile(stderrFile);

    string|io:Error rawOutput = io:fileReadString(outputFile);
    cleanupFile(outputFile);

    if rawOutput is io:Error {
        return error("Failed to read Claude output file: " + rawOutput.message());
    }

    return parseStreamJson(rawOutput.trim());
}

// Convert a JSON number to int, handling both int and decimal representations.
function jsonToInt(json val) returns int? {
    if val is int {
        return val;
    }
    if val is decimal {
        return <int>val;
    }
    if val is float {
        return <int>val;
    }
    return ();
}

// Silently delete a temp file, ignoring any error.
function cleanupFile(string path) {
    file:Error? removeResult = file:remove(path);
    if removeResult is file:Error {
        // Silently ignore cleanup errors
    }
}

// Parse NDJSON (stream-json) output from Claude.
// model      — from the "system" init event (accurate per-call model name)
// stats      — from the final "result" event (cumulative totals)
// inputTokens — sum of input_tokens + cache_creation_input_tokens + cache_read_input_tokens
function parseStreamJson(string output) returns ClaudeResult|error {
    if output.length() == 0 {
        return error("Claude returned empty output");
    }

    string? model = ();
    string? resultText = ();
    decimal? durationMs = ();
    decimal? costUsd = ();
    int? inputTokens = ();
    int? outputTokens = ();

    string[] lines = re `\n`.split(output);
    foreach string line in lines {
        string trimmed = line.trim();
        if trimmed.length() == 0 {
            continue;
        }
        json|error parsed = trimmed.fromJsonString();
        if parsed is error || !(parsed is map<json>) {
            continue;
        }
        map<json> ev = <map<json>>parsed;
        json evType = ev["type"];

        if evType == "system" && ev["subtype"] == "init" {
            // Model name is accurate here (e.g. "claude-sonnet-4-5-20251001")
            model = ev["model"] is string ? <string>ev["model"] : ();
        } else if evType == "result" {
            json rf = ev["result"];
            if !(rf is string) {
                return error("Claude result event missing 'result' field");
            }
            resultText = rf;

            json dur = ev["duration_ms"];
            durationMs = dur is decimal ? dur : (dur is int ? <decimal>dur : ());
            json cost = ev["total_cost_usd"];
            costUsd = cost is decimal ? cost : (cost is float ? <decimal>cost : ());

            json usageField = ev["usage"];
            if usageField is map<json> {
                int direct = jsonToInt(usageField["input_tokens"]) ?: 0;
                int cacheCreate = jsonToInt(usageField["cache_creation_input_tokens"]) ?: 0;
                int cacheRead = jsonToInt(usageField["cache_read_input_tokens"]) ?: 0;
                int totalIn = direct + cacheCreate + cacheRead;
                inputTokens = totalIn > 0 ? totalIn : ();
                outputTokens = jsonToInt(usageField["output_tokens"]);
            }
        }
    }

    if resultText is () {
        return error("No 'result' event found in Claude stream-json output");
    }
    return {text: resultText, model, durationMs, inputTokens, outputTokens, costUsd};
}
