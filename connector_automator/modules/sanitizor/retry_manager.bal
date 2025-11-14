
public function calculateBackoffDelay(int attempt, RetryConfig config) returns decimal {
    decimal delay = config.initialDelaySeconds;

    // Calculate exponential backoff manually
    int i = 0;
    while i < attempt {
        delay = delay * config.backoffMultiplier;
        i += 1;
    }

    // Cap at maximum delay
    if delay > config.maxDelaySeconds {
        delay = config.maxDelaySeconds;
    }

    // Add simple jitter to avoid thundering herd
    if config.jitter {
        // Add random jitter up to 25% of the delay (simplified)
        decimal jitterRange = delay * 0.25d;
        // Use a simple pseudo-random approach
        decimal randomValue = <decimal>(attempt % 100) / 100.0d;
        decimal randomJitter = (randomValue * jitterRange * 2.0d) - jitterRange;
        delay = delay + randomJitter;

        // Ensure delay is not negative
        if delay < 0.1d {
            delay = 0.1d;
        }
    }

    return delay;
}

// Helper function to determine if an error is retryable
public function isRetryableError(error err) returns boolean {
    string message = err.message().toLowerAscii();

    // Retry on these types of errors
    boolean isNetworkError = message.includes("network") ||
                            message.includes("connection") ||
                            message.includes("timeout") ||
                            message.includes("socket");

    boolean isRateLimitError = message.includes("rate limit") ||
                            message.includes("429") ||
                            message.includes("too many requests");

    boolean isServerError = message.includes("500") ||
                        message.includes("502") ||
                        message.includes("503") ||
                        message.includes("504") ||
                        message.includes("server error");

    boolean isTemporaryError = message.includes("temporary") ||
                            message.includes("unavailable") ||
                            message.includes("overloaded");

    boolean isLLMResponseError = message.includes("unrecognized token") ||
                            message.includes("model") ||
                            message.includes("service") ||
                            message.includes("api");

    return isNetworkError || isRateLimitError || isServerError || isTemporaryError || isLLMResponseError;
}
