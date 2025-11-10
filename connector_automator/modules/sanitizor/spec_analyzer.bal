import ballerina/data.jsondata;

// Helper function to extract API context (info section)
function extractApiContext(json spec) returns string {
    OpenAPISpec|error parsedSpec = jsondata:parseAsType(spec);
    if parsedSpec is error {
        return "API context not available";
    }
    string title = parsedSpec.info.title;
    string description = parsedSpec.info.description ?: "No description available";

    return string `API Title: ${title}\nAPI Description: ${description}`;
}

// Helper function to extract usage context (where schema is referenced)
function extractSchemaUsageContext(string schemaName, json spec) returns string {
    OpenAPISpec|error parsedSpec = jsondata:parseAsType(spec);
    if parsedSpec is error {
        return string `Schema ${schemaName} usage context not found`;
    }

    string[] usages = [];
    string refPattern = string `#/components/schemas/${schemaName}`;

    // Check paths for schema usage
    if parsedSpec.paths is map<PathItem> {
        map<PathItem> paths = <map<PathItem>>parsedSpec.paths;
        foreach string path in paths.keys() {
            PathItem pathItem = paths.get(path);
            string pathUsages = findSchemaUsageInPathItem(path, pathItem, refPattern);
            if pathUsages.length() > 0 {
                usages.push(pathUsages);
            }
        }
    }

    if (usages.length() > 0) {
        return string:'join("\n", ...usages);
    }
    return string `Schema '${schemaName}' usage context not found`;
}

// Helper function to collect description requests from schema
function collectDescriptionRequests(Schema schema, string schemaName, string pathPrefix,
        DescriptionRequest[] requests, map<string> locationMap, OpenAPISpec fullSpec) {
    // Check if schema itself needs description
    if schema.description is () {
        string requestId = generateRequestId(schemaName, pathPrefix, "schema");
        string context = string `Schema '${schemaName}' definition: ${schema.toJsonString()}`;
        requests.push({
            id: requestId,
            name: schemaName,
            context: context,
            schemaPath: pathPrefix.length() > 0 ? pathPrefix : schemaName
        });
        locationMap[requestId] = pathPrefix.length() > 0 ? pathPrefix : schemaName;
    }

    // Process properties
    if schema.properties is map<Schema> {
        map<Schema> properties = <map<Schema>>schema.properties;
        collectPropertyDescriptionRequests(properties, schemaName, pathPrefix, requests, locationMap, fullSpec);
    }

    // Process nested schemas (allOf, oneOf, anyOf)
    string[] nestedTypes = ["allOf", "oneOf", "anyOf"];
    foreach string nestedType in nestedTypes {
        Schema[]? nestedArray = ();
        if nestedType == "allOf" {
            nestedArray = schema.allOf;
        } else if nestedType == "oneOf" {
            nestedArray = schema.oneOf;
        } else if nestedType == "anyOf" {
            nestedArray = schema.anyOf;
        }
        if nestedArray is Schema[] {
            foreach int i in 0 ..< nestedArray.length() {
                Schema nestedSchema = nestedArray[i];
                string nestedPath = pathPrefix.length() > 0 ?
                    pathPrefix + "." + nestedType + "[" + i.toString() + "]" :
                    schemaName + "." + nestedType + "[" + i.toString() + "]";
                collectDescriptionRequests(nestedSchema, schemaName, nestedPath, requests, locationMap, fullSpec);
            }
        }
    }
}

