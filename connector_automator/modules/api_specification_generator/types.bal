// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

# Configuration for the API specification generator.
public type GeneratorConfig record {|
    # Path to the metadata JSON file produced by sdk_analyzer
    string metadataPath;
    # Output directory for the generated Ballerina specification file
    string outputDir;
    # Dataset key used for deterministic artifact naming
    string datasetKey = "";
    # Enable quiet mode (minimal output)
    boolean quietMode = false;
    # Maximum tokens for the LLM IR generation response (increased for large SDKs like S3)
    int maxTokens = 128000;
    # Enable extended thinking for higher quality IR generation
    boolean enableExtendedThinking = true;
    # Extended thinking budget tokens
    int thinkingBudgetTokens = 5000;
|};

# Result of specification generation.
public type GeneratorResult record {|
    # Whether generation succeeded
    boolean success;
    # Path to generated Ballerina specification file
    string specificationPath;
    # Path to the saved Intermediate Representation JSON file
    string? irPath = ();
    # Generation duration in milliseconds
    int durationMs;
|};

# Error type for the API specification generator.
public type GeneratorError error;

# Parameter / field kind in the IR.
public enum FieldKind {
    REQUIRED = "Required",
    INCLUDED = "Included",
    DEFAULT = "Default"
}

# Reference schema entry kind.
public enum ReferenceKind {
    STRUCTURE = "STRUCTURE",
    ENUM = "ENUM",
    COLLECTION = "COLLECTION"
}

# A single parameter of an IR function.
public type IRParameter record {|
    # Parameter name
    string name;
    # Parameter kind (Required, Included, Default)
    string kind;
    # Ballerina type name (primitive or reference name)
    string 'type;
    # Human-readable description
    string description;
    # Default value (if kind == Default)
    string? defaultValue = ();
    # If this parameter is a complex object, the reference name
    string? referenceType = ();
|};

# Return type descriptor in the IR.
public type IRReturn record {|
    # Ballerina type name
    string 'type;
    # Human-readable description
    string description;
    # Reference name if complex
    string? referenceType = ();
|};

# A function in the IR.
public type IRFunction record {|
    # Function name (camelCase)
    string name;
    # Function kind – always "Remote"
    string kind = "Remote";
    # Human-readable description
    string description;
    # Parameters (may include a spread-reference for request objects)
    IRParameter[] parameters;
    # Return type
    IRReturn 'return;
|};

# A field within a STRUCTURE reference or connection config.
public type IRField record {|
    # Field name
    string name;
    # Field kind (Required, Included, Default)
    string kind;
    # Ballerina type name
    string 'type;
    # Human-readable description
    string description;
    # Default value (if kind == Default)
    string? defaultValue = ();
|};

# STRUCTURE reference entry – a complex object with typed fields.
public type IRStructure record {|
    # Type name (PascalCase)
    string name;
    # Always "STRUCTURE"
    string kind = "STRUCTURE";
    # Fields of this structure
    IRField[] fields;
|};

# A single enum member with its Ballerina name and SDK string value.
public type IREnumValue record {|
    # SCREAMING_SNAKE_CASE Ballerina member name
    string member;
    # SDK API string value
    string value;
|};

# ENUM reference entry – a fixed set of constants.
public type IREnum record {|
    # Type name (PascalCase)
    string name;
    # Always "ENUM"
    string kind = "ENUM";
    # Native Ballerina type (usually "string")
    string nativeType;
    # Enum constant values with member names and SDK string values
    IREnumValue[] values;
|};

# COLLECTION reference entry – non-primitive container (List / Map).
public type IRCollection record {|
    # Type name (PascalCase)
    string name;
    # Always "COLLECTION"
    string kind = "COLLECTION";
    # Container kind: "List" or "Map"
    string collectionType;
    # Element / value type name
    string memberType;
|};

# Complete Intermediate Representation.
public type IntermediateRepresentation record {|
    # SDK display name
    string sdkName;
    # SDK version string
    string version;
    # Root client simple name
    string clientName;
    # Client description
    string clientDescription;
    # Connection / initialisation configuration fields
    IRField[] connectionFields;
    # Remote functions exposed by the client
    IRFunction[] functions;
    # Reference schema: structures
    IRStructure[] structures;
    # Reference schema: enums
    IREnum[] enums;
    # Reference schema: collections
    IRCollection[] collections;
|};
