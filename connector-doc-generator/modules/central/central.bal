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

import ballerina/http;

const string CENTRAL_BASE_URL = "https://api.central.ballerina.io";

# Fetch the latest published version of a Ballerina package from Ballerina Central.
#
# + pkg - Package in "org/name" format, e.g. "ballerinax/hubspot"
# + return - Latest version string, or an error if not found
public function fetchLatestVersion(string pkg) returns string|error {
    string[] parts = re `/`.split(pkg);
    if parts.length() != 2 {
        return error("Invalid package format '" + pkg + "' — expected 'org/name'");
    }
    string org = parts[0];
    string name = parts[1];

    http:Client centralClient = check new (CENTRAL_BASE_URL, timeout = 15);
    http:Response resp = check centralClient->get("/2.0/registry/packages/" + org + "/" + name,
        {"Accept": "application/json"});

    if resp.statusCode < 200 || resp.statusCode >= 300 {
        return error(string `Ballerina Central returned HTTP ${resp.statusCode} for ${pkg}`);
    }

    json body = check resp.getJsonPayload();
    if body is json[] {
        json[] versions = <json[]>body;
        if versions.length() == 0 {
            return error(string `No versions found for ${pkg} on Ballerina Central`);
        }
        if versions[0] is string {
            return <string>versions[0];
        }
        return error(string `Unexpected version format for ${pkg} on Ballerina Central`);
    }
    return error(string `Unexpected response format from Ballerina Central for ${pkg}`);
}
