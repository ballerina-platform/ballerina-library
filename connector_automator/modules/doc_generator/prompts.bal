string backtick = "`";
string tripleBacktick = "```";

// Prompt generation functions for Ballerina README
function createBallerinaOverviewPrompt(ConnectorMetadata metadata) returns string {

    return string `
You are a professional technical writer creating the "Overview" section for a Ballerina connector's README.md file. Your task is to generate a concise, two-paragraph overview that is perfectly structured and contains accurate, verified hyperlinks.

**Your Goal:** Generate an overview that precisely matches the style, tone, and format of the example below.
--- 
**PERFECT OUTPUT EXAMPLE (for Smartsheet):**

## Overview

[Smartsheet](https://www.smartsheet.com/) is a cloud-based platform that enables teams to plan, capture, manage, automate, and report on work at scale, empowering you to move from idea to impact, fast.

The ${backtick}ballerinax/smartsheet${backtick} package offers APIs to connect and interact with [Smartsheet API](https://developers.smartsheet.com/api/smartsheet/introduction) endpoints, specifically based on [Smartsheet API v2.0](https://developers.smartsheet.com/api/smartsheet/openapi).
---

**TASK INSTRUCTIONS:**

Now, generate a new overview for the following connector. DONT include any follow up questions or your opinions or any thing other than the given format. Follow these rules meticulously:

1.  **Research:** You MUST perform a web search to find the official homepage and the developer API documentation for the service.
2.  **Paragraph 1 (The Service):**
    * Write a single, compelling sentence describing what the service is and its primary value.
    * The very first mention of the service name MUST be a Markdown link to its official homepage.
3.  **Paragraph 2 (The Connector):**
    * The paragraph must start with "The ${backtick}ballerinax/[connector_lowercase_name]${backtick} package offers APIs to connect and interact with...".
    * It must include a Markdown link for the phrase "[Service Name] API" that points to the main developer portal or API documentation page you found.
    * **Crucially:** End the sentence by specifying the API version. Search for the specific API version number (e.g., v3, v2.0, 2024-04). If you can find a link to that specific version's documentation (like an OpenAPI spec), link to it.
    * **Fallback:** If you cannot find a specific, stable version number, you may state that it is based on "a recent version of the API" and use the general API documentation link again. Do not invent a version number.

Connector Information:
${getConnectorSummary(metadata)}
`;
}

function createBallerinaSetupPrompt(ConnectorMetadata metadata) returns string {
    string connectorName = metadata.connectorName;

    return string `
You are a technical writer creating the "Setup guide" section for a Ballerina connector's README.md file. Your task is to explain how a user can get the necessary API credentials from the third-party service.

Your goal is to generate a guide that is **structurally and tonally identical** to the perfect example provided below.

---
**PERFECT OUTPUT EXAMPLE (for Smartsheet):**

## Setup guide

To use the Smartsheet connector, you must have access to the Smartsheet API through a [Smartsheet developer account](${backtick}https://developers.smartsheet.com/${backtick}) and obtain an API access token. If you do not have a Smartsheet account, you can sign up for one [here](${backtick}https://www.smartsheet.com/try-it${backtick}).

### Step 1: Create a Smartsheet Account

1. Navigate to the [Smartsheet website](${backtick}https://www.smartsheet.com/${backtick}) and sign up for an account or log in if you already have one.

2. Ensure you have a Business or Enterprise plan, as the Smartsheet API is restricted to users on these plans.

### Step 2: Generate an API Access Token

1. Log in to your Smartsheet account.

2. On the left Navigation Bar at the bottom, select Account (your profile image), then Personal Settings.

3. In the new window, navigate to the API Access tab and select Generate new access token.

> **Tip:** You must copy and store this key somewhere safe. It won't be visible again in your account settings for security reasons.

---

**TASK INSTRUCTIONS:**

Now, generate a new "Setup guide" section for the ${connectorName} connector specified below. You must adhere to these rules strictly:

1.  **Perform Web Research:** You MUST search the web to find the following for the service:
    * The main website / sign-up page.
    * The developer portal or API documentation homepage.
    * An official guide or help article on how to generate API keys/access tokens.

2.  **Follow the Exact Structure:** Use the ${backtick}## Setup guide${backtick}, ${backtick}### Step 1${backtick}, and ${backtick}### Step 2${backtick} headers precisely as shown in the example.

3.  **Introductory Paragraph:** Write a paragraph explaining the need for an account and API token. It must include a Markdown link to the developer portal and the main sign-up page you found.

4.  **Step 1 (Create Account):**
    * Provide a link to the main website.
    * **Crucially, research and mention if the API access is limited to specific subscription plans** (e.g., "Business or Enterprise plan", "Pro plan or higher").

5.  **Step 2 (Generate Token):**
    * Provide clear, step-by-step instructions on how to find the API key generation page within the service's user interface.
    * **Use the official guide you researched to make these steps accurate.** (e.g., "Navigate to Settings > Developer > API Keys").

6.  **Include the Tip:** End the section with the exact "> **Tip:** ..." blockquote about saving the key securely.

**CONNECTOR INFORMATION TO USE:**
connector name: ${connectorName}

Generate the "Setup guide" section now.
`;
}

