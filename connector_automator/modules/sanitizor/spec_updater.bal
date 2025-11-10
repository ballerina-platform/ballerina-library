import ballerina/log;
import ballerina/regex;

// Helper function to update description in spec using location path
function updateDescriptionInSpec(map<Schema> schemas, string location, string description) returns error? {
    string[] pathParts = regex:split(location, "\\.");

    if pathParts.length() == 1 {
        // Schema-level description
        string schemaName = pathParts[0];
        if schemas.hasKey(schemaName) {
            Schema schema = schemas.get(schemaName);
            // Create a new schema with updated description
            Schema updatedSchema = {
                'type: schema.'type,
                description: description,
                properties: schema.properties,
                items: schema.items,
                \$ref: schema.\$ref,
                allOf: schema.allOf,
                oneOf: schema.oneOf,
                anyOf: schema.anyOf,
                'enum: schema.'enum,
                minimum: schema.minimum,
                maximum: schema.maximum,
                pattern: schema.pattern
            };
            schemas[schemaName] = updatedSchema;
        }
    } else {
        // Property-level description - navigate to the correct location
        string schemaName = pathParts[0];
        if schemas.hasKey(schemaName) {
            Schema schema = schemas.get(schemaName);
            error? result = updateNestedSchemaDescription(schema, pathParts, 1, description);
            if result is error {
                return result;
            }
            // Update the schema in the map
            schemas[schemaName] = schema;
        }
    }

    return ();
}

// Helper function to update parameter description in spec
function updateParameterDescriptionInSpec(map<PathItem> paths, string location, string description) returns error? {
    // Parse location: paths.{path}.{method}.parameters[name={paramName}]
    if location.startsWith("paths.") {
        string locationWithoutPrefix = location.substring(6); // Remove "paths."

        // Use last dot to separate path from method+rest (handles dots in path)
        int? lastDot = locationWithoutPrefix.lastIndexOf(".");
        if lastDot is int {
            string path = locationWithoutPrefix.substring(0, lastDot);
            string methodAndRest = locationWithoutPrefix.substring(lastDot + 1);

            // Separate method from any trailing part (like parameters[...] )
            int? firstDotAfterMethod = methodAndRest.indexOf(".");
            string method = firstDotAfterMethod is int ? methodAndRest.substring(0, firstDotAfterMethod) : methodAndRest;
            string paramLocation = firstDotAfterMethod is int ? methodAndRest.substring(firstDotAfterMethod + 1) : "";

            // Extract parameter name from parameters[name={paramName}]
            if paramLocation.startsWith("parameters[name=") && paramLocation.endsWith("]") {
                string paramName = paramLocation.substring(16, paramLocation.length() - 1); // Remove "parameters[name=" and "]"

                if paths.hasKey(path) {
                    PathItem pathItem = paths.get(path);
                    Operation? operation = getOperationByMethod(pathItem, method);
                    
                    if operation is Operation && operation.parameters is Parameter[] {
                        Parameter[] parameters = <Parameter[]>operation.parameters;
                        
                        // Find and update the parameter
                        foreach int i in 0 ..< parameters.length() {
                            Parameter param = parameters[i];
                            if param.name == paramName {
                                // Create updated parameter
                                Parameter updatedParam = {
                                    name: param.name,
                                    'in: param.'in,
                                    description: description,
                                    required: param.required,
                                    schema: param.schema
                                };
                                parameters[i] = updatedParam;
                                
                                // Update the operation with new parameters
                                Operation updatedOperation = {
                                    operationId: operation.operationId,
                                    summary: operation.summary,
                                    description: operation.description,
                                    tags: operation.tags,
                                    parameters: parameters,
                                    responses: operation.responses
                                };
                                
                                // Update the path item with the updated operation
                                PathItem updatedPathItem = updatePathItemOperation(pathItem, method, updatedOperation);
                                paths[path] = updatedPathItem;
                                return ();
                            }
                        }
                    }
                }
            }
        }
    }

    return error("Could not find parameter at location: " + location);
}

// Helper function to update operation description in spec
function updateOperationDescriptionInSpec(map<PathItem> paths, string location, string description) returns error? {
    // Parse location: paths.{path}.{method}
    if location.startsWith("paths.") {
        string locationWithoutPrefix = location.substring(6); // Remove "paths."

        // Use last dot to split path and method (handles dots inside path)
        int? lastDot = locationWithoutPrefix.lastIndexOf(".");
        if lastDot is int {
            string path = locationWithoutPrefix.substring(0, lastDot);
            string method = locationWithoutPrefix.substring(lastDot + 1);

            if paths.hasKey(path) {
                PathItem pathItem = paths.get(path);
                Operation? operation = getOperationByMethod(pathItem, method);
                
                if operation is Operation {
                    // Create updated operation
                    Operation updatedOperation = {
                        operationId: operation.operationId,
                        summary: operation.summary,
                        description: description,
                        tags: operation.tags,
                        parameters: operation.parameters,
                        responses: operation.responses
                    };
                    
                    // Update the path item with the updated operation
                    PathItem updatedPathItem = updatePathItemOperation(pathItem, method, updatedOperation);
                    paths[path] = updatedPathItem;
                    return ();
                }
            }
        }
    }

    return error("Could not find operation at location: " + location);
}

