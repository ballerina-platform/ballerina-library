import connector_automator.cost_calculator;
import connector_automator.utils;

import ballerina/file;
import ballerina/io;

const string TEMPLATES_PATH = "/home/hansika/dev/connector_automation/connector_automator/modules/doc_generator/templates";

public function initDocumentationGenerator() returns error? {
    return utils:initAIService();
}

public function generateAllDocumentation(string connectorPath) returns error? {

    cost_calculator:resetCostTracking();

    io:println(" Starting Document generation...");
    check generateBallerinaReadme(connectorPath);
    check generateTestsReadme(connectorPath);
    check generateExamplesReadme(connectorPath);
    check generateIndividualExampleReadmes(connectorPath);
    check generateMainReadme(connectorPath);

    utils:repeat();
    io:println("DOCUMENTATION GENERATION COST SUMMARY");
    utils:repeat();

    decimal overviewCost = cost_calculator:getStageCost("doc_generator_overview");
    decimal setupCost = cost_calculator:getStageCost("doc_generator_setup");
    decimal quickstartCost = cost_calculator:getStageCost("doc_generator_quickstart");
    decimal examplesCost = cost_calculator:getStageCost("doc_generator_examples");
    decimal testsCost = cost_calculator:getStageCost("doc_generator_tests");
    decimal individualCost = cost_calculator:getStageCost("doc_generator_individual");
    decimal mainExamplesCost = cost_calculator:getStageCost("doc_generator_main_examples");
    decimal totalCost = cost_calculator:getTotalCost();

    io:println(string `Overview Sections: $${overviewCost.toString()}`);
    io:println(string `Setup Guides: $${setupCost.toString()}`);
    io:println(string `Quickstart Sections: $${quickstartCost.toString()}`);
    io:println(string `Examples Lists: $${examplesCost.toString()}`);
    io:println(string `Test READMEs: $${testsCost.toString()}`);
    io:println(string `Individual Example READMEs: $${individualCost.toString()}`);
    io:println(string `Main Examples READMEs: $${mainExamplesCost.toString()}`);
    utils:repeat();
    io:println(string `Total Documentation Cost: $${totalCost.toString()}`);
    utils:repeat();

    io:println("All documentation generated successfully!");
}

public function generateBallerinaReadme(string connectorPath) returns error? {
    ConnectorMetadata metadata = check analyzeConnector(connectorPath);
    map<string> aiContent = check generateBallerinaContent(metadata);

    TemplateData data = createTemplateData(metadata);
    data = mergeAIContent(data, aiContent);

    string content = check processTemplate("ballerina_readme_template.md", data);

    string outputPath = connectorPath + "/ballerina/README.md";
    if !check file:test(connectorPath + "/ballerina", file:EXISTS) {
        outputPath = connectorPath + "/README.md";
    }

    string? parentPath = check file:parentPath(outputPath);
    if parentPath is string {
        check ensureDirectoryExists(parentPath);
    }
    check writeOutput(content, outputPath);

    // ✅ Show section-specific cost
    decimal sectionCost = cost_calculator:getStageCost("doc_generator_overview") +
                        cost_calculator:getStageCost("doc_generator_setup") +
                        cost_calculator:getStageCost("doc_generator_quickstart") +
                        cost_calculator:getStageCost("doc_generator_examples");
    io:println(string `Generated: ${outputPath} (Cost: $${sectionCost.toString()})`);
}

public function generateTestsReadme(string connectorPath) returns error? {
    ConnectorMetadata metadata = check analyzeConnector(connectorPath);
    map<string> aiContent = check generateTestsContent(metadata);

    TemplateData data = createTemplateData(metadata);
    data = mergeAIContent(data, aiContent);

    string content = check processTemplate("tests_readme_template.md", data);

    string outputPath = connectorPath + "/tests/README.md";
    if !check file:test(connectorPath + "/tests", file:EXISTS) {
        outputPath = connectorPath + "/ballerina/tests/README.md";
    }

    string? parentPath = check file:parentPath(outputPath);
    if parentPath is string {
        check ensureDirectoryExists(parentPath);
    }
    check writeOutput(content, outputPath);
    decimal testCost = cost_calculator:getStageCost("doc_generator_tests");
    io:println(string `Generated: ${outputPath} (Cost: $${testCost.toString()})`);
}