function createBallerinaQuickstartPrompt(ConnectorMetadata metadata) returns string {

    string connectorName = metadata.connectorName;

    return string `
You are an expert Ballerina technical writer and developer. Your task is to create a complete and perfect "Quickstart" section for a Ballerina connector's README.md file.

You MUST analyze the provided source code (${backtick}client.bal${backtick} and ${backtick}types.bal${backtick}) and follow the examples and rules below with extreme precision.

---
**PERFECT OUTPUT EXAMPLES:**

**Example 1: Bearer Token Auth with Simple Payload (Slack)**
<details>
  <summary>Click to view Slack example</summary>
  
  ## Quickstart
  
  To use the ${backtick}slack${backtick} connector in your Ballerina application, update the ${backtick}.bal${backtick} file as follows:
  
  ### Step 1: Import the module
  
  ${tripleBacktick}ballerina
  import ballerinax/slack;
  ${tripleBacktick}
  
  ### Step 2: Instantiate a new connector
  
  1. Create a ${backtick}Config.toml${backtick} file and configure the obtained access token:
  
  ${tripleBacktick}toml
  token = "<Your_Slack_Access_Token>"
  ${tripleBacktick}
  
  2. Create a ${backtick}slack:ConnectionConfig${backtick} and initialize the client:
  
  ${tripleBacktick}ballerina
  configurable string token = ?;
  
  final slack:Client slackClient = check new({
      auth: {
          token
      }
  });
  ${tripleBacktick}
  
  ### Step 3: Invoke the connector operation
  
  Now, utilize the available connector operations.
  
  #### Post a message
  
  ${tripleBacktick}ballerina
  public function main() returns error? {
      slack:ChatPostMessageResponse response = check slackClient->/chat\.postMessage.post({
          channel: "general", 
          text: "Hello from Ballerina!"
      });
  }
  ${tripleBacktick}
  
  ### Step 4: Run the Ballerina application
  
  ${tripleBacktick}bash
  bal run
  ${tripleBacktick}
</details>

**Example 2: OAuth2 Auth with Complex Payload (HubSpot Forms)**
<details>
  <summary>Click to view HubSpot Forms example</summary>

  ## Quickstart

  To use the ${backtick}HubSpot Marketing Forms${backtick} connector in your Ballerina application, update the ${backtick}.bal${backtick} file as follows:

  ### Step 1: Import the module
  
  ${tripleBacktick}ballerina
  import ballerina/oauth2;
  import ballerinax/hubspot.marketing.forms as hsmforms;
  ${tripleBacktick}
  
  ### Step 2: Instantiate a new connector
  
  1. Create a ${backtick}Config.toml${backtick} file with your credentials:
  
  ${tripleBacktick}toml
  clientId = "<Your_Client_Id>"
  clientSecret = "<Your_Client_Secret>"
  refreshToken = "<Your_Refresh_Token>"
  ${tripleBacktick}
  
  2. Create a ${backtick}hsmforms:ConnectionConfig${backtick} and initialize the client:
  
  ${tripleBacktick}ballerina
  configurable string clientId = ?;
  configurable string clientSecret = ?;
  configurable string refreshToken = ?;
  
  final hsmforms:Client hsmformsClient = check new({
      auth: {
          clientId,
          clientSecret,
          refreshToken
      }
  });
  ${tripleBacktick}
  
  ### Step 3: Invoke the connector operation
  
  Now, utilize the available connector operations.
  
  #### Create a new form
  
  ${tripleBacktick}ballerina
  public function main() returns error? {
      hsmforms:FormDefinitionCreateRequestBase newForm = {
          formType: "hubspot",
          name: "New Lead Capture Form",
          archived: false,
          fieldGroups: [
              {
                  fields: [
                      {
                          objectTypeId: "0-1",
                          name: "email",
                          label: "Email",
                          fieldType: "email",
                          required: true
                      }
                  ]
              }
          ]
      };
  
      hsmforms:FormDefinitionBase response = check hsmformsClient->/.post(newForm);
  }
  ${tripleBacktick}
  
  ### Step 4: Run the Ballerina application
  
  ${tripleBacktick}bash
  bal run
  ${tripleBacktick}
</details>

**Example 3: OAuth2 Auth with No Payload / GET (HubSpot CRM Imports)**
<details>
  <summary>Click to view HubSpot Imports example</summary>
  
  ## Quickstart
  
  ### Step 3: Invoke the connector operation
  
  #### Get a paged list of active imports
  
  ${tripleBacktick}ballerina
  public function main() returns error? {
      crmImport:CollectionResponsePublicImportResponse response = check crmImportsClient->/.get({});
  }
  ${tripleBacktick}
</details>

---

**MASTER INSTRUCTIONS CHECKLIST:**

You must follow this checklist to generate the new Quickstart section.

**1.  Analyze Authentication:**
    * **Action:** Look for ${backtick}public type ConnectionConfig${backtick} in ${backtick}types.bal${backtick}.
    * **Rule:** If the ${backtick}auth${backtick} field uses ${backtick}oauth2:OAuth2RefreshTokenGrantConfig${backtick}, you MUST generate the **OAuth2 pattern** (like Example 2). This requires importing ${backtick}ballerina/oauth2${backtick}, using ${backtick}clientId${backtick}, ${backtick}clientSecret${backtick}, ${backtick}refreshToken${backtick} in ${backtick}Config.toml${backtick}, and initializing the client with those configurable variables.
    * **Rule:** Otherwise, generate the **Bearer Token pattern** (like Example 1). This requires a simple ${backtick}token${backtick} in ${backtick}Config.toml${backtick}.

**2.  Handle Imports:**
    * **Rule:** If the module name (e.g., ${backtick}hubspot.marketing.forms${backtick}) contains dots, you MUST use an alias in the import statement (e.g., ${backtick}import ballerinax/hubspot.marketing.forms as hsmforms;${backtick}).
    * **Rule:** Always import ${backtick}ballerina/oauth2${backtick} for the OAuth2 pattern.

**3.  Select the Best Operation:**
    * **Action:** Analyze the resource and remote functions in ${backtick}client.bal${backtick}.
    * **Priority 1:** Choose a **${backtick}POST${backtick}** operation that clearly creates a new resource (e.g., a function that takes a request body payload).
    * **Priority 2:** If no suitable ${backtick}POST${backtick} is found, choose a **${backtick}GET${backtick}** operation that lists resources and does not require path parameters.

**4.  Construct the Payload:**
    * **Action:** Identify the request payload type from the signature of the operation you selected in ${backtick}client.bal${backtick}.
    * **Action:** Find the full definition of that type in ${backtick}types.bal${backtick}.
    * **Rule:** Create a variable of that type. Populate it with **simple, realistic placeholder data**. For example, use ${backtick}"New Contact Form"${backtick} for a name, not an empty string or ${backtick}"<name>"${backtick}. Only include a few essential fields to keep the example clean.
    * **CRITICAL Rule:** If you chose a ${backtick}GET${backtick} operation that does not take a payload (like Example 3), you MUST call it with an empty map: ${backtick}check client->/path.get({});${backtick}.

**5.  Assemble the Code:**
    * **Rule:** All code in Step 3 must be inside a ${backtick}public function main() returns error? { ... }${backtick}.
    * **Rule:** Create a sensible, camelCase variable name for the client instance (e.g., ${backtick}slackClient${backtick}, ${backtick}hubspotFormsClient${backtick}). Use this variable when invoking the operation.
    * **Rule:** Create a ${backtick}####${backtick} sub-heading for the operation description (e.g., ${backtick}#### Create a new form${backtick}).

**SOURCE CODE FOR YOUR ANALYSIS:**

**Connector Name:** ${connectorName}

**${backtick}client.bal${backtick} Content:**
${tripleBacktick}ballerina
${metadata.clientBalContent}
${tripleBacktick}

**${backtick}types.bal${backtick} Content:**
${tripleBacktick}ballerina
${metadata.typesBalContent}
${tripleBacktick}

---

Generate the complete and final ${backtick}## Quickstart${backtick} section now.
`;
}

