public type LLMServiceError distinct error; // custom error type for LLM related failures

// OpenAPI 3.0 specification types
public type OpenAPISpec record {|
    string openapi;
    Info info;
    map<PathItem> paths?;
    Components components?;
    // Other OpenAPI fields can be added as needed
|};

public type Info record {|
    string title;
    string description?;
    string 'version;
    // Other info fields as needed
|};

public type PathItem record {|
    Operation get?;
    Operation post?;
    Operation put?;
    Operation delete?;
    Operation patch?;
    Operation head?;
    Operation options?;
    Operation trace?;
    (Parameter|ParameterRef)[] parameters?; // Allow both inline parameters and references
|};

public type Operation record {|
    string operationId?;
    string summary?;
    string description?;
    string[] tags?;
    (Parameter|ParameterRef)[] parameters?; // Allow both inline parameters and references
    map<Response> responses?;
|};

// Inline parameter definition
public type Parameter record {|
    string name;
    string 'in?; // query, path, header, cookie - optional to handle malformed specs
    string description?;
    boolean required?;
    Schema schema?;
|};

// Parameter reference
public type ParameterRef record {|
    string \$ref;
|};

public type Response record {|
    string description?;
    map<MediaType> content?;
|};

public type MediaType record {|
    Schema schema?;
|};

public type Schema record {|
    string 'type?;
    string description?;
    map<Schema> properties?;
    Schema items?;
    string \$ref?;
    Schema[] allOf?;
    Schema[] oneOf?;
    Schema[] anyOf?;
    json[] 'enum?;
    decimal minimum?;
    decimal maximum?;
    string pattern?;
    // Other schema properties as needed
|};

public type Components record {|
    map<Schema> schemas?;
    map<Parameter> parameters?; // Add parameters to components
|};

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
