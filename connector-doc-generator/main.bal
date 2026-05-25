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

import ballerina/file;
import ballerina/http;
import ballerina/io;
import ballerina/os;
import ballerina/time;

import wso2/connector_doc_generator.category;
import wso2/connector_doc_generator.central;
import wso2/connector_doc_generator.claude;
import wso2/connector_doc_generator.extractor;
import wso2/connector_doc_generator.prompts;
import wso2/connector_doc_generator.sidebar;

const string OUTPUT_DIR = "./output";

# Connector documentation generation pipeline.
#
# Reads connector identity from Config.toml and runs a 5-step pipeline:
#   1. Fetch latest version from Ballerina Central (unless already set)
#   2. Clone source repository locally (shallow, no web browsing during generation)
#   3. Call Claude Code CLI with local Read/Glob/Grep tools (two phases)
#   4. Write the generated markdown files to the docs directory
#   5. Patch sidebars.ts and catalog/index.md
#
# + return - an error if any step fails
public function main() returns error? {
    log("=== Connector Doc Generator ===");
    log(string `Connector: ${connectorName}  |  Module: ${moduleSlug}  |  Category: ${category}`);
    log("");

    time:Utc startTime = time:utcNow();

    // ── Step 1: Resolve version ─────────────────────────────────────────────
    string resolvedVersion = connectorVersion;
    if resolvedVersion == "" {
        log(string `[1/6] Fetching latest version for ${packageName} from Ballerina Central...`);
        resolvedVersion = check central:fetchLatestVersion(packageName);
        log(string `      Latest version: ${resolvedVersion}`);
    } else {
        log(string `[1/6] Using configured version: ${resolvedVersion}`);
    }
    log("");

    // ── Step 2: Load existing docs + build prompt ───────────────────────────
    log("[2/6] Checking for existing docs...");

    string connectorDocDir = docsRoot + "/catalog/" + category + "/" + moduleSlug;
    boolean docsExist = check file:test(connectorDocDir, file:EXISTS);
    string existingDocsDir = docsExist ? connectorDocDir : "";
    if docsExist {
        log(string `      Found existing docs at: ${connectorDocDir} — running in UPDATE mode`);
    }

    check file:createDir(OUTPUT_DIR, file:RECURSIVE);

    if dryRun {
        prompts:ConnectorInput dryInput = {
            name: connectorName,
            module: moduleSlug,
            packageName: packageName,
            githubRepo: githubRepo,
            category: category,
            'version: resolvedVersion,
            existingDocsDir: existingDocsDir
        };
        string dryPromptText = check prompts:buildPrompt(dryInput);
        string promptPath = OUTPUT_DIR + "/" + moduleSlug + "-prompt.md";
        check io:fileWriteString(promptPath, dryPromptText);

        string connectorDir = docsRoot + "/catalog/" + category + "/" + moduleSlug;
        string indexPath = docsRoot + "/catalog/index.mdx";
        log("[DRY RUN] Would execute the following steps:");
        log(string `  [3/6] Clone https://github.com/ballerina-platform/${githubRepo} to /tmp/`);
        log(string `  [4a/6] Phase 1 — overview, setup guide, trigger reference (prompt: ${dryPromptText.length()} chars)`);
        log(string `  [4b/6] Phase 2 — action reference (2a discovery + 2b per-client in parallel)`);
        log(string `  [5/6] Write doc files to: ${connectorDir}/`);
        log(string `  [6/6] Patch ${sidebarPath} and ${indexPath}`);
        log("");
        log(string `  Prompt saved to: ${promptPath}`);
        return;
    }

    // ── Step 2b: Clone source repository ────────────────────────────────────
    log("[3/6] Cloning source repository (shallow)...");
    string localRepoPath = check cloneSourceRepo(githubRepo, moduleSlug, resolvedVersion);
    log(string `      Cloned to: ${localRepoPath}`);
    log("");

    prompts:ConnectorInput input = {
        name: connectorName,
        module: moduleSlug,
        packageName: packageName,
        githubRepo: githubRepo,
        category: category,
        'version: resolvedVersion,
        existingDocsDir: existingDocsDir,
        localRepoPath: localRepoPath
    };
    string promptText = check prompts:buildPrompt(input);
    string promptPath = OUTPUT_DIR + "/" + moduleSlug + "-prompt.md";
    check io:fileWriteString(promptPath, promptText);
    log(string `      Prompt saved: ${promptPath}  (${promptText.length()} chars)`);
    log("");

    // ── Step 3: Call Claude Code CLI (two phases) ───────────────────────────
    if !claude:isClaudeInstalled() {
        file:Error? removeErr = file:remove(localRepoPath, file:RECURSIVE);
        if removeErr is file:Error {
            // best-effort cleanup — ignore
        }
        return error("Claude Code CLI ('claude') not found on PATH. " +
            "Install with: npm install -g @anthropic-ai/claude-code");
    }

    // Running totals across all Claude calls
    int totalCalls = 0;
    int totalInputTokens = 0;
    int totalOutputTokens = 0;
    decimal totalCostUsd = 0.0d;

    // ── Phase 1: overview, setup-guide, trigger-reference ───────────────────
    log("[4a/6] Phase 1 — overview, setup guide, trigger reference...");
    log("       Claude is reading local source files...");

    string phase1RawPath = OUTPUT_DIR + "/" + moduleSlug + "-phase1-raw.txt";
    claude:ClaudeResult phase1Result = check claude:callClaude(promptText, maxTurns = claude:MAX_TURNS_PHASE1);
    check io:fileWriteString(phase1RawPath, phase1Result.text);
    totalCalls += 1;
    totalInputTokens += phase1Result.inputTokens ?: 0;
    totalOutputTokens += phase1Result.outputTokens ?: 0;
    totalCostUsd += phase1Result.costUsd ?: 0.0d;
    logClaudeStats(phase1Result);

    extractor:ExtractionResult phase1Extracted = extractor:extractAll(phase1Result.text);
    string phase1Overview = phase1Extracted.files["overview.md"] ?: "";

    // ── Download setup-guide images into static assets ───────────────────────
    if phase1Extracted.images.length() > 0 {
        log(string `      Downloading ${phase1Extracted.images.length()} image(s) to static assets...`);
        string imgDir = staticImgRoot + "/" + category + "/" + moduleSlug;
        check file:createDir(imgDir, file:RECURSIVE);
        foreach extractor:ImageDownload img in phase1Extracted.images {
            // Sanitize: take only the basename (strip any directory components)
            // then validate it contains only safe characters.
            string basename = img.filename;
            int? lastSlash = basename.lastIndexOf("/");
            if lastSlash is int {
                basename = basename.substring(lastSlash + 1);
            }
            int? lastBackslash = basename.lastIndexOf("\\");
            if lastBackslash is int {
                basename = basename.substring(lastBackslash + 1);
            }
            // Allow only alphanumerics, hyphens, underscores, and dots; reject everything else.
            boolean safe = re `^[A-Za-z0-9._-]+$`.isFullMatch(basename) && !basename.startsWith(".");
            if !safe || basename.length() == 0 {
                log(string `      WARN  Skipping image with unsafe filename '${img.filename}'`);
                continue;
            }
            string targetPath = imgDir + "/" + basename;
            error? dlErr = downloadFile(img.url, targetPath);
            if dlErr is error {
                log(string `      WARN  Failed to download ${img.url}: ${dlErr.message()}`);
            } else {
                log(string `      DOWNLOAD ${img.url} → ${targetPath}`);
            }
        }
    }

    // ── Phase 2a: action-reference header + client discovery ─────────────────
    log("[4b/6] Phase 2a — discovering packages and clients...");

    prompts:ConnectorInput phase2aInput = {
        name: connectorName,
        module: moduleSlug,
        packageName: packageName,
        githubRepo: githubRepo,
        category: category,
        'version: resolvedVersion,
        phase: 2,
        phase1Overview: phase1Overview,
        existingDocsDir: existingDocsDir,
        localRepoPath: localRepoPath
    };
    string phase2aPromptText = check prompts:buildPrompt(phase2aInput);
    string phase2aPromptPath = OUTPUT_DIR + "/" + moduleSlug + "-phase2a-prompt.md";
    check io:fileWriteString(phase2aPromptPath, phase2aPromptText);

    string phase2aRawPath = OUTPUT_DIR + "/" + moduleSlug + "-phase2a-raw.txt";
    claude:ClaudeResult phase2aResult = check claude:callClaude(phase2aPromptText, maxTurns = claude:MAX_TURNS_PHASE2A);
    check io:fileWriteString(phase2aRawPath, phase2aResult.text);
    totalCalls += 1;
    totalInputTokens += phase2aResult.inputTokens ?: 0;
    totalOutputTokens += phase2aResult.outputTokens ?: 0;
    totalCostUsd += phase2aResult.costUsd ?: 0.0d;
    logClaudeStats(phase2aResult);

    string actionHeader = extractor:extractActionHeader(phase2aResult.text);
    extractor:ClientInfo[] clients = extractor:extractClients(phase2aResult.text);
    log(string `      Discovered ${clients.length()} client(s): ${string:'join(", ", ...clients.map(c => c.displayName))}`);

    // ── Phase 2b: per-client sections (parallel) ──────────────────────────────
    log(string `[4c/6] Phase 2b — generating ${clients.length()} client section(s) in parallel...`);

    // Build all prompts and launch all Claude calls concurrently
    future<[string, claude:ClaudeResult]|error>[] phase2bFutures = [];
    string[] phase2bDisplayNames = [];

    foreach extractor:ClientInfo clientInfo in clients {
        prompts:ConnectorInput phase2bInput = {
            name: connectorName,
            module: moduleSlug,
            packageName: packageName,
            githubRepo: githubRepo,
            category: category,
            'version: resolvedVersion,
            phase: 3,
            phase1Overview: phase1Overview,
            targetClient: clientInfo,
            existingDocsDir: existingDocsDir,
            localRepoPath: localRepoPath
        };
        string phase2bPromptText = check prompts:buildPrompt(phase2bInput);
        string safeDisplayName = re ` `.replaceAll(clientInfo.displayName.toLowerAscii(), "-");
        string phase2bPromptPath = OUTPUT_DIR + "/" + moduleSlug + "-phase2b-" + safeDisplayName + "-prompt.md";
        check io:fileWriteString(phase2bPromptPath, phase2bPromptText);

        string phase2bRawPath = OUTPUT_DIR + "/" + moduleSlug + "-phase2b-" + safeDisplayName + "-raw.txt";
        future<[string, claude:ClaudeResult]|error> f = start runPhase2b(clientInfo.displayName, phase2bPromptText, phase2bRawPath);
        phase2bFutures.push(f);
        phase2bDisplayNames.push(clientInfo.displayName);
    }

    // Collect results in order (logging already happened as each call completed)
    string[] clientSections = [];
    foreach int i in 0 ..< phase2bFutures.length() {
        [string, claude:ClaudeResult]|error phase2bResult = wait phase2bFutures[i];
        if phase2bResult is error {
            log(string `      WARN  Phase 2b failed for '${phase2bDisplayNames[i]}': ${phase2bResult.message()}`);
            continue;
        }
        var [section, claudeResult] = phase2bResult;
        totalCalls += 1;
        totalInputTokens += claudeResult.inputTokens ?: 0;
        totalOutputTokens += claudeResult.outputTokens ?: 0;
        totalCostUsd += claudeResult.costUsd ?: 0.0d;
        if section.length() > 0 {
            clientSections.push(section);
        } else {
            log(string `      WARN  No <client_section> found for '${phase2bDisplayNames[i]}'`);
        }
    }

    // Assemble action-reference.md from header + all client sections
    string actionRefContent = actionHeader;
    if clientSections.length() > 0 {
        if actionRefContent.length() > 0 {
            actionRefContent += "\n\n";
        }
        actionRefContent += string:'join("\n\n---\n\n", ...clientSections);
    }

    // Merge all phases
    map<string> allFiles = {};
    foreach string fileName in phase1Extracted.files.keys() {
        allFiles[fileName] = phase1Extracted.files.get(fileName);
    }
    if actionRefContent.length() > 0 {
        allFiles["action-reference.md"] = actionRefContent;
    }

    extractor:ExtractionResult extracted = {
        files: allFiles,
        categoryEntry: phase1Extracted.categoryEntry,
        images: []
    };

    log("");

    // ── Step 4: Extract and write files ────────────────────────────────────
    log("[5/6] Extracting and writing documentation files...");

    if extracted.files.length() == 0 {
        file:Error? removeErr = file:remove(localRepoPath, file:RECURSIVE);
        if removeErr is file:Error {
            // best-effort cleanup — ignore
        }
        return error(string `No <file> blocks found in Claude's response. ` +
            string `Check phase1: ${phase1RawPath}  phase2: ${phase2aRawPath}`);
    }

    string connectorDir = docsRoot + "/catalog/" + category + "/" + moduleSlug;
    check file:createDir(connectorDir, file:RECURSIVE);

    string[] writtenFiles = [];
    foreach string fileName in extracted.files.keys() {
        if fileName.startsWith("__truncated__") {
            log(string `      WARN  ${fileName.substring(13)} was truncated (Claude hit output limit) — content is partial`);
            continue;
        }
        string filePath = connectorDir + "/" + fileName;
        string content = extracted.files.get(fileName);

        boolean exists = check file:test(filePath, file:EXISTS);
        if exists && !force {
            log(string `      SKIP  ${filePath}  (already exists; set force=true to overwrite)`);
            continue;
        }
        check io:fileWriteString(filePath, content);
        log(string `      WRITE ${filePath}`);
        writtenFiles.push(fileName);
    }

    if writtenFiles.length() == 0 {
        log("      No new files written (all already existed).");
    }
    log("");

    // ── Step 5: Patch sidebar and category index ────────────────────────────
    log("[6/6] Patching sidebars.ts and category index...");

    boolean hasSetup = extracted.files.hasKey("setup-guide.md");
    boolean hasTriggers = extracted.files.hasKey("trigger-reference.md");

    error? sidebarErr = sidebar:injectConnector(
        sidebarPath, connectorName, moduleSlug, category, hasSetup, hasTriggers);
    if sidebarErr is error {
        log(string `      SKIP  sidebar patch: ${sidebarErr.message()}`);
    } else {
        log(string `      PATCH ${sidebarPath}  (added '${connectorName}')`);
    }

    extractor:CategoryEntry? catEntry = extracted.categoryEntry;
    if catEntry is extractor:CategoryEntry {
        string indexPath = docsRoot + "/catalog/index.mdx";
        string[] pkgParts = re `/`.split(packageName);
        string pkgOrg = pkgParts.length() > 0 ? pkgParts[0] : "ballerinax";
        error? catErr = category:insertConnectorEntry(
            indexPath, connectorName, moduleSlug, category,
            catEntry.description, catEntry.operations, catEntry.auth,
            pkgOrg, resolvedVersion);
        if catErr is error {
            log(string `      SKIP  catalog patch: ${catErr.message()}`);
        } else {
            log(string `      PATCH ${indexPath}  (added '${connectorName}' entry)`);
        }
    } else {
        log("      SKIP  catalog patch: no <category_entry> found in Claude's response");
    }
    log("");

    // ── Cleanup cloned repo ─────────────────────────────────────────────────
    file:Error? cleanupErr = file:remove(localRepoPath, file:RECURSIVE);
    if cleanupErr is file:Error {
        log(string `WARN  Failed to remove temp repo: ${cleanupErr.message()}`);
    }

    // ── Done ────────────────────────────────────────────────────────────────
    time:Utc endTime = time:utcNow();
    decimal duration = time:utcDiffSeconds(endTime, startTime);

    log("=== Done ===");
    log(string `  Duration:        ${duration}s`);
    log(string `  Claude calls:    ${totalCalls}`);
    log(string `  Input tokens:    ${totalInputTokens}`);
    log(string `  Output tokens:   ${totalOutputTokens}`);
    log(string `  Total tokens:    ${totalInputTokens + totalOutputTokens}`);
    log(string `  Total cost:      $${totalCostUsd}`);
    log(string `  Phase 1 prompt:  ${promptPath}`);
    log(string `  Phase 2a prompt: ${phase2aPromptPath}`);
    log(string `  Phase 1 raw:     ${phase1RawPath}`);
    log(string `  Phase 2a raw:    ${phase2aRawPath}`);
    log(string `  Docs:            ${connectorDir}/`);
}

