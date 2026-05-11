import ballerina/lang.regexp;

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

// Build a targeted Java fix prompt that sends only the error-region context
// and asks for a JSON patch response (not the whole file).
public function createJavaFixPrompt(string code, CompilationError[] errors, string filePath,
        string validationFailure = "", string previousCandidate = "", int attempt = 1) returns string {
    string errorContext = prepareErrorContext(errors);
    string tripleBacktick = "```";

    // Build the error-region snippet with line numbers for context
    string regionSnippet = buildErrorRegionSnippet(code, errors, 30);

    // Build the import section (first 100 lines typically)
    string importSection = buildImportSection(code);

    string retryContext = "";
    if attempt > 1 {
        string retryOpen = "<" + "RETRY_CONTEXT" + ">";
        string retryClose = "</" + "RETRY_CONTEXT" + ">";
        retryContext = string `
${retryOpen}
Attempt: ${attempt}/3
Previous attempt failed validation: ${validationFailure}
Produce SMALLER, more targeted edits this time.
${retryClose}`;
    }

    return string `
You are an expert Java compiler specialist. Fix ONLY the reported compilation errors in a generated Ballerina native adaptor.

<FILE_INFO>
File: ${filePath}
Total lines: ${countLines(code)}
</FILE_INFO>

<COMPILATION_ERRORS>
${errorContext}
</COMPILATION_ERRORS>

<IMPORT_SECTION>
${importSection}
</IMPORT_SECTION>

<ERROR_REGION_WITH_LINE_NUMBERS>
${regionSnippet}
</ERROR_REGION_WITH_LINE_NUMBERS>

${retryContext}

<INSTRUCTIONS>
Return a JSON array of edit operations. Each operation replaces lines in the original file.

RULES:
1. Fix ONLY the reported compilation errors - do not change anything else.
2. Each edit specifies a startLine (1-based inclusive), endLine (1-based inclusive), and replacement lines.
3. Replacement lines must maintain correct Java syntax, indentation, and balanced braces.
4. For adding new catch clauses, new imports, or new lines: the replacement can have MORE lines than the original range.
5. For fixing a single line: startLine == endLine and replacement contains the corrected line.
6. Keep edits minimal - change the fewest lines possible.
7. Do NOT delete methods, fields, or functional code.
8. If an import is needed, add an edit with startLine and endLine pointing to the last existing import line, 
   and include that original import line PLUS the new import in the replacement.

FORMAT (return ONLY this JSON, no other text):
[
  {
    "startLine": <number>,
    "endLine": <number>,
    "replacement": [
      "<line1>",
      "<line2>"
    ]
  }
]

COMMON FIX PATTERNS:
- "unreported exception ... must be caught or declared to be thrown": Add a catch clause for the exception type, or add the exception to the throws declaration.
- "cannot find symbol": Add the missing import or use fully-qualified class name.
- "incompatible types": Cast or convert to the expected type.
- "method does not override": Fix method signature to match parent.
- "no suitable method found for X(Collection<WrongType>)": Use a correctly-typed collection variable already in scope, or convert elements to the expected type before passing.
</INSTRUCTIONS>

<OUTPUT_REQUIREMENTS>
Return ONLY valid JSON. No markdown, no explanations, no ${tripleBacktick} tags.
</OUTPUT_REQUIREMENTS>
`;
}

// Extract the import section (package + imports) from Java source
function buildImportSection(string code) returns string {
    string[] lines = regexp:split(re `\n`, code);
    string[] importLines = [];
    foreach string line in lines {
        string trimmed = line.trim();
        if trimmed.startsWith("package ") || trimmed.startsWith("import ") || trimmed.length() == 0 {
            importLines.push(line);
        } else if importLines.length() > 0 && !trimmed.startsWith("import ") && !trimmed.startsWith("package ") && trimmed.length() > 0 {
            // Stop after imports end
            break;
        }
    }
    return string:'join("\n", ...importLines);
}

// Build a snippet showing lines around each error with line numbers
function buildErrorRegionSnippet(string code, CompilationError[] errors, int contextRadius) returns string {
    string[] lines = regexp:split(re `\n`, code);
    int totalLines = lines.length();

    // Collect all line ranges we need to show
    int[][] ranges = [];
    foreach CompilationError err in errors {
        int startLine = err.line - contextRadius;
        if startLine < 1 {
            startLine = 1;
        }
        int endLine = err.line + contextRadius;
        if endLine > totalLines {
            endLine = totalLines;
        }
        ranges.push([startLine, endLine]);
    }

    // Merge overlapping ranges
    int[][] mergedRanges = mergeLineRanges(ranges);

    // Build snippet with line numbers
    string[] snippetParts = [];
    foreach int[] range in mergedRanges {
        int rangeStart = range[0];
        int rangeEnd = range[1];
        if snippetParts.length() > 0 {
            snippetParts.push("... (lines omitted) ...");
        }
        foreach int lineNum in rangeStart ... rangeEnd {
            int index = lineNum - 1;
            if index >= 0 && index < totalLines {
                string marker = isErrorLine(lineNum, errors) ? ">>>" : "   ";
                snippetParts.push(string `${marker} ${lineNum}: ${lines[index]}`);
            }
        }
    }

    return string:'join("\n", ...snippetParts);
}

function isErrorLine(int lineNum, CompilationError[] errors) returns boolean {
    foreach CompilationError err in errors {
        if err.line == lineNum {
            return true;
        }
    }
    return false;
}

function mergeLineRanges(int[][] ranges) returns int[][] {
    if ranges.length() == 0 {
        return [];
    }

    // Simple sort by start line
    int[][] sorted = ranges.clone();
    int i = 0;
    while i < sorted.length() - 1 {
        int j = i + 1;
        while j < sorted.length() {
            if sorted[j][0] < sorted[i][0] {
                int[] temp = sorted[i];
                sorted[i] = sorted[j];
                sorted[j] = temp;
            }
            j += 1;
        }
        i += 1;
    }

    int[][] merged = [sorted[0]];
    foreach int k in 1 ..< sorted.length() {
        int[] last = merged[merged.length() - 1];
        int[] current = sorted[k];
        if current[0] <= last[1] + 1 {
            // Overlapping or adjacent
            if current[1] > last[1] {
                last[1] = current[1];
            }
        } else {
            merged.push(current);
        }
    }

    return merged;
}

function countLines(string code) returns int {
    string[] lines = regexp:split(re `\n`, code);
    return lines.length();
}
