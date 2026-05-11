string backtick = "`";
string tripleBacktick = "`";

function createMockServerPrompt(string mockServerTemplate, string types) returns string {
    return string `
    You are an expert Ballerina developer specializing in creating flawless mock API servers. Your goal is to complete a given Ballerina service template by filling in the resource functions with realistic, type-correct mock data.

    **Phase 1: Reflection (Internal Monologue)**

    Before generating any code, take a moment to reflect on the requirements for a perfect response.
    1.  **Output Purity:** The final output must be a single, complete, raw Ballerina source code file. It absolutely cannot contain any conversational text, explanations, apologies, or markdown formatting like ${tripleBacktick}ballerina. It must start with the first line of code and end with the last.
    2.  **Structural Integrity:** I must adhere strictly to the provided template. My job is to *fill in the blanks* (the function bodies), not to refactor or add new elements.
    3.  **Server Initialization:** This is a common point of failure. The user wants the service attached directly to an ${backtick}http:Listener${backtick} on port 9090. A critical mistake to avoid is generating a separate ${backtick}public function init()${backtick}. The listener and service declaration are sufficient to define the running server. I will not add an ${backtick}init${backtick} function.
    4.  **Data Accuracy:** The mock data must be more than just plausible; it must be a perfect match for the Ballerina record types provided in the ${backtick}<AVAILABLE_TYPES>${backtick} context. I need to meticulously check every field, data type (string, int, boolean), and structure (arrays, nested records, optional fields) to ensure 100% type safety. The return value should be a JSON literal.
    5.  **Completeness:** Every single resource function in the template must be implemented. No function should be left with an empty body or a placeholder comment.

    **Phase 2: Execution**

    Now, based on my reflection, I will generate the complete ${backtick}mock_server.bal${backtick} file. I will follow these instructions with extreme precision.

    **Critically Important:**
    - Your response MUST be a complete, raw Ballerina source code file.
    - Do NOT include any explanations or markdown formatting, code fences like ${tripleBacktick}.

    <CONTEXT>
      <MOCK_SERVER_TEMPLATE>
        ${mockServerTemplate}
      </MOCK_SERVER_TEMPLATE>

      <AVAILABLE_TYPES>
        ${types}
      </AVAILABLE_TYPES>
    </CONTEXT>

    **Requirements:**
    1.  **Copyright Header:** The generated file must start with the exact copyright header from the template.
    2.  **HTTP Listener:** The service must be attached to a globally defined ${backtick}http:Listener ep0 = new (9090);${backtick}.
    3.  **NO ${backtick}init${backtick} FUNCTION:** You must not include any ${backtick}init${backtick} function. The service definition attached to the listener is the complete server configuration.
    4.  **Complete All Functions:** Implement the body for every resource function.
    5.  **Realistic & Type-Correct JSON:** Use believable data for all fields. The returned JSON structure must strictly adhere to the function's return type signature as defined in the provided types.
    6.  **Preserve Doc Comments:** All documentation comments (${backtick}# ...${backtick}) above the resource functions in the template must be preserved.

    **Example of a well-implemented resource function:**
    ${tripleBacktick}ballerina
    # Deletes the Tweet specified by the Tweet ID.
    resource function delete users/[string id]/bookmarks/[string tweet_id]() returns BookmarkMutationResponse|http:Response {
        return {
            "data": {"bookmarked": false}
        };
    }
    ${tripleBacktick}

    Now, generate the complete and final ${backtick}mock_server.bal${backtick} file.
`;
}

