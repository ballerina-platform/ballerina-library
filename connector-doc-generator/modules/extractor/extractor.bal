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

# Identifies a single client type to document in phase 2b.
public type ClientInfo record {|
    # Display name, e.g. "Client", "Apex Client", "JetStream Client"
    string displayName;
    # Fully-qualified Ballerina type, e.g. "salesforce:Client", "salesforce.apex:Client"
    string clientType;
    # Ballerina package, e.g. "ballerinax/salesforce.apex"
    string packageName;
|};

# Represents the files and metadata extracted from Claude's response.
public type ExtractionResult record {|
    # Map of filename → markdown content (e.g. "overview.md" → "...")
    map<string> files;
    # Category entry metadata for index.md patching; nil if not present in response
    CategoryEntry? categoryEntry;
|};

# Structured data for the catalog category index table row.
public type CategoryEntry record {|
    # One-line connector description for the catalog index table
    string description;
    # Comma-separated list of primary operations, e.g. "Create, Read, Update"
    string operations;
    # Authentication method, e.g. "OAuth 2.0" or "API Key"
    string auth;
|};

# Extract `<file name="...">...</file>` blocks and an optional
# `<category_entry>...</category_entry>` JSON block from Claude's response.
#
# + response - Raw text output from Claude
# + return   - ExtractionResult with files map and optional category entry
public function extractAll(string response) returns ExtractionResult {
    map<string> files = extractFiles(response);
    CategoryEntry? categoryEntry = extractCategoryEntry(response);
    return {files, categoryEntry};
}

function extractFiles(string response) returns map<string> {
    map<string> files = {};
    string remaining = response;
    string openTag = "<file name=\"";
    string closeTag = "</file>";

    while remaining.length() > 0 {
        int? tagStart = remaining.indexOf(openTag);
        if tagStart is () {
            break;
        }

        // Find the closing quote of the name attribute
        int nameStart = tagStart + openTag.length();
        int? nameEnd = remaining.indexOf("\"", nameStart);
        if nameEnd is () {
            break;
        }
        string fileName = remaining.substring(nameStart, nameEnd);

        // Find the end of the opening tag (">" after the name attribute)
        int? tagEnd = remaining.indexOf(">", nameEnd);
        if tagEnd is () {
            break;
        }

        // Content starts right after ">"
        int contentStart = tagEnd + 1;

        // Find the closing </file> tag — if missing, the response was truncated; use all remaining content
        int? closePos = remaining.indexOf(closeTag, contentStart);
        boolean truncated = closePos is ();
        int endPos = truncated ? remaining.length() : <int>closePos;

        string content = remaining.substring(contentStart, endPos).trim();
        if fileName.length() > 0 {
            files[fileName] = content;
            if truncated {
                // Mark truncated files so callers can warn the user
                files["__truncated__" + fileName] = "true";
            }
        }

        if truncated {
            break;
        }
        remaining = remaining.substring(endPos + closeTag.length());
    }

    return files;
}

# Extract the `<action_header>...</action_header>` block from a phase 2a response.
# + response - Raw text output from Claude
# + return   - Header markdown string, or empty string if not found
public function extractActionHeader(string response) returns string {
    string openTag = "<action_header>";
    string closeTag = "</action_header>";
    int? startPos = response.indexOf(openTag);
    int? endPos = response.indexOf(closeTag);
    if startPos is () {
        return "";
    }
    int end = endPos is int ? endPos : response.length();
    return response.substring(startPos + openTag.length(), end).trim();
}

# Extract the `<clients>[...]</clients>` JSON array from a phase 2a response.
# + response - Raw text output from Claude
# + return   - Array of ClientInfo parsed from the JSON, or empty array if not found
public function extractClients(string response) returns ClientInfo[] {
    string openTag = "<clients>";
    string closeTag = "</clients>";
    int? startPos = response.indexOf(openTag);
    int? endPos = response.indexOf(closeTag);
    if startPos is () || endPos is () {
        return [];
    }
    string jsonText = response.substring(startPos + openTag.length(), endPos).trim();
    json|error parsed = jsonText.fromJsonString();
    if parsed is error || !(parsed is json[]) {
        return [];
    }
    ClientInfo[] clients = [];
    foreach json item in <json[]>parsed {
        if item is map<json> {
            json pkg = item["package"];
            json ct = item["clientType"];
            json dn = item["displayName"];
            if pkg is string && ct is string && dn is string {
                clients.push({packageName: <string>pkg, clientType: <string>ct, displayName: <string>dn});
            }
        }
    }
    return clients;
}

# Extract the `<client_section>...</client_section>` block from a phase 2b response.
# Gracefully handles truncation by returning all content after the opening tag.
# + response - Raw text output from Claude
# + return   - Client section markdown, or empty string if not found
public function extractClientSection(string response) returns string {
    string openTag = "<client_section>";
    string closeTag = "</client_section>";
    int? startPos = response.indexOf(openTag);
    if startPos is () {
        return "";
    }
    int? endPos = response.indexOf(closeTag);
    int end = endPos is int ? endPos : response.length();
    return response.substring(startPos + openTag.length(), end).trim();
}

function extractCategoryEntry(string response) returns CategoryEntry? {
    string openTag = "<category_entry>";
    string closeTag = "</category_entry>";

    int? startPos = response.indexOf(openTag);
    int? endPos = response.indexOf(closeTag);
    if startPos is () || endPos is () {
        return ();
    }

    string jsonText = response.substring(startPos + openTag.length(), endPos).trim();
    json|error parsed = jsonText.fromJsonString();
    if parsed is error || !(parsed is map<json>) {
        return ();
    }

    map<json> jsonMap = <map<json>>parsed;
    json descField = jsonMap["description"];
    json opsField = jsonMap["operations"];
    json authField = jsonMap["auth"];

    if !(descField is string) || !(opsField is string) || !(authField is string) {
        return ();
    }

    return {
        description: <string>descField,
        operations: <string>opsField,
        auth: <string>authField
    };
}
