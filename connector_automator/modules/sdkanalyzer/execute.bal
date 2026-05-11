// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/io;
import ballerina/regex;
import ballerina/time;

# Execute SDK Analyzer from command-line arguments.
#
# + args - Command-line arguments [sdk-jar, javadoc-jar, output-dir, options...]
# + return - Error if execution fails
public function executeSdkAnalyzer(string... args) returns error? {
    string[] actualArgs = args;
    if args.length() > 0 && args[0] == "analyze" {
        actualArgs = args.slice(1);
    }

    if actualArgs.length() < 3 {
        printUsage();
        return;
    }

    string sdkRef = actualArgs[0];
    string javadocJar = actualArgs[1];
    string outputDir = actualArgs[2];

    // Validate outputDir to avoid accidental key=value or flag usage
    if outputDir.includes("=") || outputDir.startsWith("-") {
        io:println("Invalid output-dir argument. It looks like you passed a flag or key=value pair instead of a directory path.");
        printUsage();
        return;
    }

    AnalyzerConfig config = parseCommandLineArgs(actualArgs.slice(3));

    // Set the javadoc path from the required argument
    config.javadocPath = javadocJar;

    return analyzeSDK(sdkRef, outputDir, config);
}

# Analyze Java SDK and generate the analyzer outputs.
#
# + sdkRef - Path to the JAR file or Maven coordinate (mvn:group:artifact:version)
# + outputDir - Output directory for generated files
# + config - Analyzer configuration
# + return - Error if analysis fails
function analyzeSDK(string sdkRef, string outputDir, AnalyzerConfig config) returns error? {
    if !config.quietMode {
        io:println(string `Analyzing SDK: ${sdkRef}`);
    }

    time:Utc startTime = time:utcNow();

    AnalysisResult|AnalyzerError result = analyzeJavaSDK(sdkRef, outputDir, config);

    time:Utc endTime = time:utcNow();
    time:Seconds seconds = time:utcDiffSeconds(endTime, startTime);
    decimal duration = <decimal>seconds;

    if result is AnalysisResult {
        if !config.quietMode {
            io:println(string `Analysis completed in ${duration} seconds`);
            io:println(string `Metadata file: ${result.metadataPath}`);
        }
        return;
    }

    io:println(string `Analysis failed: ${result.message()}`);
    return result;
}

# Parse command-line arguments into configuration.
#
# + args - Command-line arguments
# + return - Parsed configuration
function parseCommandLineArgs(string[] args) returns AnalyzerConfig {
    AnalyzerConfig config = {};

    int i = 0;
    while i < args.length() {
        string arg = args[i];
        match arg {
            "yes"|"--yes"|"-y" => {
                config.autoYes = true;
            }
            "quiet"|"--quiet"|"-q" => {
                config.quietMode = true;
            }
            "include-deprecated"|"--include-deprecated" => {
                config.includeDeprecated = true;
            }
            "include-internal"|"--include-internal" => {
                config.filterInternal = false;
            }
            "include-non-public"|"--include-non-public" => {
                config.includeNonPublic = true;
            }
            "--sources" => {
                if i + 1 < args.length() {
                    config.sourcesPath = args[i + 1];
                    i = i + 1;
                }
            }
            "--javadoc" => {
                if i + 1 < args.length() {
                    config.javadocPath = args[i + 1];
                    i = i + 1;
                }
            }
            _ => {
                if arg.includes("=") {
                    string[] parts = regex:split(arg, "=");
                    if parts.length() == 2 {
                        string key = parts[0].trim();
                        string value = parts[1].trim();

                        match key {
                            "exclude-packages"|"--exclude-packages" => {
                                if value.length() > 0 {
                                    config.excludePackages = regex:split(value, ",")
                                        .map(pkg => pkg.trim())
                                        .filter(pkg => pkg.length() > 0);
                                }
                            }
                            "include-packages"|"--include-packages" => {
                                if value.length() > 0 {
                                    config.includePackages = regex:split(value, ",")
                                        .map(pkg => pkg.trim())
                                        .filter(pkg => pkg.length() > 0);
                                }
                            }
                            "max-depth"|"--max-depth" => {
                                int|error depth = int:fromString(value);
                                if depth is int {
                                    config.maxDependencyDepth = depth;
                                }
                            }
                            "methods-to-list"|"--methods-to-list" => {
                                int|error m = int:fromString(value);
                                if m is int {
                                    config.methodsToList = m;
                                }
                            }
                            "sources"|"--sources" => {
                                if value.length() > 0 {
                                    config.sourcesPath = value;
                                }
                            }
                            "javadoc"|"--javadoc" => {
                                if value.length() > 0 {
                                    config.javadocPath = value;
                                }
                            }
                            _ => {
                            }
                        }
                    }
                }
            }
        }
        i = i + 1;
    }

    return config;
}

# Print usage information.
function printUsage() {
    io:println();
    io:println("SDK Analyzer - Extract metadata/IR from Java SDK JAR files");
    io:println();
    io:println("USAGE:");
    io:println("  bal run -- analyze <sdk-jar> <javadoc-jar> <output-dir> [options]");
    io:println();
    io:println("ARGUMENTS:");
    io:println("  sdk-jar               Path to the Java SDK JAR file");
    io:println("  javadoc-jar           Path to the corresponding javadoc JAR file");
    io:println("  output-dir            Directory to save generated files");
    io:println();
    io:println("OPTIONS:");
    io:println("  yes                   Auto-confirm all prompts");
    io:println("  quiet                 Minimal logging output");
    io:println("  include-deprecated    Include deprecated methods/classes");
    io:println("  exclude-packages=     Comma-separated packages to exclude");
    io:println("  methods-to-list=N     Number of top-ranked methods to include (default: 5)");
    io:println();
    io:println("EXAMPLES:");
    io:println("  bal run -- analyze ./s3-2.25.16.jar ./s3-2.25.16-javadoc.jar ./output");
    io:println("  bal run -- analyze ./sdk.jar ./sdk-javadoc.jar ./output yes quiet");
    io:println();
    io:println("OUTPUT:");
    io:println("  - <client>-metadata.json   Complete SDK metadata for downstream generation");
    io:println("  - analysis-report.txt      Analysis summary report");
    io:println();
}
