import connector_automator.cost_calculator;

import ballerina/io;
import ballerina/log;

public function executeCodeFixer(string... args) returns error? {
    if args.length() < 1 {
        printCodeFixerUsage();
        return;
    }

    string projectPath = args[0];

    // Check for auto flag for automated mode and quiet mode for log control
    boolean autoYes = false;
    boolean quietMode = false;
    foreach string arg in args {
        if arg == "yes" {
            autoYes = true;
        } else if arg == "quiet" {
            quietMode = true;
        }
    }

    if autoYes {
        if !quietMode {
            io:println("Running in automated mode - all prompts will be auto-confirmed");
        }
    }

    if quietMode {
        if !autoYes {
            io:println("Running in quiet mode - reduced logging output");
        }
        io:println("Quiet mode enabled - minimal logging output");
    }

    if !quietMode {
        log:printInfo("Starting Ballerina code fixer", projectPath = projectPath);
    }
    io:println("=== AI-Powered Ballerina Code Fixer ===");
    io:println(string `Project path: ${projectPath}`);
    io:println("\nOperations to be performed:");
    io:println("1. Analyze Ballerina compilation errors");
    io:println("2. Generate AI-powered fixes for detected issues");
    io:println("3. Apply fixes with user confirmation");
    io:println("4. Iterate until all errors are resolved");

    if !getUserConfirmation("\nProceed with error fixing?", autoYes) {
        io:println("Operation cancelled by user.");
        return;
    }

    io:println("Starting AI-powered Ballerina code fixer...");

    FixResult|BallerinaFixerError result = fixAllErrors(projectPath, quietMode, autoYes);

    if result is FixResult {
        decimal totalCost = cost_calculator:getTotalCost();
        if result.success {
            io:println("\nAll compilation errors fixed successfully!");
            io:println(string `✓ Fixed ${result.errorsFixed} errors`);
            io:println("✓ All Ballerina files compile without errors!");

            if totalCost > 0.0d {
                io:println(string ` Total cost: $${totalCost.toString()}`);

                int totalCalls = cost_calculator:getStageMetrics("code_fixer").calls;
                if totalCalls > 0 {
                    decimal avgCostPerFix = totalCost / <decimal>totalCalls;
                    io:println(string ` Average cost per fix: $${avgCostPerFix.toString()}`);
                }
            }
        } else {
            io:println("\n⚠ Partial success:");
            io:println(string `✓ Fixed ${result.errorsFixed} errors`);
            io:println(string `${result.errorsRemaining} errors remain`);
            io:println("⚠ Some errors may require manual intervention");

            if totalCost > 0.0d {
                io:println(string `Total cost: $${totalCost.toString()}`);

                if result.errorsFixed > 0 {
                    decimal costPerFixedError = totalCost / <decimal>result.errorsFixed;
                    io:println(string ` Cost per fixed error: $${costPerFixedError.toString()}`);
                }
            }
        }

        if result.appliedFixes.length() > 0 {
            io:println("\nApplied fixes:");
            foreach string fix in result.appliedFixes {
                io:println(string `  • ${fix}`);
            }
        }

    } else {
        log:printError("Code fixer failed", 'error = result);
        io:println("Code fixing failed. Please check logs for details.");

        decimal totalCost = cost_calculator:getTotalCost();
        if totalCost > 0.0d {
            io:println(string `Cost incurred before failure: $${totalCost.toString()}`);
        }
        return result;
    }
}

// Helper function to get user confirmation
function getUserConfirmation(string message, boolean autoYes = false) returns boolean {
    if autoYes {
        io:println(string `${message} (y/n): y [auto-confirmed]`);
        return true;
    }

    io:print(string `${message} (y/n): `);
    string|io:Error userInput = io:readln();
    if userInput is io:Error {
        log:printError("Failed to read user input", 'error = userInput);
        return false;
    }
    string trimmedInput = userInput.trim().toLowerAscii();
    return trimmedInput == "y" || trimmedInput == "yes";
}

function printCodeFixerUsage() {
    io:println("Ballerina AI Code Fixer");
    io:println("Usage: bal run -- <project-path> [yes] [quiet]");
    io:println("  <project-path>: Path to the Ballerina project directory");
    io:println("  yes: Automatically answer 'yes' to all prompts (for CI/CD)");
    io:println("  quiet: Reduce logging output (minimal logs for CI/CD)");
    io:println("");
    io:println("Environment Variables:");
    io:println("  ANTHROPIC_API_KEY: Required for AI-powered fixes");
    io:println("");
    io:println("Example:");
    io:println("  bal run -- ./my-ballerina-project");
    io:println("  bal run -- ./my-ballerina-project yes");
    io:println("  bal run -- ./my-ballerina-project yes quiet");
    io:println("");
    io:println("Interactive Features:");
    io:println("  • Step-by-step confirmation for each fix");
    io:println("  • Review AI-generated changes before applying");
    io:println("  • Automatic backup creation before modifications");
    io:println("  • Progress feedback and iteration summaries");
    io:println("  • Use 'yes' argument to skip all prompts for automated execution");
    io:println("  • Use 'quiet' argument to reduce logging output for CI/CD");
}