// Helper function to collect property description requests
function collectPropertyDescriptionRequests(map<Schema> properties, string parentSchemaName, string pathPrefix,
        DescriptionRequest[] requests, map<string> locationMap, OpenAPISpec fullSpec) {
    foreach string propertyName in properties.keys() {
        Schema property = properties.get(propertyName);
        string propertyPath = pathPrefix.length() > 0 ?
            pathPrefix + ".properties." + propertyName :
            parentSchemaName + ".properties." + propertyName;

        // Check if property needs description (not $ref and no description)
        if property.description is () {
            string requestId = generateRequestId(parentSchemaName, propertyPath, "property");
            string context = string `Property '${propertyName}' in schema '${parentSchemaName}'. Property definition: ${property.toJsonString()}`;
            // add schema type infor to context for better IA understanding
            if property.'type is string {
                string propType = property.'type.toString();
                context += string ` Type: ${propType}`;
            }
            if property.'\$ref is () {
                string refValue = property.'\$ref.toString();
                context += string ` References: ${refValue}.`;
            }
            boolean isGenericRecord = false;
            if property.keys().length() == 0 {
                // Empty property definition = record {}
                isGenericRecord = true;
                context += " Generic record type - needs specific description.";
            }

            requests.push({
                id: requestId,
                name: propertyName,
                context: context,
                schemaPath: propertyPath
            });
            locationMap[requestId] = propertyPath;
        }

        // Recursively process nested properties
        if property.properties is map<Schema> {
            map<Schema> nestedProperties = <map<Schema>>property.properties;
            collectPropertyDescriptionRequests(nestedProperties, parentSchemaName, propertyPath, requests, locationMap, fullSpec);
        }

        // Process items for arrays
        if property.items is Schema {
            Schema items = <Schema>property.items;
            if items.properties is map<Schema> {
                map<Schema> itemProperties = <map<Schema>>items.properties;
                string itemPath = propertyPath + ".items";
                collectPropertyDescriptionRequests(itemProperties, parentSchemaName, itemPath, requests, locationMap, fullSpec);
            }
        }
    }
}

// Helper function to collect existing operationIds from paths
function collectExistingOperationIds(map<PathItem> paths, string[] existingOperationIds) {

    foreach string path in paths.keys() {
        PathItem pathItem = paths.get(path);
        Operation[] operations = getAllOperations(pathItem);

        foreach Operation op in operations {
            if op.operationId is string {
                existingOperationIds.push(<string>op.operationId);
            }
        }

    }
}

// Helper function to get all operations from a path item
function getAllOperations(PathItem pathItem) returns Operation[] {
    Operation[] operations = [];
    if pathItem.get is Operation {
        operations.push(<Operation>pathItem.get);
    }
    if pathItem.post is Operation {
        operations.push(<Operation>pathItem.post);
    }
    if pathItem.put is Operation {
        operations.push(<Operation>pathItem.put);
    }
    if pathItem.delete is Operation {
        operations.push(<Operation>pathItem.delete);
    }
    if pathItem.patch is Operation {
        operations.push(<Operation>pathItem.patch);
    }
    if pathItem.head is Operation {
        operations.push(<Operation>pathItem.head);
    }
    if pathItem.options is Operation {
        operations.push(<Operation>pathItem.options);
    }
    if pathItem.trace is Operation {
        operations.push(<Operation>pathItem.trace);
    }
    return operations;
}

// Helper function to collect missing operationId requests
function collectMissingOperationIdRequests(map<PathItem> paths, OperationIdRequest[] requests,
        map<string> locationMap, string apiContext) {
    string[] httpMethods = ["get", "post", "put", "delete", "patch", "head", "options", "trace"];

    foreach string path in paths.keys() {
        PathItem pathItem = paths.get(path);

        foreach string method in httpMethods {
            Operation? operation = getOperationByMethod(pathItem, method);
            if operation is Operation && operation.operationId is () {
                string requestId = generateOperationRequestId(path, method);
                string location = string `${path}.${method}`;

                OperationIdRequest request = {
                    id: requestId,
                    path: path,
                    method: method,
                    summary: operation.summary,
                    description: operation.description,
                    tags: operation.tags
                };

                requests.push(request);
                locationMap[requestId] = location;
            }
        }
    }
}

// Helper function to get operation by HTTP method
function getOperationByMethod(PathItem pathItem, string method) returns Operation? {
    match method {
        "get" => {
            return pathItem.get;
        }
        "post" => {
            return pathItem.post;
        }
        "put" => {
            return pathItem.put;
        }
        "delete" => {
            return pathItem.delete;
        }
        "patch" => {
            return pathItem.patch;
        }
        "head" => {
            return pathItem.head;
        }
        "options" => {
            return pathItem.options;
        }
        "trace" => {
            return pathItem.trace;
        }
        _ => {
            return ();
        }
    }
}

// Helper function to find schema usage in a path item
function findSchemaUsageInPathItem(string path, PathItem pathItem, string refPattern) returns string {
    string[] usages = [];
    Operation[] operations = getAllOperations(pathItem);

    foreach Operation operation in operations {
        // Check if this operation uses the schema in request/response
        if containsSchemaReference(operation, refPattern) {
            string operationDesc = operation.operationId ?: (operation.summary ?: string `${path}`);
            usages.push(string `- Used in: ${operationDesc}`);
        }
    }

    return string:'join("\n", ...usages);
}

