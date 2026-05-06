// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import connector_automator.utils;

import ballerina/ai;
import ballerina/file;
import ballerina/io;
import ballerina/regex;
import ballerina/time;

// ─────────────────────────────────────────────────────────────
// CONSTANTS
// ─────────────────────────────────────────────────────────────

// Specs smaller than this are sent to the LLM in a single prompt.
// Larger specs are chunked across multiple conversation turns.
const int SPEC_SINGLE_TURN_THRESHOLD = 100000;
const int SPEC_CHUNK_SIZE = 60000;

// ─────────────────────────────────────────────────────────────
// INTERNAL TYPES (private to this file)
// ─────────────────────────────────────────────────────────────

type ServerUrlChange record {|
    string original;
    string updated;
    string reason;
|};

type PathPrefixRule record {|
    string prefixRemoved;
    string reason;
|};

type TypeChange record {|
    string schemaName;
    string fieldName;
    string originalType;
    string updatedType;
    string reason;
|};

type NullabilityChange record {|
    string schemaName;
    string fieldName;
    boolean nullable;
    string reason;
|};

type FormatChange record {|
    string originalFormat;
    string updatedFormat;
    string reason;
|};

type SanitationRules record {|
    ServerUrlChange[] serverUrlChanges = [];
    PathPrefixRule[] pathPrefixRules = [];
    TypeChange[] typeChanges = [];
    NullabilityChange[] nullabilityChanges = [];
    FormatChange[] formatChanges = [];
    string[] rawEntries = [];
|};

// ─────────────────────────────────────────────────────────────
// PUBLIC API — called from main.bal
// ─────────────────────────────────────────────────────────────

# Generate sanitations.md after a fresh connector generation.
# Call this after sanitizor:executeSanitizor completes in the standard pipeline.
#
# + originalSpecPath - path to the raw input OpenAPI spec
# + alignedSpecPath  - path to the aligned_ballerina_openapi.json produced by sanitizor
# + outputDir        - connector root directory (sanitations.md goes to outputDir/docs/spec/)
# + quietMode        - suppress verbose output
# + return           - error if writing fails
public function generateSanitationsDoc(
        string originalSpecPath,
        string alignedSpecPath,
        string outputDir,
        boolean quietMode = false) returns error? {

    string sanitationsPath = outputDir + "/docs/spec/sanitations.md";

    json|error originalResult = io:fileReadJson(originalSpecPath);
    if originalResult is error {
        return originalResult;
    }
    json originalSpec = originalResult;

    json|error alignedResult = io:fileReadJson(alignedSpecPath);
    if alignedResult is error {
        return alignedResult;
    }
    json alignedSpec = alignedResult;

    boolean existsAlready = check file:test(sanitationsPath, file:EXISTS);

    string content;
    if existsAlready {
        if !quietMode {
            io:println("Updating existing sanitations.md...");
        }
        string existing = check io:fileReadString(sanitationsPath);
        content = check mergeWithExistingSanitations(existing, originalSpec, alignedSpec);
    } else {
        if !quietMode {
            io:println("Generating sanitations.md documentation...");
        }
        content = check buildSanitationsContent(originalSpec, alignedSpec, quietMode);
    }

    check io:fileWriteString(sanitationsPath, content);

    if !quietMode {
        string verb = existsAlready ? "Updated" : "Generated";
        io:println(string `✓ ${verb} sanitations.md at: ${sanitationsPath}`);
    }
}

# Read sanitations.md and apply all recorded changes to the new spec.
# Call this before sanitizor:executeSanitizor in the regeneration pipeline.
#
# PRIMARY path: sends both the spec and sanitations.md to the LLM; the LLM
# applies every natural-language rule and returns the fully modified spec.
# For specs that are too large for a single prompt the conversation is split
# across multiple turns (same chunking strategy as analyze_version_change.bal).
#
# FALLBACK (when LLM is unavailable): the programmatic parser extracts typed
# rules and applies them mechanically.
#
# + sanitationsPath - path to the existing sanitations.md
# + newSpecPath     - path to the newly downloaded OpenAPI spec (modified in-place)
# + quietMode       - suppress verbose output
# + return          - error if reading/writing fails
public function applySanitations(
        string sanitationsPath,
        string newSpecPath,
        boolean quietMode = false) returns error? {

    boolean exists = check file:test(sanitationsPath, file:EXISTS);
    if !exists {
        if !quietMode {
            io:println("⚠  No sanitations.md found — skipping pre-sanitization step");
        }
        return;
    }

    if !quietMode {
        io:println(string `Reading sanitations from: ${sanitationsPath}`);
    }

    string sanitationsContent = check io:fileReadString(sanitationsPath);

    json|error specReadResult = io:fileReadJson(newSpecPath);
    if specReadResult is error {
        return error(string `Failed to read spec JSON at ${newSpecPath}: ${specReadResult.message()}`);
    }
    json specJson = specReadResult;
    string specStr = specJson.toJsonString();

    if utils:isAIServiceInitialized() {
        if !quietMode {
            io:println("  Applying sanitations via AI...");
            io:println(string `  Spec size: ${specStr.length()} chars`);
        }

        json|error modifiedSpec = applySanitationsViaLLM(sanitationsContent, specStr, quietMode);
        if modifiedSpec is json {
            check io:fileWriteString(newSpecPath, modifiedSpec.toJsonString());
            if !quietMode {
                io:println("✓ Sanitations applied to new spec (AI-powered)");
            }
            return;
        }

        if !quietMode {
            io:println(string `  ⚠  AI rewrite failed (${(<error>modifiedSpec).message()})`);
            io:println("  Falling back to programmatic parser...");
        }
    }

    // Fallback: rule-based programmatic application
    SanitationRules rules = parseSanitationsMarkdown(sanitationsContent);
    if !quietMode {
        io:println(string `  Server URL rules   : ${rules.serverUrlChanges.length()}`);
        io:println(string `  Path prefix rules  : ${rules.pathPrefixRules.length()}`);
        io:println(string `  Type change rules  : ${rules.typeChanges.length()}`);
        io:println(string `  Nullability rules  : ${rules.nullabilityChanges.length()}`);
        io:println(string `  Format rules       : ${rules.formatChanges.length()}`);
    }
    check applyRulesToSpec(newSpecPath, rules, quietMode);

    if !quietMode {
        io:println("✓ Sanitations applied to new spec (rule-based)");
    }
}

