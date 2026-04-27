public function createFixPrompt(string code, CompilationError[] errors, string filePath) returns string {
    string errorContext = prepareErrorContext(errors);
    string backTick = "`";
    string tripleBacktick = "```";

    return string `
You are an expert Ballerina language and compiler specialist with deep knowledge of API connector patterns, testing frameworks, and code generation best practices.

<CONTEXT>
This code was automatically generated for API connector testing/examples and contains compilation errors that need to be fixed while preserving the original intent and functionality.

File: ${filePath}
</CONTEXT>

<COMPILATION_ERRORS>
${errorContext}
</COMPILATION_ERRORS>

<CURRENT_CODE>
${code}
</CURRENT_CODE>

<REFLECTION_PHASE>
Before providing the fix, analyze systematically:

1. **Error Root Cause Analysis**:
   - What is causing each compilation error?
   - Are there import issues, type mismatches, or syntax problems?
   - Which errors are interdependent and should be fixed together?

2. **Code Intent Recognition**:
   - What functionality is this code implementing?
   - What API operations or patterns are being used?
   - Is this following proper Ballerina connector/test patterns?

3. **Fix Strategy Planning**:
   - What minimal changes resolve each error?
   - How can I preserve original functionality while improving code quality?
   - Which Ballerina best practices should be applied?
</REFLECTION_PHASE>

<BALLERINA_CODING_RULES>
### Library Usage and Imports
- Only use libraries that are actually needed and available
- Each .bal file must include its own import statements for external libraries
- Do NOT import default langlibs (lang.string, lang.boolean, lang.float, lang.decimal, lang.int, lang.map)
- For packages with dots in names, use aliases: ${backTick}import org/package.one as one;${backTick}
- Import submodules correctly: ${backTick}import my_pkg.submodule;${backTick}

### Data Structure Rules
- Use records as canonical representations of data structures
- ALWAYS define records for data structures instead of using maps or json
- Navigate using record fields, not dynamic access
- When you have a Json variable, ALWAYS define a record and convert Json to that record

### Function and Method Invocation
- Use dot notation (.) for normal functions
- Use arrow notation (->) for remote functions or resource functions
- When invoking resource functions: ${backTick}client->/path1/["param"]/path2.get(key="value")${backTick}
- ALWAYS use named arguments: ${backTick}.get(key="value")${backTick}
- Do not invoke methods on json access expressions - use separate statements

### Variable and Type Rules
- ALWAYS use two-word camelCase for all identifiers (variables, parameters, fields)
- Mention types EXPLICITLY in variable declarations and foreach statements
- When accessing record fields, assign to a new variable first
- To narrow union/optional types, declare separate variable for if conditions
- Do not update/assign values of function parameters

### Error Handling and Best Practices
- Use proper error handling with check expressions or error returns
- Follow Ballerina naming conventions consistently
- Use meaningful variable and function names
- Avoid long comments - use // for single line comments
- Do not use dynamic listener registrations
</BALLERINA_CODING_RULES>

<TEST_CODE_SPECIFIC_RULES>
- Ensure test functions have proper @test:Config annotations
- Use appropriate test assertions (test:assertEquals, test:assertTrue, etc.)
- Handle async operations properly in tests
- Use proper test data setup and cleanup
- Include realistic but simple test data
</TEST_CODE_SPECIFIC_RULES>

<EXAMPLE_CODE_SPECIFIC_RULES>
- Make examples clear and self-contained
- Include proper error handling demonstrations
- Show both success and error scenarios
- Keep examples focused on specific functionality
- Use realistic test data with proper record types
</EXAMPLE_CODE_SPECIFIC_RULES>

<OUTPUT_REQUIREMENTS>
Your response must contain ONLY the complete, corrected Ballerina source code that:
- Resolves ALL compilation errors
- Follows ALL Ballerina coding rules above
- Preserves original functionality and intent
- Uses proper record types instead of json/maps
- Has correct import statements
- Uses explicit types and named arguments
- Follows proper error handling patterns

DO NOT include:
- Markdown code blocks or ${tripleBacktick} tags
- Any explanatory text or comments about fixes
- Thinking or analysis sections
- Any content other than raw .bal file content
</OUTPUT_REQUIREMENTS>

Now provide the complete corrected code following all rules above:
`;
}

