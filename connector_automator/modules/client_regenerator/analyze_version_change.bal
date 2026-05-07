// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/ai;
import ballerina/io;
import ballerina/lang.value;
import ballerina/os;
import ballerina/regex;
import ballerina/lang.runtime;
import ballerinax/ai.anthropic;

const string SEPARATOR = "============================================================";
const string ANTHROPIC_API_KEY_ENV = "ANTHROPIC_API_KEY";

const int MAX_RETRIES = 4;
const decimal RETRY_INITIAL_DELAY = 10.0; // seconds; doubles on each attempt

// Wraps model->chat with exponential-backoff retries for transient API errors
// (rate limits, 529 overload) which the anthropic library surfaces as errors
// with message "Unexpected response format from Anthropic API".
function chatWithRetry(ai:ModelProvider model, ai:ChatMessage[] messages) returns ai:ChatAssistantMessage|error {
    decimal delay = RETRY_INITIAL_DELAY;
    error? lastErr = ();
    foreach int attempt in 1 ..< MAX_RETRIES + 1 {
        ai:ChatAssistantMessage|error response = model->chat(messages);
        if response is ai:ChatAssistantMessage {
            return response;
        }
        lastErr = response;
        if attempt < MAX_RETRIES {
            io:println(string `API call failed (attempt ${attempt}/${MAX_RETRIES}): ${response.message()}. Retrying in ${delay}s...`);
            error? sleepErr = runtime:sleep(delay);
            if sleepErr is error {
                io:println(string `Sleep interrupted: ${sleepErr.message()}`);
            }
            delay *= 2.0d;
        }
    }
    return lastErr ?: error("Max retries exceeded");
}

// Diffs larger than this threshold are sent in multiple turns to stay within
// the OS argument-length limit and the model's single-message context budget.
const int CHUNK_SIZE = 50000;
// Maximum chunks sent in a multi-turn conversation. Beyond this the accumulated
// context overflows the model's window and causes mid-session API errors.
// 10 chunks = 500 KB — enough to capture all API-surface changes in practice.
const int MAX_CHUNKS = 10;

type AnalysisResult record {
    string changeType;
    string[] breakingChanges;
    string[] newFeatures;
    string[] bugFixes;
    string summary;
    string confidence;
};

const string VERSION_RULES = string `RULES FOR VERSION CLASSIFICATION:
- MAJOR: Breaking changes (removed/renamed methods, removed/renamed types, changed method signatures, changed field types, removed fields)
- MINOR: Backward-compatible additions (new methods, new types, new optional fields, new fields with default values)
- PATCH: Documentation changes, internal refactoring, bug fixes with no API surface changes`;

const string JSON_SCHEMA = string `{
  "changeType": "MAJOR|MINOR|PATCH",
  "breakingChanges": ["list specific breaking changes"],
  "newFeatures": ["list new features/additions"],
  "bugFixes": ["list bug fixes or improvements"],
  "summary": "concise summary of changes",
  "confidence": "HIGH|MEDIUM|LOW (your confidence in the classification based on the clarity of the diff)"
}`;

function buildModel() returns ai:ModelProvider|error {
    string apiKey = os:getEnv(ANTHROPIC_API_KEY_ENV);
    if apiKey == "" {
        return error(string `${ANTHROPIC_API_KEY_ENV} environment variable is not set`);
    }
    return check new anthropic:ModelProvider(
        apiKey,
        anthropic:CLAUDE_SONNET_4_6,
        maxTokens = 4096
    );
}

function parseAnalysisResponse(string raw) returns AnalysisResult|error {
    string cleaned = regex:replaceAll(raw.trim(), "```json|```", "");
    return check value:fromJsonStringWithType(cleaned.trim());
}

function analyzeInSingleTurn(ai:ModelProvider model, string gitDiff) returns AnalysisResult|error {
    string prompt = string `You are analyzing git diff output for a Ballerina connector to determine the semantic version change needed.

GIT DIFF:
${gitDiff}

${VERSION_RULES}

Analyze the diff and respond with ONLY a JSON object (no markdown, no explanation):
${JSON_SCHEMA}`;

    ai:ChatMessage[] messages = [{role: "user", content: prompt}];
    ai:ChatAssistantMessage response = check chatWithRetry(model, messages);

    string? content = response.content;
    if content is () {
        return error("Empty response from Anthropic API");
    }
    return parseAnalysisResponse(content);
}

