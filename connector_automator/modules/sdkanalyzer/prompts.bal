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

# System prompt for client class scoring
#
# + roleHint - Optional target role hint (admin/producer/consumer)
# + return - System prompt for evaluating client classes
public function getClientScoringSystemPrompt(string? roleHint = ()) returns string {
    string roleDirective = "";
    if roleHint is string {
        roleDirective = string ` Prioritize classes that best match the target client role: ${roleHint}.`;
    }

    return string `You are an expert Java SDK analyzer. Your task is to evaluate if a Java class is likely
        to be the root/main client class for an SDK. Analyze class characteristics and provide a score from 0-100.
        Use your knowledge of SDK design patterns and conventions to identify the primary client interface that developers would use.
        ${roleDirective}
        Return your response in format: SCORE:XX|REASON:your explanation`;
}

# User prompt for client class scoring
#
# + classInfo - Formatted class information
# + roleHint - Optional target role hint (admin/producer/consumer)
# + return - User prompt for evaluating a specific class
public function getClientScoringUserPrompt(string classInfo, string? roleHint = ()) returns string {
    string roleBlock = "";
    if roleHint is string {
        roleBlock = string `\nTarget role hint: ${roleHint}\nGive higher scores to classes that represent this role while still being a primary SDK client entry point.`;
    }

    return string `
Evaluate this Java class as a potential root SDK client class:

${classInfo}
${roleBlock}

Analyze the class structure and provide a numeric score 0-100 based on your knowledge of:
- SDK design patterns and naming conventions
- Method diversity and comprehensiveness
- Typical usage patterns in similar SDKs
- Whether this represents the main entry point for SDK operations

Consider what makes a class the primary client interface that developers would interact with.

Format: SCORE:XX|REASON:your brief explanation`;
}

# System prompt for initialization pattern detection
#
# + return - System prompt for detecting instantiation patterns
public function getInitPatternSystemPrompt() returns string {
    return string `You are a Java SDK instantiation pattern analyzer. Analyze the class structure and determine the RECOMMENDED client instantiation pattern.
        Use your knowledge of Java SDK design patterns to identify how developers should create instances of this client.
        Return your response in this EXACT format:\n
        PATTERN: <pattern-name>\n
        REASON: <1-3 line explanation>\n
        Pattern names: constructor, builder, static-factory, instance-factory, or no-constructor`;
}

# User prompt for initialization pattern detection
#
# + simpleName - Simple class name
# + packageName - Package name
# + constructorDetails - Formatted constructor information
# + staticMethodInfo - Formatted static method information
# + totalMethods - Total method count
# + isInterface - Whether class is an interface
# + return - User prompt for pattern detection
public function getInitPatternUserPrompt(
        string simpleName,
        string packageName,
        string constructorDetails,
        string staticMethodInfo,
        int totalMethods,
        boolean isInterface
) returns string {
    return "Analyze this Java SDK client class and determine the RECOMMENDED instantiation pattern:\n\n" +
        "Class: " + simpleName + "\n" +
        "Package: " + packageName + "\n\n" +
        "Constructors:\n" + constructorDetails + "\n" +
        "Static Methods: " + staticMethodInfo + "\n\n" +
        "Total Methods: " + totalMethods.toString() + "\n" +
        "Is Interface: " + isInterface.toString() + "\n\n" +
        "Based on your knowledge of SDK design patterns and the information above:\n" +
        "1. Determine the RECOMMENDED instantiation pattern\n" +
        "2. Provide a brief reason (1-3 lines) explaining why this pattern is appropriate\n\n" +
        "Consider common SDK patterns and how developers typically instantiate similar clients.\n\n" +
        "Respond in this EXACT format:\n" +
        "PATTERN: <pattern-name>\n" +
        "REASON: <explanation>";
}

# System prompt for method ranking
#
# + return - System prompt for ranking SDK methods
public function getMethodRankingSystemPrompt() returns string {
    return string `You are an expert Java SDK usage analyst. Analyze the provided method list and identify the MOST IMPORTANT methods that developers would commonly use.
        Use your knowledge of SDK usage patterns to select methods that represent core functionality and common operations.
        Focus on methods that perform actual SDK operations, NOT utility/meta methods for client configuration or instantiation.
        Return ONLY a comma-separated list of the important method NAMES. The count can vary (typically 20-40) based on SDK complexity.
        Exclude redundant overloads, rarely-used methods, and client meta methods. No commentary, just the comma-separated names.`;
}

