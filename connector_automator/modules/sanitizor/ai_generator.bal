import connector_automator.utils;

public function generateDescriptionsBatch(DescriptionRequest[] requests, string apiContext) returns BatchDescriptionResponse[]|LLMServiceError {
    if !utils:isAIServiceInitialized() {
        return error LLMServiceError("LLM service not initialized");
    }

    if requests.length() == 0 {
        return [];
    }

    // Build batch prompt with enhanced categorization
    string requestsSection = "";
    foreach int i in 0 ..< requests.length() {
        DescriptionRequest req = requests[i];
        string requestType = "field";
        if req.schemaPath.startsWith("paths.") && req.schemaPath.includes("parameters[name=") {
            requestType = "parameter";
        } else if req.schemaPath.startsWith("paths.") && !req.schemaPath.includes(".properties.") {
            requestType = "operation";
        }

        requestsSection += string `
${i + 1}. ID: ${req.id}
   Type: ${requestType}
   Name: ${req.name}
   Path: ${req.schemaPath}
   Context: ${req.context}
`;
    }

    string prompt = string `You are an API documentation expert. Generate concise, professional descriptions for the following API elements.

API CONTEXT:
${apiContext}

REQUESTS TO PROCESS:
${requestsSection}

INSTRUCTIONS:
1. For FIELD descriptions: Describe what the field represents (under 80 characters)
2. For PARAMETER descriptions: Explain the parameter's purpose (under 100 characters)
3. For OPERATION descriptions: Describe what the operation returns (under 120 characters, suitable for return parameter docs)
4. Use professional API documentation language
5. Consider the API context and element context
6. Return responses in the exact JSON format shown below
7. Do not include fenced code blocks in the response
8. Keep descriptions concise but informative

REQUIRED RESPONSE FORMAT (JSON):
{
  "descriptions": [
    {
      "id": "request_id_1",
      "description": "Generated description text"
    },
    {
      "id": "request_id_2", 
      "description": "Generated description text"
    }
  ]
}`;

    string|error response = utils:callAI(prompt);
    if response is error {
        return error LLMServiceError("Failed to generate batch descriptions", response);
    }

    // Parse JSON response
    json|error jsonResult = response.fromJsonString();
    if jsonResult is error {
        return error LLMServiceError("Failed to parse batch response JSON", jsonResult);
    }

    if jsonResult is map<json> && jsonResult.hasKey("descriptions") {
        json descriptionsJson = jsonResult.get("descriptions");
        if descriptionsJson is json[] {
            BatchDescriptionResponse[] results = [];
            foreach json desc in descriptionsJson {
                if desc is map<json> {
                    string? id = desc.get("id") is string ? <string>desc.get("id") : ();
                    string? description = desc.get("description") is string ? <string>desc.get("description") : ();
                    if id is string && description is string {
                        results.push({id: id, description: description.trim()});
                    }
                }
            }
            return results;
        }
    }
    return error LLMServiceError("Invalid batch response format");
}

