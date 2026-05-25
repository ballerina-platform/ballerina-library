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
import ballerina/io;
import ballerina/os;
import ballerina/time;

import wso2/example_doc_generator.agent_client;
import wso2/example_doc_generator.ai_client;
import wso2/example_doc_generator.batch_runner;
import wso2/example_doc_generator.prompts;
import wso2/example_doc_generator.utils;


# Entry point for the full automation pipeline.
#
# Phase 1  (Steps 1–2):  Pre-flight validation — API key and Claude Code CLI.
# Phase 2  (Steps 3–6):  Infrastructure     — code-server, extension check, and Python agent server.
# Phase 3  (Steps 7–10): Prompt generation  — build, call Claude, format, save.
# Phase 4  (Steps 11–12): Agent execution   — run agent, enforce doc structure.
# Phase 5  (Steps 13–17): Post-processing   — inject Devant button, append examples link, crop screenshots, write run log, stop agent server.
#
# + modeOrConnectorName    - connector name by default, "trigger" to run the trigger workflow, or "batch" to run a queue
# + arg2                   - connector instructions, trigger name, or first batch option
# + arg3                   - trigger instructions or second batch option
# + arg4                   - third batch option
# + return                 - an error if any step fails
public function main(string modeOrConnectorName, string arg2 = "", string arg3 = "", string arg4 = "") returns error? {
    if modeOrConnectorName == "batch" {
        check batch_runner:runBatch(arg2, arg3, arg4);
        return;
    }

    boolean triggerMode = modeOrConnectorName == "trigger";
    string workflowKind = triggerMode ? "trigger" : "connector";
    string targetName = triggerMode ? arg2.trim() : modeOrConnectorName.trim();
    if targetName == "" {
        return error(triggerMode ? "Trigger name is required. Usage: bal run -- trigger <triggerName> [additionalInstructions]" :
            "Connector name is required. Usage: bal run -- <connectorName> [additionalInstructions]");
    }
    string triggerPackage = triggerMode ? "ballerinax/" + targetName : "";
    string additionalInstructions = triggerMode ? arg3 : arg2;

    utils:log("=== WSO2 Integrator Documentation Pipeline ===");
    utils:log("");

    time:Utc startTime = time:utcNow();
    utils:log("[INFO] Start time: " + time:utcToString(startTime));
    utils:log("[INFO] Mode: " + workflowKind);
    utils:log("[INFO] " + (triggerMode ? "Trigger" : "Connector") + ": " + targetName);
    if triggerMode {
        utils:log("[INFO] Trigger package: " + triggerPackage);
    }
    if additionalInstructions != "" {
        utils:log("[INFO] Additional instructions: " + additionalInstructions);
    }
    utils:log("");

    // Track LLM usage across all direct API calls (agent cost is tracked separately)
    ai_client:LlmUsage promptGenUsage    = {inputTokens: 0, outputTokens: 0, costUsd: 0.0d};
    ai_client:LlmUsage docEnfUsage       = {inputTokens: 0, outputTokens: 0, costUsd: 0.0d};

    // ── Phase 1: Pre-flight validation ─────────────────────────────────────

    utils:log("[STEP 1] Validating Anthropic API key...");
    check ai_client:validateApiKey(llmApiKey);
    utils:log("");

    utils:log("[STEP 2] Checking if Claude Code CLI is installed...");
    boolean claudeInstalled = utils:checkClaudeCodeInstalled();
    if !claudeInstalled {
        return error("Claude Code CLI ('claude') is not installed or not on PATH. " +
                     "Install it from https://claude.ai/code and re-run the pipeline.");
    }
    utils:log("\t[INFO] Claude Code CLI is installed.");
    utils:log("");

    // ── Phase 2: Infrastructure ─────────────────────────────────────────────

    utils:log("[STEP 3] Checking if code-server is installed...");
    boolean codeServerBinaryInstalled = utils:checkCodeServerInstalled();
    if !codeServerBinaryInstalled {
        utils:log("\t[INFO] code-server not found. Installing via official script (curl -fsSL https://code-server.dev/install.sh | sh)...");
        check utils:installCodeServer();
        utils:log("\t[INFO] code-server installed successfully.");
    } else {
        utils:log("\t[INFO] code-server is already installed.");
    }
    utils:log("");

    utils:log("[STEP 4] Verifying code-server on port " + codeServerPort.toString() + "...");
    boolean codeServerRunning = utils:checkCodeServerRunning(codeServerPort);
    if !codeServerRunning {
        utils:log("\t[INFO] Code-server not running. Starting code-server...");
        check utils:startCodeServer(codeServerPort);
        utils:log("\t[INFO] Code-server started successfully.");
    } else {
        utils:log("\t[INFO] Code-server is already running.");
    }
    string codeServerUrl = "http://localhost:" + codeServerPort.toString();
    utils:log("\t[INFO] Code-server URL: " + codeServerUrl);
    utils:log("");

    utils:log("[STEP 5] Checking WSO2 Integrator extension (wso2.wso2-integrator)...");
    boolean extInstalled = utils:checkExtensionInstalled("wso2.wso2-integrator");
    if !extInstalled {
        utils:log("\t[INFO] Extension not found. Installing...");
        check utils:ensureExtensionInstalled("wso2.wso2-integrator");
        utils:log("\t[INFO] Extension installed successfully.");
    } else {
        utils:log("\t[INFO] WSO2 Integrator extension is already installed.");
    }
    utils:log("");

    utils:log("[STEP 6] Checking Python agent server on port " + agentServerPort.toString() + "...");
    boolean agentRunning = utils:checkAgentServerRunning(agentServerPort);
    boolean agentStartedByThisProcess = false;
    if !agentRunning {
        utils:log("\t[INFO] Agent server not running. Starting via `uv run agent_server.py`...");
        check utils:startAgentServer(agentServerPort);
        agentStartedByThisProcess = true;
        utils:log("\t[INFO] Agent server started.");
    } else {
        utils:log("\t[INFO] Agent server is already running.");
    }
    string agentUrl = "http://localhost:" + agentServerPort.toString();
    utils:log("\t[INFO] Agent server URL: " + agentUrl);
    utils:log("");

    // ── Phase 3: Prompt generation ──────────────────────────────────────────

    // Derive artifact slugs from the target name — no LLM call needed
    // Preserve dots so org-qualified names like "aws.sns" stay as "aws.sns" in paths/branches.
    string connectorSlug = targetName.trim().toLowerAscii();
    connectorSlug = re `\s+`.replaceAll(connectorSlug, "-");
    connectorSlug = re `[^a-z0-9\-\.]`.replaceAll(connectorSlug, "");
    // Image filenames must use underscores (dots are not safe in screenshot prefixes).
    string imgSlug = re `\.`.replaceAll(connectorSlug, "_");
    string sampleName = re `^trigger\.`.replaceAll(connectorSlug, "");
    sampleName = re `\.`.replaceAll(sampleName, "");
    string goalSlug = triggerMode ? imgSlug + "-trigger-example" : connectorSlug + "-connector-example";
    utils:log("[INFO] " + (triggerMode ? "Trigger" : "Connector") + " slug: " + goalSlug);

    // Write target name to artifacts/run-log/ for downstream steps
    string runLogDir = "./artifacts/run-log";
    file:Error? cnDirErr = file:createDir(runLogDir, file:RECURSIVE);
    if cnDirErr is file:Error {
        return error("Could not create run-log directory: " + cnDirErr.message());
    }
    string targetNameFile = triggerMode ? "trigger-name.txt" : "connector-name.txt";
    io:Error? cnWriteErr = io:fileWriteString(runLogDir + "/" + targetNameFile, targetName);
    if cnWriteErr is io:Error {
        return error("Could not write " + targetNameFile + ": " + cnWriteErr.message());
    }
    utils:log("\t[INFO] " + (triggerMode ? "Trigger" : "Connector") + " name saved to " + runLogDir + "/" + targetNameFile);
    utils:log("");

    agent_client:AgentCost? agentCost = ();
    string enforcedDocPath = "";
    error? pipelineErr = ();
    do {
    utils:log("[STEP 7] Building system and user prompts...");
    string|error cwdResult = file:getCurrentDir();
    string projectRoot = cwdResult is string ? cwdResult : os:getEnv("PWD");
    string systemPrompt = triggerMode ?
        prompts:buildTriggerSystemPrompt(projectRoot, targetName, triggerPackage, imgSlug, sampleName) :
        prompts:buildSystemPrompt(projectRoot, targetName, imgSlug);
    string userMessage = triggerMode ?
        prompts:buildTriggerUserMessage(targetName, triggerPackage, codeServerUrl, projectRoot, additionalInstructions) :
        prompts:buildConnectorUserMessage(targetName, codeServerUrl, projectRoot, additionalInstructions);

    utils:log("[STEP 8] Calling Anthropic API to generate execution prompt...");
    ai_client:LlmResult promptResult = check ai_client:callClaude(systemPrompt, userMessage, llmApiKey);
    string executionPrompt = promptResult.text;
    promptGenUsage = promptResult.usage;

    utils:log("[STEP 9] Formatting execution prompt...");
    string header = string `# Execution Prompt

<!-- ============================================================
     XML-TAGGED MARKDOWN EXECUTION PROMPT
     Generated by: WSO2 Integrator Documentation Pipeline
     Agent: Playwright MCP (Browser Automation)
     Target: Code-Server — WSO2 Integrator (Low-Code)
     ${triggerMode ? "Trigger" : "Connector"}: ${targetName}
     ============================================================ -->

`;
    string fullPrompt = header + executionPrompt;

    utils:log("[STEP 10] Saving execution prompt to " + utils:OUTPUT_DIR + "...");
    string promptPath = check utils:saveExecutionPrompt(fullPrompt, goalSlug);
    utils:log("\t[INFO] Saved to: " + promptPath);
    utils:log("");

    // ── Phase 4: Agent execution ─────────────────────────────────────────────

    utils:log("[STEP 11] Running Claude agent...");
    agentCost = check agent_client:runClaudeAgent(promptPath, agentUrl);
    utils:log("");

    // ── Phase 5: Post-processing ──────────────────────────────────────────────

    // The agent writes the doc with all browser-automation context in its window;
    // rules stated early in the system prompt get buried. This call has the rules
    // fresh in context with no other noise, so they are reliably applied.
    utils:log("[STEP 12] Enforcing documentation structure...");
    string workflowDocsDir = "./artifacts/workflow-docs";
    file:MetaData[]|file:Error dirEntries = file:readDir(workflowDocsDir);
    if dirEntries is file:MetaData[] {
        file:MetaData? latestEntry = ();
        foreach file:MetaData entry in dirEntries {
            if entry.absPath.endsWith(".md") {
                if latestEntry is () || time:utcDiffSeconds(entry.modifiedTime, latestEntry.modifiedTime) > 0d {
                    latestEntry = entry;
                }
            }
        }
        string docPath = latestEntry is file:MetaData ? latestEntry.absPath : "";
        if docPath == "" {
            check error("No .md file found in " + workflowDocsDir + " — enforcement cannot proceed.");
        } else {
            utils:log("\t[INFO] Found workflow doc: " + docPath);
            string|io:Error rawDoc = io:fileReadString(docPath);
            if rawDoc is string {
                enforcedDocPath = docPath;
                string enforcementSystemPrompt = triggerMode ?
                    prompts:buildTriggerDocEnforcementSystemPrompt() :
                    prompts:buildDocEnforcementSystemPrompt();
                ai_client:LlmResult enfResult = check ai_client:callClaude(enforcementSystemPrompt, rawDoc, llmApiKey);
                io:Error? writeErr = io:fileWriteString(docPath, enfResult.text);
                if writeErr is io:Error {
                    check error("Could not write enforced doc: " + writeErr.message());
                }
                docEnfUsage = enfResult.usage;
                utils:log("\t[INFO] Documentation structure enforced successfully.");
            } else {
                check error("Could not read workflow doc: " + rawDoc.message());
            }
        }
    } else {
        check error("Workflow docs directory not found: " + workflowDocsDir);
    }
    utils:log("");

    utils:log("[STEP 13] Injecting 'Try it yourself' section into workflow doc...");
    if triggerMode {
        utils:log("\t[INFO] Trigger mode detected — skipping connector-specific 'Try it yourself' section injection.");
    } else if enforcedDocPath != "" {
        utils:injectTryItYourselfSection(enforcedDocPath);
    } else {
        utils:log("\t[INFO] No enforced doc path available — skipping 'Try it yourself' section injection.");
    }
    utils:log("");

    utils:log("[STEP 14] Checking Ballerina Central for connector examples link...");
    if triggerMode {
        utils:log("\t[INFO] Trigger mode detected — skipping connector examples link.");
    } else if enforcedDocPath != "" {
        utils:appendExamplesSection(enforcedDocPath);
    } else {
        utils:log("\t[INFO] No enforced doc path available — skipping examples link.");
    }
    utils:log("");

    utils:log("[STEP 15] Cropping screenshots...");
    os:Process|error cropProc = os:exec({
        value: "python/.venv/bin/python",
        arguments: ["python/crop_screenshots.py"]
    });
    if cropProc is error {
        utils:log("\t[WARN] Could not launch crop_screenshots.py: " + cropProc.message());
        utils:log("\t[WARN] Run `make crop-screenshots` manually to crop screenshots.");
    } else {
        int exitCode = check cropProc.waitForExit();
        if exitCode == 0 {
            utils:log("\t[INFO] Screenshots cropped successfully.");
        } else {
            utils:log("\t[WARN] crop_screenshots.py exited with code " + exitCode.toString() + ".");
            utils:log("\t[WARN] Run `make crop-screenshots` manually to crop screenshots.");
        }
    }
    utils:log("");

    // ── Phase 5 (cont.): Finalise ─────────────────────────────────────────────

    time:Utc endTime = time:utcNow();
    decimal durationSecs = time:utcDiffSeconds(endTime, startTime);

    // Aggregate direct API call costs
    int totalInputTokens  = promptGenUsage.inputTokens  + docEnfUsage.inputTokens;
    int totalOutputTokens = promptGenUsage.outputTokens + docEnfUsage.outputTokens;
    decimal totalCostUsd  = promptGenUsage.costUsd      + docEnfUsage.costUsd;

    // Add agent SDK cost to combined total
    decimal agentCostUsd = 0.0d;
    if agentCost is agent_client:AgentCost {
        decimal? ac = agentCost.totalCostUsd;
        if ac is decimal {
            agentCostUsd = ac;
        }
    }
    decimal totalCombinedCostUsd = totalCostUsd + agentCostUsd;

    utils:log("[STEP 16] Writing run log...");
    utils:writeRunLog({
        connectorName:            targetName,
        connectorSlug:            goalSlug,
        additionalInstructions:   additionalInstructions,
        startTime:           startTime,
        endTime:             endTime,
        durationSecs:        durationSecs,
        promptGenUsage:      promptGenUsage,
        docEnfUsage:         docEnfUsage,
        agentCost:           agentCost,
        totalDirectCostUsd:  totalCostUsd,
        totalCombinedCostUsd: totalCombinedCostUsd,
        promptPath:          promptPath,
        workflowDocPath:     enforcedDocPath == "" ? "(not written)" : enforcedDocPath
    });
    utils:log("");

    // Print pipeline stats
    utils:log("--- Pipeline Stats ---");
    utils:log(string `Start time:      ${time:utcToString(startTime)}`);
    utils:log(string `End time:        ${time:utcToString(endTime)}`);
    utils:log(string `Duration:        ${durationSecs}s`);
    utils:log(string `Prompt length:   ${fullPrompt.length()} chars`);
    utils:log("--- LLM Cost Breakdown ---");
    utils:log(string `Prompt gen:      ${promptGenUsage.inputTokens} in / ${promptGenUsage.outputTokens} out  |  $${promptGenUsage.costUsd}`);
    utils:log(string `Doc enforcement: ${docEnfUsage.inputTokens} in / ${docEnfUsage.outputTokens} out  |  $${docEnfUsage.costUsd}`);
    utils:log(string `Direct API total:${totalInputTokens} in / ${totalOutputTokens} out  |  $${totalCostUsd}`);
    utils:log(string `Agent SDK:       $${agentCostUsd}`);
    utils:log(string `COMBINED TOTAL:  $${totalCombinedCostUsd}`);
    } on fail error e {
        pipelineErr = e;
    }

    utils:log("");
    if agentStartedByThisProcess {
        utils:log("[STEP 17] Stopping Python agent server...");
        error? stopErr = agent_client:stopAgentServer(agentUrl);
        if stopErr is error {
            utils:log("\t[WARN] Could not stop Python agent server: " + stopErr.message());
        } else {
            utils:log("\t[INFO] Python agent server stopped.");
        }
    } else {
        utils:log("[STEP 17] Python agent server was already running; leaving it active.");
    }

    if pipelineErr is error {
        return pipelineErr;
    }

    utils:log("");
    utils:log("=== Pipeline Complete ===");
    utils:log("Artifacts saved under '" + utils:OUTPUT_DIR + "'.");
}