# User prompt for method ranking
#
# + methodCount - Total number of methods
# + methodsList - Formatted list of methods
# + return - User prompt for method ranking
public function getMethodRankingUserPrompt(int methodCount, string methodsList) returns string {
    return "Analyze these " + methodCount.toString() + " SDK methods and select the MOST IMPORTANT ones that developers commonly use.\n\n" +
        "Use your knowledge of SDK patterns to identify:\n" +
        "- Core operations that represent the main functionality of the SDK\n" +
        "- Commonly-used methods in typical SDK workflows\n" +
        "- Methods that perform actual SDK operations (not client setup/configuration)\n\n" +
        "EXCLUDE:\n" +
        "- Client instantiation and configuration methods\n" +
        "- Utility methods for client management\n" +
        "- Rarely-used or redundant method overloads\n" +
        "- Internal/framework methods\n\n" +
        "Return a comma-separated list of the important method NAMES (no numbers, just names).\n\n" +
        "Methods:\n" + methodsList + "\n" +
        "Important method names (comma-separated):";
}

# User prompt for selecting top-N methods
# + methodCount - Total number of methods
# + methodsList - Formatted list of methods
# + n - Number of methods to select
# + return - User prompt for method selection
public function getMethodSelectionUserPrompt(int methodCount, string methodsList, int n) returns string {
    return "From the following " + methodCount.toString() + " methods, select the most commonly used " + n.toString() + " methods that developers use most frequently.\n\n" +
        "Return ONLY a comma-separated list of EXACT method NAMES (no numbers, no extra commentary).\n\n" +
        "Methods:\n" + methodsList + "\n\n" +
        "Return exactly " + n.toString() + " method names, comma-separated:";
}

# System prompt for parameter field analysis
#
# + return - System prompt for analyzing parameter fields
public function getParameterFieldAnalysisSystemPrompt() returns string {
    return "You are an expert Java SDK parameter analyzer with access to web search and official SDK documentation. " +
        "Your task is to analyze method parameters and their fields to determine which fields are REQUIRED vs OPTIONAL, " +
        "and provide human-readable descriptions for each. Use web search or SDK documentation to gather accurate information " +
        "about parameter requirements and field purposes. Return your response as a structured JSON array.";
}

# User prompt for parameter field analysis
#
# + sdkName - SDK name (e.g., \"AWS S3 SDK\")
# + sdkVersion - SDK version
# + methodName - Method name being analyzed
# + parameterInfo - Formatted parameter and field information
# + return - User prompt for field analysis
public function getParameterFieldAnalysisUserPrompt(
        string sdkName,
        string sdkVersion,
        string methodName,
        string parameterInfo
) returns string {
    return string `Analyze the following method parameter fields from ${sdkName} version ${sdkVersion}.

Method: ${methodName}

Parameter Information:
${parameterInfo}

For each field in each parameter, determine:
1. **isRequired**: Whether the field is REQUIRED (true) or OPTIONAL (false) based on SDK documentation and web search
2. **description**: A clear, human-readable description (1-2 sentences) explaining the field's purpose and usage

Use web search or consult ${sdkName} documentation to ensure accuracy. Return a JSON array with this exact structure:

[
  {
    "parameterName": "paramName",
    "fields": [
      {
        "fieldName": "fieldName",
        "isRequired": true/false,
        "description": "Clear description of what this field does"
      }
    ]
  }
]

Return ONLY the JSON array, no additional text.`;
}

# System prompt for method description generation
#
# + return - System prompt for generating method descriptions
public function getMethodDescriptionSystemPrompt() returns string {
    return string `You are an expert technical writer specializing in SDK documentation.
        Generate clear, concise, human-readable descriptions for SDK methods and their parameters.
        Use web search and official documentation to ensure accuracy. Focus on practical usage and purpose.`;
}

