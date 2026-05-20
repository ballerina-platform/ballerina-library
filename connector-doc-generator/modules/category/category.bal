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

// Category display labels as used in index.mdx — differ from sidebar labels in a few cases.
final map<string> CATALOG_CATEGORIES = {
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

# Insert a connector entry into the ConnectorCatalog component in catalog/index.mdx.
#
# Each entry is a JS object in the `connectors={[ ... ]}` array.  The new entry
# is inserted in alphabetical order by `name`.
#
# + indexPath     - Absolute path to catalog/index.mdx
# + name          - Connector display name, e.g. "PDF"
# + module        - Module slug, e.g. "pdf"
# + categorySlug  - Category slug, e.g. "built-in"
# + description   - One-line description
# + operations    - Comma-separated operations string
# + auth          - Authentication method
# + packageOrg    - Package org portion, e.g. "ballerina" or "ballerinax"
# + packageVersion - Resolved version, e.g. "0.9.0"
# + return        - nil on success, or an error
public function insertConnectorEntry(
    string indexPath,
    string name,
    string module,
    string categorySlug,
    string description,
    string operations,
    string auth,
    string packageOrg,
    string packageVersion
) returns error? {
    string|io:Error fileResult = io:fileReadString(indexPath);
    if fileResult is io:Error {
        return error(string `Catalog index not found: ${indexPath}`);
    }
    string text = <string>fileResult;

    // Build the new entry line
    string catalogCategory = CATALOG_CATEGORIES[categorySlug] ?: categorySlug;
    string link = string `${categorySlug}/${module}/overview`;
    string iconUrl = buildIconUrl(packageOrg, module, packageVersion);

    string newEntry = string `    { name: "${escapeJs(name)}", description: "${escapeJs(description)}", operations: "${escapeJs(operations)}", auth: "${escapeJs(auth)}", link: "${link}", category: "${catalogCategory}"`;
    if iconUrl.length() > 0 {
        newEntry += string `, icon: "${iconUrl}"`;
    }
    newEntry += " },";

    // If entry already exists, replace the existing line in-place
    string existingMarker = string `/${module}/overview`;
    if text.includes(existingMarker) {
        int? markerPos = text.indexOf(existingMarker);
        if markerPos is int {
            // Walk back to find the start of the line
            int lineStart = markerPos;
            while lineStart > 0 && text.substring(lineStart - 1, lineStart) != "\n" {
                lineStart -= 1;
            }
            // Walk forward to find the end of the line (include the newline)
            int lineEnd = markerPos;
            while lineEnd < text.length() && text.substring(lineEnd, lineEnd + 1) != "\n" {
                lineEnd += 1;
            }
            string newText = text.substring(0, lineStart) + newEntry + text.substring(lineEnd);
            io:Error? writeErr = io:fileWriteString(indexPath, newText);
            if writeErr is io:Error {
                return error("Failed to write catalog index: " + writeErr.message());
            }
            return;
        }
    }

    // Locate the connectors array opening
    string arrOpen = "connectors={[";
    int? arrOpenPos = text.indexOf(arrOpen);
    if arrOpenPos is () {
        return error(string `Could not find 'connectors={[' in ${indexPath}`);
    }
    int contentStart = arrOpenPos + arrOpen.length();

    // Locate the closing ]}
    int? arrClosePos = text.indexOf("  ]}", contentStart);
    if arrClosePos is () {
        return error(string `Could not find closing '  ]}' in ${indexPath}`);
    }

    // Find alphabetical insertion position within the array content
    string arrayContent = text.substring(contentStart, arrClosePos);
    int insertOffset = findAlphabeticalOffset(arrayContent, name);

    int absoluteInsert = contentStart + insertOffset;
    string newText = text.substring(0, absoluteInsert) + newEntry + "\n" + text.substring(absoluteInsert);

    io:Error? writeErr = io:fileWriteString(indexPath, newText);
    if writeErr is io:Error {
        return error("Failed to write catalog index: " + writeErr.message());
    }
}

// Find the character offset within arrayContent where the new entry should be inserted.
// Returns the offset of the first existing entry whose name is alphabetically after `newName`,
// or arrayContent.length() to append at the end.
function findAlphabeticalOffset(string arrayContent, string newName) returns int {
    string nameLower = newName.toLowerAscii();
    string remaining = arrayContent;
    int offset = 0;
    string entryPrefix = "{ name: \"";

    while remaining.length() > 0 {
        int? entryPos = remaining.indexOf(entryPrefix);
        if entryPos is () {
            break;
        }
        int nameStart = entryPos + entryPrefix.length();
        int? nameEnd = remaining.indexOf("\"", nameStart);
        if nameEnd is () {
            break;
        }
        string existingName = remaining.substring(nameStart, nameEnd);

        if nameLower < existingName.toLowerAscii() {
            // Insert before this entry — find the start of its line
            // Walk back from entryPos to find the preceding newline
            string before = remaining.substring(0, entryPos);
            int? lineStart = lastIndexOf(before, "\n");
            int lineOffset = lineStart is int ? lineStart + 1 : 0;
            return offset + lineOffset;
        }

        remaining = remaining.substring(nameEnd + 1);
        offset += nameEnd + 1;
    }

    // Append before the closing line — find the last newline in arrayContent
    int? lastNl = lastIndexOf(arrayContent, "\n");
    return lastNl is int ? lastNl + 1 : arrayContent.length();
}

// Build the Ballerina Central icon CDN URL for a package.
// Returns empty string if the pattern cannot be determined.
function buildIconUrl(string org, string module, string version) returns string {
    if org.length() == 0 || module.length() == 0 || version.length() == 0 {
        return "";
    }
    return string `https://bcentral-packageicons.azureedge.net/images/${org}_${module}_${version}.png`;
}

// Escape a string for embedding inside a JS double-quoted string literal.
function escapeJs(string s) returns string {
    string result = "";
    foreach string:Char ch in s {
        if ch == "\\" {
            result += "\\\\";
        } else if ch == "\"" {
            result += "\\\"";
        } else {
            result += ch;
        }
    }
    return result;
}

// Find the last occurrence of searchStr in text. Returns () if not found.
function lastIndexOf(string text, string searchStr) returns int? {
    int? lastFound = ();
    int searchFrom = 0;
    while searchFrom <= text.length() - searchStr.length() {
        int? pos = text.indexOf(searchStr, searchFrom);
        if pos is () {
            break;
        }
        lastFound = pos;
        searchFrom = pos + 1;
    }
    return lastFound;
}
