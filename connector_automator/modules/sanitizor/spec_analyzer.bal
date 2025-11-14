// Helper function to extract API context (info section)
function extractApiContext(json spec) returns string {
    if (spec is map<json>) {
        json|error infoResult = spec.get("info");
        if (infoResult is map<json>) {
            map<json> infoMap = <map<json>>infoResult;

            string title = "Unknown API";
            if (infoMap.hasKey("title") && infoMap.get("title") is string) {
                title = <string>infoMap.get("title");
            }

            string description = "";
            if (infoMap.hasKey("description") && infoMap.get("description") is string) {
                description = <string>infoMap.get("description");
            }

            // Truncate description if too long to avoid token limits
            if (description.length() > 1000) {
                description = description.substring(0, 1000) + "...";
            }

            return string `API: ${title}
Description: ${description}`;
        }
    }
    return "API context not available";
}

// Helper function to extract usage context (where schema is referenced)
function extractSchemaUsageContext(string schemaName, json spec) returns string {
    string[] usages = [];
    string refPattern = string `#/components/schemas/${schemaName}`;

    if (spec is map<json>) {
        // Check paths for usage
        json|error pathsResult = spec.get("paths");
        if (pathsResult is map<json>) {
            map<json> paths = <map<json>>pathsResult;
            foreach string path in paths.keys() {
                json|error pathItem = paths.get(path);
                if (pathItem is map<json>) {
                    string pathUsages = findSchemaUsageInPathItem(path, <map<json>>pathItem, refPattern);
                    if (pathUsages.length() > 0) {
                        usages.push(pathUsages);
                    }
                }
            }
        }
    }

    if (usages.length() > 0) {
        return string:'join("\n", ...usages);
    }
    return string `Schema '${schemaName}' usage context not found`;
}

// Helper function to collect description requests from schema
function collectDescriptionRequests(map<json> schemaMap, string schemaName, string pathPrefix,
        DescriptionRequest[] requests, map<string> locationMap, json fullSpec) {
    // Check if schema itself needs description
    if !schemaMap.hasKey("description") {
        string requestId = generateRequestId(schemaName, pathPrefix, "schema");
        string context = string `Schema '${schemaName}' definition: ${schemaMap.toString()}`;
        requests.push({
            id: requestId,
            name: schemaName,
            context: context,
            schemaPath: pathPrefix.length() > 0 ? pathPrefix : schemaName
        });
        locationMap[requestId] = pathPrefix.length() > 0 ? pathPrefix : schemaName;
    }

    // Process properties
    if schemaMap.hasKey("properties") {
        json|error propertiesResult = schemaMap.get("properties");
        if propertiesResult is map<json> {
            map<json> properties = <map<json>>propertiesResult;
            collectPropertyDescriptionRequests(properties, schemaName, pathPrefix, requests, locationMap, fullSpec);
        }
    }

    // Process nested schemas (allOf, oneOf, anyOf)
    string[] nestedTypes = ["allOf", "oneOf", "anyOf"];
    foreach string nestedType in nestedTypes {
        if schemaMap.hasKey(nestedType) {
            json|error nestedResult = schemaMap.get(nestedType);
            if nestedResult is json[] {
                json[] nestedArray = nestedResult;
                foreach int i in 0 ..< nestedArray.length() {
                    json nestedItem = nestedArray[i];
                    if nestedItem is map<json> {
                        map<json> nestedItemMap = <map<json>>nestedItem;
                        string nestedPath = pathPrefix.length() > 0 ?
                            pathPrefix + "." + nestedType + "[" + i.toString() + "]" :
                            schemaName + "." + nestedType + "[" + i.toString() + "]";
                        collectDescriptionRequests(nestedItemMap, schemaName, nestedPath, requests, locationMap, fullSpec);
                    }
                }
            }
        }
    }
}