function createTestGenerationPrompt(ConnectorAnalysis analysis) returns string {
    string methodTypeGuidance = "";
    string methodSignaturesSection = "";

    if analysis.methodType == "remote" {
        methodTypeGuidance = string `
**CRITICAL - Remote Method Syntax:**
This connector uses REMOTE methods, NOT resource methods. You MUST use the following syntax:
- Correct: ${backtick}Type response = check client->methodName(param1, param2);${backtick}
- WRONG: ${backtick}Type response = check client->/path/to/resource();${backtick}

The method signatures are provided in <REMOTE_METHOD_SIGNATURES>. Use these exact method names and parameters.
`;

        methodSignaturesSection = string `
      <REMOTE_METHOD_SIGNATURES>
        ${analysis.remoteMethodSignatures}
      </REMOTE_METHOD_SIGNATURES>
`;
    } else {
        methodTypeGuidance = string `
This connector uses resource methods. Use the resource path syntax from the mock server.
`;
    }
    return string `
    You are an expert Ballerina developer specializing in writing robust, production-quality test suites for connectors. Your task is to generate a comprehensive test file (${backtick}test.bal${backtick}) for the provided connector.

    **Phase 1: Reflection (Internal Monologue)**

    Before generating any code, I must reflect on the key requirements for a perfect test file.
    1.  **Output Purity:** The final output must be a single, complete, raw Ballerina source code file. No conversational text, no explanations, no apologies, and absolutely no markdown formatting like ${tripleBacktick}ballerina.
    2.  **Client Initialization: This is the most critical and complex part.** The user has provided the exact ${backtick}<CLIENT_INIT_METHOD>${backtick} signature and the necessary ${backtick}<REFERENCED_TYPE_DEFINITIONS>${backtick}. I must meticulously use this information to construct the client initialization code. I cannot use a generic template; it must be tailored precisely to the provided context to avoid compilation errors.
    ${methodTypeGuidance}
    3.  **Environment Configuration:** I need to set up a flexible testing environment. This involves:
      * Use ${backtick}final${backtick} module-level variables initialized via ${backtick}os:getEnv(...)${backtick}.
      * Use ${backtick}final boolean isLiveServer = os:getEnv("IS_LIVE_SERVER") == "true";${backtick} to switch environments.
      * Use ${backtick}final string serviceUrl${backtick} that points to the real API for live tests and to ${backtick}http://localhost:9090${backtick} for mock tests.
      * Connection/credential fields (e.g., tokens, keys) must be ${backtick}final${backtick} values resolved from environment variables.
    4.  **Test Function Logic & Assertions:** My goal is to verify the structure and success of API calls, not the specific data content.
        * I will generate one test function for each resource endpoint.
        * A common pitfall to avoid is using direct HTTP return types like ${backtick}http:Accepted${backtick}. If a successful response has no body, the function should assign the result to ${backtick}error?${backtick} and the test's purpose is to ensure no error is returned.
        * Every test function MUST include assertions to validate the response.
        * **Assertion Strategy:**
            * For responses that return a single record (object), I will assert that the data field is not nil: ${backtick}test:assertTrue(response?.data !is ());${backtick}.
            * For responses that return an array, I must check if the array is not empty: ${backtick}test:assertTrue(response.data.length() > 0);${backtick}. Using ${backtick}!is ()${backtick} on an array will fail.
            * Where applicable, I will also assert that the ${backtick}errors${backtick} field is nil: ${backtick}test:assertTrue(response?.errors is ());${backtick}.
    5.  **Completeness and Correctness:** I must ensure all necessary imports (${backtick}ballerina/os${backtick}, ${backtick}ballerina/test${backtick}, etc.) are present and that the entire file is syntactically correct and ready to compile.

    **Phase 2: Execution**

    Based on my reflection, I will now generate the complete ${backtick}test.bal${backtick} file with extreme precision.

    <CONTEXT>
      <PACKAGE_NAME>
        ${analysis.packageName}
      </PACKAGE_NAME>
      <MOCK_SERVER_IMPLEMENTATION>
        ${analysis.mockServerContent}
      </MOCK_SERVER_IMPLEMENTATION>
       <CLIENT_INIT_METHOD>
        ${analysis.initMethodSignature}
      </CLIENT_INIT_METHOD>
      <REFERENCED_TYPE_DEFINITIONS>
        ${analysis.referencedTypeDefinitions}
      </REFERENCED_TYPE_DEFINITIONS>
${methodSignaturesSection}
  
    </CONTEXT>

    **Requirements:**
    1.  **Complete File:** Your response must be a single, raw, and complete Ballerina source code file. Do not include any code fences in the response.
    2.  **Copyright Header:** The generated file must start with the standard Ballerina copyright header.
    3.  **Imports:** Include ${backtick}import ballerina/os;${backtick}, ${backtick}import ballerina/test;${backtick}, and the mock server import: ${backtick}import ${analysis.packageName}.mock.server as _;${backtick}.
    4.  **Environment Setup:** Implement ${backtick}final${backtick} variables for ${backtick}isLiveServer${backtick}, ${backtick}serviceUrl${backtick}, and any necessary credentials using ${backtick}os:getEnv${backtick}. The mock server URL must be ${backtick}http://localhost:9090/v1${backtick}.
    5.  **Correct Client Initialization:** You MUST use the provided ${backtick}<CLIENT_INIT_METHOD>${backtick} and ${backtick}<REFERENCED_TYPE_DEFINITIONS>${backtick} to correctly initialize the client.
    6.  **Full Test Coverage:** Generate a test function for each resource endpoint in the mock server.
    7.  **Correct Method Invocation Syntax:** ${analysis.methodType == "remote" ? "Use REMOTE method syntax (->methodName())" : "Use resource method syntax (->/path)"}.
    8.  **Smart Assertions:** Each test must contain assertions. Use ${backtick}test:assertTrue(response.data.length() > 0);${backtick} for arrays and ${backtick}test:assertTrue(response?.data !is ());${backtick} for records. Also, check that the ${backtick}errors${backtick} field is nil where appropriate.
    9.  **Proper Return Types:** For functions that return a non-record success response (e.g., HTTP 202 Accepted), the test variable should be of type ${backtick}error?${backtick}.
    10. **Advanced, Correct Assertions:**
        * For functions returning ${backtick}error?${backtick}, **you must use ${backtick}test:assertTrue(response is (), "...");${backtick}**. Crucially, **DO NOT use ${backtick}test:assertNil${backtick}**.
        * Apply the nuanced assertion strategy for records: check array length for arrays, check ${backtick}!is ()${backtick} for optional records, and check a nested field for mandatory records.
    9.  **Test Groups:** All test functions must be annotated with ${backtick}@test:Config { groups: ["live_tests", "mock_tests"] }${backtick}.

    **Example of a well-written test file structure:**
    ${tripleBacktick}ballerina
    // Copyright (c) 2025, WSO2 LLC. ([http://www.wso2.com](http://www.wso2.com)).
    // ... (rest of the header)

    import ballerina/os;
    import ballerina/test;
    import organization/twitter.mock.server as _;

    final boolean isLiveServer = os:getEnv("IS_LIVE_SERVER") == "true";
    final string token = isLiveServer ? os:getEnv("TWITTER_TOKEN") : "test_token";
    final string serviceUrl = isLiveServer ? "[https://api.twitter.com/2](https://api.twitter.com/2)" : "http://localhost:9090/v1";

    // This block MUST be constructed using the provided <CLIENT_INIT_METHOD> and <REFERENCED_TYPE_DEFINITIONS>
    ConnectionConfig config = {auth: {token}};
    final Client twitter = check new Client(config, serviceUrl);

    @test:Config {
        groups: ["live_tests", "mock_tests"]
    }
    isolated function testPostTweet() returns error? {
        TweetCreateResponse response = check twitter->/tweets.post(payload = {
            text: "My test tweet"
        });
        // Assertion for a single record response
        test:assertTrue(response?.data !is ());
        test:assertTrue(response?.errors is ());
    }

    @test:Config {
        groups: ["live_tests", "mock_tests"]
    }
    isolated function testFindSpecificUser() returns error? {
        Get2UsersResponse response = check twitter->/users(ids = ["2244994945"]);
        // Assertion for an array response
        test:assertTrue(response.data.length() > 0, "Expected a non-empty user array");
        test:assertTrue(response?.errors is ());
    }

    @test:Config {
        groups: ["live_tests", "mock_tests"]
    }
    isolated function testAddResourceToLibrary() returns error? {
        // Test for a response with no body, checking only for success.
        error? response = check appleMusicClient->/me/library.post(ids = ["1440857781"]);
        test:assertNil(response, "Expected no error on successful post");
    }
    ${tripleBacktick}

    Now, generate the complete and final ${backtick}test.bal${backtick} file.
`;
}