function createBallerinaExamplesPrompt(ConnectorMetadata metadata) returns string {

    return string `

You are a technical writer tasked with creating the "Examples" section for a Ballerina connector's README.md file.

Your goal is to generate a section that is **structurally identical** to the perfect example provided below, including the exact introductory paragraph and the formatted list.

---
**PERFECT OUTPUT EXAMPLE (for Smartsheet):**

## Examples

The ${backtick}Smartsheet${backtick} connector provides practical examples illustrating usage in various scenarios. Explore these [examples](https://github.com/ballerina-platform/module-ballerinax-smartsheet/tree/main/examples), covering the following use cases:

1. [Project task management](https://github.com/ballerina-platform/module-ballerinax-smartsheet/tree/main/examples/project_task_management) - Demonstrates how to automate project task creation using Ballerina connector for Smartsheet.
2. [Basic sheet operations](https://github.com/ballerina-platform/module-ballerinax-smartsheet/tree/main/examples/basic_sheet_operations) - Illustrates creating, retrieving, and deleting sheets.

---

**TASK INSTRUCTIONS:**

Now, generate a new "Examples" section for the connector specified below. You must follow these rules precisely:

1.  **Replicate the Header and Intro:** Start with the ${backtick}## Examples${backtick} header. Use the exact introductory paragraph from the example, replacing the connector name and the main examples URL with the information provided. The main examples URL is the GitHub Repo URL followed by ${backtick}/tree/main/examples${backtick}.

2.  **Create an Ordered List:** For each example directory name provided in the "Connector Information", create one item in an ordered list (1., 2., 3., etc.).

3.  **Format Each List Item:** Each item in the list MUST follow this exact format:
    ${backtick}[Example Title](URL_to_example) - One-sentence description.${backtick}
    * **Example Title:** Convert the snake_case directory name (e.g., ${backtick}project_task_management${backtick}) into a human-readable, lowercase title (e.g., "project task management").
    * **URL_to_example:** Construct the full URL to the specific example's directory. This will be ${backtick}[GitHub_Repo_URL]/tree/main/examples/[example_directory_name]${backtick}.
    * **One-sentence description:** Write a single, concise sentence that summarizes the purpose of the example based on its name.

**CONNECTOR INFORMATION TO USE:**
${getConnectorSummary(metadata)}
Available Examples: ${metadata.examples.toString()}
`;
}