// Runs a single phase 2b Claude call and logs stats immediately on completion.
// Called via `start` so multiple clients run concurrently.
function runPhase2b(string displayName, string promptText, string rawPath) returns [string, claude:ClaudeResult]|error {
    claude:ClaudeResult result = check claude:callClaude(promptText, model = claude:FAST_MODEL, maxTurns = claude:MAX_TURNS_PHASE2B);
    check io:fileWriteString(rawPath, result.text);
    log(string `      Completed: '${displayName}'`);
    logClaudeStats(result);
    string section = extractor:extractClientSection(result.text);
    return [section, result];
}

function cloneSourceRepo(string repo, string slug, string 'version) returns string|error {
    int ts = <int>time:utcNow()[0];
    string repoPath = string `/tmp/conn_doc_${slug}_${ts}`;
    string cloneUrl = string `https://github.com/ballerina-platform/${repo}`;
    string tag = string `v${'version}`;

    os:Process|error proc = os:exec({
        value: "git",
        arguments: ["clone", "--depth", "1", "--branch", tag, cloneUrl, repoPath]
    });
    if proc is error {
        return error("Failed to start git clone: " + proc.message());
    }
    int|error exitCode = proc.waitForExit();
    if exitCode is error {
        return error("git clone error: " + exitCode.message());
    }
    if exitCode != 0 {
        return error(string `git clone failed (exit ${exitCode}) for ${cloneUrl} at tag '${tag}'`);
    }
    return repoPath;
}

