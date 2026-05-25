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

# Builds the connector user message containing only the dynamic/variable parts:
# connector name, code-server URL, and absolute artifact paths. All rules, template
# structure, and formatting instructions live in system_prompt.bal.
#
# + connectorName          - Exact Ballerina Central package name (e.g. "mysql", "kafka")
# + codeServerUrl          - The URL where code-server is running
# + projectRoot            - Absolute path to the project root directory
# + additionalInstructions - Optional extra instructions for the agent (empty string if none)
# + return - the user message string
public function buildConnectorUserMessage(string connectorName, string codeServerUrl, string projectRoot, string additionalInstructions = "") returns string {
    string screenshotsDir = projectRoot + "/artifacts/screenshots";
    string workflowDocsDir = projectRoot + "/artifacts/workflow-docs";
    string additionalInstructionsSection = additionalInstructions != "" ? string `

ADDITIONAL INSTRUCTIONS (these take priority and must be followed exactly):
${additionalInstructions}
` : "";
    return string `Generate a highly detailed execution prompt for the following goal.

THE MAIN GOAL (this must be the central focus of the ENTIRE execution prompt):
Create a WSO2 Integrator integration using the ${connectorName} connector from Ballerina Central. The integration must:
1. Locate and add the ${connectorName} connector from the connector palette.
2. Configure the connection by binding required parameters to configurable variables where appropriate.
3. Add an entry point or automation flow and call the primary operation for this connector type.
4. Log or otherwise surface the operation result when the operation returns a value.
5. Document every step with screenshots at the mandatory milestones.
${additionalInstructionsSection}
Make sure the goal above is clearly reflected in:
- The prompt TITLE (name the connector explicitly)
- The OVERVIEW section (first sentence must state the connector and operation)
- The OBJECTIVES (list connector-specific implementation objectives)
- The IMPLEMENTATION STAGES (Stage 5+ must break down this exact goal into detailed, actionable steps with specific UI element names, fields to fill, buttons to click)
- The DELIVERABLES (filename should use the connector name)
- The SUCCESS CRITERIA (what does a successful ${connectorName} connector integration look like?)

CODE-SERVER URL: ${codeServerUrl}
(Use this exact URL in Stage 1 when navigating to the code-server instance)

Screenshots directory: ${screenshotsDir}
Workflow docs directory: ${workflowDocsDir}
IMPORTANT: Use these ABSOLUTE paths when specifying filenames for browser_take_screenshot and when writing workflow documentation. Do NOT use relative paths.`;
}
