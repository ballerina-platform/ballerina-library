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

import ballerina/regex;

# Extract numeric value from LLM response text
#
# + responseText - Response text from LLM
# + return - Extracted number or error
public function extractNumberFromResponse(string responseText) returns int|error {
    // Try to find first number in the response
    string[] parts = regex:split(responseText, "[^0-9]");

    foreach string part in parts {
        if part.length() > 0 {
            int|error num = int:fromString(part.trim());
            if num is int {
                return num;
            }
        }
    }

    return error("No number found in response: " + responseText);
}

# Parse initialization pattern from LLM response
#
# + responseText - Response text from LLM
# + return - Pattern type
public function parseInitPattern(string responseText) returns string {
    string lower = responseText.toLowerAscii();

    if lower.includes("builder") {
        return "builder";
    } else if lower.includes("static-factory") || lower.includes("static factory") {
        return "static-factory";
    } else if lower.includes("instance-factory") || lower.includes("instance factory") {
        return "instance-factory";
    } else if lower.includes("factory") {
        return "static-factory";
    } else if lower.includes("no-constructor") || lower.includes("no constructor") {
        return "no-constructor";
    } else if lower.includes("constructor") {
        return "constructor";
    }

    return "";
}

# Detect builder pattern methods in a class
#
# + methods - Methods to analyze
# + return - List of builder method names
public function detectBuilderMethods(MethodInfo[] methods) returns string[] {
    string[] builderMethods = [];

    foreach MethodInfo method in methods {
        string nameLower = method.name.toLowerAscii();
        if nameLower.startsWith("with") || nameLower.startsWith("set") {
            builderMethods.push(method.name);
        }
    }

    return builderMethods;
}

# Detect factory pattern methods in a class
#
# + methods - Methods to analyze
# + return - List of factory method names
public function detectFactoryMethods(MethodInfo[] methods) returns string[] {
    string[] factoryMethods = [];

    foreach MethodInfo method in methods {
        string nameLower = method.name.toLowerAscii();
        if method.isStatic && (
            nameLower.startsWith("create") ||
            nameLower.startsWith("of") ||
            nameLower.startsWith("from") ||
            nameLower.startsWith("new") ||
            nameLower.startsWith("build")
        ) {
            factoryMethods.push(method.name);
        }
    }

    return factoryMethods;
}

# Generate initialization code snippet for a pattern
#
# + patternName - Pattern type
# + rootClient - The client class
# + return - Initialization code snippet
public function generateInitializationCode(string patternName, ClassInfo rootClient) returns string {
    match patternName {
        "constructor" => {
            return rootClient.simpleName + " client = new " + rootClient.simpleName + "();";
        }
        "builder" => {
            return rootClient.simpleName + " client = " + rootClient.simpleName + ".builder().build();";
        }
        "static-factory" => {
            return rootClient.simpleName + " client = " + rootClient.simpleName + ".create();";
        }
        "instance-factory" => {
            return rootClient.simpleName + " client = factory.create" + rootClient.simpleName + "();";
        }
        _ => {
            return "// " + rootClient.simpleName + " client = ...";
        }
    }
}
