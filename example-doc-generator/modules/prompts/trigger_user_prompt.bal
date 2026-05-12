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

# Builds the user message containing only the dynamic/variable parts:
# trigger name, trigger package, code-server URL, and absolute artifact paths. All rules, template
# structure, and formatting instructions live in system_prompt.bal.
#
# + triggerName            - Exact Ballerina Central package name (e.g. "trigger.github", "kafka")
# + triggerPackage         - Full Ballerina Central package path (e.g. "ballerinax/trigger.github", "ballerina/http")
# + codeServerUrl          - The URL where code-server is running
# + projectRoot            - Absolute path to the project root directory
# + additionalInstructions - Optional extra instructions for the agent (empty string if none)
# + return - the user message string
public function buildTriggerUserMessage(string triggerName, string triggerPackage, string codeServerUrl, string projectRoot, string additionalInstructions = "") returns string {
    string bt = "`";
    string screenshotsDir = projectRoot + "/artifacts/screenshots";
    string workflowDocsDir = projectRoot + "/artifacts/workflow-docs";
    string additionalInstructionsSection = additionalInstructions != "" ? string `

ADDITIONAL INSTRUCTIONS (these take priority and must be followed exactly):
${additionalInstructions}
` : "";
    return string `Generate a highly detailed execution prompt for the following goal.

THE MAIN GOAL (this must be the central focus of the ENTIRE execution prompt):
Create a WSO2 Integrator integration using the ${triggerName} trigger
(${triggerPackage} from Ballerina Central). The integration must:
1. Open the Artifacts palette via "+ Add Artifact" and select the
   ${triggerName} trigger from the appropriate category
   (Integration as API / Event Integration / File Integration).
2. Configure the trigger listener by binding each required string/int parameter
   to a configuration variable (Ballerina ${bt}configurable string${bt} /
   ${bt}configurable int${bt}) using the Helper Panel. Enum/dropdown fields
   (e.g. Event Channel) should be set directly — no configuration needed.
   Always use Ballerina declaration order in prose — "configurable string",
   never "string configurable".
3. After clicking Create, add the primary event handler from the Service view
   via "+ Add Handler" → select handler → define the Message payload via
   Message Configuration → Define Value → Create Type Schema: enter a unique
   PascalCase record name, add each payload field with the + icon (name + type),
   select Save on the modal, then Save the handler configuration. Do NOT use
   the Import tab / paste JSON / Import Type path. Some triggers (Salesforce,
   Twilio, TCP) pre-register handlers and have no "+ Add Handler" panel;
   some (MQTT, ASB, Salesforce, Twilio, TCP, FTP, File) have library-defined
   payload types and no Define Value modal — for those, the per-trigger
   ADDITIONAL INSTRUCTIONS block tells the agent which alternate surface to
   capture for screenshots 04 and 05. HTTP/GraphQL use "+ Add Resource" /
   "+ Create Operations" instead.
4. Add log:printInfo(<paramName>.toJsonString()) inside the handler body via the
   pro-code exception (Read + Edit tools on the .bal file directly). The handler
   parameter may be named payload, event, message, data, afterEntry, etc. — use
   the actual parameter name from the source.
5. Navigate back to the Service view so the registered handler row is visible.
6. Document every step with screenshots at the 7 mandatory milestones:
   _01_artifact_palette, _02_trigger_config_form, _03_configurations_panel,
   _04_add_handler_panel, _05_message_define_value, _06_handler_flow,
   _07_service_view_final. Screenshot 07 is the final milestone.
${additionalInstructionsSection}
Make sure the goal above is clearly reflected in:
- The prompt TITLE (name the trigger explicitly)
- The OVERVIEW section (first sentence must state the trigger and event category)
- The OBJECTIVES (list trigger-specific implementation objectives)
- The IMPLEMENTATION STAGES (Stage 5+ must break down this exact goal into detailed, actionable steps with specific UI element names, fields to fill, buttons to click)
- The DELIVERABLES (filename should use the trigger name)
- The SUCCESS CRITERIA (what does a successful ${triggerName} trigger integration look like?)

CODE-SERVER URL: ${codeServerUrl}
(Use this exact URL in Stage 1 when navigating to the code-server instance)

Screenshots directory: ${screenshotsDir}
Workflow docs directory: ${workflowDocsDir}
IMPORTANT: Use these ABSOLUTE paths when specifying filenames for browser_take_screenshot and when writing workflow documentation. Do NOT use relative paths.`;
}
