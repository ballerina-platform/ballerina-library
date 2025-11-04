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
    return string `
    You are an expert Ballerina developer specializing in writing robust, production-quality test suites for connectors. Your task is to generate a comprehensive test file (${backtick}test.bal${backtick}) for the provided connector.

    **Phase 1: Reflection (Internal Monologue)**

    Before generating any code, I must reflect on the key requirements for a perfect test file.
    1.  **Output Purity:** The final output must be a single, complete, raw Ballerina source code file. No conversational text, no explanations, no apologies, and absolutely no markdown formatting like ${tripleBacktick}ballerina.
    2.  **Client Initialization: This is the most critical and complex part.** The user has provided the exact ${backtick}<CLIENT_INIT_METHOD>${backtick} signature and the necessary ${backtick}<REFERENCED_TYPE_DEFINITIONS>${backtick}. I must meticulously use this information to construct the client initialization code. I cannot use a generic template; it must be tailored precisely to the provided context to avoid compilation errors.
    3.  **Environment Configuration:** I need to set up a flexible testing environment. This involves:
        * A configurable boolean ${backtick}isLiveServer${backtick} to switch between environments, reading from an environment variable.
        * A configurable ${backtick}serviceUrl${backtick} that points to the real API for live tests and to ${backtick}http://localhost:9090${backtick} for mock tests.
        * Configurable variables for credentials (e.g., tokens, keys) that are read from environment variables only when ${backtick}isLiveServer${backtick} is true.
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
    </CONTEXT>

    **Requirements:**
    1.  **Complete File:** Your response must be a single, raw, and complete Ballerina source code file. Do not include any code fences in the response.
    2.  **Copyright Header:** The generated file must start with the standard Ballerina copyright header.
    3.  **Imports:** Include ${backtick}import ballerina/os;${backtick}, ${backtick}import ballerina/test;${backtick}, and the mock server import: ${backtick}import ${analysis.packageName}.mock.server as _;${backtick}.
    4.  **Environment Setup:** Implement configurable variables for ${backtick}isLiveServer${backtick}, ${backtick}serviceUrl${backtick}, and any necessary credentials as shown in the example. The mock server URL must be ${backtick}http://localhost:9090/v1${backtick}.
    5.  **Correct Client Initialization:** You MUST use the provided ${backtick}<CLIENT_INIT_METHOD>${backtick} and ${backtick}<REFERENCED_TYPE_DEFINITIONS>${backtick} to correctly initialize the client.
    6.  **Full Test Coverage:** Generate a test function for each resource endpoint in the mock server.
    7.  **Smart Assertions:** Each test must contain assertions. Use ${backtick}test:assertTrue(response.data.length() > 0);${backtick} for arrays and ${backtick}test:assertTrue(response?.data !is ());${backtick} for records. Also, check that the ${backtick}errors${backtick} field is nil where appropriate.
    8.  **Proper Return Types:** For functions that return a non-record success response (e.g., HTTP 202 Accepted), the test variable should be of type ${backtick}error?${backtick}.
    9. **Advanced, Correct Assertions:**
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

    configurable boolean isLiveServer = os:getEnv("IS_LIVE_SERVER") == "true";
    configurable string token = isLiveServer ? os:getEnv("TWITTER_TOKEN") : "test_token";
    configurable string serviceUrl = isLiveServer ? "[https://api.twitter.com/2](https://api.twitter.com/2)" : "http://localhost:9090/v1";

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
