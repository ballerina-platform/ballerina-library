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

import ballerina/io;

final string ESC = "\u{1B}";

# Wraps the bracketed label at the start of a log line in an ANSI colour sequence.
# Unrecognised labels (or lines with no `]`) are returned unchanged.
#
# Supported labels and their colours:
#   [STEP ...]  bold cyan     — pipeline step headers
#   [INFO]      green         — informational messages
#   [ERROR]     bold red      — error messages
#   [SESSION]   bold cyan
#   [SYSTEM]    blue
#   [CLAUDE]    orange
#   [TOOL]      bold yellow
#   [RESULT]    bold magenta
#   [USAGE]     dim white
#
# + line - the full log line string
# + return - the line with the label coloured, or the original line unchanged
public function colorize(string line) returns string {
    string reset = ESC + "[0m";
    // Find the first '[' so any leading indent (tabs/spaces) is preserved
    int? openBracket = line.indexOf("[");
    if openBracket is () {
        return line;
    }
    string indent = openBracket > 0 ? line.substring(0, openBracket) : "";
    string fromBracket = line.substring(openBracket);
    int? closingBracket = fromBracket.indexOf("]");
    if closingBracket is () {
        return line;
    }
    string label = fromBracket.substring(0, closingBracket + 1);
    string rest = fromBracket.substring(closingBracket + 1);

    string colorCode = "";
    if label.startsWith("[STEP") {
        colorCode = ESC + "[1;36m";  // bold cyan
    } else if label == "[INFO]" {
        colorCode = ESC + "[32m";    // green
    } else if label == "[ERROR]" {
        colorCode = ESC + "[1;31m";  // bold red
    } else if label == "[SESSION]" {
        colorCode = ESC + "[1;36m";  // bold cyan
    } else if label == "[SYSTEM]" {
        colorCode = ESC + "[34m";    // blue
    } else if label == "[CLAUDE]" {
        colorCode = ESC + "[38;5;214m";  // orange
    } else if label == "[TOOL]" {
        colorCode = ESC + "[1;33m";  // bold yellow
    } else if label == "[RESULT]" {
        colorCode = ESC + "[1;35m";  // bold magenta
    } else if label == "[USAGE]" {
        colorCode = ESC + "[2;37m";  // dim white
    }
    if colorCode == "" {
        return line;
    }
    return indent + colorCode + label + reset + rest;
}

# Prints a log line, colouring the bracketed label prefix if recognised.
# + line - the log line to print
public function log(string line) {
    io:println(colorize(line));
}
