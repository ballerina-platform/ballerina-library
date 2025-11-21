import ballerina/io;
import ballerina/log;

public function executeCodeFixer(string... args) returns error? {
    if args.length() < 1 {
        printUsage();
        return;
    }

    string projectPath = args[0];

    boolean autoYes = false;
    boolean quietMode = false;
    foreach string arg in args {
        if arg == "yes" {
            autoYes = true;
        } else if arg == "quiet" {
            quietMode = true;
        }
    }

    if autoYes && !quietMode {
        io:println("ℹ  Auto-confirm mode enabled");
    }
    if quietMode {
        io:println("ℹ  Quiet mode enabled");
    }

    printOperationPlan(projectPath, quietMode);

    if !getUserConfirmation("Proceed with error fixing?", autoYes) {
        io:println("✗ Operation cancelled");
        return;
    }

    io:println("");
    io:println("Analyzing and fixing errors...");

    FixResult|BallerinaFixerError result = fixAllErrors(projectPath, quietMode, autoYes);

    if result is FixResult {
        printFixSummary(result, quietMode);
    } else {
        if !quietMode {
            log:printError("Code fixer failed", 'error = result);
        }
        io:println(string `✗ Fixing failed: ${result.message()}`);
        return result;
    }
}

function printOperationPlan(string projectPath, boolean quietMode) {
    if quietMode {
        return;
    }

    string sep = createSeparator("=", 70);
    io:println(sep);
    io:println("Code Error Fixing");
    io:println(sep);
    io:println(string `Project: ${projectPath}`);
    io:println("");
    io:println("Operations:");
    io:println("  1. Analyze compilation errors");
    io:println("  2. Generate AI-powered fixes");
    io:println("  3. Apply fixes with confirmation");
    io:println("  4. Iterate until resolved");
    io:println(sep);
}

function printFixSummary(FixResult result, boolean quietMode) {
    string sep = createSeparator("=", 70);

    io:println("");
    io:println(sep);

    if result.success {
        io:println("✓ All Errors Fixed");
        io:println(sep);
        io:println("");
        io:println(string `Fixed: ${result.errorsFixed} error${result.errorsFixed == 1 ? "" : "s"}`);
        if result.errorsFixed > 0 {
            io:println("✓ Project compiles successfully");
        } else {
            io:println("✓ No errors found (project already compiles)");
        }
    } else {
        io:println("⚠  Partial Success");
        io:println(sep);
        io:println("");
        io:println(string `Fixed     : ${result.errorsFixed} error${result.errorsFixed == 1 ? "" : "s"}`);
        io:println(string `Remaining : ${result.errorsRemaining} error${result.errorsRemaining == 1 ? "" : "s"}`);
        io:println("");
        io:println("⚠  Manual intervention may be required");
    }

    if result.appliedFixes.length() > 0 && !quietMode {
        io:println("");
        io:println("Applied Fixes:");
        foreach string fix in result.appliedFixes {
            io:println(string `  • ${fix}`);
        }
    }

    if result.remainingFixes.length() > 0 && result.errorsRemaining > 0 && !quietMode {
        io:println("");
        io:println("Remaining Issues:");
        foreach string issue in result.remainingFixes {
            io:println(string `  • ${issue}`);
        }
    }

    io:println("");
    io:println("Next Steps:");
    if result.success {
        io:println("  • Run tests: bal test");
        io:println("  • Generate examples: bal run -- generate-examples <path>");
        io:println("  • Generate docs: bal run -- generate-docs generate-all <path>");
    } else {
        io:println("  • Review remaining errors manually");
        io:println("  • Check backup files (*.backup) if needed");
        io:println("  • Run: bal build to see current status");
    }

    io:println(sep);
}

function getUserConfirmation(string message, boolean autoYes = false) returns boolean {
    if autoYes {
        return true;
    }
    io:print(string `${message} (y/n): `);
    string|io:Error userInput = io:readln();
    if userInput is io:Error {
        log:printError("Failed to read input", 'error = userInput);
        return false;
    }
    return userInput.trim().toLowerAscii() is "y"|"yes";
}

function createSeparator(string char, int length) returns string {
    string[] chars = [];
    int i = 0;
    while i < length {
        chars.push(char);
        i += 1;
    }
    return string:'join("", ...chars);
}

function printUsage() {
    io:println("Code Error Fixer");
    io:println("");
    io:println("USAGE");
    io:println("  bal run -- fix-code <project-path> [options]");
    io:println("");
    io:println("OPTIONS");
    io:println("  yes      Auto-confirm all fixes");
    io:println("  quiet    Minimal logging output");
    io:println("");
    io:println("EXAMPLES");
    io:println("  bal run -- fix-code ./ballerina-project");
    io:println("  bal run -- fix-code ./ballerina-project yes");
    io:println("  bal run -- fix-code ./ballerina-project yes quiet");
    io:println("");
    io:println("ENVIRONMENT");
    io:println("  ANTHROPIC_API_KEY    Required for AI-powered fixes");
    io:println("");
    io:println("FEATURES");
    io:println("  • Interactive fix confirmation");
    io:println("  • Automatic backup creation");
    io:println("  • Progress tracking and summaries");
    io:println("  • Iterative error resolution");
    io:println("  • CI/CD friendly with auto-confirm mode");
    io:println("");
}
