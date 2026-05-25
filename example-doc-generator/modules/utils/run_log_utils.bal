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

const string RUN_LOG_DIR = "./artifacts/run-log";

# Token usage and cost for a single direct LLM API call.
public type LlmCallUsage record {
    # Number of input (prompt) tokens consumed
    int inputTokens;
    # Number of output (completion) tokens generated
    int outputTokens;
    # Estimated cost in USD based on model pricing
    decimal costUsd;
};

# Token usage and cost reported by the Claude Agent SDK for the full agent run.
public type AgentRunCost record {
    # Total USD cost reported by the agent SDK (nil if not available)
    decimal? totalCostUsd;
    # Input tokens consumed across the entire agent run
    int inputTokens;
    # Output tokens generated across the entire agent run
    int outputTokens;
    # Cache read tokens (prompt caching)
    int cacheReadTokens;
    # Cache write tokens (prompt caching)
    int cacheWriteTokens;
    # Number of conversation turns in the agent run (nil if not available)
    int? numTurns;
};

# All data needed to write a pipeline run log entry.
public type RunLogEntry record {
    # The connector name (exact Ballerina Central package name)
    string connectorName;
    # Filename-safe slug derived from the connector name
    string connectorSlug;
    # Optional extra instructions passed to the agent (empty string if none)
    string additionalInstructions;
    # Pipeline start time
    time:Utc startTime;
    # Pipeline end time
    time:Utc endTime;
    # Total pipeline duration in seconds
    decimal durationSecs;
    # Token usage for the execution prompt generation call
    LlmCallUsage promptGenUsage;
    # Token usage for the doc enforcement call
    LlmCallUsage docEnfUsage;
    # Token usage and cost from the agent SDK run (nil if agent did not run)
    AgentRunCost? agentCost;
    # Total cost of direct Anthropic API calls (excludes agent SDK)
    decimal totalDirectCostUsd;
    # Combined cost including both direct API calls and agent SDK
    decimal totalCombinedCostUsd;
    # Path to the saved execution prompt file
    string promptPath;
    # Path to the generated workflow doc (or "(not written)" if absent)
    string workflowDocPath;
};

# Writes a structured, pretty-printed JSON run log to artifacts/run-log/.
# Failures are logged as warnings — this function never propagates errors.
#
# + entry - all pipeline run metrics and artifact paths
public function writeRunLog(RunLogEntry entry) {
    io:Error? keepErr = io:fileWriteString(RUN_LOG_DIR + "/.keep", "");
    if keepErr is io:Error {
        log("\t[WARN] writeRunLog: could not create run-log dir: " + keepErr.message());
        return;
    }

    string timestamp = time:utcToString(entry.startTime);
    string tsSlug = re `[:\.]`.replaceAll(timestamp, "-");
    string logPath = RUN_LOG_DIR + "/" + entry.connectorSlug + "_" + tsSlug + ".json";

    AgentRunCost? ac = entry.agentCost;
    json agentCostJson = ac is AgentRunCost ? {
        "totalCostUsd":     ac.totalCostUsd,
        "inputTokens":      ac.inputTokens,
        "outputTokens":     ac.outputTokens,
        "cacheReadTokens":  ac.cacheReadTokens,
        "cacheWriteTokens": ac.cacheWriteTokens,
        "numTurns":         ac.numTurns
    } : "not available";

    json logJson = {
        "connectorName":            entry.connectorName,
        "connectorSlug":            entry.connectorSlug,
        "additionalInstructions":   entry.additionalInstructions == "" ? () : entry.additionalInstructions,
        "model":            "claude-sonnet-4-6",
        "startTime":        timestamp,
        "endTime":          time:utcToString(entry.endTime),
        "durationSeconds":  entry.durationSecs,
        "llmCalls": {
            "promptGeneration": {
                "inputTokens":  entry.promptGenUsage.inputTokens,
                "outputTokens": entry.promptGenUsage.outputTokens,
                "costUsd":      entry.promptGenUsage.costUsd
            },
            "docEnforcement": {
                "inputTokens":  entry.docEnfUsage.inputTokens,
                "outputTokens": entry.docEnfUsage.outputTokens,
                "costUsd":      entry.docEnfUsage.costUsd
            },
            "agentExecution": agentCostJson
        },
        "totalDirectApiCostUsd": entry.totalDirectCostUsd,
        "totalCombinedCostUsd":  entry.totalCombinedCostUsd,
        "artifacts": {
            "executionPromptPath": entry.promptPath,
            "workflowDocPath":     entry.workflowDocPath
        }
    };

    io:Error? writeErr = io:fileWriteJson(logPath, logJson);
    if writeErr is io:Error {
        log("\t[WARN] writeRunLog: could not write run log: " + writeErr.message());
    } else {
        log("\t[INFO] Run log saved to: " + logPath);
    }
}