function analyzeInChunks(ai:ModelProvider model, string gitDiff) returns AnalysisResult|error {
    int totalChunks = (gitDiff.length() + CHUNK_SIZE - 1) / CHUNK_SIZE;
    int chunksToSend = totalChunks > MAX_CHUNKS ? MAX_CHUNKS : totalChunks;
    boolean truncated = totalChunks > MAX_CHUNKS;

    if truncated {
        io:println(string `Diff has ${totalChunks} chunks — capping at ${MAX_CHUNKS} to stay within model context limit (${MAX_CHUNKS * CHUNK_SIZE / 1000}KB of ${gitDiff.length() / 1000}KB analysed)`);
    } else {
        io:println(string `Diff too large for single turn — splitting into ${chunksToSend} chunks`);
    }

    ai:ChatMessage[] messages = [];

    string truncationNote = truncated
        ? string ` NOTE: the diff is very large; you will receive only the first ${chunksToSend} of ${totalChunks} parts (~${MAX_CHUNKS * CHUNK_SIZE / 1000}KB of ~${gitDiff.length() / 1000}KB). Focus on API-surface changes visible in the portion you receive.`
        : "";

    string intro = string `I will send you a large git diff for a Ballerina connector in ${chunksToSend} parts because of its size.${truncationNote} Please wait until you have received all parts before analysing. After each part simply acknowledge with "Received part X/${chunksToSend}." and nothing else.`;
    messages.push({role: "user", content: intro});

    ai:ChatAssistantMessage introAck = check chatWithRetry(model, messages);
    messages.push({role: "assistant", content: introAck.content ?: ""});

    // Send only up to MAX_CHUNKS chunks
    foreach int i in 0 ..< chunksToSend {
        int startIdx = i * CHUNK_SIZE;
        int endIdx = startIdx + CHUNK_SIZE;
        int safeEnd = endIdx < gitDiff.length() ? endIdx : gitDiff.length();
        string chunk = gitDiff.substring(startIdx, safeEnd);

        io:println(string `Sending chunk ${i + 1}/${chunksToSend} (${chunk.length()} chars)`);

        messages.push({role: "user", content: string `Part ${i + 1}/${chunksToSend}:\n\n${chunk}`});
        ai:ChatAssistantMessage chunkAck = check chatWithRetry(model, messages);
        messages.push({role: "assistant", content: chunkAck.content ?: ""});
    }

    string truncationWarning = truncated
        ? string `\n\nIMPORTANT: You only received the first ~${MAX_CHUNKS * CHUNK_SIZE / 1000}KB of a ~${gitDiff.length() / 1000}KB diff. Base your classification on what you saw; set confidence to LOW if you cannot be certain.`
        : "";

    string analysisRequest = string `You have received all ${chunksToSend} parts of the git diff.${truncationWarning}

${VERSION_RULES}

Analyze the complete diff and respond with ONLY a JSON object (no markdown, no explanation):
${JSON_SCHEMA}`;

    messages.push({role: "user", content: analysisRequest});
    ai:ChatAssistantMessage response = check chatWithRetry(model, messages);

    string? content = response.content;
    if content is () {
        return error("Empty response from Anthropic API after chunked delivery");
    }
    return parseAnalysisResponse(content);
}

function analyzeWithAnthropic(string gitDiff) returns AnalysisResult|error {
    ai:ModelProvider model = check buildModel();

    if gitDiff.length() <= CHUNK_SIZE {
        return analyzeInSingleTurn(model, gitDiff);
    }
    return analyzeInChunks(model, gitDiff);
}

// Accepts a file path so the diff is never passed as a shell argument,
// avoiding the OS ARG_MAX limit for large connectors (e.g. Asana).
public function main(string diffFilePath) returns error? {
    io:println(string `Reading diff from file: ${diffFilePath}`);
    string gitDiffContent = check io:fileReadString(diffFilePath);

    io:println("Analyzing git diff...");
    io:println(string `Diff size: ${gitDiffContent.length()} chars`);

    if gitDiffContent.length() == 0 {
        return error("Git diff file is empty");
    }

    AnalysisResult analysis = check analyzeWithAnthropic(gitDiffContent);

    io:println(SEPARATOR);
    io:println("VERSION CHANGE ANALYSIS");
    io:println(SEPARATOR);
    io:println(string `
Version Bump: ${analysis.changeType}
Confidence:   ${analysis.confidence}

Summary:
${analysis.summary}`);

    if analysis.breakingChanges.length() > 0 {
        io:println("\nBREAKING CHANGES:");
        foreach string change in analysis.breakingChanges {
            io:println(string `  - ${change}`);
        }
    }

    if analysis.newFeatures.length() > 0 {
        io:println("\nNEW FEATURES:");
        foreach string feature in analysis.newFeatures {
            io:println(string `  - ${feature}`);
        }
    }

    if analysis.bugFixes.length() > 0 {
        io:println("\nIMPROVEMENTS:");
        foreach string fix in analysis.bugFixes {
            io:println(string `  - ${fix}`);
        }
    }

    io:println(SEPARATOR);

    json resultJson = check analysis.cloneWithType(json);
    check io:fileWriteJson("analysis_result.json", resultJson);
    io:println("Saved to: analysis_result.json");
}
