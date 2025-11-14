string backTick = "`";
string tripleBackTick = "```";

function getExampleCodegenerationPrompt(ConnectorDetails details, string useCase, string targetedContext) returns string {
    return string `
You are an expert Ballerina developer with deep knowledge of API connector patterns, client initialization, and example code best practices.

<CONTEXT>
Connector: ${details.connectorName}
Task: Generate a complete, compilable Ballerina example demonstrating the following use case
Use Case: ${useCase}
</CONTEXT>

<REFLECTION_PHASE>
Before writing the code, think through this systematically:

1. **Use Case Analysis**:
   - What is the main workflow this example should demonstrate?
   - What are the key steps in this use case?
   - What data flow is expected (input → processing → output)?

2. **Function Selection & Sequencing**:
   - Which exact functions from "Relevant Code Definitions" do I need?
   - What is the logical order of function calls?
   - How do outputs from one function feed into the next?

3. **Client Initialization Strategy**:
   - What configuration parameters does the client need?
   - Which configurable variables should I define?
   - How should I handle connection setup and error scenarios?

4. **Data Structure Planning**:
   - What record types do I need to define or import?
   - How will I handle API responses and requests?
   - What realistic test data should I use?

5. **Example Quality Validation**:
   - Is this example clear and educational?
   - Does it demonstrate real-world usage patterns?
   - Will a developer understand how to adapt this for their needs?
</REFLECTION_PHASE>

<CRITICAL_REQUIREMENTS>
**EXACT NAME USAGE**: You MUST use the exact function and type names from "Relevant Code Definitions" below. Do NOT modify, shorten, or invent names. Auto-generated names may be long - use them verbatim.

**FUNCTION SOURCE**: Your ONLY source for function signatures is the "Relevant Code Definitions" section. Every function call must exactly match these signatures.
</CRITICAL_REQUIREMENTS>

<BALLERINA_EXAMPLE_GUIDELINES>
### File Structure
- Generate a single, complete ${backTick}main.bal${backTick} file
- Include all necessary imports (${backTick}ballerina/io${backTick}, ${backTick}ballerinax/${details.connectorName}${backTick})
- Use ${backTick}public function main() returns error?${backTick} as entry point

### Client Initialization
- Use exact init function signature from "Client Initialization" section
- Define configurable variables for credentials and configuration
- Follow ConnectionConfig structure exactly as provided
- Include proper error handling for client creation

### Data Types and Imports
- Import connector types using: ${backTick}${details.connectorName}:relevantTypeName${backTick}
- Do NOT redefine types that exist in the connector
- Use proper record types for structured data
- Define custom records only when necessary for example clarity

### Code Quality
- Print results of each step using ${backTick}io:println()${backTick}
- Use meaningful variable names that reflect the use case
- Include realistic test data appropriate for the connector domain
- Demonstrate error handling where appropriate
- Make the code self-explanatory and educational
</BALLERINA_EXAMPLE_GUIDELINES>

<OUTPUT_FORMATTING_RULES>
- **Your entire response must be raw Ballerina code.**
- **Under no circumstances should you wrap the output in markdown code fences like ${tripleBackTick}ballerina or ${tripleBackTick}.**
- The response must not contain any explanations, markdown, or any text that is not valid Ballerina code.
- The code must be ready to be saved directly to a ${backTick}.bal${backTick} file and compiled.
</OUTPUT_FORMATTING_RULES>

<RELEVANT_CODE_DEFINITIONS>
${targetedContext}
</RELEVANT_CODE_DEFINITIONS>

Now apply your reflection and generate the complete example code:
`;
}

function getUsecasePrompt(ConnectorDetails details, string[] usedFunctions) returns string {
    string previouslyUsedSection = "";
    if usedFunctions.length() > 0 {
        string[] formattedUsedFunctions = from string func in usedFunctions
            select string `- '${func}'`;
        previouslyUsedSection = string `
<PREVIOUSLY_USED_FUNCTIONS>
The following functions have already been used in previous examples.
Create a NEW and DISTINCT use case that avoids these functions to ensure variety:
${string:'join("\n", ...formattedUsedFunctions)}
</PREVIOUSLY_USED_FUNCTIONS>
`;
    }

    return string `
You are a Ballerina software architect and API integration expert specializing in creating realistic, educational use cases.

<CONTEXT>
Connector: ${details.connectorName}
Task: Design a unique, multi-step workflow that demonstrates practical API usage patterns
</CONTEXT>

${previouslyUsedSection}

<FUNCTION_IDENTIFICATION_RULES>
**Critical**: Extract function identifiers using these EXACT rules:
- **Resource functions**: Use format "METHOD function.path" (e.g., "get admin.apps.approved.list")
- **Remote functions**: Use only the function name (e.g., "createRepository")

Follow these rules precisely for the 'requiredFunctions' array.
</FUNCTION_IDENTIFICATION_RULES>

<AVAILABLE_FUNCTIONS>
${details.functionSignatures}
</AVAILABLE_FUNCTIONS>

<INSTRUCTIONS>
Analyze the connector capabilities and create a realistic, multi-step use case that:
1. Solves a real-world problem developers would face
2. Uses 2-3 functions in a logical sequence  
3. Demonstrates practical API usage patterns
4. Avoids previously used functions to ensure variety
5. Is educational and relevant to developers

**Your entire response must be a raw JSON string, without any markdown formatting like ${tripleBackTick}json ... ${tripleBackTick}.**
Return ONLY a valid JSON object with no additional text, explanations, or reflection sections.
</INSTRUCTIONS>

<OUTPUT_FORMAT>
{
  "useCase": "A unique, multi-step workflow description that solves a real problem.",
  "requiredFunctions": ["get admin.teams.list", "post admin.teams.create"]
}
</OUTPUT_FORMAT>

Generate the JSON response now:
`;
}

function getExampleNamePrompt(string useCase) returns string {
    return string `
You are a technical documentation expert specializing in creating clear, descriptive example names.

<CONTEXT>
Task: Generate a concise, professional example name for the following use case
Use Case: ${useCase}
</CONTEXT>

<NAMING_GUIDELINES>
**Requirements**:
- Exactly 3-4 words maximum
- Use kebab-case (lowercase with hyphens)
- Be descriptive and professional
- Focus on the main action or workflow
- Avoid generic terms like "example" or "demo"

**Good Examples**:
- "channel-message-posting"
- "user-profile-creation" 
- "file-upload-workflow"
- "team-member-invitation"
- "project-status-tracking"

**Avoid**:
- Generic names like "basic-example"
- Too many words or complex phrases
- Technical jargon that's not widely understood

**The output must be the raw name itself, not wrapped in any markdown or quotes.**
</NAMING_GUIDELINES>

Generate ONLY the example name following kebab-case format, no additional text or explanations:
`;
}