function containsSchemaReference(Operation operation, string refPattern) returns boolean {
    // Check parameters
    if operation.parameters is Parameter[] {
        Parameter[] parameters = <Parameter[]>operation.parameters;
        foreach Parameter param in parameters {
            if param.schema is Schema {
                Schema schema = <Schema>param.schema;
                if schema.\$ref is string && (<string>schema.\$ref).includes(refPattern) {
                    return true;
                }
            }
        }
    }

    // Check responses
    if operation.responses is map<Response> {
        map<Response> responses = <map<Response>>operation.responses;
        foreach string responseCode in responses.keys() {
            Response response = responses.get(responseCode);
            if response.content is map<MediaType> {
                map<MediaType> content = <map<MediaType>>response.content;
                foreach string contentType in content.keys() {
                    MediaType mediaType = content.get(contentType);
                    if mediaType.schema is Schema {
                        Schema schema = <Schema>mediaType.schema;
                        if schema.\$ref is string && (<string>schema.\$ref).includes(refPattern) {
                            return true;
                        }
                    }
                }
            }
        }
    }

    return false;
}

// Helper function to collect parameter description requests
function collectParameterDescriptionRequests(json spec, DescriptionRequest[] requests, map<string> locationMap) {
    OpenAPISpec|error parsedSpec = jsondata:parseAsType(spec);
    if parsedSpec is error {
        return;
    }
    if parsedSpec.paths is map<PathItem> {
        map<PathItem> paths = <map<PathItem>>parsedSpec.paths;
        foreach string path in paths.keys() {
            PathItem pathItem = paths.get(path);
            Operation[] operations = getAllOperations(pathItem);

            foreach Operation operation in operations {
                string method = getMethodForOperation(pathItem, operation);
                if operation.parameters is Parameter[] {
                    Parameter[] parameters = <Parameter[]>operation.parameters;

                    foreach Parameter param in parameters {
                        string paramIn = param.'in ?: "unknown";
                        if paramIn == "unknown" {
                            continue;
                        }
                        boolean needsDescription = param.description is () ||
                            (param.description is string && (<string>param.description).trim().length() == 0);

                        if needsDescription {
                            string operationId = operation.operationId ?: string `${method.toUpperAscii()} ${path}`;
                            string requestId = generateRequestId("param", string `${path}_${method}_${param.name}`, "parameter");
                            string context = string `${paramIn} parameter '${param.name}' for operation: ${operationId}. Parameter definition: ${param.toJsonString()}`;

                            // Add schema type info for better context
                            if param.schema is Schema {
                                Schema schema = <Schema>param.schema;
                                if schema.'type is string {
                                    string paramType = <string>schema.'type;
                                    context += string ` Type: ${paramType}.`;
                                }
                                if schema.'enum is json[] {
                                    json[] enumValues = <json[]>schema.'enum;
                                    context += string ` Allowed values: ${enumValues.toString()}.`;
                                }
                            }

                            // Add required/optional info
                            boolean isRequired = param.required ?: false;
                            context += string ` Required: ${isRequired}.`;

                            requests.push({
                                id: requestId,
                                name: param.name,
                                context: context,
                                schemaPath: string `paths.${path}.${method}.parameters[name=${param.name}]`
                            });
                            locationMap[requestId] = string `paths.${path}.${method}.parameters[name=${param.name}]`;
                        }
                    }
                }
            }
        }
    }
}

// Helper function to get HTTP method for an operation
function getMethodForOperation(PathItem pathItem, Operation targetOperation) returns string {
    if pathItem.get == targetOperation {
        return "get";
    }
    if pathItem.post == targetOperation {
        return "post";
    }
    if pathItem.put == targetOperation {
        return "put";
    }
    if pathItem.delete == targetOperation {
        return "delete";
    }
    if pathItem.patch == targetOperation {
        return "patch";
    }
    if pathItem.head == targetOperation {
        return "head";
    }
    if pathItem.options == targetOperation {
        return "options";
    }
    if pathItem.trace == targetOperation {
        return "trace";
    }
    return "unknown";
}

