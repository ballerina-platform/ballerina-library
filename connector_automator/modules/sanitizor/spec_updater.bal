import ballerina/log;
import ballerina/regex;

// Helper function to update description in spec using location path
function updateDescriptionInSpec(map<json> schemas, string location, string description) returns error? {
    string[] pathParts = regex:split(location, "\\.");

    if pathParts.length() == 1 {
        // Schema-level description
        string schemaName = pathParts[0];
        json|error schemaResult = schemas.get(schemaName);
        if schemaResult is map<json> {
            map<json> schemaMap = <map<json>>schemaResult;
            schemaMap["description"] = description;
            // No need to reassign since we're modifying the original reference
        }
    } else {
        // Property-level description - navigate to the correct location
        string schemaName = pathParts[0];
        json|error schemaResult = schemas.get(schemaName);
        if schemaResult is map<json> {
            error? result = updateNestedDescription(<map<json>>schemaResult, pathParts, 1, description);
            if result is error {
                return result;
            }
        }
    }

    return ();
}

// Helper function to update parameter description in spec
function updateParameterDescriptionInSpec(map<json> paths, string location, string description) returns error? {
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

                json|error pathItem = paths.get(path);
                if pathItem is map<json> {
                    map<json> pathItemMap = <map<json>>pathItem;

                    if pathItemMap.hasKey(method) {
                        json|error operation = pathItemMap.get(method);
                        if operation is map<json> {
                            map<json> operationMap = <map<json>>operation;

                            if operationMap.hasKey("parameters") {
                                json|error parametersResult = operationMap.get("parameters");
                                if parametersResult is json[] {
                                    json[] parameters = parametersResult;

                                    // Find the parameter by name
                                    foreach int i in 0 ..< parameters.length() {
                                        json param = parameters[i];
                                        if param is map<json> {
                                            map<json> paramMap = <map<json>>param;
                                            if paramMap.hasKey("name") && paramMap.get("name") == paramName {
                                                paramMap["description"] = description;
                                                return ();
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

    return error("Could not find parameter at location: " + location);
}

// Helper function to update operation description in spec
function updateOperationDescriptionInSpec(map<json> paths, string location, string description) returns error? {
    // Parse location: paths.{path}.{method}
    if location.startsWith("paths.") {
        string locationWithoutPrefix = location.substring(6); // Remove "paths."

        // Use last dot to split path and method (handles dots inside path)
        int? lastDot = locationWithoutPrefix.lastIndexOf(".");
        if lastDot is int {
            string path = locationWithoutPrefix.substring(0, lastDot);
            string method = locationWithoutPrefix.substring(lastDot + 1);

            json|error pathItem = paths.get(path);
            if pathItem is map<json> {
                map<json> pathItemMap = <map<json>>pathItem;

                if pathItemMap.hasKey(method) {
                    json|error operation = pathItemMap.get(method);
                    if operation is map<json> {
                        map<json> operationMap = <map<json>>operation;
                        operationMap["description"] = description;
                        return ();
                    }
                }
            }
        }
    }

    return error("Could not find operation at location: " + location);
}

// Recursive helper to safely update nested descriptions
function updateNestedDescription(map<json> current, string[] pathParts, int index, string description) returns error? {
    if index == pathParts.length() {
        // We've reached the target - add description
        current["description"] = description;
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
            json|error arrayResult = current.get(arrayName);
            if arrayResult is json[] {
                json[] array = arrayResult;
                if indexResult < array.length() && array[indexResult] is map<json> {
                    return updateNestedDescription(<map<json>>array[indexResult], pathParts, index + 1, description);
                }
            }
        }
    } else {
        json|error nextResult = current.get(part);
        if nextResult is map<json> {
            return updateNestedDescription(<map<json>>nextResult, pathParts, index + 1, description);
        }
    }

    return ();
}

// Helper function to update operationId in the spec
function updateOperationIdInSpec(map<json> paths, string location, string operationId) returns error? {
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

        json|error pathItem = paths.get(path);
        if pathItem is map<json> {
            map<json> pathItemMap = <map<json>>pathItem;

            if pathItemMap.hasKey(method) {
                json|error operation = pathItemMap.get(method);
                if operation is map<json> {
                    map<json> operationMap = <map<json>>operation;
                    operationMap["operationId"] = operationId;
                    return ();
                }
            }
        }
    }

    return error("Could not find operation at location: " + location);
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

// Helper function to update response description in spec
function updateResponseDescriptionInSpec(map<json> paths, string location, string description) returns error? {
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

                json|error pathItem = paths.get(path);
                if pathItem is map<json> {
                    map<json> pathItemMap = <map<json>>pathItem;

                    if pathItemMap.hasKey(method) {
                        json|error operation = pathItemMap.get(method);
                        if operation is map<json> {
                            map<json> operationMap = <map<json>>operation;

                            if operationMap.hasKey("responses") {
                                json|error responsesResult = operationMap.get("responses");
                                if responsesResult is map<json> {
                                    map<json> responses = <map<json>>responsesResult;

                                    if responses.hasKey(responseCode) {
                                        json|error responseResult = responses.get(responseCode);
                                        if responseResult is map<json> {
                                            map<json> response = <map<json>>responseResult;
                                            response["description"] = description;
                                            return ();
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

    return error("Could not find response at location: " + location);
}