// ─────────────────────────────────────────────────────────────
// LLM-BASED SPEC REWRITING
// ─────────────────────────────────────────────────────────────

// Entry point: chooses single-turn or multi-turn depending on spec size.
function applySanitationsViaLLM(
        string sanitationsContent,
        string specStr,
        boolean quietMode) returns json|error {

    if specStr.length() <= SPEC_SINGLE_TURN_THRESHOLD {
        if !quietMode {
            io:println("  Single-pass AI rewrite...");
        }
        return rewriteSpecSingleTurn(sanitationsContent, specStr);
    }

    if !quietMode {
        int chunks = (specStr.length() + SPEC_CHUNK_SIZE - 1) / SPEC_CHUNK_SIZE;
        io:println(string `  Large spec — splitting into ${chunks} chunks for AI rewrite...`);
    }
    return rewriteSpecChunked(sanitationsContent, specStr, quietMode);
}

function rewriteSpecSingleTurn(string sanitationsContent, string specStr) returns json|error {
    string prompt = buildApplySanitationsPrompt(sanitationsContent, specStr);
    string|error response = utils:callAI(prompt);
    if response is error {
        return error("AI spec rewrite failed: " + response.message());
    }
    return parseModifiedSpec(response);
}

// Multi-turn chunked rewrite for large specs.
// Works identically to the chunked diff analysis in analyze_version_change.bal:
// 1. Tell the model it will receive the spec in N parts + the sanitations doc.
// 2. Send each chunk, collect acknowledgments.
// 3. In the final turn, ask for the fully rewritten spec.
function rewriteSpecChunked(
        string sanitationsContent,
        string specStr,
        boolean quietMode) returns json|error {

    int totalChunks = (specStr.length() + SPEC_CHUNK_SIZE - 1) / SPEC_CHUNK_SIZE;

    ai:ChatMessage[] messages = [];

    string intro = string `I will send you a large OpenAPI spec in ${totalChunks} parts. After receiving all parts I will ask you to apply the changes described in a sanitations document. Please wait and after each part simply acknowledge with "Received part X/${totalChunks}." and nothing else.

Here is the sanitations document listing every change that must be applied to the spec:

${sanitationsContent}`;

    messages.push({role: "user", content: intro});
    string|error introReply = utils:callAIWithMessages(messages);
    if introReply is error {
        return error("AI conversation init failed: " + introReply.message());
    }
    messages.push({role: "assistant", content: introReply});

    foreach int i in 0 ..< totalChunks {
        int startIdx = i * SPEC_CHUNK_SIZE;
        int endIdx = startIdx + SPEC_CHUNK_SIZE;
        int safeEnd = endIdx < specStr.length() ? endIdx : specStr.length();
        string chunk = specStr.substring(startIdx, safeEnd);

        if !quietMode {
            io:println(string `  Sending spec chunk ${i + 1}/${totalChunks} (${chunk.length()} chars)...`);
        }

        messages.push({role: "user", content: string `OpenAPI spec part ${i + 1}/${totalChunks}:\n\n${chunk}`});
        string|error chunkReply = utils:callAIWithMessages(messages);
        if chunkReply is error {
            return error(string `AI failed on chunk ${i + 1}: ${chunkReply.message()}`);
        }
        messages.push({role: "assistant", content: chunkReply});
    }

    // Final turn: request the rewritten spec
    string finalRequest = string `You have now received all ${totalChunks} parts of the OpenAPI spec and the sanitations document at the start of our conversation.

Apply ALL the changes described in the sanitations document to the complete spec and return the fully modified OpenAPI spec as valid JSON. No markdown code blocks, no explanation — only the JSON.`;

    messages.push({role: "user", content: finalRequest});
    string|error finalReply = utils:callAIWithMessages(messages);
    if finalReply is error {
        return error("AI failed on final rewrite request: " + finalReply.message());
    }

    return parseModifiedSpec(finalReply);
}

function buildApplySanitationsPrompt(string sanitationsContent, string specStr) returns string {
    return string `You are applying documented sanitation changes to an OpenAPI specification.

SANITATIONS DOCUMENT:
${sanitationsContent}

OPENAPI SPEC (JSON):
${specStr}

TASK: Apply ALL changes described in the sanitations document to the OpenAPI spec.

Common change types to look for and apply:
- **Server URL changes**: update the "url" field inside the "servers" array
- **Path prefix removal**: remove the specified prefix from all keys in the "paths" object
- **Format changes**: replace format values (e.g. "date-time" → "datetime") everywhere in the spec
- **Nullable fields**: add "nullable": true to the specified property inside components/schemas
- **Type changes**: change the "type" of a specified schema property (e.g. "string" → "integer")

Do NOT apply:
- Changes about Ballerina code constructs (int:signed32, record fields in generated code)
- Summary or description text enhancements (those are handled by a separate AI step)
- The OpenAPI CLI command at the bottom of the document

Return ONLY the complete modified OpenAPI spec as valid JSON. No markdown code fences, no explanation text.`;
}

function parseModifiedSpec(string raw) returns json|error {
    string cleaned = raw.trim();
    // Strip markdown code fences if the model added them
    if cleaned.startsWith("```") {
        int? firstNewline = cleaned.indexOf("\n");
        if firstNewline is int {
            cleaned = cleaned.substring(firstNewline + 1);
        }
        if cleaned.endsWith("```") {
            cleaned = cleaned.substring(0, cleaned.length() - 3).trim();
        }
    }
    json|error result = cleaned.fromJsonString();
    if result is error {
        return error("Failed to parse AI-modified spec as JSON: " + result.message());
    }
    return result;
}

// ─────────────────────────────────────────────────────────────
// MARKDOWN GENERATION — fresh (no existing file)
// ─────────────────────────────────────────────────────────────

