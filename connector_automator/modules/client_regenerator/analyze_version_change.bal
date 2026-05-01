import ballerina/ai;
import ballerina/io;
import ballerina/lang.value;
import ballerina/os;
import ballerina/regex;
import ballerinax/ai.anthropic;

const string SEPARATOR = "============================================================";

type AnalysisResult record {
    string changeType;
    string[] breakingChanges;
    string[] newFeatures;
    string[] bugFixes;
    string summary;
    string confidence;
};

function analyzeWithAnthropic(string gitDiff) returns AnalysisResult|error {
    string apiKey = os:getEnv("ANTHROPIC_API_KEY");
    if apiKey == "" {
        return error("ANTHROPIC_API_KEY environment variable is not set");
    }

    ai:ModelProvider model = check new anthropic:ModelProvider(
        apiKey,
        anthropic:CLAUDE_SONNET_4_6,
        maxTokens = 1024
    );

    string prompt = string `You are analyzing git diff output for a Ballerina connector to determine the semantic version change needed.

GIT DIFF:
${gitDiff}

RULES FOR VERSION CLASSIFICATION:
- MAJOR: Breaking changes (removed/renamed methods, removed/renamed types, changed method signatures, changed field types, removed fields)
- MINOR: Backward-compatible additions (new methods, new types, new optional fields, new fields with default values)
- PATCH: Documentation changes, internal refactoring, bug fixes with no API surface changes

Analyze the diff and respond with ONLY a JSON object (no markdown, no explanation):
{
  "changeType": "MAJOR|MINOR|PATCH",
  "breakingChanges": ["list specific breaking changes"],
  "newFeatures": ["list new features/additions"],
  "bugFixes": ["list bug fixes or improvements"],
  "summary": "concise summary of changes",
  "confidence": "HIGH|MEDIUM|LOW (your confidence in the classification based on the clarity of the diff)"
}`;

    ai:ChatMessage[] messages = [{role: "user", content: prompt}];
    ai:ChatAssistantMessage response = check model->chat(messages);

    string? content = response.content;
    if content is () {
        return error("Empty response from Anthropic API");
    }

    string cleaned = regex:replaceAll(content.trim(), "```json|```", "");
    return check value:fromJsonStringWithType(cleaned.trim());
}

public function main(string gitDiffContent) returns error? {
    io:println("Analyzing git diff...");
    io:println(string `Diff size: ${gitDiffContent.length()} chars`);

    if gitDiffContent.length() == 0 {
        return error("Git diff content is empty");
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
