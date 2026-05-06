// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/io;

import wso2/connector_doc_generator.extractor;

const string PROMPT_TEMPLATE_PHASE1  = "./resources/prompt-template-phase1.md";
const string PROMPT_TEMPLATE_PHASE2A = "./resources/prompt-template-phase2a.md";
const string PROMPT_TEMPLATE_PHASE2B = "./resources/prompt-template-phase2b.md";

// Map of category slug → display label (must match CATALOG_CATEGORIES in modules/category/category.bal)
final map<string> CATEGORIES = {
    "ai-ml": "AI & ML",
    "built-in": "Built-in",
    "cloud-infrastructure": "Cloud & Infrastructure",
    "communication": "Communication",
    "crm-sales": "CRM & Sales",
    "database": "Database",
    "developer-tools": "Developer Tools",
    "ecommerce": "E-Commerce",
    "erp-business": "ERP & Business",
    "finance-accounting": "Finance & Accounting",
    "healthcare": "Healthcare",
    "hrms": "HRMS",
    "marketing-social": "Marketing & Social",
    "messaging": "Messaging",
    "productivity-collaboration": "Productivity & Collaboration",
    "security-identity": "Security & Identity",
    "storage-file": "Storage & Files"
};

# Input parameters for prompt generation.
public type ConnectorInput record {|
    # Connector display name, e.g. "HubSpot"
    string name;
    # Module slug, e.g. "hubspot"
    string module;
    # Ballerina package, e.g. "ballerinax/hubspot"
    string packageName;
    # GitHub repo name, e.g. "module-ballerinax-hubspot"
    string githubRepo;
    # Category slug, e.g. "crm-sales"
    string category;
    # Package version, e.g. "3.0.0"
    string 'version;
    # Generation phase: 1 = overview/setup/triggers, 2 = action-reference header+discovery, 3 = per-client section
    int phase = 1;
    # overview.md from phase 1 — passed to phase 2a/2b as context
    string phase1Overview = "";
    # Phase 2b only: which client to document
    extractor:ClientInfo? targetClient = ();
    # Local path to the cloned source repository (e.g. /tmp/conn_doc_salesforce_123)
    string localRepoPath = "";
    # Path to existing connector docs dir — non-empty triggers update mode
    string existingDocsDir = "";
|};

# Build the full prompt by loading the template and substituting connector variables.
#
# + input - Connector identity information
# + return - Complete prompt string, or an error if the template file cannot be read
public function buildPrompt(ConnectorInput input) returns string|error {
    string templatePath = input.phase == 3 ? PROMPT_TEMPLATE_PHASE2B
        : input.phase == 2 ? PROMPT_TEMPLATE_PHASE2A
        : PROMPT_TEMPLATE_PHASE1;
    string|io:Error templateResult = io:fileReadString(templatePath);
    if templateResult is io:Error {
        return error(string `Prompt template not found at '${templatePath}'. ` +
            "Run the generator from the connector-doc-generator-bal project root.");
    }

    string categoryLabel = CATEGORIES[input.category] ?: input.category;
    string updateModeNote = buildUpdateModeNote(input.existingDocsDir, input.phase);

    string prompt = <string>templateResult;
    prompt = replaceAll(prompt, "{{name}}", input.name);
    prompt = replaceAll(prompt, "{{module}}", input.module);
    prompt = replaceAll(prompt, "{{packageName}}", input.packageName);
    prompt = replaceAll(prompt, "{{githubRepo}}", input.githubRepo);
    prompt = replaceAll(prompt, "{{version}}", input.'version);
    prompt = replaceAll(prompt, "{{category}}", input.category);
    prompt = replaceAll(prompt, "{{categoryLabel}}", categoryLabel);
    prompt = replaceAll(prompt, "{{updateModeNote}}", updateModeNote);
    prompt = replaceAll(prompt, "{{phase1Overview}}", input.phase1Overview);
    prompt = replaceAll(prompt, "{{localRepoPath}}", input.localRepoPath);

    // Phase 2b client-specific substitutions
    extractor:ClientInfo? tc = input.targetClient;
    if input.phase == 3 {
        if tc is () {
            return error("Phase 2b prompt requires targetClient but it was not set in ConnectorInput");
        }
        prompt = replaceAll(prompt, "{{clientPackage}}", tc.packageName);
        prompt = replaceAll(prompt, "{{clientType}}", tc.clientType);
        prompt = replaceAll(prompt, "{{clientDisplayName}}", tc.displayName);
    }

    return prompt;
}

# Return the display label for a category slug.
#
# + slug - Category slug, e.g. "crm-sales"
# + return - Display label, e.g. "CRM & Sales", or the slug itself if not found
public function getCategoryLabel(string slug) returns string {
    return CATEGORIES[slug] ?: slug;
}

// Build the update-mode note injected when existing docs are present.
// Returns empty string for fresh generation.
function buildUpdateModeNote(string existingDocsDir, int phase) returns string {
    if existingDocsDir.length() == 0 {
        return "";
    }

    string note = "---\n\n## Update Mode\n\n" +
        "This connector already has documentation. Use the `Read` tool to read the existing files " +
        "before generating, then **update only what has changed** — preserve accurate sections word-for-word.\n\n" +
        "Existing docs are at: `" + existingDocsDir + "/`\n\n";

    if phase == 1 {
        note += "Relevant files to read first:\n" +
            "- `" + existingDocsDir + "/overview.md`\n" +
            "- `" + existingDocsDir + "/setup-guide.md`\n" +
            "- `" + existingDocsDir + "/trigger-reference.md`\n";
    } else if phase == 3 {
        note += "Relevant file to read first:\n" +
            "- `" + existingDocsDir + "/action-reference.md`\n";
    }

    note += "\n**Rules:**\n" +
        "- Preserve any section that is still accurate word-for-word\n" +
        "- Update only the parts that differ from the current source code\n" +
        "- Add new operations/clients/config fields that are missing\n" +
        "- Remove operations/fields that no longer exist in the source\n" +
        "- Still output the complete files (not diffs) — unchanged sections included\n";

    return note;
}

// Replace all occurrences of `searchStr` in `text` with `replacement`.
function replaceAll(string text, string searchStr, string replacement) returns string {
    string result = text;
    int? pos = result.indexOf(searchStr);
    while pos is int {
        string before = result.substring(0, pos);
        string after = result.substring(pos + searchStr.length());
        result = before + replacement + after;
        pos = result.indexOf(searchStr, pos + replacement.length());
    }
    return result;
}