function logClaudeStats(claude:ClaudeResult result) {
    log("      ── Claude stats ──────────────────────");
    log(string `      Model:    ${result.model ?: "claude-opus-4-6"}`);
    decimal? dur = result.durationMs;
    if dur is decimal {
        log(string `      Duration: ${dur / 1000.0d}s`);
    }
    int? inp = result.inputTokens;
    int? out = result.outputTokens;
    if inp is int && out is int {
        log(string `      Tokens:   ${inp} in / ${out} out`);
    }
    decimal? cost = result.costUsd;
    if cost is decimal {
        log(string `      Cost:     $${cost}`);
    }
    log("      ──────────────────────────────────────");
    log("");
}

// Permitted hostnames for image downloads. Images are sourced from GitHub only.
final string[] ALLOWED_IMAGE_HOSTS = [
    "raw.githubusercontent.com",
    "github.com",
    "user-images.githubusercontent.com"
];

function validateImageHost(string hostname) returns error? {
    // Reject literal IPv4 addresses (e.g. 192.168.1.1)
    if re `^\d{1,3}(\.\d{1,3}){3}$`.isFullMatch(hostname) {
        return error("Rejected literal IPv4 address in image URL: " + hostname);
    }
    // Reject literal IPv6 addresses (contain colons, e.g. [::1])
    if hostname.includes(":") || hostname.includes("[") {
        return error("Rejected literal IPv6 address in image URL: " + hostname);
    }
    // Enforce allowlist
    foreach string allowed in ALLOWED_IMAGE_HOSTS {
        if hostname == allowed || hostname.endsWith("." + allowed) {
            return;
        }
    }
    return error(string `Image host '${hostname}' is not in the allowed list`);
}