# User prompt for method description generation
#
# + sdkName - SDK name
# + sdkVersion - SDK version  
# + methodName - Method name
# + methodSignature - Method signature with types
# + return - User prompt for method description
public function getMethodDescriptionUserPrompt(
        string sdkName,
        string sdkVersion,
        string methodName,
        string methodSignature
) returns string {
    return string `Generate documentation for this ${sdkName} v${sdkVersion} method.

Method: ${methodName}
Signature: ${methodSignature}

Provide a JSON object with:
1. **methodDescription**: Clear explanation (2-3 sentences) of what the method does and when to use it
2. **parameters**: Array of parameter descriptions

Use web search or ${sdkName} documentation for accuracy.

JSON format:
{
  "methodDescription": "Description of the method",
  "parameters": [
    {
      "parameterName": "name",
      "description": "What this parameter represents"
    }
  ]
}

Return ONLY the JSON object.`;
}

# System prompt for client class description
#
# + return - System prompt for generating client class description
public function getClientDescriptionSystemPrompt() returns string {
    return string `You are a technical writer. Generate a brief, simple description (1-2 sentences) of what a Java SDK client class does. Be concise and practical.`;
}

# User prompt for client class description
#
# + className - Simple class name
# + methodCount - Number of public methods
# + return - User prompt for client description
public function getClientDescriptionUserPrompt(string className, int methodCount) returns string {
    return string `Write a 1-2 sentence description of the ${className} client class. It has ${methodCount} public methods for SDK operations. Keep it simple and focus on what developers use it for.`;
}

# System prompt for method description
#
# + return - System prompt for generating method description
public function getMethodDescriptionSimpleSystemPrompt() returns string {
    return string `You are a technical writer. Generate a brief, simple description (1 sentence) of what a Java method does. Be concise and practical.`;
}

# User prompt for method description
#
# + methodName - Method name
# + returnType - Return type
# + return - User prompt for method description
public function getMethodDescriptionSimpleUserPrompt(string methodName, string returnType) returns string {
    return string `Write a 1 sentence description of what the ${methodName} method does. It returns ${returnType}. Keep it simple.`;
}

# System prompt for parameter description
#
# + return - System prompt for generating parameter description
public function getParameterDescriptionSystemPrompt() returns string {
    return string `You are a technical writer. Generate a brief description (1 sentence) of what a method parameter is used for. Be concise.`;
}

# User prompt for parameter description
#
# + paramName - Parameter name
# + paramType - Parameter type
# + return - User prompt for parameter description
public function getParameterDescriptionUserPrompt(string paramName, string paramType) returns string {
    return string `Write a 1 sentence description of what the ${paramName} parameter (type ${paramType}) is used for. Keep it simple.`;
}

# System prompt for field description
#
# + return - System prompt for generating field description
public function getFieldDescriptionSystemPrompt() returns string {
    return string `You are a technical writer. Generate a brief description (1 sentence) of what a request field is used for. Be concise and practical.`;
}

# User prompt for field description
#
# + fieldName - Field name
# + fieldType - Field type
# + isRequired - Whether field is required
# + return - User prompt for field description
public function getFieldDescriptionUserPrompt(string fieldName, string fieldType, boolean isRequired) returns string {
    string req = isRequired ? "required" : "optional";
    return string `Write a 1 sentence description of what the ${fieldName} field (type ${fieldType}, ${req}) is used for. Be practical.`;
}

# System prompt for field requirement analysis
#
# + return - System prompt for determining if fields are required
public function getFieldRequirementSystemPrompt() returns string {
    return string `You are an expert SDK analyzer. Analyze request object fields to determine if they are required or optional.
        Return ONLY a JSON array with format: [{\"field\":\"fieldName\",\"required\":true/false,\"reason\":\"brief explanation\"}].
        Required fields are those essential for the operation (IDs, keys, required parameters).
        Optional fields are configurations, metadata, or settings with sensible defaults.`;
}

# User prompt for field requirement analysis
#
# + methodName - Method name for context
# + parameterType - Parameter type name
# + fields - List of field names and types
# + return - User prompt for field requirement analysis
public function getFieldRequirementUserPrompt(string methodName, string parameterType, string fields) returns string {
    return string `
Analyze these fields from ${parameterType} used in method ${methodName}:

${fields}

For each field, determine if it's REQUIRED (essential for operation) or OPTIONAL (configuration/metadata).
Return JSON array only: [{"field":"fieldName","required":true/false,"reason":"brief explanation"}]`;
}

