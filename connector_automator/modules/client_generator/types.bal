# OpenAPI tool configuration options
public type OpenAPIToolOptions record {|
    # License file path to add copyright/license header to generated files
    string license = "docs/license.txt";
    # Tags to filter operations that need to be generated
    string[] tags?;
    # List of specific operations to generate
    string[] operations?;
    # Client method type - resource methods or remote methods
    "resource"|"remote" clientMethod = "resource";
|};

# Default OpenAPI tool options - can be overridden via configuration
configurable OpenAPIToolOptions options = {};

public type ClientGeneratorConfig record {|
    boolean autoYes = false;
    boolean quietMode = false;
    OpenAPIToolOptions? toolOptions = ();
|};