function createOperationSelectionPrompt(string[] operationIds, int maxOperations) returns string {
    string operationList = string:'join(", ", ...operationIds);

    return string `
You are an expert API designer. Your task is to select the ${maxOperations} most useful and frequently used operations from the following list of API operations.

**CRITICAL: Your response must be ONLY a comma-separated list of operation IDs with NO spaces between them. This will be used directly in a bal openapi command.**

<OPERATIONS>
${operationList}
</OPERATIONS>

Consider these criteria when selecting operations:
1. **Core CRUD Operations**: Basic create, read, update, delete operations
2. **Most Frequently Used**: Operations that developers typically use first
3. **Representative Coverage**: Cover different resource types (albums, songs, artists, etc.)
4. **Search & Discovery**: Include search and listing operations
5. **Authentication Flow**: Include any auth-related operations

For Apple Music API specifically, prioritize:
- Get catalog albums/artists/songs (single and multiple)
- Search functionality
- Library operations (get user's library content)
- Core browsing operations

Select exactly ${maxOperations} operation IDs that provide the most value for developers getting started with this API.

**IMPORTANT: Return ONLY the comma-separated list with no spaces, like this format:**
getAlbumsFromCatalog,getAlbumFromCatalog,getArtistsFromCatalog,getArtistFromCatalog,getSongsFromCatalog,getSongFromCatalog,getSearchResponseFromCatalog,getAlbumsFromLibrary,getArtistsFromLibrary,getSongsFromLibrary

Your response:`;
}