// Process multiple operationId requests in a single LLM call
public function generateOperationIdsBatch(OperationIdRequest[] requests, string apiContext, string[] existingOperationIds) returns BatchOperationIdResponse[]|LLMServiceError {
    if !utils:isAIServiceInitialized() {
        return error LLMServiceError("LLM service not initialized");
    }

    if requests.length() == 0 {
        return [];
    }

    string requestsSection = "";
    foreach int i in 0 ..< requests.length() {
        OperationIdRequest req = requests[i];
        string tags = req.tags is string[] ? string:'join(", ", ...<string[]>req.tags) : "N/A";
        requestsSection += string `
${i + 1}. ID: ${req.id}
   Path: ${req.path}
   Method: ${req.method.toUpperAscii()}
   Summary: ${req.summary ?: "N/A"}
   Description: ${req.description ?: "N/A"}
   Tags: ${tags}
`;
    }

    string existingIdsStr = string:'join(", ", ...existingOperationIds);

    string prompt = string `You are an expert in REST API design. Generate meaningful, unique camelCase operationIds for these API operations.

API CONTEXT:
${apiContext}

EXISTING OPERATION IDS (avoid conflicts):
${existingIdsStr}

OPERATIONS TO NAME:
${requestsSection}

REQUIREMENTS:
- Use camelCase (e.g., getUserProfile, createPlaylist, updateUserSettings)
- Be descriptive and follow REST conventions (get*, create*, update*, delete*, list*)
- Ensure operationIds are unique and don't conflict with existing ones
- Consider HTTP method, path, and operation purpose
- Keep names concise but clear (prefer verbs + nouns)
- Do not include fenced code blocks in the response

REQUIRED RESPONSE FORMAT (JSON):
{
  "operationIds": [
    {
      "id": "request_id_1",
      "operationId": "getUserProfile"
    },
    {
      "id": "request_id_2",
      "operationId": "createPlaylist"
    }
  ]
}`;

    string|error response = utils:callAI(prompt);
    if response is error {
        return error LLMServiceError("Failed to generate batch operationIds", response);
    }

    json|error jsonResult = response.fromJsonString();
    if jsonResult is error {
        return error LLMServiceError("Failed to parse batch operationId response JSON", jsonResult);
    }

    if jsonResult is map<json> && jsonResult.hasKey("operationIds") {
        json operationIdsJson = jsonResult.get("operationIds");
        if operationIdsJson is json[] {
            BatchOperationIdResponse[] results = [];
            foreach json opId in operationIdsJson {
                if opId is map<json> {
                    string? id = opId.get("id") is string ? <string>opId.get("id") : ();
                    string? operationId = opId.get("operationId") is string ? <string>opId.get("operationId") : ();
                    if id is string && operationId is string {
                        results.push({id: id, operationId: operationId.trim()});
                    }
                }
            }
            return results;
        }
    }
    return error LLMServiceError("Invalid batch operationId response format");
}

public function generateSchemaNamesBatch(SchemaRenameRequest[] requests, string apiContext, string[] existingNames) returns BatchRenameResponse[]|LLMServiceError {
    if !utils:isAIServiceInitialized() {
        return error LLMServiceError("LLM service not initialized");
    }

    if requests.length() == 0 {
        return [];
    }

    string requestsSection = "";
    foreach int i in 0 ..< requests.length() {
        SchemaRenameRequest req = requests[i];
        requestsSection += string `
${i + 1}. Original: ${req.originalName}
   Definition: ${req.schemaDefinition}
   Usage: ${req.usageContext}
`;
    }

    string existingNamesStr = string:'join(", ", ...existingNames);

    string prompt = string `You are an expert in naming OpenAPI schemas. Generate meaningful, unique PascalCase names for these schemas.

API CONTEXT:
${apiContext}

EXISTING SCHEMA NAMES (avoid conflicts):
${existingNamesStr}

SCHEMAS TO RENAME:
${requestsSection}

REQUIREMENTS:
- Use PascalCase (e.g., UserProfile, AttachmentResponse)
- Be descriptive but concise (2-3 words max)
- Ensure names are unique and don't conflict with existing names
- Consider schema role (Request, Response, List, Details, etc.)
- Do not include fenced code blocks in the response. 

REQUIRED RESPONSE FORMAT (JSON):
{
  "renames": [
    {
      "originalName": "InlineResponse200",
      "newName": "UserListResponse"
    },
    {
      "originalName": "InlineResponse201",
      "newName": "CreateUserResponse"
    }
  ]
}`;

    string|error response = utils:callAI(prompt);
    if response is error {
        return error LLMServiceError("Failed to generate batch schema names", response);
    }

    json|error jsonResult = response.fromJsonString();
    if jsonResult is error {
        return error LLMServiceError("Failed to parse batch rename response JSON", jsonResult);
    }

    if jsonResult is map<json> && jsonResult.hasKey("renames") {
        json renamesJson = jsonResult.get("renames");
        if renamesJson is json[] {
            BatchRenameResponse[] results = [];
            foreach json rename in renamesJson {
                if rename is map<json> {
                    string? originalName = rename.get("originalName") is string ? <string>rename.get("originalName") : ();
                    string? newName = rename.get("newName") is string ? <string>rename.get("newName") : ();
                    if originalName is string && newName is string {
                        results.push({originalName: originalName, newName: newName.trim()});
                    }
                }
            }
            return results;
        }
    }
    return error LLMServiceError("Invalid batch rename response format");
}