// Helper function to update response description in spec
function updateResponseDescriptionInSpec(map<PathItem> paths, string location, string description) returns error? {
    // Parse location: paths.{path}.{method}.responses.{responseCode}.description
    if location.startsWith("paths.") {
        string locationWithoutPrefix = location.substring(6); // Remove "paths."

        // Split by dots, but be careful with path segments that might contain dots
        string[] locationParts = regex:split(locationWithoutPrefix, "\\.");

        if locationParts.length() >= 5 { // minimum: path, method, "responses", responseCode, "description"
            // Last three parts are always "responses", responseCode, "description"
            int responsesIndex = locationParts.length() - 3;
            int responseCodeIndex = locationParts.length() - 2;
            int descriptionIndex = locationParts.length() - 1;

            if locationParts[responsesIndex] == "responses" && locationParts[descriptionIndex] == "description" {
                string responseCode = locationParts[responseCodeIndex];

                // Reconstruct path and method (everything before "responses")
                string[] pathAndMethodParts = locationParts.slice(0, responsesIndex);

                // Last part is method, rest is path
                string method = pathAndMethodParts[pathAndMethodParts.length() - 1];
                string[] pathParts = pathAndMethodParts.slice(0, pathAndMethodParts.length() - 1);
                string path = string:'join(".", ...pathParts);

                if paths.hasKey(path) {
                    PathItem pathItem = paths.get(path);
                    Operation? operation = getOperationByMethod(pathItem, method);
                    
                    if operation is Operation && operation.responses is map<Response> {
                        map<Response> responses = <map<Response>>operation.responses;
                        
                        if responses.hasKey(responseCode) {
                            Response response = responses.get(responseCode);
                            
                            // Create updated response
                            Response updatedResponse = {
                                description: description,
                                content: response.content
                            };
                            responses[responseCode] = updatedResponse;
                            
                            // Update the operation with new responses
                            Operation updatedOperation = {
                                operationId: operation.operationId,
                                summary: operation.summary,
                                description: operation.description,
                                tags: operation.tags,
                                parameters: operation.parameters,
                                responses: responses
                            };
                            
                            // Update the path item with the updated operation
                            PathItem updatedPathItem = updatePathItemOperation(pathItem, method, updatedOperation);
                            paths[path] = updatedPathItem;
                            return ();
                        }
                    }
                }
            }
        }
    }

    return error("Could not find response at location: " + location);
}

// Helper function to update operationId in the spec
function updateOperationIdInSpec(map<PathItem> paths, string location, string operationId) returns error? {
    // Expect location like "{path}.{method}" (no leading "paths." here)
    // To be robust, tolerate both "paths.{path}.{method}" and "{path}.{method}"
    string loc = location;
    if loc.startsWith("paths.") {
        loc = loc.substring(6);
    }

    int? lastDot = loc.lastIndexOf(".");
    if lastDot is int {
        string path = loc.substring(0, lastDot);
        string method = loc.substring(lastDot + 1);

        if paths.hasKey(path) {
            PathItem pathItem = paths.get(path);
            Operation? operation = getOperationByMethod(pathItem, method);
            
            if operation is Operation {
                // Create updated operation
                Operation updatedOperation = {
                    operationId: operationId,
                    summary: operation.summary,
                    description: operation.description,
                    tags: operation.tags,
                    parameters: operation.parameters,
                    responses: operation.responses
                };
                
                // Update the path item with the updated operation
                PathItem updatedPathItem = updatePathItemOperation(pathItem, method, updatedOperation);
                paths[path] = updatedPathItem;
                return ();
            }
        }
    }

    return error("Could not find operation at location: " + location);
}