// prompt generation functions for tests README

function createTestReadmePrompt(ConnectorMetadata metadata) returns string {

    string conectorName = metadata.connectorName;
    string lowerCaseConnectorName = conectorName.toLowerAscii();

    return string `
    You are a senior Ballerina developer creating the README.md file for the tests directory of a Ballerina connector.

Your goal is to generate a complete "Running Tests" guide that is **structurally and textually identical** to the perfect example provided below, only replacing the service-specific placeholders.

---
**PERFECT OUTPUT EXAMPLE (for Smartsheet):**

# Running Tests

## Prerequisites
You need an API Access token from Smartsheet developer account.

To do this, refer to [Ballerina Smartsheet Connector](${backtick}https://github.com/ballerina-platform/module-ballerinax-smartsheet/blob/main/ballerina/README.md${backtick}).

## Running Tests

There are two test environments for running the Smartsheet connector tests. The default test environment is the mock server for Smartsheet API. The other test environment is the actual Smartsheet API.

You can run the tests in either of these environments and each has its own compatible set of tests.

 Test Groups | Environment
-------------|---------------------------------------------------
 mock_tests  | Mock server for Smartsheet API (Default Environment)
 live_tests  | Smartsheet API

## Running Tests in the Mock Server

To execute the tests on the mock server, ensure that the ${backtick}IS_LIVE_SERVER${backtick} environment variable is either set to ${backtick}false${backtick} or unset before initiating the tests.

This environment variable can be configured within the ${backtick}Config.toml${backtick} file located in the tests directory or specified as an environmental variable.

#### Using a Config.toml File

Create a ${backtick}Config.toml${backtick} file in the tests directory and the following content:

${tripleBacktick}toml
isLiveServer = false
${tripleBacktick}

#### Using Environment Variables

Alternatively, you can set your authentication credentials as environment variables:
If you are using linux or mac, you can use following method:
${tripleBacktick}bash
   export IS_LIVE_SERVER=false
${tripleBacktick}
If you are using Windows you can use following method:
${tripleBacktick}bash
   setx IS_LIVE_SERVER false
${tripleBacktick}
Then, run the following command to run the tests:

${tripleBacktick}bash
   ./gradlew clean test
${tripleBacktick}

## Running Tests Against Smartsheet Live API

#### Using a Config.toml File

Create a ${backtick}Config.toml${backtick} file in the tests directory and add your authentication credentials:

${tripleBacktick}toml
   isLiveServer = true
   token = "<your-smartsheet-access-token>"
${tripleBacktick}

#### Using Environment Variables

Alternatively, you can set your authentication credentials as environment variables:
If you are using linux or mac, you can use following method:
${tripleBacktick}bash
   export IS_LIVE_SERVER=true
   export SMARTSHEET_TOKEN="<your-smartsheet-access-token>"
${tripleBacktick}

If you are using Windows you can use following method:
${tripleBacktick}bash
   setx IS_LIVE_SERVER true
   setx SMARTSHEET_TOKEN <your-smartsheet-access-token>
${tripleBacktick}
Then, run the following command to run the tests:

${tripleBacktick}bash
   ./gradlew clean test
${tripleBacktick}
---

**TASK INSTRUCTIONS:**

Now, generate a new "Running Tests" README for the connector specified below. You must use the example above as a strict template and replace the placeholders as follows:

1.  Replace every instance of **"Smartsheet"** with **"${conectorName}"**.
2.  Replace every instance of **"smartsheet"** (in lowercase) with **"${lowerCaseConnectorName}"**. This applies to URLs and token placeholders like ${backtick}<your-smartsheet-access-token>${backtick}.
3.  Replace the link to the main README with the link matching the provided GitHub Repo URL, specifically pointing to ${backtick}/ballerina/README.md${backtick}.
4.  In the final "Environment Variables" section for the live API, replace **"SMARTSHEET_TOKEN"** with **"[CONNECTOR_UPPERCASE_NAME]_TOKEN"**.
5.  All other text, formatting, code blocks, and commands must be kept exactly the same.

Generate the complete "Running Tests" README now.
`;

}

