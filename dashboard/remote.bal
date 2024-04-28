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
import ballerina/lang.regexp;
import ballerina/os;
import ballerina/url;
import ballerinax/github;
import ballerina/io;

int issueCount = 0;

const string GITHUB_ORG = "ballerina-platform";
const string BALLERINA_LIBRARY_REPO = "ballerina-library";

configurable string token = os:getEnv(BALLERINA_BOT_TOKEN);

http:Client git = check new (GITHUB_RAW_LINK, config = {
    auth: {
        token
    },
    retryConfig: {
        count: HTTP_REQUEST_RETRIES,
        interval: HTTP_REQUEST_DELAY_IN_SECONDS,
        backOffFactor: HTTP_REQUEST_DELAY_MULTIPLIER
    }
});

final github:Client github = check new ({
    retryConfig: {
        count: HTTP_REQUEST_RETRIES,
        interval: HTTP_REQUEST_DELAY_IN_SECONDS,
        backOffFactor: HTTP_REQUEST_DELAY_MULTIPLIER
    },
    auth: {token}
});

function getDefaultBranch(string moduleName) returns string|error {
    github:FullRepository repository = check github->/repos/[GITHUB_ORG]/[moduleName];
    return repository.default_branch;

}

isolated function getRepoBadges(Module module) returns RepoBadges|error {
    string moduleName = module.name;
    string defaultBranch = module.default_branch;
    github:WorkflowResponse workflowResponse = check github->/repos/[GITHUB_ORG]/[module.name]/actions/workflows;
    WorkflowBadge codeCov = module.display_code_cov_badge ? {
            name: "CodeCov",
            badgeUrl: string `${CODECOV_BADGE_URL}/${BALLERINA_ORG_NAME}/${moduleName}/branch/${defaultBranch}/graph/badge.svg`,
            htmlUrl: string `${CODECOV_BADGE_URL}/${BALLERINA_ORG_NAME}/${moduleName}`
        } : {
            name: "CodeCov",
            badgeUrl: NABADGE,
            htmlUrl: ""
        };
    WorkflowBadge release = check getLatestRelease(moduleName);
    WorkflowBadge pullRequests = check getPullRequestsBadge(module);
    RepoBadges repoBadges = {
        release,
        codeCov,
        pullRequests,
        bugs: check getBugsBadge(moduleName)
    };

    foreach github:Workflow workflow in workflowResponse.workflows {
        string workflowFileName = getWorkflowFileName(workflow.path);
        if workflowFileName == WORKFLOW_MASTER_BUILD || workflowFileName == WORKFLOW_MASTER_CI_BUILD {
            repoBadges.buildStatus = {
                name: "Build",
                badgeUrl: getBadgeUrl(moduleName, workflowFileName, defaultBranch),
                htmlUrl: getWorkflowUrl(moduleName, workflowFileName)
            };
        }
        if workflowFileName == WORKFLOW_TRIVY {
            repoBadges.trivy = {
                name: "Trivy",
                badgeUrl: getBadgeUrl(moduleName, workflowFileName, defaultBranch),
                htmlUrl: getWorkflowUrl(moduleName, workflowFileName)
            };
        }
        if workflowFileName == WORKFLOW_PROCESS_LOAD_TESTS {
            repoBadges.loadTests = {
                name: "Load Tests",
                badgeUrl: getBadgeUrl(moduleName, workflowFileName, defaultBranch),
                htmlUrl: getWorkflowUrl(moduleName, workflowFileName)
            };
        }
        if workflowFileName == WORKFLOW_BAL_TEST_GRAALVM {
            repoBadges.graalvmCheck = {
                name: "GraalVM Check",
                badgeUrl: getBadgeUrl(moduleName, workflowFileName, defaultBranch),
                htmlUrl: getWorkflowUrl(moduleName, workflowFileName)
            };
        }
    }
    return repoBadges;
}

isolated function getBugsBadge(string moduleName) returns WorkflowBadge|error {
    string shortName = getModuleShortName(moduleName);
    github:Issue[] issues = check github->/repos/[GITHUB_ORG]/[BALLERINA_LIBRARY_REPO]/issues(labels = string `Type/Bug,module/${shortName}`, state = "open");
    int bugCount = issues.length();
    io:println(string `${moduleName} bug count: ${bugCount}`);
    string labelColour = bugCount == 0 ? BADGE_COLOR_GREEN : BADGE_COLOR_YELLOW;
    string issueFilter = check url:encode(string `is:open label:module/${shortName} label:Type/Bug`, ENCODING);
    string query = string `${issueFilter}&color=${labelColour}&label=`;

    string badgeUrl = string `${GITHUB_BADGE_URL}/issues-search/${BALLERINA_ORG_NAME}/${BALLERINA_STANDARD_LIBRARY}?query=${query}`;
    string htmlUrl = string `${BALLERINA_ORG_URL}/${BALLERINA_STANDARD_LIBRARY}/issues?q=${issueFilter}`;
    return {
        name: "Bugs",
        badgeUrl,
        htmlUrl
    };
}

isolated function getLatestRelease(string moduleName) returns WorkflowBadge|error {
    github:Release|error release = github->/repos/[GITHUB_ORG]/[moduleName]/releases/latest;
    if release is error {
        return {
            name: "N/A",
            badgeUrl: NABADGE,
            htmlUrl: ""
        };
    }
    string badgeUrl = string `${GITHUB_BADGE_URL}/v/release/${GITHUB_ORG}/${moduleName}?color=${BADGE_COLOR_GREEN}&label=`;
    return {
        name: "Latest Release",
        badgeUrl,
        htmlUrl: release.url
    };
}

isolated function getPullRequestsBadge(Module module) returns WorkflowBadge|error {
    string badgeUrl = string `${GITHUB_BADGE_URL}/issues-pr-raw/${BALLERINA_ORG_NAME}/${module.name}.svg?label=`;
    string htmlUrl = string `${BALLERINA_ORG_URL}/${module.name}/pulls`;
    return {
        name: "Pull Requests",
        badgeUrl,
        htmlUrl
    };
}

isolated function getWorkflowFileName(string workflowPath) returns string {
    string[] pathParts = regexp:split(re `/`, workflowPath);
    return pathParts[pathParts.length() - 1];
}

isolated function getBadgeUrl(string moduleName, string workflow, string defaultBranch) returns string {
    return string `${GITHUB_BADGE_URL}/actions/workflow/status/${BALLERINA_ORG_NAME}/${moduleName}/${workflow}?branch=${defaultBranch}&label=`;
}

isolated function getWorkflowUrl(string moduleName, string workflow) returns string {
    return string `${BALLERINA_ORG_URL}/${moduleName}/actions/workflows/${workflow}`;
}