// Helper function to update a specific operation in a PathItem
function updatePathItemOperation(PathItem pathItem, string method, Operation updatedOperation) returns PathItem {
    match method {
        "get" => {
            return {
                get: updatedOperation,
                post: pathItem.post,
                put: pathItem.put,
                delete: pathItem.delete,
                patch: pathItem.patch,
                head: pathItem.head,
                options: pathItem.options,
                trace: pathItem.trace,
                parameters: pathItem.parameters
            };
        }
        "post" => {
            return {
                get: pathItem.get,
                post: updatedOperation,
                put: pathItem.put,
                delete: pathItem.delete,
                patch: pathItem.patch,
                head: pathItem.head,
                options: pathItem.options,
                trace: pathItem.trace,
                parameters: pathItem.parameters
            };
        }
        "put" => {
            return {
                get: pathItem.get,
                post: pathItem.post,
                put: updatedOperation,
                delete: pathItem.delete,
                patch: pathItem.patch,
                head: pathItem.head,
                options: pathItem.options,
                trace: pathItem.trace,
                parameters: pathItem.parameters
            };
        }
        "delete" => {
            return {
                get: pathItem.get,
                post: pathItem.post,
                put: pathItem.put,
                delete: updatedOperation,
                patch: pathItem.patch,
                head: pathItem.head,
                options: pathItem.options,
                trace: pathItem.trace,
                parameters: pathItem.parameters
            };
        }
        "patch" => {
            return {
                get: pathItem.get,
                post: pathItem.post,
                put: pathItem.put,
                delete: pathItem.delete,
                patch: updatedOperation,
                head: pathItem.head,
                options: pathItem.options,
                trace: pathItem.trace,
                parameters: pathItem.parameters
            };
        }
        "head" => {
            return {
                get: pathItem.get,
                post: pathItem.post,
                put: pathItem.put,
                delete: pathItem.delete,
                patch: pathItem.patch,
                head: updatedOperation,
                options: pathItem.options,
                trace: pathItem.trace,
                parameters: pathItem.parameters
            };
        }
        "options" => {
            return {
                get: pathItem.get,
                post: pathItem.post,
                put: pathItem.put,
                delete: pathItem.delete,
                patch: pathItem.patch,
                head: pathItem.head,
                options: updatedOperation,
                trace: pathItem.trace,
                parameters: pathItem.parameters
            };
        }
        "trace" => {
            return {
                get: pathItem.get,
                post: pathItem.post,
                put: pathItem.put,
                delete: pathItem.delete,
                patch: pathItem.patch,
                head: pathItem.head,
                options: pathItem.options,
                trace: updatedOperation,
                parameters: pathItem.parameters
            };
        }
        _ => {
            return pathItem; // No change if method not recognized
        }
    }
}

// Recursive helper to safely update nested schema descriptions
function updateNestedSchemaDescription(Schema schema, string[] pathParts, int index, string description) returns error? {
    if index == pathParts.length() {
        // We've reached the target - this should update the schema in place
        // Note: This is a limitation of the current approach - we need to modify the caller
        return ();
    }

    string part = pathParts[index];

    if part.includes("[") {
        // Handle array indices like "allOf[0]"
        string[] indexParts = regex:split(part, "\\[");
        string arrayName = indexParts[0];
        string indexStr = regex:replaceAll(indexParts[1], "\\]", "");
        int|error indexResult = int:fromString(indexStr);

        if indexResult is int {
            Schema[]? nestedArray = ();
            if arrayName == "allOf" {
                nestedArray = schema.allOf;
            } else if arrayName == "oneOf" {
                nestedArray = schema.oneOf;
            } else if arrayName == "anyOf" {
                nestedArray = schema.anyOf;
            }
            
            if nestedArray is Schema[] && indexResult < nestedArray.length() {
                return updateNestedSchemaDescription(nestedArray[indexResult], pathParts, index + 1, description);
            }
        }
    } else if part == "properties" && schema.properties is map<Schema> {
        // This is more complex - we need to handle property updates
        map<Schema> properties = <map<Schema>>schema.properties;
        if index + 1 < pathParts.length() {
            string propName = pathParts[index + 1];
            if properties.hasKey(propName) {
                Schema property = properties.get(propName);
                if index + 2 == pathParts.length() {
                    // This is the target property - update its description
                    Schema updatedProperty = {
                        'type: property.'type,
                        description: description,
                        properties: property.properties,
                        items: property.items,
                        \$ref: property.\$ref,
                        allOf: property.allOf,
                        oneOf: property.oneOf,
                        anyOf: property.anyOf,
                        'enum: property.'enum,
                        minimum: property.minimum,
                        maximum: property.maximum,
                        pattern: property.pattern
                    };
                    properties[propName] = updatedProperty;
                    return ();
                } else {
                    return updateNestedSchemaDescription(property, pathParts, index + 2, description);
                }
            }
        }
    }

    return ();
}

// Helper function to update schema references throughout the JSON structure
function updateSchemaReferences(json jsonData, map<string> nameMapping, boolean quietMode = false) returns json {
    if (jsonData is map<json>) {
        map<json> resultMap = {};

        foreach string key in jsonData.keys() {
            json|error value = jsonData.get(key);
            if (value is json) {
                if (key == "$ref" && value is string) {
                    // Update schema reference if it matches a renamed schema
                    string refValue = <string>value;
                    if (refValue.startsWith("#/components/schemas/")) {
                        string schemaName = refValue.substring(21); // Remove "#/components/schemas/"
                        string? newName = nameMapping[schemaName];
                        if (newName is string) {
                            string newRef = "#/components/schemas/" + newName;
                            resultMap[key] = newRef;
                            if !quietMode {
                                log:printInfo("Updated schema reference", oldRef = refValue, newRef = newRef);
                            }
                        } else {
                            resultMap[key] = value;
                        }
                    } else {
                        resultMap[key] = value;
                    }
                } else {
                    // Recursively process nested structures
                    resultMap[key] = updateSchemaReferences(value, nameMapping, quietMode);
                }
            }
        }

        return resultMap;
    } else if (jsonData is json[]) {
        json[] resultArray = [];
        foreach json item in jsonData {
            resultArray.push(updateSchemaReferences(item, nameMapping, quietMode));
        }
        return resultArray;
    } else {
        // Primitive values remain unchanged
        return jsonData;
    }
}