// prompt generation functions for main README

function createHeaderAndBadges(ConnectorMetadata metadata) returns string {
    string connectorName = metadata.connectorName;
    string lowercaseConnectorName = connectorName.toLowerAscii();
    string githubRepoUrl = string `https://github.com/ballerina-platform/module-ballerinax-${lowercaseConnectorName}`;
    string githubOrgAndRepo = string `ballerina-platform/module-ballerinax-${lowercaseConnectorName}`;

    return string `
# Ballerina ${metadata.connectorName} connector

[![Build](${githubRepoUrl}/actions/workflows/ci.yml/badge.svg)](${githubRepoUrl}/actions/workflows/ci.yml)
[![Trivy](${githubRepoUrl}/actions/workflows/trivy-scan.yml/badge.svg)](${githubRepoUrl}/actions/workflows/trivy-scan.yml)
[![GraalVM Check](${githubRepoUrl}/actions/workflows/build-with-bal-test-graalvm.yml/badge.svg)](${githubRepoUrl}/actions/workflows/build-with-bal-test-graalvm.yml)
[![GitHub Last Commit](https://img.shields.io/github/last-commit/${githubOrgAndRepo}.svg)](https://github.com/${githubOrgAndRepo}/commits/master)
[![GitHub Issues](https://img.shields.io/github/issues/ballerina-platform/ballerina-library/module/${lowercaseConnectorName}.svg?label=Open%20Issues)](https://github.com/ballerina-platform/ballerina-library/labels/module%${lowercaseConnectorName})
`;
}