// Enhanced prompt with type context for better error resolution
public function createFixPromptWithContext(string code, CompilationError[] errors, string filePath, string typeContext) returns string {
    // If no type context, use the original prompt
    if typeContext.length() == 0 {
        return createFixPrompt(code, errors, filePath);
    }

    string errorContext = prepareErrorContext(errors);
    string backTick = "`";
    string tripleBacktick = "```";

    return string `
You are an expert Ballerina language and compiler specialist with deep knowledge of API connector patterns, testing frameworks, and code generation best practices.

<CONTEXT>
This code was automatically generated for API connector testing/examples and contains compilation errors that need to be fixed while preserving the original intent and functionality.

File: ${filePath}
</CONTEXT>

<COMPILATION_ERRORS>
${errorContext}
</COMPILATION_ERRORS>

<${typeContext}>

<CURRENT_CODE>
${code}
</CURRENT_CODE>

<CRITICAL_TYPE_HANDLING_RULES>
The type definitions above are AUTHORITATIVE. When fixing errors related to field access:

1. **For "invalid field access" errors on optional fields:**
   - If a field is defined as ${backTick}fieldName?${backTick} (optional), you MUST use member access: ${backTick}response["fieldName"]${backTick}
   - Cast the result appropriately: ${backTick}string? reportId = <string?>response["reportId"];${backTick}
   - Do NOT use ${backTick}response.fieldName${backTick} or ${backTick}response?.fieldName${backTick} for rest fields

2. **For "not a required field" errors:**
   - The field might be a rest field in an open record
   - Use member access with proper type casting: ${backTick}<TypeName?>response["field"]${backTick}

3. **For "incompatible types" with anydata:**
   - Cast explicitly: ${backTick}<string?>response["field"]${backTick}
   - Or use ensureType: ${backTick}string reportId = check response["reportId"].ensureType();${backTick}

4. **For unknown types:**
   - Check if the type exists in the provided type definitions
   - Use the exact type name as defined
   - If a ${backTick}WithErrors${backTick} variant doesn't exist, use the base type
</CRITICAL_TYPE_HANDLING_RULES>

<REFLECTION_PHASE>
Before providing the fix, analyze systematically:

1. **Error Root Cause Analysis**:
   - What is causing each compilation error?
   - Review the RELEVANT TYPE DEFINITIONS to understand the actual structure
   - Are fields optional (${backTick}?${backTick}), rest fields, or required?
   - Which errors are interdependent and should be fixed together?

2. **Type-Aware Fix Strategy**:
   - For each type-related error, verify against the provided type definitions
   - Use member access ${backTick}["field"]${backTick} for optional/rest fields
   - Use field access ${backTick}.field${backTick} only for required fields
   - Apply proper type casts when dealing with anydata or json
</REFLECTION_PHASE>

<BALLERINA_CODING_RULES>
### Library Usage and Imports
- Only use libraries that are actually needed and available
- Each .bal file must include its own import statements for external libraries
- Do NOT import default langlibs (lang.string, lang.boolean, lang.float, lang.decimal, lang.int, lang.map)
- For packages with dots in names, use aliases: ${backTick}import org/package.one as one;${backTick}

### Field Access Rules (CRITICAL)
- Required fields: Use ${backTick}.fieldName${backTick}
- Optional fields defined with ${backTick}?${backTick}: Use ${backTick}.fieldName${backTick} or ${backTick}?.fieldName${backTick}
- Rest fields (not explicitly defined in record): Use ${backTick}["fieldName"]${backTick} with type cast
- When error says "not a required field", ALWAYS use member access ${backTick}["field"]${backTick}

### Function and Method Invocation
- Use dot notation (.) for normal functions
- Use arrow notation (->) for remote functions or resource functions
- When invoking resource functions: ${backTick}client->/path1/["param"]/path2.get(key="value")${backTick}
- ALWAYS use named arguments: ${backTick}.get(key="value")${backTick}

### Error Handling
- Use proper error handling with check expressions or error returns
- For nullable fields, handle the nil case appropriately
</BALLERINA_CODING_RULES>

<OUTPUT_REQUIREMENTS>
Your response must contain ONLY the complete, corrected Ballerina source code that:
- Resolves ALL compilation errors
- Uses the EXACT field access pattern based on field definition (member access for rest fields)
- Follows ALL Ballerina coding rules above
- Preserves original functionality and intent
- Has correct import statements

DO NOT include:
- Markdown code blocks or ${tripleBacktick} tags
- Any explanatory text or comments about fixes
- Thinking or analysis sections
- Any content other than raw .bal file content
</OUTPUT_REQUIREMENTS>

Now provide the complete corrected code following all rules above:
`;
}

