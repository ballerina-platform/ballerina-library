public type LLMServiceError distinct error; // custom error type for LLM related failures

// Batch processing types
public type DescriptionRequest record {
    string id;
    string name;
    string context;
    string schemaPath; // e.g., "User.properties.email" or "User"
};

public type SchemaRenameRequest record {
    string originalName;
    string schemaDefinition;
    string usageContext;
};

public type BatchDescriptionResponse record {
    string id;
    string description;
};

public type BatchRenameResponse record {
    string originalName;
    string newName;
};

public type OperationIdRequest record {
    string id;
    string path;
    string method;
    string summary?;
    string description?;
    string[] tags?;
};

public type BatchOperationIdResponse record {
    string id;
    string operationId;
};

public type RetryConfig record {
    int maxRetries = 3;
    decimal initialDelaySeconds = 1.0;
    decimal maxDelaySeconds = 60.0;
    decimal backoffMultiplier = 2.0;
    boolean jitter = true;
};