function createUsefulLinksSection(ConnectorMetadata metadata) returns string {

    string lowercaseName = metadata.connectorName.toLowerAscii();
    return string `
## Useful links

* For more information go to the [${backtick}${lowercaseName}${backtick} package](https://central.ballerina.io/ballerinax/${lowercaseName}/latest).
* For example demonstrations of the usage, go to [Ballerina By Examples](https://ballerina.io/learn/by-example/).
* Chat live with us via our [Discord server](https://discord.gg/ballerinalang).
* Post all technical questions on Stack Overflow with the [#ballerina](https://stackoverflow.com/questions/tagged/ballerina) tag.
`;
}

// prompt generation functions for example README
public function createIndividualExamplePrompt(ExampleData exampleData, ConnectorMetadata connectorMetadata) returns string {
    return string `
    You are a senior Ballerina developer and technical writer. Your goal is to create a complete, self-contained README.md file for a single Ballerina example. The structure of the README **must adapt** based on the patterns you identify in the provided Ballerina code.

---
**PERFECT OUTPUT EXAMPLES (Notice the differences):**

**Example 1: HTTP Service with Multiple Connectors (Bearer Token)**
<details>
  <summary>Click to view HTTP Service example</summary>
  
  # Project Task Management Integration
  
  This example demonstrates how to automate project task creation...
  
  ## Prerequisites
  
  1. **Smartsheet Setup**
     > Refer the [Smartsheet setup guide](${backtick}https://...${backtick}) here.
  
  2. **Slack Setup**
     > Refer the [Slack setup guide](${backtick}https://...${backtick}) here.
  
  3. For this example, create a ${backtick}Config.toml${backtick} file with your credentials:
  
  ${tripleBacktick}toml
  smartsheetToken = "SMARTSHEET_ACCESS_TOKEN"
  slackToken = "SLACK_TOKEN"
  ...
  ${tripleBacktick}
  
  ## Run the Example
  
  1. Execute the command:
  
  ${tripleBacktick}bash
  bal run
  ${tripleBacktick}
  
  2. The service will start. You can test it by sending a POST request:
  
  ${tripleBacktick}bash
  curl -X POST http://localhost:8080/projects ...
  ${tripleBacktick}
</details>

**Example 2: Command-Line Script with OAuth2**
<details>
  <summary>Click to view Command-Line Script example</summary>

  # Customer Feedback Import
  
  This use case demonstrates how to import CRM records...
  
  ## Prerequisites
  
  1. **Setup HubSpot developer account**
     > Refer to the [Setup guide](${backtick}https://...${backtick}) to obtain credentials.
  
  2. **Configuration**
     Create a ${backtick}Config.toml${backtick} file...
  
  ${tripleBacktick}toml
  clientId = "<Client ID>"
  clientSecret = "<Client Secret>"
  refreshToken = "<Refresh Token>"
  ${tripleBacktick}
  
  ## Run the example
  
  Execute the following command to run the example. The script will print its progress to the console.
  
  ${tripleBacktick}shell
  bal run
  ${tripleBacktick}
</details>

---

**MASTER INSTRUCTIONS CHECKLIST:**

You must analyze the provided Ballerina code and generate a README by strictly following this checklist.

**1.  Analyze the Title and Introduction:**
    * Generate a human-readable title from the example's directory name ("${exampleData.exampleDirName}").
    * Write a 1-2 sentence introduction that summarizes what the ${backtick}main.bal${backtick} code *actually does*. If it's a script that performs a sequence of actions, describe that sequence.

**2.  Analyze Prerequisites:**
    * **Identify Connectors:** Find all ${backtick}import ballerinax/...${backtick} statements. For each unique connector, create a "Setup" prerequisite section with a link to its main setup guide.
    * **CRITICAL for Config.toml:** Analyze the ${backtick}configurable${backtick} variables at the top of the ${backtick}main.bal${backtick} file. Your ${backtick}Config.toml${backtick} example **MUST** exactly match these variables.
        * Look for lines starting with ${backtick}configurable${backtick} (e.g., ${backtick}configurable string bearerToken = ?;${backtick})
        * Extract the EXACT variable names used (e.g., if code has "bearerToken", use "bearerToken" not "developerToken")
        * If you see ${backtick}configurable string clientId${backtick}, you **MUST** include ${backtick}clientId${backtick}, ${backtick}clientSecret${backtick}, and ${backtick}refreshToken${backtick} in the TOML file.
        * If you see ${backtick}configurable string token${backtick} or ${backtick}configurable string bearerToken${backtick}, you **MUST** include only that exact variable name in the TOML file.
        * Use descriptive placeholder values like ${backtick}"<Your Bearer Token>"${backtick} or ${backtick}"<Your Client ID>"${backtick}.

**3.  Analyze the "Run the Example" Section:**
    * **Action:** Analyze the ${backtick}main.bal${backtick} file for the presence of an ${backtick}http:Listener${backtick}.
    * **Rule A (HTTP Service):** If an ${backtick}http:Listener${backtick} is present, your "Run the Example" section **MUST** provide a sample ${backtick}curl${backtick} command to test the service, as shown in Example 1. Infer the endpoint path, HTTP method, and a realistic JSON payload from the resource function's signature.
    * **Rule B (Script):** If **NO** ${backtick}http:Listener${backtick} is present, your "Run the Example" section **MUST NOT** include a ${backtick}curl${backtick} command. It should only show the ${backtick}bal run${backtick} command.

**CRITICAL CONFIG.TOML VALIDATION EXAMPLES:**

**If code has:**
${tripleBacktick}ballerina
configurable string bearerToken = ?;
configurable string storefront = "us";
${tripleBacktick}

**Generate Config.toml as:**
${tripleBacktick}toml
bearerToken = "<Your Bearer Token>"
storefront = "us"
${tripleBacktick}

**If code has:**
${tripleBacktick}ballerina
configurable string clientId = ?;
configurable string clientSecret = ?;
configurable string refreshToken = ?;
${tripleBacktick}

**Generate Config.toml as:**
${tripleBacktick}toml
clientId = "<Your Client ID>"
clientSecret = "<Your Client Secret>"  
refreshToken = "<Your Refresh Token>"
${tripleBacktick}

**EXAMPLE CODE TO ANALYZE:**
- **Connector:** ${connectorMetadata.connectorName}
- **Example Name:** ${exampleData.exampleName}
- **Main Ballerina File Content:**
${tripleBacktick}ballerina
${exampleData.mainBalContent}
${tripleBacktick}

Generate the complete README.md now, strictly following the checklist and adapting its structure to the code provided. Pay special attention to matching the EXACT variable names from configurable declarations to the Config.toml file.
`;
}

