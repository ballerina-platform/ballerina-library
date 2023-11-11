// Copyright (c) 2022, WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/http;
import ballerina/os;
import ballerinax/github;

int issueCount = 0;

http:Client git = check new (GITHUB_RAW_LINK, config = {
    auth: {
        token: os:getEnv(BALLERINA_BOT_TOKEN)
    },
    retryConfig: {
        count: HTTP_REQUEST_RETRIES,
        interval: HTTP_REQUEST_DELAY_IN_SECONDS,
        backOffFactor: HTTP_REQUEST_DELAY_MULTIPLIER
    }
});

github:ConnectionConfig config = {
    auth: {
        token: os:getEnv(BALLERINA_BOT_TOKEN)
    },
    retryConfig: {
        count: HTTP_REQUEST_RETRIES,
        interval: HTTP_REQUEST_DELAY_IN_SECONDS,
        backOffFactor: HTTP_REQUEST_DELAY_MULTIPLIER
    }
};

github:Client githubClient = check new (config);

function getDefaultBranch(string moduleName) returns string|error {
    stream<github:Branch, github:Error?> branches = check githubClient->getBranches(BALLERINA_ORG_NAME, moduleName);
    stream<github:Branch, github:Error?> filter = branches.filter(filterBranch);

    record {|github:Branch value;|}? defaultBranch = check filter.next();
    return defaultBranch == () ? "" : defaultBranch.value.name;
}

function filterBranch(github:Branch branch) returns boolean {
    return branch.name == "master" || branch.name == "main";
}

function getIssuesCount(string repoName, string shortName) returns int|error? {
    stream<github:Issue, github:Error?> issues =
        check githubClient->getIssues(BALLERINA_ORG_NAME, repoName,
        issueFilters = {labels: ["Type/Bug", string `module/${shortName}`], states: [github:ISSUE_OPEN]});
    issueCount = 0;
    _ = check issues.forEach(count);
    return issueCount;
}

function count(github:Issue issue) {
    issueCount += 1;
}

function openUrl(string page, string url) returns http:Response|error {
    http:Client httpClient = check new (page, config = {
        auth: {
            token: os:getEnv(BALLERINA_BOT_TOKEN)
        },
        retryConfig: {
            count: HTTP_REQUEST_RETRIES,
            interval: HTTP_REQUEST_DELAY_IN_SECONDS,
            backOffFactor: HTTP_REQUEST_DELAY_MULTIPLIER
        }
    });

    http:Response response = check httpClient->get(url);
    return response;
}