// Generate Examples README
public function generateIndividualExampleReadmes(string connectorPath) returns error? {
    ConnectorMetadata metadata = check analyzeConnector(connectorPath);

    string examplesPath = connectorPath + "/examples";

    // Check if examples directory exists
    if !check file:test(examplesPath, file:EXISTS) {
        io:println("No examples directory found at: " + examplesPath);
        return;
    }

    // Get all example directories
    file:MetaData[] examples = check file:readDir(examplesPath);
    int exampleCount = 0;

    foreach file:MetaData example in examples {
        if example.dir {
            string exampleDirName = example.absPath.substring(examplesPath.length() + 1);
            string exampleDirPath = examplesPath + "/" + exampleDirName;

            error? result = generateSingleExampleReadme(example.absPath, exampleDirName, metadata);
            if result is error {
                io:println("Failed to generate README for " + exampleDirName + ": " + result.message());
            } else {
                exampleCount += 1;
                decimal avgCost = exampleCount > 0 ? cost_calculator:getStageCost("doc_generator_individual") / <decimal>exampleCount : 0.0d;
                io:println(string `Generated: ${exampleDirPath}/README.md (Approx. cost: $${avgCost.toString()})`);
            }
        }
    }

    decimal totalIndividualCost = cost_calculator:getStageCost("doc_generator_individual");
    if exampleCount > 0 {
        io:println(string `Total Individual Examples Cost: $${totalIndividualCost.toString()} (${exampleCount} examples)`);
    }
}

function generateSingleExampleReadme(string examplePath, string exampleDirName, ConnectorMetadata metadata) returns error? {
    // Read all .bal files in the example directory
    ExampleData exampleData = check analyzeExampleDirectory(examplePath, exampleDirName);

    // Generate AI content for this specific example
    map<string> aiContent = check generateIndividualExampleContent(exampleData, metadata);

    // Create template data
    TemplateData data = createTemplateData(metadata);
    data = mergeAIContent(data, aiContent);

    // Add example-specific data
    data.CONNECTOR_NAME = metadata.connectorName;

    string content = check processTemplate("example_specific_template.md", data);

    string readmeFileName = formatExampleName(exampleDirName) + ".md";
    string outputPath = examplePath + "/" + readmeFileName;

    check writeOutput(content, outputPath);
}

function generateIndividualExampleContent(ExampleData exampleData, ConnectorMetadata connectorMetadata) returns map<string>|error {
    map<string> content = {};
    string prompt = createIndividualExamplePrompt(exampleData, connectorMetadata);
    string result = check callAI(prompt);

    cost_calculator:trackUsageFromText("doc_generator_individual", prompt, result, "claude-4-sonnet");

    content["individual_readme"] = result;
    return content;
}

public function generateExamplesReadme(string connectorPath) returns error? {
    ConnectorMetadata metadata = check analyzeConnector(connectorPath);
    map<string> aiContent = check generateExamplesContent(metadata);

    TemplateData data = createTemplateData(metadata);
    data = mergeAIContent(data, aiContent);

    string content = check processTemplate("examples_readme_template.md", data);

    string outputPath = connectorPath + "/examples/README.md";

    string? parentPath = check file:parentPath(outputPath);
    if parentPath is string {
        check ensureDirectoryExists(parentPath);
    }
    check writeOutput(content, outputPath);
    decimal examplesCost = cost_calculator:getStageCost("doc_generator_main_examples");
    io:println(string `Generated: ${outputPath} (Cost: $${examplesCost.toString()})`);
}

public function generateMainReadme(string connectorPath) returns error? {
    ConnectorMetadata metadata = check analyzeConnector(connectorPath);
    map<string> aiContent = check generateMainContent(metadata);

    TemplateData data = createTemplateData(metadata);
    data = mergeAIContent(data, aiContent);

    string content = check processTemplate("main_readme_template.md", data);

    string outputPath = connectorPath + "/README.md";

    string? parentPath = check file:parentPath(outputPath);
    if parentPath is string {
        check ensureDirectoryExists(parentPath);
    }
    check writeOutput(content, outputPath);
    io:println(string `Generated: ${outputPath}`);
}

function generateBallerinaContent(ConnectorMetadata metadata) returns map<string>|error {
    map<string> content = {};
    string overviewPrompt = createBallerinaOverviewPrompt(metadata);
    string overviewResult = check callAI(overviewPrompt);
    cost_calculator:trackUsageFromText("doc_generator_overview", overviewPrompt, overviewResult, "claude-4-sonnet");
    content["overview"] = overviewResult;

    string setupPrompt = createBallerinaSetupPrompt(metadata);
    string setupResult = check callAI(setupPrompt);
    cost_calculator:trackUsageFromText("doc_generator_setup", setupPrompt, setupResult, "claude-4-sonnet");
    content["setup"] = setupResult;

    string quickstartPrompt = createBallerinaQuickstartPrompt(metadata);
    string quickstartResult = check callAI(quickstartPrompt);
    cost_calculator:trackUsageFromText("doc_generator_quickstart", quickstartPrompt, quickstartResult, "claude-4-sonnet");
    content["quickstart"] = quickstartResult;

    string examplesPrompt = createBallerinaExamplesPrompt(metadata);
    string examplesResult = check callAI(examplesPrompt);
    cost_calculator:trackUsageFromText("doc_generator_examples", examplesPrompt, examplesResult, "claude-4-sonnet");
    content["examples"] = examplesResult;

    return content;
}