// Helper function to collect operation description requests
function collectOperationDescriptionRequests(json spec, DescriptionRequest[] requests, map<string> locationMap) {
    OpenAPISpec|error parsedSpec = jsondata:parseAsType(spec);
    if parsedSpec is error {
        return;
    }

    if parsedSpec.paths is map<PathItem> {
        map<PathItem> paths = <map<PathItem>>parsedSpec.paths;
        foreach string path in paths.keys() {
            PathItem pathItem = paths.get(path);
            Operation[] operations = getAllOperations(pathItem);

            foreach Operation operation in operations {
                string method = getMethodForOperation(pathItem, operation);

                // Check if operation needs description
                if operation.description is () {
                    string operationId = operation.operationId ?: string `${method.toUpperAscii()} ${path}`;
                    string summary = operation.summary ?: "";

                    string requestId = generateRequestId("operation", string `${path}_${method}`, "description");
                    string context = string `Operation '${operationId}' (${method.toUpperAscii()} ${path})`;
                    if summary.length() > 0 {
                        context += string `. Summary: ${summary}`;
                    }
                    context += ". This description will be used for the return parameter documentation in the generated client.";

                    // Add response info for context
                    if operation.responses is map<Response> {
                        map<Response> responses = <map<Response>>operation.responses;
                        string[] responseCodes = responses.keys().clone();
                        if responseCodes.length() > 0 {
                            context += string ` Response codes: ${string:'join(", ", ...responseCodes)}.`;
                        }
                    }

                    requests.push({
                        id: requestId,
                        name: operationId,
                        context: context,
                        schemaPath: string `paths.${path}.${method}`
                    });
                    locationMap[requestId] = string `paths.${path}.${method}`;
                }

                // Check for empty response descriptions
                if operation.responses is map<Response> {
                    map<Response> responses = <map<Response>>operation.responses;
                    foreach string responseCode in responses.keys() {
                        Response response = responses.get(responseCode);

                        // Check if response has missing or empty description
                        boolean needsDescription = response.description is () ||
                            (response.description is string && (<string>response.description).trim().length() == 0);

                        if needsDescription {
                            // Try to get from referenced schema
                            string? schemaDescription = getReferencedSchemaDescription(response, parsedSpec);

                            string operationId = operation.operationId ?: string `${method.toUpperAscii()} ${path}`;
                            string summary = operation.summary ?: "";

                            string requestId = generateRequestId("response", string `${path}_${method}_${responseCode}`, "description");
                            string context = string `Response description for ${responseCode} status in operation '${operationId}' (${method.toUpperAscii()} ${path}).`;
                            if summary.length() > 0 {
                                context += string ` Operation summary: ${summary}.`;
                            }
                            if schemaDescription is string {
                                context += string ` Referenced schema description: "${schemaDescription}".`;
                            }
                            context += " Generate a response-specific description that explains what this HTTP response represents.";

                            requests.push({
                                id: requestId,
                                name: string `${operationId}_${responseCode}_Response`,
                                context: context,
                                schemaPath: string `paths.${path}.${method}.responses.${responseCode}.description`
                            });
                            locationMap[requestId] = string `paths.${path}.${method}.responses.${responseCode}.description`;
                        }
                    }
                }
            }
        }
    }
}

// Helper function to get description from referenced schema
function getReferencedSchemaDescription(Response response, OpenAPISpec spec) returns string? {
    if response.content is map<MediaType> {
        map<MediaType> content = <map<MediaType>>response.content;

        // Check common content types
        string[] contentTypes = ["application/json", "application/xml", "text/plain", "*/*"];
        foreach string contentType in contentTypes {
            if content.hasKey(contentType) {
                MediaType mediaType = content.get(contentType);

                if mediaType.schema is Schema {
                    Schema schema = <Schema>mediaType.schema;

                    if schema.\$ref is string {
                        string refValue = <string>schema.\$ref;
                        if refValue.startsWith("#/components/schemas/") {
                            string schemaName = refValue.substring(21); // Remove "#/components/schemas/"
                            return getSchemaDescriptionFromSpec(schemaName, spec);
                        }
                    } else if schema.description is string {
                        string desc = <string>schema.description;
                        if desc.trim().length() > 0 {
                            return desc;
                        }
                    }
                }
            }
        }
    }
    return ();
}

// Helper function to get schema description from components/schemas
function getSchemaDescriptionFromSpec(string schemaName, OpenAPISpec spec) returns string? {
    Components? components = spec.components;
    if components is Components {
        map<Schema>? schemas = components.schemas;
        if schemas is map<Schema> {
            if schemas.hasKey(schemaName) {
                Schema schema = schemas.get(schemaName);
                if schema.description is string {
                    string desc = <string>schema.description;
                    if desc.trim().length() > 0 {
                        return desc;
                    }
                }
            }
        }
    }
    return ();
}