function createMainExampleReadmePrompt(ConnectorMetadata metadata) returns string {

    return string `
You are a senior technical writer creating the main README.md for a Ballerina connector's "examples" directory.

Your goal is to generate a complete guide that is **structurally and textually identical** to the perfect example provided below, filling in the dynamic content based on the connector information.

---
**PERFECT OUTPUT EXAMPLE (for Twitter):**

# Examples

The ${backtick}twitter${backtick} connector provides practical examples illustrating usage in various scenarios. Explore these [examples](https://github.com/ballerina-platform/module-ballerinax-twitter/tree/main/examples), covering use cases like Direct message company mentions, and tweet performance tracker.

1. [Direct message company mentions](https://github.com/ballerina-platform/module-ballerinax-twitter/tree/main/examples/DM-mentions) - Integrate Twitter to send direct messages to users who mention the company in tweets.

2. [Tweet performance tracker](https://github.com/ballerina-platform/module-ballerinax-twitter/tree/main/examples/tweet-performance-tracker) - Analyze the performance of tweets posted by a user over the past month.

## Prerequisites

1. Generate Twitter credentials to authenticate the connector as described in the [Setup guide](https://central.ballerina.io/ballerinax/twitter/latest#setup-guide).

2. For each example, create a ${backtick}Config.toml${backtick} file the related configuration. Here's an example of how your ${backtick}Config.toml${backtick} file should look:

    ${tripleBacktick}toml
    token = "<Access Token>"
    ${tripleBacktick}

## Running an Example

Execute the following commands to build an example from the source:

* To build an example:

    ${tripleBacktick}bash
    bal build
    ${tripleBacktick}

* To run an example:

    ${tripleBacktick}bash
    bal run
    ${tripleBacktick}
---

**TASK INSTRUCTIONS:**

Now, generate a new "Examples" README for the connector specified below. You must use the example above as a strict template and adhere to these rules:

1.  **Header and Introduction:**
    * Start with the ${backtick}# Examples${backtick} header.
    * Write the introductory paragraph, replacing the connector name and constructing the main examples URL from the GitHub Repo URL provided.
    * Based on the list of "Available Example Directories", infer and mention a few representative use cases at the end of the sentence.

2.  **Numbered Example List:**
    * For each directory name in "Available Example Directories", create one item in a numbered list (1., 2., 3., etc.).
    * Each list item MUST follow this format: ${backtick}[Example Title](URL_to_example) - One-sentence description.${backtick}
    * **Example Title:** Convert the directory name (e.g., "DM-mentions") into a human-readable title (e.g., "Direct message company mentions").
    * **URL_to_example:** Construct the full URL using the GitHub Repo URL and the example directory name.
    * **One-sentence description:** Write a single, concise sentence that summarizes the purpose of the example based on its name.

3.  **Static Sections:**
    * Append the ${backtick}## Prerequisites${backtick} section exactly as shown, but replace the service name ("Twitter") and the link to the setup guide.
    * Append the ${backtick}## Running an Example${backtick} section exactly as shown. **Do not change this section.**

**CONNECTOR INFORMATION TO USE:**
${getConnectorSummary(metadata)}
Available Example Directories: ${metadata.examples.toString()}

Generate the complete examples/README.md now.
`;
}
