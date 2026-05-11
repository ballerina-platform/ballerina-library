import ballerina/ai;
import ballerina/log;
import ballerina/os;
import ballerina/regex;
import ballerinax/ai.anthropic;

string cachedApiKey = "";
ai:ModelProvider? defaultModel = ();

public function initAIService(boolean quietMode = false) returns error? {
    string apiKey = os:getEnv("ANTHROPIC_API_KEY");
    if apiKey.length() == 0 {
        return error("ANTHROPIC_API_KEY environment variable is not set");
    }
    cachedApiKey = apiKey;

    ai:ModelProvider|error provider = new anthropic:ModelProvider(
        apiKey,
        anthropic:CLAUDE_SONNET_4_6,
        maxTokens = 128000,
        timeout = 1200,
        httpVersion = "1.1"
    );
    if provider is error {
        return error("Failed to initialize AI model provider", provider);
    }
    defaultModel = provider;

    if !quietMode {
        log:printInfo("LLM service initialized successfully");
    }
}

public function callAI(string prompt) returns string|error {
    ai:ModelProvider? model = defaultModel;
    if model is () {
        return error("AI model not initialized. Please call initAIService() first.");
    }
    ai:ChatMessage[] messages = [{role: "user", content: prompt}];
    ai:ChatAssistantMessage|error response = model->chat(messages);
    if response is error {
        return error("AI generation failed: " + response.message());
    }
    return extractResponseContent(response);
}

public function callAIAdvanced(string userPrompt, string systemPrompt = "", int maxTokens = 128000,
        boolean enableExtendedThinking = false, int thinkingBudgetTokens = 0) returns string|error {
    if cachedApiKey.length() == 0 {
        return error("AI model not initialized. Please call initAIService() first.");
    }

    ai:ModelProvider|error provider = new anthropic:ModelProvider(
        cachedApiKey,
        anthropic:CLAUDE_SONNET_4_6,
        maxTokens = maxTokens,
        timeout = 1200,
        httpVersion = "1.1"
    );
    if provider is error {
        return error("Failed to create AI model provider", provider);
    }

    ai:ChatMessage[] messages = [];
    if systemPrompt.length() > 0 {
        messages.push({role: "system", content: systemPrompt});
    }
    messages.push({role: "user", content: userPrompt});

    ai:ChatAssistantMessage|error response = provider->chat(messages);
    if response is error {
        error? cause = response.cause();
        string causeDetail = cause is error ? " | " + cause.message() : "";
        return error("AI generation failed: " + response.message() + causeDetail);
    }
    return extractResponseContent(response);
}

public function isAIServiceInitialized() returns boolean {
    return defaultModel !is ();
}

# Extract a JSON object string from an LLM response that may be wrapped in markdown fences.
#
# + responseText - Full LLM response text
# + return - Extracted JSON object string or error
public function extractJsonFromLLMResponse(string responseText) returns string|error {
    if responseText.includes("```json") {
        string[] parts = regex:split(responseText, "```json");
        if parts.length() >= 2 {
            string block = parts[1];
            int? closingIdx = block.indexOf("```");
            if closingIdx is int && closingIdx > 0 {
                return block.substring(0, closingIdx).trim();
            }
            return block.trim();
        }
    }

    if responseText.includes("```") {
        string[] parts = regex:split(responseText, "```");
        if parts.length() >= 3 {
            string block = parts[1].trim();
            int? newline = block.indexOf("\n");
            if newline is int && newline < 10 {
                string tag = block.substring(0, newline).trim();
                if tag == "json" || tag == "" {
                    block = block.substring(newline + 1);
                }
            }
            return block.trim();
        }
    }

    int? startIdx = responseText.indexOf("{");
    int? endIdx = responseText.lastIndexOf("}");
    if startIdx is int && endIdx is int && endIdx > startIdx {
        return responseText.substring(startIdx, endIdx + 1).trim();
    }

    return error("Could not extract JSON from LLM response.");
}

isolated function extractResponseContent(ai:ChatAssistantMessage response) returns string|error {
    string? content = response.content;
    if content is string {
        return content;
    }
    return error("AI response content is empty.");
}

