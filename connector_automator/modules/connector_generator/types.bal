import wso2/connector_automator.sdkanalyzer as analyzer;
import wso2/connector_automator.api_specification_generator as api;

# Configuration for connector generation.
public type ConnectorGeneratorConfig record {|
    # Path to the metadata JSON file produced by sdk_analyzer
    string metadataPath;
    # Path to the Intermediate Representation JSON file produced by the API specification generator
    string irPath;
    # Path to the parsed API specification Ballerina file produced by the API specification generator
    string apiSpecPath;
    # Output directory for the generated connector artifacts
    string outputDir;
    # Enable quiet mode for minimal console output
    boolean quietMode = false;
    # Maximum tokens for the LLM response during connector generation
    int maxTokens = 128000;
    # Enable extended thinking for deep mapping/code reasoning
    boolean enableExtendedThinking = true;
    # Extended thinking budget tokens
    int thinkingBudgetTokens = 4000;
    # Enable post-generation code fixing for generated artifacts
    boolean enableCodeFixing = false;
    # Code fixing mode: auto-apply or report-only
    string fixMode = "auto-apply";
    # Maximum fix iterations to run in the fixer
    int maxFixIterations = 3;
    # SDK version hint extracted from dataset key (e.g., sqs-2.31.66 -> 2.31.66)
    string sdkVersionHint = "";
|};

# Parsed method parameter from API spec signature.
public type SpecMethodParameter record {|
    # Parameter type (e.g., string, int, custom type)
    string 'type;
    # Parameter name
    string name;
    # Indicates if the parameter is a config spread parameter
    boolean isConfigSpread = false;
|};

# Parsed API spec method signature.
public type SpecMethodSignature record {|
    # Method name
    string name;
    # List of method parameters
    SpecMethodParameter[] parameters;
    # Method return type
    string returnType;
|};

# Method mapping between API spec and native-library metadata.
public type MethodMapping record {|
    # API spec method signature
    SpecMethodSignature specMethod;
    # Matched native method info from metadata, if any
    analyzer:MethodInfo? javaMethod = ();
|};

# Parsed API spec model.
public type ParsedApiSpec record {|
    # Header and type definitions extracted from the API spec, to be included in `types.bal`.
    string headerAndTypes;
    # List of client method signatures defined in the API spec, to be implemented in `client.bal`.
    SpecMethodSignature[] clientMethods;
    # Name of the connection configuration type found in the spec's init() signature.
    # Defaults to "ConnectionConfig" when the init signature cannot be parsed.
    string configTypeName = "ConnectionConfig";
|};

# Connector generation result.
public type ConnectorGeneratorResult record {|
    # Indicates if the connector generation was successful.
    boolean success;
    # Path to the generated client file.
    string clientPath;
    # Path to the generated types file.
    string typesPath;
    # Path to the generated native adaptor file.
    string nativeAdaptorPath;
    # Count of mapped methods.
    int mappedMethodCount;
    # Count of API spec methods discovered
    int specMethodCount;
    # Duration of the connector generation process in milliseconds.
    int durationMs;
    # Indicates whether code fixing stage was executed.
    boolean codeFixingRan = false;
    # Indicates whether code fixing stage resolved all detected issues.
    boolean codeFixingSuccess = false;
|};

# Connector generator error.
public type ConnectorGeneratorError error;

# Loaded generation inputs.
public type ConnectorGenerationInputs record {|
    # Structured SDK metadata loaded from the metadata JSON file.
    analyzer:StructuredSDKMetadata metadata;
    # Intermediate Representation loaded from the IR JSON file.
    api:IntermediateRepresentation ir;
    # Parsed API specification loaded from the API spec Ballerina file.
    ParsedApiSpec parsedSpec;
    # Raw metadata JSON text
    string metadataJsonText;
    # Raw IR JSON text
    string irJsonText;
    # Raw API spec Ballerina source text
    string apiSpecText;
|};

# Parameter binding between API spec and native method parameters/fields.
public type ParameterBinding record {|
    # Parameter name in API spec method
    string specParam;
    # Parameter/field name on native side
    string javaParam;
    # Binding strategy category
    string bindingType;
    # Transform expression if bindingType = Transform
    string? transformExpr = ();
|};

# LLM-decided method mapping entry.
public type GeneratedMethodMapping record {|
    # API spec method name
    string specMethod;
    # Native method name from metadata
    string javaMethod;
    # Confidence score in [0,1]
    decimal confidence;
    # Mapping rationale
    string reason;
    # Parameter-level bindings
    ParameterBinding[] parameterBindings;
|};

# Validation block returned by LLM.
public type GeneratedValidation record {|
    # Indicates whether all API spec methods were mapped
    boolean allSpecMethodsMapped;
    # API spec methods that remained unmapped
    string[] unmappedSpecMethods;
    # Extra Java mappings that do not correspond to spec methods
    string[] extraMappedJavaMethods;
    # Signature mismatch notes
    string[] signatureMismatches;
    # Type reference mismatch notes
    string[] typeReferenceErrors;
    # Additional notes/warnings
    string[] notes;
|};

# Full LLM generation output schema.
public type GeneratedConnectorBundle record {|
    # Target client class name
    string clientClassName;
    # Suggested types file name
    string typeFileName;
    # Suggested client file name
    string clientFileName;
    # Suggested native adaptor file path
    string nativeAdaptorFilePath;    
    # Native adaptor class name
    string nativeAdaptorClassName;
    # Method mappings
    GeneratedMethodMapping[] methodMappings;
    # Generated Ballerina types source
    string typesBal;
    # Generated Ballerina client source
    string clientBal;
    # Generated Java native adaptor source
    string nativeAdaptorJava;
    # Validation details
    GeneratedValidation validation;
|};