function buildSanitationsContent(json originalSpec, json alignedSpec, boolean quietMode) returns string|error {
    string[] sectionBlocks = buildAutoDetectedSections(originalSpec, alignedSpec, 1);
    string[] lines = [];

    lines.push("# Sanitation for OpenAPI specification");
    lines.push("");
    lines.push("This document records the sanitation done on top of the official OpenAPI specification.");
    lines.push("");

    foreach string block in sectionBlocks {
        lines.push(block);
        lines.push("");
    }

    lines.push(buildFooter());
    return string:'join("\n", ...lines);
}

// ─────────────────────────────────────────────────────────────
// MARKDOWN GENERATION — merge with existing file
// ─────────────────────────────────────────────────────────────

// Preserve human-authored sections; replace stale auto-generated sections with fresh detection.
function mergeWithExistingSanitations(string existing, json originalSpec, json alignedSpec) returns string|error {
    string header = extractFileHeader(existing);
    string[] existingSections = extractNumberedSections(existing);
    string footer = extractFileFooter(existing);

    string updatedHeader = updateDateInHeader(header);

    // Separate human-authored sections from previously auto-generated ones
    string[] humanSections = [];
    foreach string section in existingSections {
        if !section.includes("<!-- auto-generated -->") {
            humanSections.push(section);
        }
    }

    // Fresh auto-detection always replaces stale auto sections
    string[] freshSections = buildAutoDetectedSections(originalSpec, alignedSpec, 1);

    // Only add auto-detected sections not already covered by human-authored content
    string humanText = string:'join("\n", ...humanSections).toLowerAscii();
    string[] filteredFreshSections = [];
    foreach string section in freshSections {
        if !isSectionAlreadyCovered(section, humanText) {
            filteredFreshSections.push(section);
        }
    }

    // Reassemble: human sections first, then fresh auto sections
    string[] allSections = [];
    allSections.push(...humanSections);
    allSections.push(...filteredFreshSections);

    string[] renumbered = renumberSections(allSections);

    string[] parts = [updatedHeader, ""];
    foreach string s in renumbered {
        parts.push(s);
        parts.push("");
    }
    parts.push(footer);

    return string:'join("\n", ...parts);
}

// Build the auto-detectable section blocks starting at a given index.
function buildAutoDetectedSections(json originalSpec, json alignedSpec, int startIndex) returns string[] {
    string[] blocks = [];
    string bt = "`";
    int idx = startIndex;

    // Server URL
    string origServer = extractServerUrl(originalSpec);
    string newServer = extractServerUrl(alignedSpec);
    if origServer != "" && newServer != "" && origServer != newServer {
        blocks.push(string `${idx}. Change the ${bt}url${bt} property of the servers object
- **Original**: ${bt}${origServer}${bt}
- **Updated**: ${bt}${newServer}${bt}
- **Reason**: Common prefix added to base URL to simplify endpoint paths.`);
        idx += 1;
    }

    // Path prefix removal
    string prefix = detectRemovedPathPrefix(originalSpec, alignedSpec);
    if prefix != "" {
        blocks.push(string `${idx}. Update the API Paths
- **Original**: Paths included common prefix ${bt}${prefix}${bt} in each endpoint.
- **Updated**: Common prefix removed from endpoints as it is now in the base URL.
- **Reason**: Simplifies API paths and avoids duplication.`);
        idx += 1;
    }

    // Format changes
    FormatChange[] formatChanges = detectFormatChanges(originalSpec, alignedSpec);
    foreach FormatChange fc in formatChanges {
        blocks.push(string `${idx}. Update ${bt}${fc.originalFormat}${bt} to ${bt}${fc.updatedFormat}${bt}
- **Original**: ${bt}"format":"${fc.originalFormat}"${bt}
- **Updated**: ${bt}"format":"${fc.updatedFormat}"${bt}
- **Reason**: ${fc.reason}`);
        idx += 1;
    }

    // Nullability changes
    NullabilityChange[] nullChanges = detectNullabilityChanges(originalSpec, alignedSpec);
    foreach NullabilityChange nc in nullChanges {
        string nowStr = nc.nullable ? "nullable" : "not nullable";
        string wasStr = nc.nullable ? "not nullable" : "nullable";
        blocks.push(string `${idx}. Change ${bt}${nc.schemaName} ${nc.fieldName}${bt} to ${nowStr}
- **Original**: The ${bt}${nc.fieldName}${bt} field in ${bt}${nc.schemaName}${bt} was ${bt}${wasStr}${bt}.
- **Updated**: The ${bt}${nc.fieldName}${bt} field has been updated to be ${bt}${nowStr}${bt}.
- **Reason**: ${nc.reason}`);
        idx += 1;
    }

    // Type changes
    TypeChange[] typeChanges = detectTypeChanges(originalSpec, alignedSpec);
    foreach TypeChange tc in typeChanges {
        string fieldIdentifier = tc.schemaName != "" ? string `${tc.schemaName}.${tc.fieldName}` : tc.fieldName;
        blocks.push(string `${idx}. Change ${bt}${fieldIdentifier}${bt} from ${bt}${tc.originalType}${bt} to ${bt}${tc.updatedType}${bt}
- **Original**: The ${bt}${tc.fieldName}${bt} field was defined as a ${bt}${tc.originalType}${bt}.
- **Updated**: The ${bt}${tc.fieldName}${bt} field has been changed to ${bt}${tc.updatedType}${bt}.
- **Reason**: ${tc.reason}`);
        idx += 1;
    }

    // Mark every auto-detected block so mergeWithExistingSanitations can identify and replace them
    string[] markedBlocks = [];
    foreach string block in blocks {
        markedBlocks.push(block + "\n<!-- auto-generated -->");
    }
    return markedBlocks;
}

function buildFooter() returns string {
    return "## OpenAPI cli command\n\nThe following command was used to generate the Ballerina client from the OpenAPI specification.\nThe command should be executed from the repository root directory.\n\n```bash\nbal openapi -i docs/spec/openapi.json -o ballerina --mode client --license docs/license.txt\n```\n\nNote: The license year is hardcoded to 2025, change if necessary.";
}

// ─────────────────────────────────────────────────────────────
// FILE STRUCTURE HELPERS
// ─────────────────────────────────────────────────────────────

