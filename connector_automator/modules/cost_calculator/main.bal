import ballerina/io;
import ballerina/log;
import ballerina/time;

public class CostCalculator {
    private map<StageMetrics> stageMetrics;
    private decimal totalCost;
    private time:Utc startTime;
    private string sessionId;

    public function init() {
        self.stageMetrics = {};
        self.totalCost = 0.0d;
        self.startTime = time:utcNow();
        self.sessionId = time:utcToString(self.startTime);
    }

    public function recordUsage(string stageName, int inputTokens, int outputTokens,
            string model = "claude-4-sonnet", decimal customRate = 0.0d) {
        decimal cost = customRate > 0.0d ? customRate : calculateCost(inputTokens, outputTokens, model);

        if self.stageMetrics.hasKey(stageName) {
            StageMetrics existing = self.stageMetrics.get(stageName);
            self.stageMetrics[stageName] = {
                inputTokens: existing.inputTokens + inputTokens,
                outputTokens: existing.outputTokens + outputTokens,
                cost: existing.cost + cost,
                calls: existing.calls + 1,
                model: model,
                lastUpdated: time:utcNow()
            };
        } else {
            self.stageMetrics[stageName] = {
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cost: cost,
                calls: 1,
                model: model,
                lastUpdated: time:utcNow()
            };
        }

        self.totalCost += cost;
        log:printInfo(string `Cost recorded for ${stageName}: $${cost.toString()} (Total: $${self.totalCost.toString()})`);
    }

    public function getStageCost(string stageName) returns decimal {
        if self.stageMetrics.hasKey(stageName) {
            return self.stageMetrics.get(stageName).cost;
        }
        return 0.0d;
    }

    public function getStageMetrics(string stageName) returns StageMetrics {
        if self.stageMetrics.hasKey(stageName) {
            return self.stageMetrics.get(stageName);
        }
        // Return empty metrics if stage doesn't exist
        return {
            inputTokens: 0,
            outputTokens: 0,
            cost: 0.0d,
            calls: 0,
            model: "claude-4-sonnet",
            lastUpdated: time:utcNow()
        };
    }

    public function getTotalCost() returns decimal {
        return self.totalCost;
    }

    public function generateReport() returns CostReport {
        time:Utc endTime = time:utcNow();
        time:Seconds duration = time:utcDiffSeconds(endTime, self.startTime);

        return {
            sessionId: self.sessionId,
            startTime: self.startTime,
            endTime: endTime,
            duration: duration,
            totalCost: self.totalCost,
            stageBreakdown: self.stageMetrics.clone(),
            summary: self.generateSummary()
        };
    }

    private function generateSummary() returns CostSummary {
        int totalInputTokens = 0;
        int totalOutputTokens = 0;
        int totalCalls = 0;
        string mostExpensiveStage = "";
        decimal highestCost = 0.0d;

        foreach var [stageName, metrics] in self.stageMetrics.entries() {
            totalInputTokens += metrics.inputTokens;
            totalOutputTokens += metrics.outputTokens;
            totalCalls += metrics.calls;

            if metrics.cost > highestCost {
                highestCost = metrics.cost;
                mostExpensiveStage = stageName;
            }
        }

        return {
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens,
            totalCalls: totalCalls,
            averageCostPerCall: totalCalls > 0 ? self.totalCost / <decimal>totalCalls : 0.0d,
            mostExpensiveStage: mostExpensiveStage,
            stageCount: self.stageMetrics.length()
        };
    }

    public function printReport() {
        CostReport report = self.generateReport();
        string separator = self.repeatString("=", 60);
        string dashLine = self.repeatString("-", 60);

        io:println("\n" + separator);
        io:println("CONNECTOR AUTOMATOR - COST REPORT");
        io:println(separator);
        io:println(string `Session ID: ${report.sessionId}`);
        io:println(string `Duration: ${report.duration.toString()} seconds`);
        io:println(string `Total Cost: $${report.totalCost.toString()}`);
        io:println();

        io:println("STAGE BREAKDOWN:");
        io:println(dashLine);
        foreach var [stageName, metrics] in report.stageBreakdown.entries() {
            decimal percentage = self.totalCost > 0.0d ? (metrics.cost / self.totalCost) * 100.0d : 0.0d;
            io:println(string `${stageName}:`);
            io:println(string `  Cost: $${metrics.cost.toString()} (${percentage.toString()}%)`);
            io:println(string `  Tokens: ${metrics.inputTokens} in, ${metrics.outputTokens} out`);
            io:println(string `  Calls: ${metrics.calls}, Model: ${metrics.model}`);
            io:println();
        }

        io:println("SUMMARY:");
        io:println(dashLine);
        CostSummary summary = report.summary;
        io:println(string `Total Input Tokens: ${summary.totalInputTokens.toString()}`);
        io:println(string `Total Output Tokens: ${summary.totalOutputTokens.toString()}`);
        io:println(string `Total API Calls: ${summary.totalCalls.toString()}`);
        io:println(string `Average Cost per Call: $${summary.averageCostPerCall.toString()}`);
        io:println(string `Most Expensive Stage: ${summary.mostExpensiveStage}`);
        io:println(separator);
    }

    private function repeatString(string str, int count) returns string {
        string result = "";
        foreach int i in 0 ..< count {
            result += str;
        }
        return result;
    }

    public function exportReport(string filePath) returns error? {
        CostReport report = self.generateReport();

        // Convert to JSON manually since CostReport contains complex types
        json reportJson = {
            "sessionId": report.sessionId,
            "startTime": time:utcToString(report.startTime),
            "endTime": time:utcToString(report.endTime),
            "duration": report.duration,
            "totalCost": report.totalCost,
            "summary": {
                "totalInputTokens": report.summary.totalInputTokens,
                "totalOutputTokens": report.summary.totalOutputTokens,
                "totalCalls": report.summary.totalCalls,
                "averageCostPerCall": report.summary.averageCostPerCall,
                "mostExpensiveStage": report.summary.mostExpensiveStage,
                "stageCount": report.summary.stageCount
            },
            "stageBreakdown": self.convertStageMetricsToJson(report.stageBreakdown)
        };

        check io:fileWriteJson(filePath, reportJson);
        log:printInfo(string `Cost report exported to: ${filePath}`);
    }

    private function convertStageMetricsToJson(map<StageMetrics> stageMetrics) returns json {
        map<json> result = {};
        foreach var [stageName, metrics] in stageMetrics.entries() {
            result[stageName] = {
                "inputTokens": metrics.inputTokens,
                "outputTokens": metrics.outputTokens,
                "cost": metrics.cost,
                "calls": metrics.calls,
                "model": metrics.model,
                "lastUpdated": time:utcToString(metrics.lastUpdated)
            };
        }
        return result;
    }
}

function calculateCost(int inputTokens, int outputTokens, string model) returns decimal {
    // Pricing per 1K tokens (as of 2024)
    map<[decimal, decimal]> pricing = {
        "claude-4-sonnet": [0.003d, 0.015d], // [input, output] per 1K tokens
        "claude-3-haiku": [0.00025d, 0.00125d],
        "gpt-4": [0.03d, 0.06d],
        "gpt-3.5-turbo": [0.0015d, 0.002d]
    };

    [decimal, decimal] rates = pricing.hasKey(model) ? pricing.get(model) : [0.003d, 0.015d];
    decimal inputCost = (<decimal>inputTokens / 1000.0d) * rates[0];
    decimal outputCost = (<decimal>outputTokens / 1000.0d) * rates[1];

    return inputCost + outputCost;
}