function generateTestsContent(ConnectorMetadata metadata) returns map<string>|error {
    map<string> content = {};
    string testsPrompt = createTestReadmePrompt(metadata);
    string testsResult = check callAI(testsPrompt);
    cost_calculator:trackUsageFromText("doc_generator_tests", testsPrompt, testsResult, "claude-4-sonnet");
    content["testing_approach"] = testsResult;

    return content;
}

function generateExamplesContent(ConnectorMetadata metadata) returns map<string>|error {
    map<string> content = {};
    string mainExamplesPrompt = createMainExampleReadmePrompt(metadata);
    string mainExamplesResult = check callAI(mainExamplesPrompt);
    cost_calculator:trackUsageFromText("doc_generator_main_examples", mainExamplesPrompt, mainExamplesResult, "claude-4-sonnet");
    content["main_examples_readme"] = mainExamplesResult;

    return content;
}

function generateMainContent(ConnectorMetadata metadata) returns map<string>|error {
    map<string> content = {};

    content["header_and_badges"] = createHeaderAndBadges(metadata);
    content["useful_links"] = createUsefulLinksSection(metadata);

    string overviewPrompt = createBallerinaOverviewPrompt(metadata);
    string overviewResult = check callAI(overviewPrompt);
    cost_calculator:trackUsageFromText("doc_generator_overview", overviewPrompt, overviewResult, "claude-4-sonnet");
    content["overview"] = overviewResult;

    string setupPrompt = createBallerinaSetupPrompt(metadata);
    string setupResult = check callAI(setupPrompt);
    cost_calculator:trackUsageFromText("doc_generator_setup", setupPrompt, setupResult, "claude-4-sonnet");
    content["setup"] = setupResult;

    string quickstartPrompt = createBallerinaQuickstartPrompt(metadata);
    string quickstartResult = check callAI(quickstartPrompt);
    cost_calculator:trackUsageFromText("doc_generator_quickstart", quickstartPrompt, quickstartResult, "claude-4-sonnet");
    content["quickstart"] = quickstartResult;

    string examplesPrompt = createBallerinaExamplesPrompt(metadata);
    string examplesResult = check callAI(examplesPrompt);
    cost_calculator:trackUsageFromText("doc_generator_examples", examplesPrompt, examplesResult, "claude-4-sonnet");
    content["examples"] = examplesResult;
    return content;
}

function callAI(string prompt) returns string|error {
    return utils:callAI(prompt);
}

function ensureDirectoryExists(string dirPath) returns error? {
    if !check file:test(dirPath, file:EXISTS) {
        check file:createDir(dirPath, file:RECURSIVE);
    }
}

// Template processing functions
function processTemplate(string templateName, TemplateData data) returns string|error {
    string templatePath = TEMPLATES_PATH + "/" + templateName;

    if !check file:test(templatePath, file:EXISTS) {
        return error("Template not found: " + templatePath);
    }

    string template = check io:fileReadString(templatePath);
    return substituteVariables(template, data);
}