function downloadFile(string url, string targetPath) returns error? {
    // Only HTTPS is permitted — reject plain HTTP
    string httpsPrefix = "https://";
    if !url.startsWith(httpsPrefix) {
        return error("Only HTTPS image URLs are allowed: " + url);
    }
    string withoutProtocol = url.substring(httpsPrefix.length());

    int? slashIdx = withoutProtocol.indexOf("/");
    if slashIdx is () {
        return error("Invalid URL (no path component): " + url);
    }
    string hostWithPort = withoutProtocol.substring(0, slashIdx);
    string path = withoutProtocol.substring(slashIdx);

    // Strip port for hostname validation
    string hostname = hostWithPort;
    int? colonIdx = hostWithPort.indexOf(":");
    if colonIdx is int {
        hostname = hostWithPort.substring(0, colonIdx);
    }
    check validateImageHost(hostname);

    string host = httpsPrefix + hostWithPort;
    http:Client httpClient = check new (host, timeout = 30);
    http:Response resp = check httpClient->get(path);
    if resp.statusCode < 200 || resp.statusCode >= 300 {
        return error(string `HTTP ${resp.statusCode} downloading ${url}`);
    }
    byte[] bytes = check resp.getBinaryPayload();
    check io:fileWriteBytes(targetPath, bytes);
}

function log(string message) {
    io:println(message);
}
