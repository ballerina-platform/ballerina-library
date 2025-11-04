import ballerina/log;

// Global cost calculator instance
CostCalculator costCalculator = new ();

// Public functions for modules to use
public function trackUsage(string stageName, int inputTokens, int outputTokens, string model = "claude-4-sonnet") {
    costCalculator.recordUsage(stageName, inputTokens, outputTokens, model);
}

public function trackUsageFromText(string stageName, string inputText, string outputText, string model = "claude-4-sonnet") {
    int inputTokens = estimateTokens(inputText);
    int outputTokens = estimateTokens(outputText);
    costCalculator.recordUsage(stageName, inputTokens, outputTokens, model);
}

public function getStageCost(string stageName) returns decimal {
    return costCalculator.getStageCost(stageName);
}

public function getStageMetrics(string stageName) returns StageMetrics {
    return costCalculator.getStageMetrics(stageName);
}

public function getTotalCost() returns decimal {
    return costCalculator.getTotalCost();
}

public function printCostReport() {
    costCalculator.printReport();
}

public function exportCostReport(string filePath) returns error? {
    return costCalculator.exportReport(filePath);
}

public function resetCostTracking() {
    costCalculator = new ();
    log:printInfo("Cost tracking reset");
}
