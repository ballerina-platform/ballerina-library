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
import wso2/example_doc_generator.utils;

# Anthropic message content block.
type ContentBlock record {
    # The type of content block (e.g. "text")
    string 'type;
    # The text content (present when type is "text")
    string text?;
};

# Anthropic token usage info.
type UsageInfo record {
    # Number of input tokens consumed
    int input_tokens;
    # Number of output tokens generated
    int output_tokens;
};

# Anthropic Messages API response (partial — only fields we need).
type MessagesResponse record {
    # Unique identifier for this message
    string id;
    # The model used to generate the response
    string model;
    # The reason the model stopped generating
    string stop_reason?;
    # The content blocks in the response
    ContentBlock[] content;
    # Token usage for this response
    UsageInfo? usage;
};

# Default Claude model to use.
const string DEFAULT_MODEL = "claude-sonnet-4-6";

# Anthropic API base URL.
const string ANTHROPIC_BASE_URL = "https://api.anthropic.com";

# Anthropic API version header value.
const string ANTHROPIC_VERSION = "2023-06-01";

# Claude Sonnet 4.6 pricing: $3.00 per million input tokens.
final decimal INPUT_COST_PER_TOKEN = 0.000003d;

# Claude Sonnet 4.6 pricing: $15.00 per million output tokens.
final decimal OUTPUT_COST_PER_TOKEN = 0.000015d;

# Token usage and USD cost for a single LLM API call.
public type LlmUsage record {
    # Number of input (prompt) tokens consumed
    int inputTokens;
    # Number of output (completion) tokens generated
    int outputTokens;
    # Estimated cost in USD based on model pricing
    decimal costUsd;
};

# Result of a Claude API call — the generated text plus token usage/cost.
public type LlmResult record {
    # The generated text content
    string text;
    # Token usage and cost for this call
    LlmUsage usage;
};

# Validates the Anthropic API key by sending a minimal test request.
# Logs a clean success message or extracts and displays error details.
# Fails fast before the expensive pipeline calls run.
#
# + apiKey - the Anthropic API key
# + return - nil on success, or an error with the HTTP diagnostic details
public function validateApiKey(string apiKey) returns error? {
    utils:log("\t[INFO] Sending ping request...");

    http:Client httpClient = check new (ANTHROPIC_BASE_URL);

    json payload = {
        "model": DEFAULT_MODEL,
        "max_tokens": 10,
        "messages": [
            {"role": "user", "content": "Reply with the single word: OK"}
        ]
    };

    http:Request req = new;
    req.setJsonPayload(payload);
    req.setHeader("x-api-key", apiKey);
    req.setHeader("anthropic-version", ANTHROPIC_VERSION);
    req.setHeader("content-type", "application/json");

    http:Response response = check httpClient->post("/v1/messages", req);
    int statusCode = response.statusCode;

    if statusCode >= 200 && statusCode < 300 {
        utils:log("\t[INFO] ✓ API key is valid — Anthropic responded successfully.");
        return;
    }

    // Handle error response
    string|error body = response.getTextPayload();
    string errorMsg = "API key validation failed";
    if body is string {
        json|error jsonBody = body.fromJsonString();
        if jsonBody is map<json> {
            json errField = jsonBody["error"];
            if errField is map<json> {
                json msgField = errField["message"];
                if msgField is string {
                    errorMsg = msgField;
                }
            }
        }
    }

    utils:log(string `\t[ERROR] HTTP ${statusCode}: ${errorMsg}`);
    return error(string `Anthropic API key validation failed (HTTP ${statusCode}): ${errorMsg}`);
}

# Sends the system and user prompts to Claude and returns the generated text plus usage.
#
# + systemPrompt - the system prompt instructing the model
# + userMessage - the user message with the goal details
# + apiKey - the Anthropic API key
# + return - LlmResult with text and token usage/cost, or an error
public function callClaude(string systemPrompt, string userMessage, string apiKey) returns LlmResult|error {
    utils:log("\t[INFO] Model:              " + DEFAULT_MODEL);
    utils:log("\t[INFO] System prompt len:  " + systemPrompt.length().toString() + " chars");
    utils:log("\t[INFO] User message len:   " + userMessage.length().toString() + " chars");
    utils:log("\t[INFO] Sending request to Anthropic API...");

    json payload = {
        "model": DEFAULT_MODEL,
        "max_tokens": 16000,
        "system": systemPrompt,
        "messages": [
            {"role": "user", "content": userMessage}
        ]
    };

    // Generous timeout — large prompts can take 2–3 minutes to generate
    http:Client httpClient = check new (ANTHROPIC_BASE_URL, timeout = 300);

    http:Request req = new;
    req.setJsonPayload(payload);
    req.setHeader("x-api-key", apiKey);
    req.setHeader("anthropic-version", ANTHROPIC_VERSION);
    req.setHeader("content-type", "application/json");

    http:Response response = check httpClient->post("/v1/messages", req);
    int statusCode = response.statusCode;

    if statusCode < 200 || statusCode >= 300 {
        string|error errBody = response.getTextPayload();
        string detail = errBody is string ? errBody : "(unable to read response body)";
        utils:log("\t[ERROR] Anthropic API returned HTTP " + statusCode.toString());
        utils:log("\t[ERROR] Response: " + detail);
        return error(string `Anthropic API returned HTTP ${statusCode}: ${detail}`);
    }

    json responseJson = check response.getJsonPayload();
    MessagesResponse msgResp = check responseJson.cloneWithType(MessagesResponse);

    if msgResp.content.length() == 0 {
        return error("No content blocks in Anthropic API response");
    }

    // Find the first text block
    string resultText = "";
    foreach ContentBlock block in msgResp.content {
        if block.'type == "text" {
            string? text = block.text;
            if text is string {
                resultText = text;
                break;
            }
        }
    }

    if resultText.trim().length() == 0 {
        return error("Empty text content in Anthropic API response");
    }

    utils:log("\t[INFO] Response received. Length: " + resultText.length().toString() + " chars");

    LlmUsage usageData = {inputTokens: 0, outputTokens: 0, costUsd: 0.0d};
    UsageInfo? usage = msgResp.usage;
    if usage is UsageInfo {
        int inTok = usage.input_tokens;
        int outTok = usage.output_tokens;
        decimal cost = (<decimal>inTok * INPUT_COST_PER_TOKEN) + (<decimal>outTok * OUTPUT_COST_PER_TOKEN);
        usageData = {inputTokens: inTok, outputTokens: outTok, costUsd: cost};
        utils:log("\t[USAGE] Input: " + inTok.toString()
            + " | Output: " + outTok.toString()
            + " | Total: " + (inTok + outTok).toString()
            + " | Cost: $" + cost.toString());
    }

    return {text: resultText, usage: usageData};
}