function substituteVariables(string template, TemplateData data) returns string {
    string result = template;

    // Simple string replacement function
    string connectorName = data.CONNECTOR_NAME ?: "";
    if connectorName != "" {
        result = simpleReplace(result, "{{CONNECTOR_NAME}}", connectorName);
    }

    string version = data.VERSION ?: "";
    if version != "" {
        result = simpleReplace(result, "{{VERSION}}", version);
    }

    string description = data.DESCRIPTION ?: "";
    if description != "" {
        result = simpleReplace(result, "{{DESCRIPTION}}", description);
    }

    string overview = data.AI_GENERATED_OVERVIEW ?: "";
    if overview != "" {
        result = simpleReplace(result, "{{AI_GENERATED_OVERVIEW}}", overview);
    }

    string setup = data.AI_GENERATED_SETUP ?: "";
    if setup != "" {
        result = simpleReplace(result, "{{AI_GENERATED_SETUP}}", setup);
    }

    string quickstart = data.AI_GENERATED_QUICKSTART ?: "";
    if quickstart != "" {
        result = simpleReplace(result, "{{AI_GENERATED_QUICKSTART}}", quickstart);
    }

    string examples = data.AI_GENERATED_EXAMPLES ?: "";
    if examples != "" {
        result = simpleReplace(result, "{{AI_GENERATED_EXAMPLES}}", examples);
    }

    string usage = data.AI_GENERATED_USAGE ?: "";
    if usage != "" {
        result = simpleReplace(result, "{{AI_GENERATED_USAGE}}", usage);
    }

    string testingApproach = data.AI_GENERATED_TESTING_APPROACH ?: "";
    if testingApproach != "" {
        result = simpleReplace(result, "{{AI_GENERATED_TESTING_APPROACH}}", testingApproach);
    }

    string exampleDescriptions = data.AI_GENERATED_EXAMPLE_DESCRIPTIONS ?: "";
    if exampleDescriptions != "" {
        result = simpleReplace(result, "{{AI_GENERATED_EXAMPLE_DESCRIPTIONS}}", exampleDescriptions);
    }

    string gettingStarted = data.AI_GENERATED_GETTING_STARTED ?: "";
    if gettingStarted != "" {
        result = simpleReplace(result, "{{AI_GENERATED_GETTING_STARTED}}", gettingStarted);
    }

    string headerAndBadges = data.AI_GENERATED_HEADER_AND_BADGES ?: "";
    if headerAndBadges != "" {
        result = simpleReplace(result, "{{AI_GENERATED_HEADER_AND_BADGES}}", headerAndBadges);
    }

    string usefulLinks = data.AI_GENERATED_USEFUL_LINKS ?: "";
    if usefulLinks != "" {
        result = simpleReplace(result, "{{AI_GENERATED_USEFUL_LINKS}}", usefulLinks);
    }
    string individualReadme = data.AI_GENERATED_INDIVIDUAL_README ?: "";
    if individualReadme != "" {
        result = simpleReplace(result, "{{AI_GENERATED_INDIVIDUAL_README}}", individualReadme);
    }
    string mainExamplesReadme = data.AI_GENERATED_MAIN_EXAMPLES_README ?: "";
    if mainExamplesReadme != "" {
        result = simpleReplace(result, "{{AI_GENERATED_MAIN_EXAMPLES_README}}", mainExamplesReadme);
    }
    return result;
}

function simpleReplace(string text, string searchFor, string replaceWith) returns string {
    string result = text;
    int? index = result.indexOf(searchFor);
    while index is int {
        string before = result.substring(0, index);
        string after = result.substring(index + searchFor.length());
        result = before + replaceWith + after;
        index = result.indexOf(searchFor);
    }
    return result;
}

function writeOutput(string content, string outputPath) returns error? {
    check io:fileWriteString(outputPath, content);
}

function createTemplateData(ConnectorMetadata metadata) returns TemplateData {
    return {
        CONNECTOR_NAME: metadata.connectorName,
        VERSION: metadata.version

    };
}

function mergeAIContent(TemplateData baseData, map<string> aiContent) returns TemplateData {
    TemplateData merged = baseData.clone();

    foreach var [key, value] in aiContent.entries() {
        match key {
            "overview" => {
                merged.AI_GENERATED_OVERVIEW = value;
            }
            "setup" => {
                merged.AI_GENERATED_SETUP = value;
            }
            "quickstart" => {
                merged.AI_GENERATED_QUICKSTART = value;
            }
            "examples" => {
                merged.AI_GENERATED_EXAMPLES = value;
            }
            "usage" => {
                merged.AI_GENERATED_USAGE = value;
            }
            "testing_approach" => {
                merged.AI_GENERATED_TESTING_APPROACH = value;
            }
            "test_scenarios" => {
                merged.AI_GENERATED_TEST_SCENARIOS = value;
            }
            "example_descriptions" => {
                merged.AI_GENERATED_EXAMPLE_DESCRIPTIONS = value;
            }
            "getting_started" => {
                merged.AI_GENERATED_GETTING_STARTED = value;
            }
            "header_and_badges" => {
                merged.AI_GENERATED_HEADER_AND_BADGES = value;
            }
            "useful_links" => {
                merged.AI_GENERATED_USEFUL_LINKS = value;
            }
            "individual_readme" => {
                merged.AI_GENERATED_INDIVIDUAL_README = value;
            }
            "main_examples_readme" => {
                merged.AI_GENERATED_MAIN_EXAMPLES_README = value;
            }

        }
    }

    return merged;
}

