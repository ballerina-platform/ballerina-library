import ballerina/file;
import ballerina/io;
import ballerina/regex;

function safeSubstring(string str, int startIndex, int endIndex) returns string {
    int actualEnd = endIndex < str.length() ? endIndex : str.length();
    if actualEnd <= startIndex {
        return str;
    }
    return str.substring(startIndex, actualEnd);
}

function parsePrDescription(string prDescription) returns map<string[]>|error {
    map<string[]> changes = {
        "Added": [],
        "Changed": [],
        "Fixed": []
    };

    string[] lines = regex:split(prDescription, "\n");
    string currentSection = "";

    foreach string line in lines {
        string trimmed = line.trim();

        if trimmed == "Breaking Changes" || trimmed == "### Breaking Changes" {
            currentSection = "Changed";
            io:println("Found Breaking Changes section");
        } else if trimmed == "New Features" || trimmed == "### New Features" {
            currentSection = "Added";
            io:println("Found New Features section");
        } else if trimmed == "Improvements" || trimmed == "### Improvements" {
            currentSection = "Fixed";
            io:println("Found Improvements section");
        } else if trimmed.startsWith("- ") {
            string item = trimmed.substring(2).trim();

            if item.length() > 0 && currentSection.length() > 0 {
                string[] existing = changes[currentSection] ?: [];
                existing.push(item);
                changes[currentSection] = existing;

                string preview = safeSubstring(item, 0, 50);
                if item.length() > 50 {
                    preview = preview + "...";
                }
                io:println(string `Added to ${currentSection}: ${preview}`);
            }
        }
    }

    return changes;
}

function generateUnreleasedSection(map<string[]> changes) returns string {
    string[] lines = ["## [Unreleased]", ""];

    string[] added = changes["Added"] ?: [];
    if added.length() > 0 {
        lines.push("### Added");
        foreach string item in added {
            lines.push(string `- ${item}`);
        }
        lines.push("");
    }

    string[] changed = changes["Changed"] ?: [];
    if changed.length() > 0 {
        lines.push("### Changed");
        foreach string item in changed {
            lines.push(string `- ${item}`);
        }
        lines.push("");
    }

    string[] fixed = changes["Fixed"] ?: [];
    if fixed.length() > 0 {
        lines.push("### Fixed");
        foreach string item in fixed {
            lines.push(string `- ${item}`);
        }
        lines.push("");
    }

    return string:'join("\n", ...lines);
}

function findChangelogFile() returns string|error? {
    string[] possibleNames = ["CHANGELOG.md", "changelog.md", "Changelog.md", "ChangeLog.md"];

    foreach string name in possibleNames {
        if check file:test(name, file:EXISTS) {
            return name;
        }
    }

    return ();
}

function updateChangelog(string prDescription) returns error? {
    io:println("Updating CHANGELOG.md...");
    io:println(string `PR Description length: ${prDescription.length()} chars`);
    io:println("First 200 chars of PR description:");

    string preview = safeSubstring(prDescription, 0, 200);
    io:println(preview);

    map<string[]> changes = check parsePrDescription(prDescription);

    int totalChanges = (changes["Added"] ?: []).length() +
                       (changes["Changed"] ?: []).length() +
                       (changes["Fixed"] ?: []).length();

    io:println(string `Total changes found: ${totalChanges}`);
    io:println(string `Added: ${(changes["Added"] ?: []).length()}`);
    io:println(string `Changed: ${(changes["Changed"] ?: []).length()}`);
    io:println(string `Fixed: ${(changes["Fixed"] ?: []).length()}`);

    if totalChanges == 0 {
        io:println("No changelog entries found in PR description");
        return;
    }

    string? existingFile = check findChangelogFile();
    string changelogPath = existingFile is string ? existingFile : "CHANGELOG.md";

    io:println(string `Using changelog file: ${changelogPath}`);

    string newUnreleasedSection = generateUnreleasedSection(changes);

    if existingFile is string {
        io:println("Updating existing CHANGELOG.md");
        string content = check io:fileReadString(changelogPath);
        string[] lines = regex:split(content, "\n");

        int unreleasedIndex = -1;
        foreach int i in 0 ..< lines.length() {
            if lines[i].trim().startsWith("## [Unreleased]") {
                unreleasedIndex = i;
                break;
            }
        }

        if unreleasedIndex >= 0 {
            int nextSectionIndex = lines.length();
            foreach int i in (unreleasedIndex + 1) ..< lines.length() {
                if lines[i].trim().startsWith("## [") {
                    nextSectionIndex = i;
                    break;
                }
            }

            string[] updatedLines = [];

            foreach int i in 0 ..< unreleasedIndex {
                updatedLines.push(lines[i]);
            }

            string[] newSectionLines = regex:split(newUnreleasedSection, "\n");
            foreach string line in newSectionLines {
                updatedLines.push(line);
            }

            foreach int i in nextSectionIndex ..< lines.length() {
                updatedLines.push(lines[i]);
            }

            string updatedContent = string:'join("\n", ...updatedLines);
            check io:fileWriteString(changelogPath, updatedContent);
            io:println("Updated existing CHANGELOG.md");
        } else {
            int insertIndex = 0;

            foreach int i in 0 ..< lines.length() {
                if lines[i].trim().startsWith("#") && !lines[i].trim().startsWith("##") {
                    insertIndex = i + 1;
                    break;
                }
            }

            string[] updatedLines = [];

            foreach int i in 0 ..< insertIndex {
                updatedLines.push(lines[i]);
            }

            if insertIndex < lines.length() && lines[insertIndex].trim().length() > 0 {
                updatedLines.push("");
            }

            string[] newSectionLines = regex:split(newUnreleasedSection, "\n");
            foreach string line in newSectionLines {
                updatedLines.push(line);
            }

            foreach int i in insertIndex ..< lines.length() {
                updatedLines.push(lines[i]);
            }

            string updatedContent = string:'join("\n", ...updatedLines);
            check io:fileWriteString(changelogPath, updatedContent);
            io:println("Added [Unreleased] section to existing CHANGELOG.md");
        }
    } else {
        io:println("Creating new CHANGELOG.md");
        string changelogTemplate = string `# Change Log

This file contains all the notable changes done to the Ballerina connector through the releases.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

${newUnreleasedSection}`;

        check io:fileWriteString(changelogPath, changelogTemplate);
        io:println("Created new CHANGELOG.md");
    }

    io:println(string `Added ${totalChanges} changelog entries`);
}

public function runUpdateChangelog(string prDescription) returns error? {
    check updateChangelog(prDescription);
}
