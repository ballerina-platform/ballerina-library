import connector_automator.cost_calculator;
import connector_automator.utils;

public function initExampleGenerator() returns error? {
    return utils:initAIService();
}

public function generateUseCaseAndFunctions(ConnectorDetails details, string[] usedFunctions) returns json|error {
    string prompt = getUsecasePrompt(details, usedFunctions);

    if !utils:isAIServiceInitialized() {
        return error("AI model not initialized. Please call initExampleGenerator() first.");
    }

    string result = check utils:callAI(prompt);

    cost_calculator:trackUsageFromText("example_generator_usecase", prompt, result, "claude-4-sonnet");

    return result.fromJsonString();

}

public function generateExampleCode(ConnectorDetails details, string useCase, string targetedContext) returns string|error {
    string prompt = getExampleCodegenerationPrompt(details, useCase, targetedContext);

    if !utils:isAIServiceInitialized() {
        return error("AI model not initialized. Please call initExampleGenerator() first.");
    }

    string result = check utils:callAI(prompt);
    cost_calculator:trackUsageFromText("example_generator_code", prompt, result, "claude-4-sonnet");
    return result;

}

public function generateExampleName(string useCase) returns string|error {
    string prompt = getExampleNamePrompt(useCase);

    if !utils:isAIServiceInitialized() {
        return error("AI model not initialized. Please call initExampleGenerator() first.");
    }

    string|error result = utils:callAI(prompt);
    if result is error {
        return error("Failed to generate example name", result);
    }

    cost_calculator:trackUsageFromText("example_generator_name", prompt, result, "claude-4-sonnet");
    return result == "" ? "example-1" : result;
}