// SDK workflow prompt templates (live tests only, no mock server).
// Note: `backtick` is reused from the shared prompts.bal in this module.
string sdkTripleBacktick = "```";

function createSdkTestGenerationPrompt(ConnectorAnalysis analysis) returns string {
    string methodTypeGuidance = "";
    string methodSignaturesSection = "";

    if analysis.methodType == "remote" {
        methodTypeGuidance = string `
**CRITICAL - Remote Method Syntax:**
This connector uses REMOTE methods, NOT resource methods. You MUST use the following syntax:
- Correct: ${backtick}Type response = check client->methodName(param1, param2);${backtick}
- WRONG: ${backtick}Type response = check client->/path/to/resource();${backtick}

The method signatures are provided in <REMOTE_METHOD_SIGNATURES>. Use these exact method names and parameters.
`;

        methodSignaturesSection = string `
      <REMOTE_METHOD_SIGNATURES>
        ${analysis.remoteMethodSignatures}
      </REMOTE_METHOD_SIGNATURES>
`;
    } else {
        methodTypeGuidance = string `
This connector uses resource methods. Use the resource path syntax from the mock server.
`;
    }

    string enumSection = "";
    if analysis.enumDefinitions.length() > 0 {
        enumSection = string `
      <ENUM_DEFINITIONS>
        ${analysis.enumDefinitions}
      </ENUM_DEFINITIONS>
`;
    }

    return string `
    You are an expert Ballerina developer specializing in robust, production-quality LIVE integration tests for connectors. Your task is to generate a complete ${backtick}test.bal${backtick} file for the provided connector.

    **Phase 1: Reflection (Internal Monologue)**

    Before generating any code, I must reflect on the key requirements for a perfect test file.
    1.  **Output Purity:** The final output must be a single, complete, raw Ballerina source code file. No conversational text, no explanations, no apologies, and absolutely no markdown formatting like ${sdkTripleBacktick}ballerina.
    2.  **Client Initialization: This is the most critical and complex part.** The user has provided the exact ${backtick}<CLIENT_INIT_METHOD>${backtick} signature and the necessary ${backtick}<REFERENCED_TYPE_DEFINITIONS>${backtick}. I must meticulously use this information to construct the client initialization code. I cannot use a generic template; it must be tailored precisely to the provided context to avoid compilation errors.
    ${methodTypeGuidance}
    3.  **Environment Configuration (LIVE ONLY):**
      * There is NO mock server in this project.
      * Tests must run against live endpoints using the generated Ballerina client.
      * Use ${backtick}final${backtick} module-level variables initialized via ${backtick}os:getEnv("ENV_VAR_NAME")${backtick} for ALL credentials and connection details. Do NOT use ${backtick}configurable${backtick} variables.
      * Example pattern:
        ${backtick}final string accessKey = os:getEnv("ACCESS_KEY");${backtick}
        ${backtick}final string secretKey = os:getEnv("SECRET_KEY");${backtick}
        ${backtick}final string region = os:getEnv("REGION");${backtick}
      * Derive the environment variable names from the ConnectionConfig field names (uppercased with underscores). Do NOT hard-code vendor-specific names.
      * Define boolean gating flags such as ${backtick}testsEnabled${backtick} that check whether the required environment variables are non-empty:
        ${backtick}final boolean testsEnabled = accessKey.length() > 0 && secretKey.length() > 0;${backtick}
      * If listener-specific tests exist, similarly define ${backtick}listenerTestsEnabled${backtick}.
    4.  **Test Function Logic & Assertions:** My goal is to verify API behavior, response shape, and error handling for live calls.
        * **Coverage target:** Generate AT LEAST one primary happy-path test for EVERY client operation listed in the signatures/paths. Then add additional edge-case and use-case tests for operations that accept optional parameters, produce different result shapes, or involve state transitions (create→use→delete). The total test count should comfortably exceed the number of client operations.
        * A common pitfall to avoid is using direct HTTP return types like ${backtick}http:Accepted${backtick}. If a successful response has no body, the function should assign the result to ${backtick}error?${backtick} and the test's purpose is to ensure no error is returned.
        * Every test function MUST include assertions to validate the response.
        * NEVER write tautological assertions that can become always-true hints (e.g., ${backtick}(value is string) && (<string>value).length() > 0${backtick} after non-nil checks).
        * NEVER write assertions that are logically always true, such as:
          - ${backtick}test:assertTrue(x !is () || x is (), ...);${backtick}
          - ${backtick}test:assertTrue(response is SomeResponseType, ...);${backtick} when ${backtick}response${backtick} is already declared as ${backtick}SomeResponseType${backtick}
        * For optional fields, write meaningful checks only when appropriate:
          - If field may legally be absent, DO NOT assert type compatibility using unions like ${backtick}value is T || value is ()${backtick} (this is redundant and triggers compiler hints).
          - Instead, assert behavior only in the non-nil branch (e.g., ${backtick}if value is T { test:assertTrue(...); }${backtick}) and otherwise skip optional-field assertions.
          - If field is required for the operation's success path, assert non-empty/non-nil value directly.
        * Prefer assertions like ${backtick}test:assertTrue((value ?: "").length() > 0, ...);${backtick}.
        * **Live API Behavior Expectations (CRITICAL):**
          - Optional fields in live API responses are often nil/empty when not populated, even on successful calls
          - Array results may be completely empty (zero items) when no data matches the query
          - Collections (lists, arrays) may return nil instead of empty array structure
          - Previously created resources may still exist from earlier test runs; assertions must tolerate this
          - Assertions should validate required fields or successful behavior, not redundant static type checks
        * **Assertion Strategy:**
            * For responses that return a single record (object), do NOT assert ${backtick}response is ResponseType${backtick} when ${backtick}response${backtick} is already declared as that type.
            * For optional fields within that response, only assert if they are required for the operation to succeed; do NOT assert optional fields are non-nil
            * For responses that return arrays or list fields, prefer checks on length/required content only when semantically required by the operation.
            * Where applicable, also assert that the ${backtick}errors${backtick} field is nil: ${backtick}test:assertTrue(response?.errors is ());${backtick}.
            * Avoid any assertion that the compiler can prove always true at compile time.
    5.  **Completeness and Correctness:** I must ensure all necessary imports (${backtick}ballerina/os${backtick}, ${backtick}ballerina/test${backtick}, etc.) are present and that the entire file is syntactically correct and ready to compile.

    **Phase 2: Execution**

    Based on my reflection, I will now generate the complete ${backtick}test.bal${backtick} file with extreme precision.

    <CONTEXT>
      <PACKAGE_NAME>
        ${analysis.packageName}
      </PACKAGE_NAME>
      <CLIENT_INIT_METHOD>
        ${analysis.initMethodSignature}
      </CLIENT_INIT_METHOD>
      <REFERENCED_TYPE_DEFINITIONS>
        ${analysis.referencedTypeDefinitions}
      </REFERENCED_TYPE_DEFINITIONS>
      <CONNECTION_CONFIG_DEFINITION>
        ${analysis.connectionConfigDefinition}
      </CONNECTION_CONFIG_DEFINITION>
${enumSection}${methodSignaturesSection}
    </CONTEXT>

    **Requirements:**
    1.  **Complete File:** Your response must be a single, raw, and complete Ballerina source code file. Do not include any code fences in the response.
    2.  **Copyright Header:** The generated file must start with the standard Ballerina copyright header.
    3.  **Imports:** Include ${backtick}import ballerina/os;${backtick}, ${backtick}import ballerina/test;${backtick}, and connector imports. Include ${backtick}import ballerina/io;${backtick} when printing runtime notices. Do NOT import any mock server module.
    4.  **Environment Setup:** Build client configuration from ${backtick}final${backtick} variables populated via ${backtick}os:getEnv()${backtick}. Implement helper functions like ${backtick}isLiveTestEnabled()${backtick} and ${backtick}getClient()${backtick}. Include comments showing which environment variables to export before running tests.
        - Use a sentinel error prefix exactly: ${backtick}LIVE_TEST_DISABLED:${backtick}
        - If required env vars are empty/missing, return ${backtick}error("LIVE_TEST_DISABLED: ...")${backtick}.
        - If runtime/client creation panics or returns an error for other reasons, return that error (test must fail, not silently pass).
    5.  **Correct Client Initialization:** You MUST use the provided ${backtick}<CLIENT_INIT_METHOD>${backtick} and ${backtick}<REFERENCED_TYPE_DEFINITIONS>${backtick} to correctly initialize the client.
    6.  **Full Test Coverage:** Generate test functions for ALL client operations present in the provided signatures. Do not skip any operation. For operations that accept optional parameters or involve state transitions, add additional edge-case tests so total tests comfortably exceed the operation count.
    7.  **Correct Method Invocation Syntax:** ${analysis.methodType == "remote" ? "Use REMOTE method syntax (->methodName())" : "Use resource method syntax (->/path)"}.
    8.  **Smart Assertions:** Each test must contain assertions.
    9.  **Proper Return Types:** For functions that return a non-record success response (e.g., HTTP 202 Accepted), the test variable should be of type ${backtick}error?${backtick}.
    10. **Advanced, Correct Assertions:**
        * For functions returning ${backtick}error?${backtick}, **you must use ${backtick}test:assertTrue(response is (), "...");${backtick}**. Crucially, **DO NOT use ${backtick}test:assertNil${backtick}**.
        * Apply the nuanced assertion strategy for records: check array length for arrays, check ${backtick}!is ()${backtick} for optional records, and check a nested field for mandatory records.
      * Never generate redundant assertions like ${backtick}test:assertTrue(response is SomeType, ...);${backtick} when ${backtick}response${backtick} is already statically typed as ${backtick}SomeType${backtick}.
      * Do not create unused local variables; if a return value is intentionally ignored, assign it to ${backtick}_${backtick} (e.g., ${backtick}_ = os:setEnv("KEY", value);${backtick}).
    11. **Strict Enum Usage:** If ${backtick}<ENUM_DEFINITIONS>${backtick} is provided, use enum member names only where the Ballerina parameter type is explicitly an enum type.
        * **CRITICAL - Never use enum members as optional array parameter values** (e.g. do NOT write ${backtick}attributeNames = [SOME_ENUM]${backtick}). If a method has an optional array parameter, simply omit it — call the method without that argument and the API will provide a default response.
        * **CRITICAL - Never use computed enum key syntax in map literals** (e.g. do NOT write ${backtick}{[ENUM_KEY]: "value"}${backtick}). For ${backtick}map<string>${backtick} parameters, always use plain string literal keys matching the API's expected format.
    12. **Resource Name Uniqueness (CRITICAL for Live Testing):** When creating test resources (queues, topics, buckets, entities, etc.), use unique names to differentiate test executions.
        * Do NOT use hardcoded resource names that conflict on repeated runs
        * Use a pattern like: ${backtick}const string TEST_RESOURCE_NAME = "test_resource_" + check time:uuid();${backtick} or similar unique identifier
        * This prevents "resource already exists" or "name conflict" errors when tests run multiple times against the live API
    13. **Test Enable/Disable Behavior (NO groups):**
      * Do NOT add any ${backtick}groups${backtick} field to ${backtick}@test:Config${backtick}. This project has only live tests — there is no group distinction.
      * All standard live tests must use ${backtick}@test:Config { enable: testsEnabled }${backtick}.
      * If listener-specific tests are generated, annotate them with ${backtick}@test:Config { enable: listenerTestsEnabled }${backtick}.
      * Do NOT implement skip-by-return as the primary mechanism for missing credentials.
      * Add a dedicated credential-notice test function (e.g. ${backtick}testLiveCredentialSkipNotice${backtick}) with ${backtick}@test:Config { enable: !testsEnabled }${backtick} that prints a clear message like "Live tests are skipped because required credentials are not set" and performs a trivial pass assertion.
    14. **Test Ordering with dependsOn:** Use ${backtick}dependsOn${backtick} ONLY where one test truly requires state created by another (e.g. a "send message" test depends on "create resource"). Do NOT add dependsOn to independent tests.
    15. **Runtime Gating Rule:**
      - At test start, obtain client via helper: ${backtick}Client|error clientResult = getClient();${backtick}
      - Primary skipping must come from ${backtick}@test:Config.enable${backtick} using the ${backtick}final boolean testsEnabled${backtick} flag (derived from env vars).
      - If ${backtick}getClient()${backtick} still returns ${backtick}LIVE_TEST_DISABLED:${backtick}, treat it as a defensive fallback and keep behavior consistent with the enable-based gating strategy.
      - For non-disable errors, return the error from the test function (fail test).
    16. **Resource Helper:** Provide a helper (e.g. ${backtick}getTestResourceUrl${backtick}) that tries an env-var first, then falls back to creating the resource via the client (idempotent create-or-get pattern) so tests are self-contained without mandatory env setup beyond credentials.
    17. **No Vendor or SDK References:** Do not add any vendor or SDK references in generated comments, test names, assertion messages, or helper descriptions. Keep wording generic and connector-centric. Do NOT mention specific tool names, SDK versions, or vendor product names in code comments.

    Now, generate the complete and final ${backtick}test.bal${backtick} file.
`;
}

function sdkCreateOperationSelectionPrompt(string[] operationIds, int maxOperations) returns string {
    string operationList = string:'join(", ", ...operationIds);

    return string `
You are an expert API designer. Your task is to select the ${maxOperations} most useful and frequently used operations from the following list of API operations.

**CRITICAL: Your response must be ONLY a comma-separated list of operation IDs with NO spaces between them. This will be used directly in a bal openapi command.**

<OPERATIONS>
${operationList}
</OPERATIONS>

Consider these criteria when selecting operations:
1. **Core CRUD Operations**: Basic create, read, update, delete operations
2. **Most Frequently Used**: Operations that developers typically use first
3. **Representative Coverage**: Cover different resource types available in the API
4. **Search & Discovery**: Include search and listing operations
5. **Lifecycle Operations**: Include setup, teardown, and configuration operations

Select exactly ${maxOperations} operation IDs that provide the most value for developers getting started with this API.

**IMPORTANT: Return ONLY the comma-separated list with no spaces, like this format:**
createResource,getResource,listResources,updateResource,deleteResource,searchResources

Your response:`;
}
