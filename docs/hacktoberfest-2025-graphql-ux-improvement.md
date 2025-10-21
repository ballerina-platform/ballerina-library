# GraphQL Schema Generation UX Improvement

## Issue Reference
- **Issue**: [ballerina-platform/ballerina-library#6382](https://github.com/ballerina-platform/ballerina-library/issues/6382)
- **Hacktoberfest 2025 Contribution**
- **Contributor**: [@darkgrecher](https://github.com/darkgrecher)

## Problem Statement
The GraphQL SDL schema generation tool had poor UX where file conflict prompts appeared **after** expensive schema processing, causing users to wait unnecessarily before being able to decline file overwrites.

### Original Behavior (Poor UX)
```bash
$ bal graphql -i service.bal -o .
# [3-5 second delay for project loading, compilation, schema processing]
There is already a file named 'schema_graphql.graphql' in the target location. Do you want to overwrite the file? [y/N] n
# Tool still creates unwanted duplicate files despite user saying "No"
```

## Solution Implemented
Applied **"check preconditions early"** UX principle by moving file conflict detection to the beginning of the process.

### New Behavior (Excellent UX)
```bash
$ bal graphql -i service.bal -o .
There is already a file named 'schema_graphql.graphql' in the target location.
Do you want to overwrite the file [Y/N] ? n
Schema generation cancelled by user.
# Immediate exit - no wasted computation, no unwanted files
```

## Technical Changes

### File Modified
`graphql-tools/graphql-schema-file-generator/src/main/java/io/ballerina/graphql/schema/generator/SdlSchemaGenerator.java`

### Key Improvements
1. **Immediate file conflict check** - Added `checkFileConflictsForDefaultSchema()` method at the start of `generate()`
2. **Clean prompt formatting** - Split cramped single line into readable two-line format
3. **Instant user choice respect** - Exit immediately when user declines
4. **Zero wasted computation** - No project loading/compilation before user consent

### Code Changes
```java
public static void generate(Path filePath, Path outPath, String serviceBasePath, PrintStream outStream) {
    // IMMEDIATE file conflict check - before ANY expensive processing
    if (!checkFileConflictsForDefaultSchema(outPath, outStream)) {
        return; // Exit immediately if user chooses not to overwrite
    }
    
    // Only proceed with expensive operations if user consented
    Project project = ProjectLoader.loadProject(filePath);
    // ... rest of processing
}

private static boolean checkFileConflictsForDefaultSchema(Path outPath, PrintStream outStream) {
    Path defaultSchemaFile = outPath.resolve("schema_graphql.graphql");
    if (Files.exists(defaultSchemaFile)) {
        // Clean two-line formatting
        System.out.println("There is already a file named 'schema_graphql.graphql' in the target location.");
        String userInput = System.console().readLine("Do you want to overwrite the file [Y/N] ? ");
        if (!Objects.equals(userInput.toLowerCase(Locale.ENGLISH), "y")) {
            outStream.println("Schema generation cancelled by user.");
            return false; // Exit immediately - respect user's choice
        }
    }
    return true;
}
```

## Impact
- ⚡ **Instant feedback** - No waiting for expensive processing
- 🎨 **Clean UX** - Readable two-line prompt format
- 🛑 **Immediate exit** - Respects user choice without delay
- 💨 **Zero waste** - No computation on declined operations
- 📱 **Better accessibility** - Clearer prompt formatting

## Testing
- **Platform**: Windows 11, Ballerina 2201.12.7
- **JDK**: Java 21 compatible compilation
- **Scenarios**: Tested both "Yes" and "No" user responses
- **Performance**: Immediate response (vs 3-5 second delay previously)

## Hacktoberfest 2025
This contribution improves developer experience for the Ballerina GraphQL tooling as part of WSO2's Hacktoberfest initiative, focusing on UX enhancements that make CLI tools more responsive and user-friendly.