// Helper function to collect property description requests
function collectPropertyDescriptionRequests(map<json> properties, string parentSchemaName, string pathPrefix,
        DescriptionRequest[] requests, map<string> locationMap, json fullSpec) {
    foreach string propertyName in properties.keys() {
        json|error propertyResult = properties.get(propertyName);
        if propertyResult is map<json> {
            map<json> propertyMap = <map<json>>propertyResult;
            string propertyPath = pathPrefix.length() > 0 ?
                pathPrefix + ".properties." + propertyName :
                parentSchemaName + ".properties." + propertyName;

            // Check if property needs description (not $ref and no description)
            if !propertyMap.hasKey("description") {
                string requestId = generateRequestId(parentSchemaName, propertyPath, "property");
                string context = string `Property '${propertyName}' in schema '${parentSchemaName}'. Property definition: ${propertyMap.toString()}`;
                // add schema type infor to context for better IA understanding
                if propertyMap.hasKey("type") {
                    string propType = propertyMap.get("type").toString();
                    context += string ` Type: ${propType}`;
                }
                if propertyMap.hasKey("$ref") {
                    string refValue = propertyMap.get("$ref").toString();
                    context += string ` References: ${refValue}.`;
                }
                boolean isGenericRecord = false;
                if propertyMap.keys().length() == 0 {
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
            if propertyMap.hasKey("properties") {
                json|error nestedPropertiesResult = propertyMap.get("properties");
                if nestedPropertiesResult is map<json> {
                    map<json> nestedProperties = <map<json>>nestedPropertiesResult;
                    collectPropertyDescriptionRequests(nestedProperties, parentSchemaName, propertyPath, requests, locationMap, fullSpec);
                }
            }

            // Process items for arrays
            if propertyMap.hasKey("items") {
                json|error itemsResult = propertyMap.get("items");
                if itemsResult is map<json> {
                    map<json> items = <map<json>>itemsResult;
                    if items.hasKey("properties") {
                        json|error itemPropertiesResult = items.get("properties");
                        if itemPropertiesResult is map<json> {
                            map<json> itemProperties = <map<json>>itemPropertiesResult;
                            string itemPath = propertyPath + ".items";
                            collectPropertyDescriptionRequests(itemProperties, parentSchemaName, itemPath, requests, locationMap, fullSpec);
                        }
                    }
                }
            }
        }
    }
}

// Helper function to collect existing operationIds from paths
function collectExistingOperationIds(map<json> paths, string[] existingOperationIds) {
    string[] httpMethods = ["get", "post", "put", "delete", "patch", "head", "options", "trace"];

    foreach string path in paths.keys() {
        json|error pathItem = paths.get(path);
        if pathItem is map<json> {
            map<json> pathItemMap = <map<json>>pathItem;

            foreach string method in httpMethods {
                if pathItemMap.hasKey(method) {
                    json|error operation = pathItemMap.get(method);
                    if operation is map<json> {
                        map<json> operationMap = <map<json>>operation;
                        if operationMap.hasKey("operationId") {
                            json|error operationIdResult = operationMap.get("operationId");
                            if operationIdResult is string {
                                existingOperationIds.push(<string>operationIdResult);
                            }
                        }
                    }
                }
            }
        }
    }
}

// Helper function to collect missing operationId requests
function collectMissingOperationIdRequests(map<json> paths, OperationIdRequest[] requests,
        map<string> locationMap, string apiContext) {
    string[] httpMethods = ["get", "post", "put", "delete", "patch", "head", "options", "trace"];

    foreach string path in paths.keys() {
        json|error pathItem = paths.get(path);
        if pathItem is map<json> {
            map<json> pathItemMap = <map<json>>pathItem;

            foreach string method in httpMethods {
                if pathItemMap.hasKey(method) {
                    json|error operationResult = pathItemMap.get(method);
                    if operationResult is map<json> {
                        map<json> operation = <map<json>>operationResult;

                        // Check if operationId is missing
                        if !operation.hasKey("operationId") {
                            string requestId = generateOperationRequestId(path, method);
                            string location = string `${path}.${method}`;

                            // Safely extract optional fields
                            string? summary = ();
                            if operation.hasKey("summary") {
                                json summaryJson = operation.get("summary");
                                if summaryJson is string {
                                    summary = summaryJson;
                                }
                            }

                            string? description = ();
                            if operation.hasKey("description") {
                                json descriptionJson = operation.get("description");
                                if descriptionJson is string {
                                    description = descriptionJson;
                                }
                            }

                            string[]? tags = ();
                            if operation.hasKey("tags") {
                                json tagsJson = operation.get("tags");
                                if tagsJson is json[] {
                                    string[] tagStrings = [];
                                    foreach json tag in tagsJson {
                                        if tag is string {
                                            tagStrings.push(tag);
                                        }
                                    }
                                    if tagStrings.length() > 0 {
                                        tags = tagStrings;
                                    }
                                }
                            }

                            OperationIdRequest request = {
                                id: requestId,
                                path: path,
                                method: method,
                                summary: summary,
                                description: description,
                                tags: tags
                            };

                            requests.push(request);
                            locationMap[requestId] = location;
                        }
                    }
                }
            }
        }
    }
}

// Helper function to find schema usage in a path item
function findSchemaUsageInPathItem(string path, map<json> pathItem, string refPattern) returns string {
    string[] usages = [];

    // Define the possible HTTP methods to check for
    string[] possibleMethods = ["get", "post", "put", "delete", "patch", "head", "options", "trace"];

    // Dynamically check what methods are actually available in this path item
    foreach string method in possibleMethods {
        if (pathItem.hasKey(method)) {
            json|error operationResult = pathItem.get(method);
            if (operationResult is map<json>) {
                map<json> operation = <map<json>>operationResult;

                // Check if this operation uses the schema in request/response
                if (containsSchemaReference(operation, refPattern)) {
                    string? operationId = operation.get("operationId") is string ? <string>operation.get("operationId") : ();
                    string? summary = operation.get("summary") is string ? <string>operation.get("summary") : ();

                    string operationDesc = operationId ?: (summary ?: string `${method.toUpperAscii()} ${path}`);
                    usages.push(string `- Used in: ${operationDesc}`);
                }
            }
        }
    }

    return string:'join("\n", ...usages);
}

function containsSchemaReference(json data, string refPattern) returns boolean {
    if (data is map<json>) {
        foreach string key in data.keys() {
            json|error value = data.get(key);
            if (value is json) {
                if (key == "$ref" && value is string && (<string>value).includes(refPattern)) {
                    return true;
                }
                if (containsSchemaReference(value, refPattern)) {
                    return true;
                }
            }
        }
    } else if (data is json[]) {
        foreach json item in data {
            if (containsSchemaReference(item, refPattern)) {
                return true;
            }
        }
    }
    return false;
}

// Helper function to collect parameter description requests
function collectParameterDescriptionRequests(json spec, DescriptionRequest[] requests, map<string> locationMap) {
    json|error pathsResult = spec.paths;
    if pathsResult is map<json> {
        foreach string path in pathsResult.keys() {
            json|error pathResult = pathsResult.get(path);
            if pathResult is map<json> {
                map<json> pathItem = <map<json>>pathResult;
                string[] httpMethods = ["get", "post", "put", "delete", "patch", "head", "options", "trace"];

                foreach string method in httpMethods {
                    if pathItem.hasKey(method) {
                        json|error operationResult = pathItem.get(method);
                        if operationResult is map<json> {
                            map<json> operation = <map<json>>operationResult;

                            // Process parameters array if it exists and is not empty
                            if operation.hasKey("parameters") {
                                json|error parametersResult = operation.get("parameters");
                                if parametersResult is json[] {
                                    json[] parametersArray = parametersResult;

                                    // Only process if parameters array has content
                                    if parametersArray.length() > 0 {
                                        foreach json param in parametersArray {
                                            if param is map<json> {
                                                map<json> paramMap = <map<json>>param;

                                                // Only check if parameter completely lacks description
                                                boolean needsDescription = false;

                                                if !paramMap.hasKey("description") {
                                                    needsDescription = true;
                                                } else {
                                                    json|error descResult = paramMap.get("description");
                                                    if descResult is string {
                                                        string currentDescription = <string>descResult;
                                                        // Only flag if description is truly empty
                                                        if currentDescription.trim().length() == 0 {
                                                            needsDescription = true;
                                                        }
                                                    }
                                                }

                                                if needsDescription && paramMap.hasKey("name") {
                                                    string paramName = <string>paramMap.get("name");
                                                    string paramIn = paramMap.hasKey("in") ? <string>paramMap.get("in") : "query";
                                                    string operationId = operation.hasKey("operationId") ? <string>operation.get("operationId") : string `${method.toUpperAscii()} ${path}`;

                                                    string requestId = generateRequestId("param", string `${path}_${method}_${paramName}`, "parameter");
                                                    string context = string `${paramIn} parameter '${paramName}' for operation: ${operationId}. Parameter definition: ${paramMap.toString()}`;

                                                    // Add schema type info for better context
                                                    if paramMap.hasKey("schema") {
                                                        json|error schemaResult = paramMap.get("schema");
                                                        if schemaResult is map<json> {
                                                            map<json> schema = <map<json>>schemaResult;
                                                            if schema.hasKey("type") {
                                                                string paramType = <string>schema.get("type");
                                                                context += string ` Type: ${paramType}.`;
                                                            }
                                                            if schema.hasKey("enum") {
                                                                json enumValues = schema.get("enum");
                                                                context += string ` Allowed values: ${enumValues.toString()}.`;
                                                            }
                                                            if schema.hasKey("minimum") {
                                                                context += string ` Minimum: ${schema.get("minimum").toString()}.`;
                                                            }
                                                            if schema.hasKey("maximum") {
                                                                context += string ` Maximum: ${schema.get("maximum").toString()}.`;
                                                            }
                                                            if schema.hasKey("pattern") {
                                                                context += string ` Pattern: ${schema.get("pattern").toString()}.`;
                                                            }
                                                        }
                                                    }

                                                    // Add required/optional info
                                                    boolean isRequired = paramMap.hasKey("required") && paramMap.get("required") == true;
                                                    context += string ` Required: ${isRequired}.`;

                                                    requests.push({
                                                        id: requestId,
                                                        name: paramName,
                                                        context: context,
                                                        schemaPath: string `paths.${path}.${method}.parameters[name=${paramName}]`
                                                    });
                                                    locationMap[requestId] = string `paths.${path}.${method}.parameters[name=${paramName}]`;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// Helper function to collect operation description requests (for client return parameters)
function collectOperationDescriptionRequests(json spec, DescriptionRequest[] requests, map<string> locationMap) {
    json|error pathsResult = spec.paths;
    if pathsResult is map<json> {
        foreach string path in pathsResult.keys() {
            json|error pathResult = pathsResult.get(path);
            if pathResult is map<json> {
                map<json> pathItem = <map<json>>pathResult;
                string[] httpMethods = ["get", "post", "put", "delete", "patch", "head", "options", "trace"];

                foreach string method in httpMethods {
                    if pathItem.hasKey(method) {
                        json|error operationResult = pathItem.get(method);
                        if operationResult is map<json> {
                            map<json> operation = <map<json>>operationResult;

                            // Check if operation needs description (this becomes return parameter description)
                            if !operation.hasKey("description") {
                                string operationId = operation.hasKey("operationId") ? <string>operation.get("operationId") : string `${method.toUpperAscii()} ${path}`;
                                string summary = operation.hasKey("summary") ? <string>operation.get("summary") : "";

                                string requestId = generateRequestId("operation", string `${path}_${method}`, "description");
                                string context = string `Operation '${operationId}' (${method.toUpperAscii()} ${path})`;
                                if summary.length() > 0 {
                                    context += string `. Summary: ${summary}`;
                                }
                                context += ". This description will be used for the return parameter documentation in the generated client.";

                                // Add response info for context
                                if operation.hasKey("responses") {
                                    json|error responsesResult = operation.get("responses");
                                    if responsesResult is map<json> {
                                        string[] responseCodes = [];
                                        foreach string code in responsesResult.keys() {
                                            responseCodes.push(code);
                                        }
                                        if responseCodes.length() > 0 {
                                            context += string ` Response codes: ${string:'join(", ", ...responseCodes)}.`;
                                        }
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

                            // NEW: Check for empty response descriptions
                            if operation.hasKey("responses") {
                                json|error responsesResult = operation.get("responses");
                                if responsesResult is map<json> {
                                    map<json> responses = <map<json>>responsesResult;

                                    foreach string responseCode in responses.keys() {
                                        json|error responseResult = responses.get(responseCode);
                                        if responseResult is map<json> {
                                            map<json> response = <map<json>>responseResult;

                                            // Check if response has empty description
                                            if response.hasKey("description") {
                                                json|error descResult = response.get("description");
                                                if descResult is string && (<string>descResult).trim().length() == 0 {
                                                    // Found empty description, try to get from referenced schema
                                                    string? schemaDescription = getReferencedSchemaDescription(response, spec);

                                                    if schemaDescription is string {
                                                        // We have a schema description to use, create AI request for better response-specific description
                                                        string operationId = operation.hasKey("operationId") ? <string>operation.get("operationId") : string `${method.toUpperAscii()} ${path}`;
                                                        string summary = operation.hasKey("summary") ? <string>operation.get("summary") : "";

                                                        string requestId = generateRequestId("response", string `${path}_${method}_${responseCode}`, "description");
                                                        string context = string `Response description for ${responseCode} status in operation '${operationId}' (${method.toUpperAscii()} ${path}).`;
                                                        if summary.length() > 0 {
                                                            context += string ` Operation summary: ${summary}.`;
                                                        }
                                                        context += string ` Referenced schema description: "${schemaDescription}".`;
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
                        }
                    }
                }
            }
        }
    }
}

// Helper function to get description from referenced schema
function getReferencedSchemaDescription(map<json> response, json spec) returns string? {
    if response.hasKey("content") {
        json|error contentResult = response.get("content");
        if contentResult is map<json> {
            map<json> content = <map<json>>contentResult;

            // Check common content types
            string[] contentTypes = ["application/json", "application/xml", "text/plain", "*/*"];
            foreach string contentType in contentTypes {
                if content.hasKey(contentType) {
                    json|error mediaTypeResult = content.get(contentType);
                    if mediaTypeResult is map<json> {
                        map<json> mediaType = <map<json>>mediaTypeResult;

                        if mediaType.hasKey("schema") {
                            json|error schemaResult = mediaType.get("schema");
                            if schemaResult is map<json> {
                                map<json> schema = <map<json>>schemaResult;

                                if schema.hasKey("$ref") {
                                    string? refValue = schema.get("$ref") is string ? <string>schema.get("$ref") : ();
                                    if refValue is string && refValue.startsWith("#/components/schemas/") {
                                        string schemaName = refValue.substring(21); // Remove "#/components/schemas/"
                                        return getSchemaDescriptionFromSpec(schemaName, spec);
                                    }
                                } else if schema.hasKey("description") {
                                    string? desc = schema.get("description") is string ? <string>schema.get("description") : ();
                                    if desc is string && desc.trim().length() > 0 {
                                        return desc;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return ();
}

// Helper function to get schema description from components/schemas
function getSchemaDescriptionFromSpec(string schemaName, json spec) returns string? {
    if spec is map<json> {
        json|error componentsResult = spec.get("components");
        if componentsResult is map<json> {
            map<json> components = <map<json>>componentsResult;
            json|error schemasResult = components.get("schemas");
            if schemasResult is map<json> {
                map<json> schemas = <map<json>>schemasResult;
                json|error schemaResult = schemas.get(schemaName);
                if schemaResult is map<json> {
                    map<json> schema = <map<json>>schemaResult;
                    if schema.hasKey("description") {
                        string? desc = schema.get("description") is string ? <string>schema.get("description") : ();
                        if desc is string && desc.trim().length() > 0 {
                            return desc;
                        }
                    }
                }
            }
        }
    }
    return ();
}
