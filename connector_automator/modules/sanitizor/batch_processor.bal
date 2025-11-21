import ballerina/data.jsondata;
import ballerina/io;
import ballerina/lang.runtime;
import ballerina/log;

configurable RetryConfig retryConfig = {};

// Process multiple description requests with retry and exponential backoff
public function generateDescriptionsBatchWithRetry(DescriptionRequest[] requests, string apiContext, boolean quietMode = false, RetryConfig? config = ()) returns BatchDescriptionResponse[]|LLMServiceError {
    RetryConfig retryConf = config ?: retryConfig;

    int attempt = 0;
    while attempt <= retryConf.maxRetries {
        BatchDescriptionResponse[]|LLMServiceError result = generateDescriptionsBatch(requests, apiContext);

        if result is BatchDescriptionResponse[] {
            if !quietMode && attempt > 0 {
                log:printInfo("Batch description generation succeeded after retry", attempt = attempt);
            }
            return result;
        } else {
            // Check if this is the last attempt
            if attempt == retryConf.maxRetries {
                if !quietMode {
                    log:printError("Batch description generation failed after all retries",
                            finalAttempt = attempt, maxRetries = retryConf.maxRetries, 'error = result);
                }
                return result;
            }

            // Check if error is retryable
            if !isRetryableError(result) {
                if !quietMode {
                    log:printError("Non-retryable error in batch description generation", 'error = result);
                }
                return result;
            }

            // Calculate backoff delay and wait
            decimal delay = calculateBackoffDelay(attempt, retryConf);
            if !quietMode {
                log:printWarn("Batch description generation failed, retrying",
                        attempt = attempt + 1, maxRetries = retryConf.maxRetries,
                        delaySeconds = delay, 'error = result);
            }

            runtime:sleep(delay);
            attempt += 1;
        }
    }

    // This should never be reached, but just in case
    return error LLMServiceError("Unexpected error in retry logic");
}

// Generate missing operationIds with retry and exponential backoff
public function generateOperationIdsBatchWithRetry(OperationIdRequest[] requests, string apiContext, string[] existingOperationIds, boolean quietMode = false, RetryConfig? config = ()) returns BatchOperationIdResponse[]|LLMServiceError {
    RetryConfig retryConf = config ?: retryConfig;

    int attempt = 0;
    while attempt <= retryConf.maxRetries {
        BatchOperationIdResponse[]|LLMServiceError result = generateOperationIdsBatch(requests, apiContext, existingOperationIds);

        if result is BatchOperationIdResponse[] {
            if attempt > 0 {
                log:printInfo("Batch operationId generation succeeded after retry", attempt = attempt);
            }
            return result;
        } else {
            // Check if this is the last attempt
            if attempt == retryConf.maxRetries {
                log:printError("Batch operationId generation failed after all retries",
                        finalAttempt = attempt, maxRetries = retryConf.maxRetries, 'error = result);
                return result;
            }

            // Check if error is retryable
            if !isRetryableError(result) {
                log:printError("Non-retryable error in batch operationId generation", 'error = result);
                return result;
            }

            // Calculate backoff delay and wait
            decimal delay = calculateBackoffDelay(attempt, retryConf);
            log:printWarn("Batch operationId generation failed, retrying",
                    attempt = attempt + 1, maxRetries = retryConf.maxRetries,
                    delaySeconds = delay, 'error = result);

            runtime:sleep(delay);
            attempt += 1;
        }
    }

    // This should never be reached, but just in case
    return error LLMServiceError("Unexpected error in retry logic");
}

public function generateSchemaNamesBatchWithRetry(SchemaRenameRequest[] requests, string apiContext, string[] existingNames, boolean quietMode = false, RetryConfig? config = ()) returns BatchRenameResponse[]|LLMServiceError {
    RetryConfig retryConf = config ?: retryConfig;

    int attempt = 0;
    while attempt <= retryConf.maxRetries {
        BatchRenameResponse[]|LLMServiceError result = generateSchemaNamesBatch(requests, apiContext, existingNames);

        if result is BatchRenameResponse[] {
            if attempt > 0 {
                log:printInfo("Batch schema naming succeeded after retry", attempt = attempt);
            }
            return result;
        } else {
            // Check if this is the last attempt
            if attempt == retryConf.maxRetries {
                log:printError("Batch schema naming failed after all retries",
                        finalAttempt = attempt, maxRetries = retryConf.maxRetries, 'error = result);
                return result;
            }

            // Check if error is retryable
            if !isRetryableError(result) {
                log:printError("Non-retryable error in batch schema naming", 'error = result);
                return result;
            }

            // Calculate backoff delay and wait
            decimal delay = calculateBackoffDelay(attempt, retryConf);
            log:printWarn("Batch schema naming failed, retrying",
                    attempt = attempt + 1, maxRetries = retryConf.maxRetries,
                    delaySeconds = delay, 'error = result);

            runtime:sleep(delay);
            attempt += 1;
        }
    }

    // This should never be reached, but just in case
    return error LLMServiceError("Unexpected error in retry logic");
}

// Batch processing to include parameters and operations
public function addMissingDescriptionsBatchWithRetry(string specFilePath, int batchSize = 20, boolean quietMode = false, RetryConfig? config = ()) returns int|LLMServiceError {
    if !quietMode {
        log:printInfo("Processing OpenAPI spec for missing descriptions",
                specPath = specFilePath, batchSize = batchSize);
    }

    // Read the OpenAPI spec file
    json|error specResult = io:fileReadJson(specFilePath);
    if specResult is error {
        return error LLMServiceError("Failed to read OpenAPI spec file", specResult);
    }

    json specJson = specResult;
    int descriptionsAdded = 0;

    if specJson is map<json> {
        map<json> specMap = <map<json>>specJson;
        string apiContext = extractApiContext(specJson);

        // Collect all missing description requests
        DescriptionRequest[] allRequests = [];
        map<string> requestToLocationMap = {}; // Map request ID to location for updating

        // 1. Collect schema and property descriptions (existing logic)
        json|error componentsResult = specMap.get("components");
        if componentsResult is map<json> {
            json|error schemasResult = componentsResult.get("schemas");
            if schemasResult is map<json> {
                map<json> schemas = <map<json>>schemasResult;

                foreach string schemaName in schemas.keys() {
                    json|error schemaResult = schemas.get(schemaName);
                    if schemaResult is map<json> {
                        map<json> schemaMap = <map<json>>schemaResult;
                        collectDescriptionRequests(schemaMap, schemaName, "", allRequests, requestToLocationMap, specJson);
                    }
                }
            }
        }

        // 2. Collect parameter descriptions (ENHANCED - only processes existing parameters)
        collectParameterDescriptionRequests(specJson, allRequests, requestToLocationMap);

        // 3. Collect operation descriptions for return parameters (ENHANCED - includes response descriptions)
        collectOperationDescriptionRequests(specJson, allRequests, requestToLocationMap);

        // Process requests in batches with retry
        int totalRequests = allRequests.length();
        if !quietMode {
            log:printInfo("Collected description requests", totalRequests = totalRequests);
        }

        int startIdx = 0;
        while startIdx < totalRequests {
            int endIdx = startIdx + batchSize;
            if endIdx > totalRequests {
                endIdx = totalRequests;
            }

            DescriptionRequest[] batch = allRequests.slice(startIdx, endIdx);
            if !quietMode {
                log:printInfo("Processing batch with retry", batchNumber = (startIdx / batchSize) + 1,
                        batchSize = batch.length());
            }

            BatchDescriptionResponse[]|LLMServiceError batchResult = generateDescriptionsBatchWithRetry(batch, apiContext, quietMode, config);
            if batchResult is BatchDescriptionResponse[] {
                if !quietMode {
                    io:println(string `  ✓ Batch ${(startIdx / batchSize) + 1} processed (${batchResult.length()} descriptions)`);
                }

                // Apply the generated descriptions
                foreach BatchDescriptionResponse response in batchResult {
                    string? location = requestToLocationMap[response.id];
                    if location is string {
                        error? updateResult = ();

                        // Determine update method based on location type
                        if location.startsWith("paths.") && location.includes("parameters[name=") {
                            // Parameter description
                            json|error pathsResult = specMap.get("paths");
                            if pathsResult is map<json> {
                                updateResult = updateParameterDescriptionInSpec(<map<json>>pathsResult, location, response.description);
                            }
                        } else if location.startsWith("paths.") && location.includes(".responses.") && location.endsWith(".description") {
                            // Response description (NEW)
                            json|error pathsResult = specMap.get("paths");
                            if pathsResult is map<json> {
                                updateResult = updateResponseDescriptionInSpec(<map<json>>pathsResult, location, response.description);
                            }
                        } else if location.startsWith("paths.") && !location.includes(".properties.") && !location.includes(".responses.") {
                            // Operation description
                            json|error pathsResult = specMap.get("paths");
                            if pathsResult is map<json> {
                                updateResult = updateOperationDescriptionInSpec(<map<json>>pathsResult, location, response.description);
                            }
                        } else {
                            // Schema/property description 
                            json|error componentsResult2 = specMap.get("components");
                            if componentsResult2 is map<json> {
                                json|error schemasResult2 = componentsResult2.get("schemas");
                                if schemasResult2 is map<json> {
                                    updateResult = updateDescriptionInSpec(<map<json>>schemasResult2, location, response.description);
                                }
                            }
                        }

                        if updateResult is () {
                            descriptionsAdded += 1;
                            if !quietMode {
                                log:printInfo("Applied batch description", id = response.id, location = location);
                            }
                        } else {
                            log:printError("Failed to apply description", id = response.id, 'error = updateResult);
                        }
                    }
                }
            } else {
                if !quietMode {
                    log:printError("Batch processing failed after all retries", batchNumber = (startIdx / batchSize) + 1, 'error = batchResult);
                    io:println(string `  ✗ Batch ${(startIdx / batchSize) + 1} failed`);
                }
                // Continue with next batch instead of failing completely
            }
            startIdx += batchSize;
        }
    }

    // Save updated spec back to file
    string|error prettifiedResult = jsondata:prettify(specJson);
    if prettifiedResult is error {
        return error LLMServiceError("Failed to prettify JSON", prettifiedResult);
    }

    error? writeResult = io:fileWriteString(specFilePath, prettifiedResult);
    if writeResult is error {
        return error LLMServiceError("Failed to write updated OpenAPI spec", writeResult);
    }

    return descriptionsAdded;
}

// Batch version of renameInlineResponseSchemas with retry and configurable batch size
public function renameInlineResponseSchemasBatchWithRetry(string specFilePath, int batchSize = 10, boolean quietMode = false, RetryConfig? config = ()) returns int|LLMServiceError {
    if !quietMode {
        log:printInfo("Processing OpenAPI spec to rename InlineResponse schemas (batch mode with retry)",
                specPath = specFilePath, batchSize = batchSize);
    }

    // Read the OpenAPI spec file
    json|error specResult = io:fileReadJson(specFilePath);
    if specResult is error {
        return error LLMServiceError("Failed to read OpenAPI spec file", specResult);
    }

    json specJson = specResult;

    if !(specJson is map<json>) {
        return error LLMServiceError("Invalid OpenAPI spec format");
    }

    map<json> specMap = <map<json>>specJson;

    // Get components/schemas
    json|error componentsResult = specMap.get("components");
    if !(componentsResult is map<json>) {
        return error LLMServiceError("No components section found in OpenAPI spec");
    }

    map<json> components = <map<json>>componentsResult;
    json|error schemasResult = components.get("schemas");
    if !(schemasResult is map<json>) {
        return error LLMServiceError("No schemas section found in components");
    }

    map<json> schemas = <map<json>>schemasResult;

    // Collect all existing schema names to ensure global uniqueness
    string[] allExistingNames = [];
    foreach string schemaName in schemas.keys() {
        if (!schemaName.startsWith("InlineResponse")) {
            allExistingNames.push(schemaName);
        }
    }

    // Collect all InlineResponse schemas for batch processing
    SchemaRenameRequest[] renameRequests = [];
    string apiContext = extractApiContext(specMap);

    foreach string schemaName in schemas.keys() {
        if (schemaName.startsWith("InlineResponse") || schemaName.endsWith("AllOf2") || schemaName.endsWith("OneOf2")) {
            json|error schemaResult = schemas.get(schemaName);
            if (schemaResult is map<json>) {
                string schemaDefinition = (<map<json>>schemaResult).toJsonString();
                string usageContext = extractSchemaUsageContext(schemaName, specMap);

                renameRequests.push({
                    originalName: schemaName,
                    schemaDefinition: schemaDefinition,
                    usageContext: usageContext
                });
            }
        }
    }

    if renameRequests.length() == 0 {
        if !quietMode {
            log:printInfo("No InlineResponse schemas found to rename");
        }
        return 0;
    }

    map<string> nameMapping = {};
    int renamedCount = 0;
    int totalRequests = renameRequests.length();

    if !quietMode {
        log:printInfo("Collected schema rename requests", totalRequests = totalRequests);
    }

    // Process requests in batches with retry
    int startIdx = 0;
    while startIdx < totalRequests {
        int endIdx = startIdx + batchSize;
        if endIdx > totalRequests {
            endIdx = totalRequests;
        }

        SchemaRenameRequest[] batch = renameRequests.slice(startIdx, endIdx);
        if !quietMode {
            log:printInfo("Processing schema rename batch with retry", batchNumber = (startIdx / batchSize) + 1,
                    batchSize = batch.length());
        }

        BatchRenameResponse[]|LLMServiceError batchResult = generateSchemaNamesBatchWithRetry(batch, apiContext, allExistingNames, quietMode, config);
        if batchResult is BatchRenameResponse[] {
            if !quietMode {
                io:println(string `  ✓ Batch ${(startIdx / batchSize) + 1} processed (${batchResult.length()} schemas)`);
            }

            // Process the generated names
            foreach BatchRenameResponse response in batchResult {
                string newName = response.newName;

                // Validate that the generated name is safe for JSON and schema naming
                if (isValidSchemaName(newName)) {
                    // Double-check uniqueness (LLM should handle this, but safety first)
                    if (!isNameTaken(newName, allExistingNames, nameMapping)) {
                        // Add the name to our tracking list to prevent future conflicts
                        allExistingNames.push(newName);
                        nameMapping[response.originalName] = newName;
                        if !quietMode {
                            log:printInfo("Generated new name for schema", oldName = response.originalName, newName = newName);
                        }
                        renamedCount += 1;
                    } else {
                        // Fallback if LLM somehow generated a duplicate
                        log:printWarn("LLM generated duplicate name, using fallback",
                                schema = response.originalName, duplicateName = newName);
                        string fallbackName = newName + "Alt";
                        int counter = 1;
                        while (isNameTaken(fallbackName, allExistingNames, nameMapping)) {
                            fallbackName = newName + "Alt" + counter.toString();
                            counter += 1;
                        }
                        allExistingNames.push(fallbackName);
                        nameMapping[response.originalName] = fallbackName;
                        renamedCount += 1;
                    }
                } else {
                    log:printWarn("Generated name is not valid, using fallback",
                            schema = response.originalName, invalidName = newName);
                    string fallbackBaseName = "Schema" + response.originalName.substring(14);
                    string fallbackName = fallbackBaseName;
                    int counter = 1;
                    while (isNameTaken(fallbackName, allExistingNames, nameMapping)) {
                        fallbackName = fallbackBaseName + counter.toString();
                        counter += 1;
                    }
                    allExistingNames.push(fallbackName);
                    nameMapping[response.originalName] = fallbackName;
                    renamedCount += 1;
                }
            }
        } else {
            if !quietMode {
                log:printError("Schema rename batch processing failed after all retries",
                        batchNumber = (startIdx / batchSize) + 1, 'error = batchResult);
                io:println(string `  ✗ Batch ${(startIdx / batchSize) + 1} failed`);
            }
            // Continue with next batch instead of failing completely
        }

        startIdx += batchSize;
    }

    // Apply the renaming if we have any mappings
    if (nameMapping.length() > 0) {
        // First, rename the schema definitions in the schemas map
        map<json> newSchemas = {};
        foreach string oldName in schemas.keys() {
            json|error schemaValue = schemas.get(oldName);
            if (schemaValue is json) {
                if (nameMapping.hasKey(oldName)) {
                    string? newNameResult = nameMapping[oldName];
                    if (newNameResult is string) {
                        newSchemas[newNameResult] = schemaValue;
                    }
                } else {
                    newSchemas[oldName] = schemaValue;
                }
            }
        }

        // Update the schemas in the components section
        components["schemas"] = newSchemas;
        specMap["components"] = components;

        // Update all $ref references throughout the spec
        json updatedSpecResult = updateSchemaReferences(specMap, nameMapping, quietMode);

        // Write the updated spec back to file
        string|error prettifiedResult = jsondata:prettify(updatedSpecResult);
        if prettifiedResult is error {
            return error LLMServiceError("Failed to prettify JSON", prettifiedResult);
        }

        error? writeResult = io:fileWriteString(specFilePath, prettifiedResult);
        if writeResult is error {
            return error LLMServiceError("Failed to write updated OpenAPI spec", writeResult);
        }
    }

    return renamedCount;
}

// Add missing operationIds to OpenAPI spec operations (batch mode with retry)
public function addMissingOperationIdsBatchWithRetry(string specFilePath, int batchSize = 15, boolean quietMode = false, RetryConfig? config = ()) returns int|LLMServiceError {
    if !quietMode {
        log:printInfo("Processing OpenAPI spec for missing operationIds (batch mode with retry)",
                specPath = specFilePath, batchSize = batchSize);
    }

    // Read the OpenAPI spec file
    json|error specResult = io:fileReadJson(specFilePath);
    if specResult is error {
        return error LLMServiceError("Failed to read OpenAPI spec file", specResult);
    }

    json specJson = specResult;

    if !(specJson is map<json>) {
        return error LLMServiceError("Invalid OpenAPI spec format");
    }

    map<json> specMap = <map<json>>specJson;

    // Get paths section
    json|error pathsResult = specMap.get("paths");
    if !(pathsResult is map<json>) {
        return error LLMServiceError("No paths section found in OpenAPI spec");
    }

    map<json> paths = <map<json>>pathsResult;

    // Collect all existing operationIds to ensure uniqueness
    string[] existingOperationIds = [];
    collectExistingOperationIds(paths, existingOperationIds);

    // Collect all missing operationId requests
    OperationIdRequest[] missingOperationIds = [];
    map<string> requestToLocationMap = {}; // Map request ID to location for updating

    string apiContext = extractApiContext(specMap);
    collectMissingOperationIdRequests(paths, missingOperationIds, requestToLocationMap, apiContext);

    int totalRequests = missingOperationIds.length();
    if totalRequests == 0 {
        if !quietMode {
            log:printInfo("No missing operationIds found");
        }
        return 0;
    }

    if !quietMode {
        log:printInfo("Collected missing operationId requests", totalRequests = totalRequests);
    }

    int operationIdsAdded = 0;

    // Process requests in batches with retry
    int startIdx = 0;
    while startIdx < totalRequests {
        int endIdx = startIdx + batchSize;
        if endIdx > totalRequests {
            endIdx = totalRequests;
        }

        OperationIdRequest[] batch = missingOperationIds.slice(startIdx, endIdx);
        if !quietMode {
            log:printInfo("Processing operationId batch with retry", batchNumber = (startIdx / batchSize) + 1,
                    batchSize = batch.length());
        }

        BatchOperationIdResponse[]|LLMServiceError batchResult = generateOperationIdsBatchWithRetry(batch, apiContext, existingOperationIds, quietMode, config);
        if batchResult is BatchOperationIdResponse[] {
            if !quietMode {
                io:println(string `  ✓ Batch ${(startIdx / batchSize) + 1} processed (${batchResult.length()} operations)`);
            }

            // Apply the generated operationIds
            foreach BatchOperationIdResponse response in batchResult {
                string? location = requestToLocationMap[response.id];
                if location is string {
                    error? updateResult = updateOperationIdInSpec(paths, location, response.operationId);
                    if updateResult is () {
                        // Add to existing list to prevent conflicts in next batches
                        existingOperationIds.push(response.operationId);
                        operationIdsAdded += 1;
                        if !quietMode {
                            log:printInfo("Applied batch operationId", id = response.id,
                                    location = location, operationId = response.operationId);
                        }
                    } else {
                        log:printError("Failed to apply operationId", id = response.id, 'error = updateResult);
                    }
                }
            }
        } else {
            if !quietMode {
                log:printError("OperationId batch processing failed after all retries",
                        batchNumber = (startIdx / batchSize) + 1, 'error = batchResult);
                io:println(string `  ✗ Batch ${(startIdx / batchSize) + 1} failed`);
            }
            // Continue with next batch instead of failing completely
        }
        startIdx += batchSize;
    }

    // Save updated spec back to file
    string|error prettifiedResult = jsondata:prettify(specJson);
    if prettifiedResult is error {
        return error LLMServiceError("Failed to prettify JSON", prettifiedResult);
    }

    error? writeResult = io:fileWriteString(specFilePath, prettifiedResult);
    if writeResult is error {
        return error LLMServiceError("Failed to write updated OpenAPI spec", writeResult);
    }

    return operationIdsAdded;
}