// Everything before the first numbered section (author, created, intro paragraph, etc.)
function extractFileHeader(string content) returns string {
    string[] lines = regex:split(content, "\n");
    int firstSection = lines.length();
    foreach int i in 0 ..< lines.length() {
        if regex:matches(lines[i].trim(), "[0-9]+\\..*") {
            firstSection = i;
            break;
        }
    }
    if firstSection == 0 {
        return "";
    }
    string[] headerLines = lines.slice(0, firstSection);
    // Trim trailing blank lines from header
    int last = headerLines.length() - 1;
    while last > 0 && headerLines[last].trim() == "" {
        last -= 1;
    }
    return string:'join("\n", ...headerLines.slice(0, last + 1));
}

// Each numbered block as a separate string (without the trailing blank line)
function extractNumberedSections(string content) returns string[] {
    string[] sections = [];
    string[] lines = regex:split(content, "\n");

    int i = 0;
    while i < lines.length() {
        string line = lines[i].trim();
        // Stop when we hit the ## footer
        if line.startsWith("## ") {
            break;
        }
        if regex:matches(line, "[0-9]+\\..*") {
            string[] block = [lines[i]];
            int j = i + 1;
            while j < lines.length() {
                string next = lines[j].trim();
                if regex:matches(next, "[0-9]+\\..*") || next.startsWith("## ") {
                    break;
                }
                block.push(lines[j]);
                j += 1;
            }
            // Trim trailing blank lines from block
            int last = block.length() - 1;
            while last > 0 && block[last].trim() == "" {
                last -= 1;
            }
            sections.push(string:'join("\n", ...block.slice(0, last + 1)));
            i = j;
            continue;
        }
        i += 1;
    }
    return sections;
}

// Everything from the first ## heading (footer) to end of file
function extractFileFooter(string content) returns string {
    string[] lines = regex:split(content, "\n");
    int footerStart = lines.length();
    foreach int i in 0 ..< lines.length() {
        if lines[i].trim().startsWith("## ") {
            footerStart = i;
            break;
        }
    }
    if footerStart >= lines.length() {
        return buildFooter();
    }
    return string:'join("\n", ...lines.slice(footerStart));
}

// Rewrite the section numbers (1. 2. 3. ...) to be sequential
function renumberSections(string[] sections) returns string[] {
    string[] result = [];
    foreach int i in 0 ..< sections.length() {
        string s = sections[i];
        // Replace the leading "N." with the correct number
        int? dot = s.indexOf(".");
        if dot is int {
            result.push(string `${i + 1}.` + s.substring(dot + 1));
        } else {
            result.push(s);
        }
    }
    return result;
}

// Update _Updated_: YYYY/MM/DD in header to today's date
function updateDateInHeader(string header) returns string {
    time:Civil today = time:utcToCivil(time:utcNow());
    string month = today.month < 10 ? string `0${today.month}` : today.month.toString();
    string day = today.day < 10 ? string `0${today.day}` : today.day.toString();
    string dateStr = string `${today.year}/${month}/${day}`;
    return regex:replaceAll(header, "_Updated_:.*", string `_Updated_: ${dateStr} \\`);
}

// True if the new section's key signal is already present in the existing file text
function isSectionAlreadyCovered(string newSection, string existingLower) returns boolean {
    string sectionLower = newSection.toLowerAscii();

    // Server URL change: look for URL patterns
    if sectionLower.includes("servers object") || sectionLower.includes("url") && sectionLower.includes("server") {
        return existingLower.includes("servers object") ||
               (existingLower.includes("url") && existingLower.includes("server"));
    }

    // Path prefix: look for "api paths" or "path prefix"
    if sectionLower.includes("api paths") || sectionLower.includes("path prefix") || sectionLower.includes("common prefix") {
        return existingLower.includes("api paths") ||
               existingLower.includes("path prefix") ||
               existingLower.includes("common prefix");
    }

    // Format change: check the specific format value
    if sectionLower.includes("format") {
        // Extract the format values from the section to check specifically
        int? quoteStart = newSection.indexOf("\"format\":\"");
        if quoteStart is int {
            string afterQuote = newSection.substring(quoteStart + 10);
            int? quoteEnd = afterQuote.indexOf("\"");
            if quoteEnd is int {
                string formatVal = afterQuote.substring(0, quoteEnd).toLowerAscii();
                return existingLower.includes(formatVal);
            }
        }
        return existingLower.includes("date-time") || existingLower.includes("datetime");
    }

    // Nullability: check schema.field combo
    if sectionLower.includes("nullable") {
        // Extract field name from section
        int? bt1 = newSection.indexOf("`");
        if bt1 is int {
            int? bt2 = newSection.indexOf("`", bt1 + 1);
            if bt2 is int {
                string token = newSection.substring(bt1 + 1, bt2).toLowerAscii();
                return existingLower.includes(token) && existingLower.includes("nullable");
            }
        }
        return existingLower.includes("nullable");
    }

    // Type change: check field name
    if sectionLower.includes("from") && (sectionLower.includes("string") || sectionLower.includes("integer")) {
        int? bt1 = newSection.indexOf("`");
        if bt1 is int {
            int? bt2 = newSection.indexOf("`", bt1 + 1);
            if bt2 is int {
                string fieldName = newSection.substring(bt1 + 1, bt2).toLowerAscii();
                if fieldName.length() > 0 {
                    return existingLower.includes(fieldName);
                }
            }
        }
    }

    return false;
}

// ─────────────────────────────────────────────────────────────
// MARKDOWN PARSING (fallback — used when LLM unavailable)
// ─────────────────────────────────────────────────────────────

function parseSanitationsMarkdown(string content) returns SanitationRules {
    SanitationRules rules = {};
    string[] lines = regex:split(content, "\n");

    int i = 0;
    while i < lines.length() {
        string line = lines[i].trim();

        // Match numbered list items like "1. ..." or "12. ..."
        if regex:matches(line, "[0-9]+\\..*") {
            string sectionTitle = line.toLowerAscii();

            // Collect the whole block until the next numbered item
            string[] blockLines = [lines[i]];
            int j = i + 1;
            while j < lines.length() {
                string nextLine = lines[j].trim();
                if regex:matches(nextLine, "[0-9]+\\..*") {
                    break;
                }
                blockLines.push(lines[j]);
                j += 1;
            }
            string block = string:'join("\n", ...blockLines);

            if sectionTitle.includes("url") && sectionTitle.includes("server") {
                ServerUrlChange? sc = parseServerUrlBlock(blockLines);
                if sc is ServerUrlChange {
                    rules.serverUrlChanges.push(sc);
                }
            } else if sectionTitle.includes("path") &&
                    (sectionTitle.includes("prefix") || sectionTitle.includes("endpoint") || sectionTitle.includes("api path")) {
                PathPrefixRule? pr = parsePathPrefixBlock(blockLines);
                if pr is PathPrefixRule {
                    rules.pathPrefixRules.push(pr);
                }
            } else if sectionTitle.includes("format") || sectionTitle.includes("date-time") || sectionTitle.includes("datetime") {
                FormatChange? fc = parseFormatBlock(blockLines);
                if fc is FormatChange {
                    rules.formatChanges.push(fc);
                }
            } else if sectionTitle.includes("nullable") || sectionTitle.includes("null") {
                NullabilityChange? nc = parseNullabilityBlock(blockLines);
                if nc is NullabilityChange {
                    rules.nullabilityChanges.push(nc);
                }
            } else if sectionTitle.includes("type") || sectionTitle.includes("integer") ||
                    sectionTitle.includes("string") || sectionTitle.includes("change") {
                TypeChange? tc = parseTypeChangeBlock(blockLines);
                if tc is TypeChange {
                    rules.typeChanges.push(tc);
                }
            } else {
                rules.rawEntries.push(block);
            }

            i = j;
            continue;
        }

        i += 1;
    }

    return rules;
}

// Extract the value for an "- **Original**:" or "- **Updated**:" line,
// handling two formats:
//   (a) inline: `- **Original**: `https://api.example.com``
//   (b) multi-line: `- **Original**:\n`https://api.example.com``
function extractValueAllowingNextLine(string[] lines, int labelIdx) returns string {
    string labelLine = lines[labelIdx].trim();
    // Try same-line backtick first
    string inlineVal = extractFirstBacktickValue(labelLine);
    if inlineVal != "" {
        return inlineVal;
    }
    // Value may be on the immediately following non-empty line
    int j = labelIdx + 1;
    while j < lines.length() {
        string nextLine = lines[j].trim();
        if nextLine == "" {
            j += 1;
            continue;
        }
        // Could be a bare URL, a backtick-wrapped value, or a new label → stop
        if nextLine.startsWith("- **") {
            break;
        }
        // Strip surrounding backticks if present
        if nextLine.startsWith("`") && nextLine.endsWith("`") && nextLine.length() > 2 {
            return nextLine.substring(1, nextLine.length() - 1);
        }
        // Plain value (no backticks)
        return nextLine;
    }
    return "";
}

function parseServerUrlBlock(string[] lines) returns ServerUrlChange? {
    string original = "";
    string updated = "";
    string reason = "";

    foreach int idx in 0 ..< lines.length() {
        string t = lines[idx].trim();
        if t.startsWith("- **Original**") {
            original = extractValueAllowingNextLine(lines, idx);
        } else if t.startsWith("- **Updated**") {
            updated = extractValueAllowingNextLine(lines, idx);
        } else if t.startsWith("- **Reason**") {
            int? colon = t.indexOf(":");
            if colon is int {
                reason = t.substring(colon + 1).trim();
            }
        }
    }

    if original != "" && updated != "" {
        return {original, updated, reason};
    }
    return ();
}

function parsePathPrefixBlock(string[] lines) returns PathPrefixRule? {
    string prefixRemoved = "";
    string reason = "";

    foreach int idx in 0 ..< lines.length() {
        string t = lines[idx].trim();
        if t.startsWith("- **Original**") {
            string val = extractValueAllowingNextLine(lines, idx);
            // For path prefix blocks the "original" contains the path that had the prefix,
            // e.g. "/crm/v4/associations/...". Extract the common prefix from it.
            if val != "" && prefixRemoved == "" {
                prefixRemoved = val;
            }
        } else if t.startsWith("- **Reason**") {
            int? colon = t.indexOf(":");
            if colon is int {
                reason = t.substring(colon + 1).trim();
            }
        }
    }

    // If the "Original" line mentions a prefix explicitly in backticks in the heading, prefer that
    if lines.length() > 0 {
        string heading = lines[0].trim().toLowerAscii();
        if heading.includes("prefix") || heading.includes("common") {
            string[] allBt = extractAllBacktickValues(lines[0]);
            if allBt.length() > 0 {
                prefixRemoved = allBt[0];
            }
        }
    }

    if prefixRemoved != "" {
        return {prefixRemoved, reason};
    }
    return ();
}

function parseFormatBlock(string[] lines) returns FormatChange? {
    string originalFormat = "";
    string updatedFormat = "";
    string reason = "";

    foreach int idx in 0 ..< lines.length() {
        string t = lines[idx].trim();
        if t.startsWith("- **Original**") {
            originalFormat = cleanFormatValue(extractValueAllowingNextLine(lines, idx));
        } else if t.startsWith("- **Updated**") {
            updatedFormat = cleanFormatValue(extractValueAllowingNextLine(lines, idx));
        } else if t.startsWith("- **Reason**") {
            int? colon = t.indexOf(":");
            if colon is int {
                reason = t.substring(colon + 1).trim();
            }
        }
    }

    if originalFormat != "" && updatedFormat != "" {
        return {originalFormat, updatedFormat, reason};
    }
    return ();
}

function parseNullabilityBlock(string[] lines) returns NullabilityChange? {
    string schemaName = "";
    string fieldName = "";
    boolean nullable = true;
    string reason = "";

    // Parse schema/field from section title line
    if lines.length() > 0 {
        string titleLine = lines[0];
        string titleLower = titleLine.toLowerAscii();
        string[] backtickVals = extractAllBacktickValues(titleLine);
        if backtickVals.length() >= 1 {
            string[] nameParts = regex:split(backtickVals[0], " ");
            if nameParts.length() >= 2 {
                schemaName = nameParts[0];
                fieldName = nameParts[1];
            } else if nameParts.length() == 1 {
                fieldName = nameParts[0];
            }
        }
        nullable = !titleLower.includes("not nullable");
    }

    foreach string line in lines {
        string t = line.trim();
        if t.startsWith("- **Reason**") {
            int? colon = t.indexOf(":");
            if colon is int {
                reason = t.substring(colon + 1).trim();
            }
        }
    }

    if fieldName != "" {
        return {schemaName, fieldName, nullable, reason};
    }
    return ();
}

function parseTypeChangeBlock(string[] lines) returns TypeChange? {
    string schemaName = "";
    string fieldName = "";
    string originalType = "";
    string updatedType = "";
    string reason = "";

    // Parse field from section title: `SchemaName.fieldName` (dot) or legacy `SchemaName fieldName` (space)
    if lines.length() > 0 {
        string[] backtickVals = extractAllBacktickValues(lines[0]);
        if backtickVals.length() >= 1 {
            string token = backtickVals[0];
            int? dotPos = token.indexOf(".");
            if dotPos is int {
                schemaName = token.substring(0, dotPos);
                fieldName = token.substring(dotPos + 1);
            } else {
                string[] nameParts = regex:split(token, " ");
                if nameParts.length() >= 2 {
                    schemaName = nameParts[0];
                    fieldName = nameParts[1];
                } else {
                    fieldName = token;
                }
            }
        }
    }

    foreach int idx in 0 ..< lines.length() {
        string t = lines[idx].trim();
        if t.startsWith("- **Original**") {
            // Hand-written format: "The `fieldName` field was defined as a `type`." → last backtick value
            string[] vals = extractAllBacktickValues(t);
            if vals.length() == 0 {
                originalType = extractValueAllowingNextLine(lines, idx);
            } else {
                originalType = vals[vals.length() - 1];
            }
        } else if t.startsWith("- **Updated**") {
            string[] vals = extractAllBacktickValues(t);
            if vals.length() == 0 {
                updatedType = extractValueAllowingNextLine(lines, idx);
            } else {
                updatedType = vals[vals.length() - 1];
            }
        } else if t.startsWith("- **Reason**") {
            int? colon = t.indexOf(":");
            if colon is int {
                reason = t.substring(colon + 1).trim();
            }
        }
    }

    if fieldName != "" && originalType != "" && updatedType != "" {
        return {schemaName, fieldName, originalType, updatedType, reason};
    }
    return ();
}

// ─────────────────────────────────────────────────────────────
// APPLY RULES TO SPEC (fallback — used when LLM unavailable)
// ─────────────────────────────────────────────────────────────

function applyRulesToSpec(string specPath, SanitationRules rules, boolean quietMode) returns error? {
    json|error specResult = io:fileReadJson(specPath);
    if specResult is error {
        return error("Failed to read spec at " + specPath + ": " + specResult.message());
    }

    json specJson = specResult;
    if !(specJson is map<json>) {
        return error("Spec is not a JSON object");
    }

    map<json> spec = <map<json>>specJson;

    foreach ServerUrlChange sc in rules.serverUrlChanges {
        applyServerUrlChange(spec, sc, quietMode);
    }

    foreach PathPrefixRule pr in rules.pathPrefixRules {
        applyPathPrefixRemoval(spec, pr, quietMode);
    }

    foreach FormatChange fc in rules.formatChanges {
        applyFormatChange(spec, fc, quietMode);
    }

    foreach NullabilityChange nc in rules.nullabilityChanges {
        applyNullabilityChange(spec, nc, quietMode);
    }

    foreach TypeChange tc in rules.typeChanges {
        applyTypeChange(spec, tc, quietMode);
    }

    string updatedContent = spec.toJsonString();
    check io:fileWriteString(specPath, updatedContent);
}

function applyServerUrlChange(map<json> spec, ServerUrlChange sc, boolean quietMode) {
    json|error serversResult = spec.get("servers");
    if serversResult is json[] {
        json[] servers = <json[]>serversResult;
        foreach json server in servers {
            if server is map<json> {
                map<json> serverMap = <map<json>>server;
                json|error urlResult = serverMap.get("url");
                if urlResult is string && <string>urlResult == sc.original {
                    serverMap["url"] = sc.updated;
                    if !quietMode {
                        io:println(string `  ✓ Server URL: ${sc.original} → ${sc.updated}`);
                    }
                }
            }
        }
    }
}

function applyPathPrefixRemoval(map<json> spec, PathPrefixRule pr, boolean quietMode) {
    json|error pathsResult = spec.get("paths");
    if pathsResult is map<json> {
        map<json> paths = <map<json>>pathsResult;
        map<json> newPaths = {};
        int modified = 0;

        foreach string path in paths.keys() {
            json|error pathValue = paths.get(path);
            if pathValue is json {
                if path.startsWith(pr.prefixRemoved) {
                    string newPath = path.substring(pr.prefixRemoved.length());
                    if newPath == "" || newPath == "/" {
                        newPath = "/";
                    }
                    newPaths[newPath] = pathValue;
                    modified += 1;
                } else {
                    newPaths[path] = pathValue;
                }
            }
        }

        spec["paths"] = newPaths;
        if !quietMode && modified > 0 {
            io:println(string `  ✓ Removed path prefix '${pr.prefixRemoved}' from ${modified} paths`);
        }
    }
}

function applyFormatChange(map<json> spec, FormatChange fc, boolean quietMode) {
    int count = countFormatOccurrences(spec, fc.originalFormat);
    replaceFormatValues(spec, fc.originalFormat, fc.updatedFormat);
    if !quietMode && count > 0 {
        io:println(string `  ✓ Format '${fc.originalFormat}' → '${fc.updatedFormat}' (${count} occurrences)`);
    }
}

function replaceFormatValues(json data, string originalFormat, string updatedFormat) {
    if data is map<json> {
        map<json> dataMap = <map<json>>data;
        foreach string key in dataMap.keys() {
            json|error val = dataMap.get(key);
            if val is json {
                if key == "format" && val is string && <string>val == originalFormat {
                    dataMap[key] = updatedFormat;
                } else {
                    replaceFormatValues(val, originalFormat, updatedFormat);
                }
            }
        }
    } else if data is json[] {
        json[] arr = <json[]>data;
        foreach json item in arr {
            replaceFormatValues(item, originalFormat, updatedFormat);
        }
    }
}

function countFormatOccurrences(json data, string formatValue) returns int {
    int count = 0;
    if data is map<json> {
        map<json> dataMap = <map<json>>data;
        foreach string key in dataMap.keys() {
            json|error val = dataMap.get(key);
            if val is json {
                if key == "format" && val is string && <string>val == formatValue {
                    count += 1;
                } else {
                    count += countFormatOccurrences(val, formatValue);
                }
            }
        }
    } else if data is json[] {
        json[] arr = <json[]>data;
        foreach json item in arr {
            count += countFormatOccurrences(item, formatValue);
        }
    }
    return count;
}

function applyNullabilityChange(map<json> spec, NullabilityChange nc, boolean quietMode) {
    map<json> schemas = extractSchemas(spec);
    string[] targets = nc.schemaName != "" ? [nc.schemaName] : schemas.keys();

    foreach string schemaName in targets {
        json|error schemaResult = schemas.get(schemaName);
        if schemaResult is map<json> {
            boolean changed = applyNullabilityToSchema(<map<json>>schemaResult, nc.fieldName, nc.nullable);
            if changed && !quietMode {
                io:println(string `  ✓ ${schemaName}.${nc.fieldName} → nullable=${nc.nullable}`);
            }
        }
    }
}

function applyNullabilityToSchema(map<json> schemaMap, string fieldName, boolean nullable) returns boolean {
    json|error propertiesResult = schemaMap.get("properties");
    if propertiesResult is map<json> {
        map<json> properties = <map<json>>propertiesResult;
        if !properties.hasKey(fieldName) {
            return false;
        }
        json|error fieldResult = properties.get(fieldName);
        if fieldResult is map<json> {
            map<json> fieldMap = <map<json>>fieldResult;
            fieldMap["nullable"] = nullable;
            return true;
        }
    }
    return false;
}

function applyTypeChange(map<json> spec, TypeChange tc, boolean quietMode) {
    map<json> schemas = extractSchemas(spec);
    string[] targets = tc.schemaName != "" ? [tc.schemaName] : schemas.keys();

    foreach string schemaName in targets {
        json|error schemaResult = schemas.get(schemaName);
        if schemaResult is map<json> {
            boolean changed = applyTypeChangeToSchema(<map<json>>schemaResult, tc.fieldName, tc.originalType, tc.updatedType);
            if changed && !quietMode {
                io:println(string `  ✓ ${schemaName}.${tc.fieldName}: ${tc.originalType} → ${tc.updatedType}`);
            }
        }
    }
}

function applyTypeChangeToSchema(map<json> schemaMap, string fieldName, string originalType, string updatedType) returns boolean {
    json|error propertiesResult = schemaMap.get("properties");
    if propertiesResult is map<json> {
        map<json> properties = <map<json>>propertiesResult;
        if !properties.hasKey(fieldName) {
            return false;
        }
        json|error fieldResult = properties.get(fieldName);
        if fieldResult is map<json> {
            map<json> fieldMap = <map<json>>fieldResult;
            if !fieldMap.hasKey("type") {
                return false;
            }
            json|error currentType = fieldMap.get("type");
            if currentType is string && <string>currentType == originalType {
                fieldMap["type"] = updatedType;
                return true;
            }
        }
    }
    return false;
}

// ─────────────────────────────────────────────────────────────
// DIFF HELPERS — used during sanitations.md generation
// ─────────────────────────────────────────────────────────────

function extractServerUrl(json spec) returns string {
    if spec is map<json> {
        json|error serversResult = spec.get("servers");
        if serversResult is json[] {
            json[] servers = <json[]>serversResult;
            if servers.length() > 0 {
                json firstServer = servers[0];
                if firstServer is map<json> {
                    json|error urlResult = firstServer.get("url");
                    if urlResult is string {
                        return <string>urlResult;
                    }
                }
            }
        }
    }
    return "";
}

function detectRemovedPathPrefix(json originalSpec, json alignedSpec) returns string {
    string[] originalPaths = extractPathKeys(originalSpec);
    string[] alignedPaths = extractPathKeys(alignedSpec);

    if originalPaths.length() == 0 || alignedPaths.length() == 0 {
        return "";
    }

    string firstOriginal = originalPaths[0];
    string firstAligned = alignedPaths[0];

    // The prefix is what was prepended; aligned path is suffix of original path
    if firstOriginal.length() > firstAligned.length() {
        int suffixStart = firstOriginal.length() - firstAligned.length();
        string suffix = firstOriginal.substring(suffixStart);
        if suffix == firstAligned {
            return firstOriginal.substring(0, suffixStart);
        }
    }

    return "";
}

function extractPathKeys(json spec) returns string[] {
    string[] keys = [];
    if spec is map<json> {
        json|error pathsResult = spec.get("paths");
        if pathsResult is map<json> {
            map<json> paths = <map<json>>pathsResult;
            foreach string key in paths.keys() {
                keys.push(key);
            }
        }
    }
    return keys;
}

function detectFormatChanges(json originalSpec, json alignedSpec) returns FormatChange[] {
    FormatChange[] changes = [];

    boolean origHasDatetime = specContainsFormat(originalSpec, "date-time");
    boolean alignedHasNewFormat = specContainsFormat(alignedSpec, "datetime");

    if origHasDatetime && alignedHasNewFormat {
        changes.push({
            originalFormat: "date-time",
            updatedFormat: "datetime",
            reason: "The `date-time` format is not compatible with the openAPI generation tool. Updated to `datetime` for Ballerina compatibility."
        });
    }

    return changes;
}

function specContainsFormat(json spec, string formatValue) returns boolean {
    if spec is map<json> {
        map<json> specMap = <map<json>>spec;
        foreach string key in specMap.keys() {
            json|error val = specMap.get(key);
            if val is json {
                if key == "format" && val is string && <string>val == formatValue {
                    return true;
                }
                if specContainsFormat(val, formatValue) {
                    return true;
                }
            }
        }
    } else if spec is json[] {
        json[] arr = <json[]>spec;
        foreach json item in arr {
            if specContainsFormat(item, formatValue) {
                return true;
            }
        }
    }
    return false;
}

function detectNullabilityChanges(json originalSpec, json alignedSpec) returns NullabilityChange[] {
    NullabilityChange[] changes = [];

    map<json> originalSchemas = extractSchemas(originalSpec);
    map<json> alignedSchemas = extractSchemas(alignedSpec);

    foreach string schemaName in alignedSchemas.keys() {
        json|error alignedSchemaResult = alignedSchemas.get(schemaName);
        json|error originalSchemaResult = originalSchemas.get(schemaName);

        if alignedSchemaResult is map<json> {
            map<json> alignedSchema = <map<json>>alignedSchemaResult;
            map<json> originalSchema = originalSchemaResult is map<json> ? <map<json>>originalSchemaResult : {};

            json|error aPropsResult = alignedSchema.get("properties");
            json|error oPropsResult = originalSchema.get("properties");

            if aPropsResult is map<json> {
                map<json> aProps = <map<json>>aPropsResult;
                map<json> oProps = oPropsResult is map<json> ? <map<json>>oPropsResult : {};

                foreach string fieldName in aProps.keys() {
                    json|error aFieldResult = aProps.get(fieldName);
                    json|error oFieldResult = oProps.get(fieldName);

                    if aFieldResult is map<json> {
                        map<json> aField = <map<json>>aFieldResult;
                        boolean isNullableInAligned = aField.hasKey("nullable") &&
                                aField.get("nullable") == true;

                        boolean isNullableInOriginal = false;
                        if oFieldResult is map<json> {
                            map<json> oField = <map<json>>oFieldResult;
                            isNullableInOriginal = oField.hasKey("nullable") &&
                                    oField.get("nullable") == true;
                        }

                        if isNullableInAligned && !isNullableInOriginal {
                            changes.push({
                                schemaName,
                                fieldName,
                                nullable: true,
                                reason: "The API can return a null value for this field."
                            });
                        }
                    }
                }
            }
        }
    }

    return changes;
}

function detectTypeChanges(json originalSpec, json alignedSpec) returns TypeChange[] {
    TypeChange[] changes = [];

    map<json> originalSchemas = extractSchemas(originalSpec);
    map<json> alignedSchemas = extractSchemas(alignedSpec);

    foreach string schemaName in alignedSchemas.keys() {
        json|error alignedSchemaResult = alignedSchemas.get(schemaName);
        json|error originalSchemaResult = originalSchemas.get(schemaName);

        if alignedSchemaResult is map<json> && originalSchemaResult is map<json> {
            map<json> alignedSchema = <map<json>>alignedSchemaResult;
            map<json> originalSchema = <map<json>>originalSchemaResult;

            json|error aPropsResult = alignedSchema.get("properties");
            json|error oPropsResult = originalSchema.get("properties");

            if aPropsResult is map<json> && oPropsResult is map<json> {
                map<json> aProps = <map<json>>aPropsResult;
                map<json> oProps = <map<json>>oPropsResult;

                foreach string fieldName in aProps.keys() {
                    json|error aFieldResult = aProps.get(fieldName);
                    json|error oFieldResult = oProps.get(fieldName);

                    if aFieldResult is map<json> && oFieldResult is map<json> {
                        map<json> aField = <map<json>>aFieldResult;
                        map<json> oField = <map<json>>oFieldResult;

                        // Fields using $ref / oneOf / anyOf have no "type" key — skip them
                        if !aField.hasKey("type") || !oField.hasKey("type") {
                            continue;
                        }

                        json|error aTypeResult = aField.get("type");
                        json|error oTypeResult = oField.get("type");

                        if aTypeResult is string && oTypeResult is string {
                            string aType = <string>aTypeResult;
                            string oType = <string>oTypeResult;
                            if aType != oType {
                                changes.push({
                                    schemaName,
                                    fieldName,
                                    originalType: oType,
                                    updatedType: aType,
                                    reason: string `The API returns ${fieldName} as ${aType}; updated for accurate representation.`
                                });
                            }
                        }
                    }
                }
            }
        }
    }

    return changes;
}

function extractSchemas(json spec) returns map<json> {
    if spec is map<json> {
        json|error componentsResult = spec.get("components");
        if componentsResult is map<json> {
            map<json> components = <map<json>>componentsResult;
            json|error schemasResult = components.get("schemas");
            if schemasResult is map<json> {
                return <map<json>>schemasResult;
            }
        }
    }
    return {};
}

// ─────────────────────────────────────────────────────────────
// STRING UTILITIES
// ─────────────────────────────────────────────────────────────

function extractFirstBacktickValue(string line) returns string {
    int? startPos = line.indexOf("`");
    if startPos is int {
        int searchFrom = startPos + 1;
        if searchFrom < line.length() {
            int? end = line.indexOf("`", searchFrom);
            if end is int && end > startPos {
                return line.substring(startPos + 1, end);
            }
        }
    }
    return "";
}

function extractAllBacktickValues(string line) returns string[] {
    string[] values = [];
    int pos = 0;
    while pos < line.length() {
        int? startPos = line.indexOf("`", pos);
        if startPos is () {
            break;
        }
        int startVal = startPos;
        int searchFrom = startVal + 1;
        if searchFrom >= line.length() {
            break;
        }
        int? end = line.indexOf("`", searchFrom);
        if end is () {
            break;
        }
        int endVal = end;
        values.push(line.substring(startVal + 1, endVal));
        pos = endVal + 1;
    }
    return values;
}

function cleanFormatValue(string raw) returns string {
    string trimmed = raw.trim();
    // Handle `"format":"value"` or `"foramt":"value"` (handles typos in hand-written docs)
    int? colonQuotePos = trimmed.indexOf(":\"");
    if colonQuotePos is int {
        string afterColon = trimmed.substring(colonQuotePos + 2);
        int? endQuote = afterColon.indexOf("\"");
        if endQuote is int {
            return afterColon.substring(0, endQuote).trim();
        }
        return afterColon.trim();
    }
    // Plain value (no key wrapper) — just strip any stray quotes
    return regex:replaceAll(trimmed, "\"", "").trim();
}