# System prompt for connection field LLM enrichment.
#
# + return - System prompt for enriching connection fields
public function getConnectionFieldEnrichmentSystemPrompt() returns string {
    return "You are an expert Java SDK analyzer with broad knowledge of Java SDK design patterns " +
        "across many vendors and ecosystems.\n\n" +
        "You will receive a list of builder/factory configuration fields extracted from a Java SDK client. " +
        "For EACH field produce a JSON object with EXACTLY these keys:\n\n" +
        "  name          (string)        — exact field name as given\n" +
        "  description   (string)        — developer-friendly description, 1-2 sentences\n" +
        "  isRequired    (boolean)       — true if essential for a basic connection, false otherwise\n" +
        "  ballerinaType (string)        — one of: string | int | boolean | enum | record | object | uri\n" +
        "  enumValues    (string[]|null) — for ballerinaType==\"enum\" ONLY: 3-8 representative constant " +
        "names. Omit SDK-internal sentinel values (UNKNOWN, UNRECOGNIZED, etc.). null for all other types.\n" +
        "  subFields     (object[]|null) — for ballerinaType==\"record\" ONLY: 2-6 key sub-fields as " +
        "[{\"name\":\"x\",\"type\":\"string\",\"description\":\"...\",\"isRequired\":false}]. null for all other types.\n\n" +
        "RULES:\n" +
        "- Use your knowledge of common SDK configuration patterns: endpoint, region, credentials,\n" +
        "  httpClient, retryPolicy, timeout, proxyConfig, transport, applicationName, etc.\n" +
        "- Infer the field purpose from the field name, Java type, and any provided typeContext.\n" +
        "- Do not assume any specific vendor or cloud provider — be accurate for whichever SDK is provided.\n" +
        "- Return ONLY a valid JSON array — no markdown fences, no commentary.";
}

# User prompt for connection field LLM enrichment.
#
# + sdkPackage - Root package of the SDK (e.g. software.amazon.awssdk.services.sqs)
# + clientSimpleName - Simple name of the root client class (e.g. SqsClient)
# + fields - All connection fields collected by collectBuilderSetters
# + return - User prompt for the LLM API call
public function getConnectionFieldEnrichmentUserPrompt(
        string sdkPackage,
        string clientSimpleName,
        ConnectionFieldInfo[] fields
) returns string {
    string header = "SDK package: " + sdkPackage + "\n" +
        "Client: " + clientSimpleName + "\n\n" +
        "Enrich the following " + fields.length().toString() +
        " connection/configuration fields:\n\n";

    string body = "";
    foreach int i in 0 ..< fields.length() {
        ConnectionFieldInfo f = fields[i];
        body += (i + 1).toString() + ". name: " + f.name + "\n";
        body += "   javaType: " + f.fullType + "\n";
        body += "   simpleType: " + f.typeName + "\n";

        string? ctx = f.level1Context;
        if ctx is string && ctx.trim().length() > 0 {
            body += "   typeContext: " + ctx + "\n";
        }

        string? existingDesc = f.description;
        if existingDesc is string && existingDesc.trim().length() > 0 {
            body += "   javadocHint: " + existingDesc + "\n";
        }
        body += "\n";
    }

    string footer =
        "Return a JSON array — one object per field IN THE SAME ORDER.\n" +
        "Required keys per object: name, description, isRequired, ballerinaType, enumValues, subFields.\n\n" +
        "Enum example (a geographic region selector — adapt values to the actual SDK):\n" +
        "{\"name\":\"region\",\"description\":\"Geographic region for the service endpoint.\",\"isRequired\":true," +
        "\"ballerinaType\":\"enum\",\"enumValues\":[\"US_EAST\",\"EU_WEST\",\"AP_SOUTHEAST\",\"US_WEST\"]," +
        "\"subFields\":null}\n\n" +
        "Record example (a credential configuration — adapt field names to the actual SDK):\n" +
        "{\"name\":\"credentials\",\"description\":\"Credentials used to authenticate requests.\"," +
        "\"isRequired\":false,\"ballerinaType\":\"record\",\"enumValues\":null,\"subFields\":[" +
        "{\"name\":\"clientId\",\"type\":\"string\",\"description\":\"Client identifier.\",\"isRequired\":true}," +
        "{\"name\":\"clientSecret\",\"type\":\"string\",\"description\":\"Client secret or key.\",\"isRequired\":true}]}\n\n" +
        "Return ONLY the JSON array.";

    return header + body + footer;
}
