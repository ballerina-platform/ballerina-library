import ballerina/lang.regexp;
import ballerina/time;

public type StageMetrics record {|
    int inputTokens;
    int outputTokens;
    decimal cost;
    int calls;
    string model;
    time:Utc lastUpdated;
|};

public type CostSummary record {|
    int totalInputTokens;
    int totalOutputTokens;
    int totalCalls;
    decimal averageCostPerCall;
    string mostExpensiveStage;
    int stageCount;
|};

public type CostReport record {|
    string sessionId;
    time:Utc startTime;
    time:Utc endTime;
    time:Seconds duration;
    decimal totalCost;
    map<StageMetrics> stageBreakdown;
    CostSummary summary;
|};

// Utility function to estimate tokens from text
public function estimateTokens(string text) returns int {
    // Account for whitespace, punctuation, Unicode
    int words = regexp:split(re `\s+`, text.trim()).length();
    int chars = text.length();
    // More sophisticated heuristic based on tokenization patterns
    return int:max(words + chars / 6, chars / 4);
}
