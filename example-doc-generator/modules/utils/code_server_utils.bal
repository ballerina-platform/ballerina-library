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

import ballerina/os;
import ballerina/lang.runtime;

# Checks whether the code-server binary is available on PATH.
# Runs `code-server --version`; a zero exit code means it is installed.
# + return - true if code-server is installed, false otherwise
public function checkCodeServerInstalled() returns boolean {
    os:Process|error proc = os:exec({
        value: "code-server",
        arguments: ["--version"]
    });
    if proc is error {
        return false;
    }
    int|error exitCode = proc.waitForExit();
    return exitCode is int && exitCode == 0;
}

# Installs code-server using the official installer script:
#   curl -fsSL https://code-server.dev/install.sh | sh
# The pipe is a shell construct, so this is run via `sh -c`.
# + return - an error if the installer script fails
public function installCodeServer() returns error? {
    os:Process|error proc = os:exec({
        value: "sh",
        arguments: ["-c", "curl -fsSL https://code-server.dev/install.sh | sh"]
    });
    if proc is error {
        return error("Failed to launch code-server installer: " + proc.message());
    }
    int|error exitCode = proc.waitForExit();
    if exitCode is error {
        return error("code-server installer script failed: " + exitCode.message());
    }
    if exitCode != 0 {
        return error("code-server installer script failed with exit code: " + exitCode.toString());
    }
}

# Checks whether the Claude Code CLI ('claude') is available on PATH.
# Runs `claude --version`; a zero exit code means it is installed.
# + return - true if Claude Code CLI is installed, false otherwise
public function checkClaudeCodeInstalled() returns boolean {
    os:Process|error proc = os:exec({
        value: "claude",
        arguments: ["--version"]
    });
    if proc is error {
        return false;
    }
    int|error exitCode = proc.waitForExit();
    return exitCode is int && exitCode == 0;
}

# Checks whether code-server is reachable on the given port using curl.
# + port - the port to check
# + return - true if code-server is running, false otherwise
public function checkCodeServerRunning(int port) returns boolean {
    os:Process|error proc = os:exec({
        value: "curl",
        arguments: ["-s", "-L", "-o", "/dev/null", "-w", "%{http_code}",
                    "--max-time", "3", "http://localhost:" + port.toString()]
    });
    if proc is error {
        return false;
    }
    int|error exitCode = proc.waitForExit();
    return exitCode is int && exitCode == 0;
}

# Checks whether a VS Code extension is installed in code-server.
# Runs `code-server --list-extensions` directly (no shell) and searches stdout
# for an exact line match of extensionId.
# extensionId is validated against a strict allowlist before use.
# + extensionId - the extension identifier to look for (e.g. "wso2.wso2-integrator")
# + return - true if the extension is installed, false otherwise
public function checkExtensionInstalled(string extensionId) returns boolean {
    string safeExtensionId = extensionId.trim();
    if !isValidExtensionId(safeExtensionId) {
        return false;
    }
    os:Process|error proc = os:exec({
        value: "code-server",
        arguments: ["--list-extensions"]
    });
    if proc is error {
        return false;
    }
    byte[]|error outBytes = proc.output();
    int|error exitCode = proc.waitForExit();
    if outBytes is error || exitCode is error {
        return false;
    }
    string|error outStr = string:fromBytes(outBytes);
    if outStr is error {
        return false;
    }
    string[] lines = re`\n`.split(outStr);
    foreach string line in lines {
        if line.trim() == safeExtensionId {
            return true;
        }
    }
    return false;
}

# Ensures a VS Code extension is installed in code-server.
# Installs the extension from the Open VSX marketplace.
# + extensionId - the extension identifier (e.g. "wso2.wso2-integrator")
# + return - an error if the install attempt fails
public function ensureExtensionInstalled(string extensionId) returns error? {
    string safeExtensionId = extensionId.trim();
    if !isValidExtensionId(safeExtensionId) {
        return error("Invalid extension id. Expected marketplace id format such as publisher.extension.");
    }
    log("\t[INFO] Trying marketplace install for: " + safeExtensionId);
    os:Process|error marketProc = os:exec({
        value: "code-server",
        arguments: ["--install-extension", safeExtensionId]
    });
    if marketProc is error {
        return error("Failed to launch extension install: " + marketProc.message());
    }
    int|error marketExit = marketProc.waitForExit();
    if marketExit is error {
        return error("Extension install process error: " + marketExit.message());
    }
    if marketExit != 0 {
        return error("Extension install failed with exit code: " + marketExit.toString());
    }
}

function isValidExtensionId(string extensionId) returns boolean {
    string trimmedId = extensionId.trim();
    if trimmedId == "" || trimmedId.startsWith("-") {
        return false;
    }
    return re`[A-Za-z0-9][A-Za-z0-9_-]*([.][A-Za-z0-9][A-Za-z0-9_-]*)+`.isFullMatch(trimmedId);
}

# Starts code-server on the given port and waits until it is ready.
# + port - the port to bind code-server to
# + return - an error if code-server fails to start within the timeout
public function startCodeServer(int port) returns error? {
    os:Process|error proc = os:exec({
        value: "code-server",
        arguments: ["--auth", "none", "--bind-addr", "127.0.0.1:" + port.toString()]
    });
    if proc is error {
        return error("Failed to start code-server: " + proc.message());
    }
    // Wait up to 15 seconds for code-server to become ready
    int attempts = 0;
    while attempts < 15 {
        runtime:sleep(1);
        if checkCodeServerRunning(port) {
            return;
        }
        attempts += 1;
    }
    return error("Code-server did not become ready within 15 seconds on port " + port.toString());
}
