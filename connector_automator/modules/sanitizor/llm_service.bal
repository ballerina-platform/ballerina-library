import connector_automator.utils;

public function initLLMService(boolean quietMode = false) returns LLMServiceError? {
    error? result = utils:initAIService(quietMode);
    if result is error {
        return error LLMServiceError("Failed to initialize LLM service", result);
    }
}