// Enhanced prompt with type context AND fix history to prevent oscillation
public function createFixPromptWithHistory(string code, CompilationError[] errors, string filePath, string typeContext, string fixHistory) returns string {
    // If no history, use the context-aware prompt
    if fixHistory.length() == 0 {
        return createFixPromptWithContext(code, errors, filePath, typeContext);
    }

    string errorContext = prepareErrorContext(errors);
    string backTick = "`";
    string tripleBacktick = "```";

    string typeContextSection = "";
    if typeContext.length() > 0 {
        typeContextSection = string `
<${typeContext}>
`;
    }

    return string `
You are an expert Ballerina language and compiler specialist with deep knowledge of API connector patterns, testing frameworks, and code generation best practices.

<CONTEXT>
This code was automatically generated for API connector testing/examples and contains compilation errors that need to be fixed while preserving the original intent and functionality.

File: ${filePath}
</CONTEXT>

<COMPILATION_ERRORS>
${errorContext}
</COMPILATION_ERRORS>
${typeContextSection}
<CURRENT_CODE>
${code}
</CURRENT_CODE>

<CRITICAL_FIX_HISTORY>
**IMPORTANT**: Previous fix attempts for this file have FAILED. You must NOT repeat the same approaches.

${fixHistory}

**ANALYSIS OF FAILED PATTERNS**:
If you see oscillation between these error patterns, apply the COMBINED fix:

Pattern 1: "not a required field" or "invalid field access"
  - This means you tried: ${backTick}response.fieldName${backTick} or ${backTick}response?.fieldName${backTick}
  - This approach FAILED because the field is a rest field, not an explicit field

Pattern 2: "incompatible types: expected 'SomeType?', found 'anydata'"
  - This means you tried: ${backTick}response["fieldName"]${backTick}
  - This approach FAILED because member access returns anydata

**THE CORRECT COMBINED SOLUTION**:
When BOTH patterns appear in history, you MUST use:
${tripleBacktick}ballerina
// For rest fields that return anydata, ALWAYS combine member access WITH type cast:
string? fieldValue = <string?>response["fieldName"];

// Or use ensureType for non-optional:
string fieldValue = check response["fieldName"].ensureType();
${tripleBacktick}

DO NOT try ${backTick}response.field${backTick} again - it already failed.
DO NOT try ${backTick}response["field"]${backTick} without cast - it already failed.
You MUST use ${backTick}<ExpectedType?>response["field"]${backTick}
</CRITICAL_FIX_HISTORY>

<BALLERINA_FIELD_ACCESS_RULES>
### Field Access - This is CRITICAL

1. **For rest fields (NOT explicitly defined in record)**:
   - WRONG: ${backTick}response.field${backTick} → "not a required field" error
   - WRONG: ${backTick}response["field"]${backTick} → returns anydata, type mismatch
   - CORRECT: ${backTick}<ExpectedType?>response["field"]${backTick}
   - CORRECT: ${backTick}check response["field"].ensureType()${backTick}

2. **For optional fields (defined with ?)**:
   - Use: ${backTick}response?.field${backTick} or ${backTick}response.field${backTick} (if record allows)

3. **For required fields (explicitly defined)**:
   - Use: ${backTick}response.field${backTick}

### Type Casting with Member Access
When accessing a rest field, the return type is ${backTick}anydata${backTick}. You MUST cast:
${tripleBacktick}ballerina
// If expecting string?:
string? status = <string?>response["status"];

// If expecting int?:
int? count = <int?>response["count"];

// If expecting a record type:
MyRecord? data = <MyRecord?>response["data"];
${tripleBacktick}
</BALLERINA_FIELD_ACCESS_RULES>

<OUTPUT_REQUIREMENTS>
Your response must contain ONLY the complete, corrected Ballerina source code that:
- Resolves ALL compilation errors
- DOES NOT repeat any fix that already failed (check the history above)
- Uses the COMBINED approach (member access + type cast) for rest fields
- Preserves original functionality and intent
- Has correct import statements

DO NOT include:
- Markdown code blocks or ${tripleBacktick} tags
- Any explanatory text or comments about fixes
- Any content other than raw .bal file content
</OUTPUT_REQUIREMENTS>

Now provide the complete corrected code. Remember: DO NOT repeat failed approaches from the history.
`;
}


