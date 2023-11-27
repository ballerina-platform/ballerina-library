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
import ballerina/url;

isolated function getLibraryDashboardRow(Module module, string level) returns string|error {
    string dashboardLine = check getDashboardRow(module);
    return string `|${level}${dashboardLine}`;
}

isolated function getToolsDashboardRow(Module module) returns string|error {
    string moduleName = module.name;
    string defaultBranch = module.default_branch ?: "";

    string repoLink = getRepoLink(moduleName);
    string releaseBadge = getReleaseBadge(moduleName);
    string buildStatusBadge = check getBuildStatusBadge(moduleName, defaultBranch);
    string trivyBadge = check getTrivyBadge(moduleName, defaultBranch);
    string codecovBadge = getCodecovBadge(moduleName, defaultBranch);
    string bugsBadge = check getBugsBadge(moduleName);
    string pullRequestsBadge = getPullRequestsBadge(moduleName);

    return string `|${repoLink}|${releaseBadge}|${buildStatusBadge}|${trivyBadge}|${codecovBadge}|${bugsBadge}|${pullRequestsBadge}|`;
}

isolated function getDashboardRow(Module module) returns string|error {
    string moduleName = module.name;
    string defaultBranch = module.default_branch ?: "";
    string repoLink = getRepoLink(moduleName);
    string releaseBadge = getReleaseBadge(moduleName);
    string buildStatusBadge = check getBuildStatusBadge(moduleName, defaultBranch);
    string trivyBadge = check getTrivyBadge(moduleName, defaultBranch);
    string codecovBadge = getCodecovBadge(moduleName, defaultBranch);
    string bugsBadge = check getBugsBadge(moduleName);
    string pullRequestsBadge = getPullRequestsBadge(moduleName);
    string loadTestsBadge;

    // websub/websubhub load tests are in websubhub module, hence `websub` load-test badge should be same as `websubhub` load-test badge
    if moduleName == "module-ballerina-websub" {
        loadTestsBadge = check getLoadTestsBadge("module-ballerina-websubhub", "main");
    } else {
        loadTestsBadge = check getLoadTestsBadge(moduleName, defaultBranch);
    }

    string balTestNativeBadge = check getBalTestNativeBadge(moduleName, defaultBranch);
    return string `|${repoLink}|${releaseBadge}|${buildStatusBadge}|${trivyBadge}|${codecovBadge}|${bugsBadge}|${pullRequestsBadge}|${loadTestsBadge}|${balTestNativeBadge}|`;
}

isolated function getRepoLink(string moduleName) returns string {
    string shortName = getModuleShortName(moduleName);
    return string `[${shortName}](${BALLERINA_ORG_URL}/${moduleName})`;
}

isolated function getReleaseBadge(string moduleName) returns string {
    string badgeUrl = string `${GITHUB_BADGE_URL}/v/release/${BALLERINA_ORG_NAME}/${moduleName}?sort=semver&color=${BADGE_COLOR_GREEN}&label=`;
    string repoUrl = string `${BALLERINA_ORG_URL}/${moduleName}/releases`;
    return string `[![GitHub Release](${badgeUrl})](${repoUrl})`;
}

isolated function getBuildStatusBadge(string moduleName, string defaultBranch) returns string|error {
    string workflowName = WORKFLOW_MASTER_BUILD;
    string workflowFileUrl = string `/${BALLERINA_ORG_NAME}/${moduleName}/master/.github/workflows/${workflowName}`;
    http:Response openUrlResponse = check openUrl(GITHUB_RAW_LINK, workflowFileUrl);
    if openUrlResponse.statusCode == http:STATUS_NOT_FOUND {
        workflowName = WORKFLOW_MASTER_CI_BUILD;
    }
    string repoUrl = string `${BALLERINA_ORG_URL}/${moduleName}/actions/workflows/${workflowName}`;
    string badgeUrl = getGithubBadgeUrl(moduleName, workflowName, defaultBranch, "");
    return string `[![Build](${badgeUrl})](${repoUrl})`;
}

isolated function getTrivyBadge(string moduleName, string defaultBranch) returns string|error {
    string workflowFileUrl = string `/${BALLERINA_ORG_NAME}/${moduleName}/master/.github/workflows/${WORKFLOW_TRIVY}`;
    http:Response openUrlResponse = check openUrl(GITHUB_RAW_LINK, workflowFileUrl);
    string badgeUrl = getGithubBadgeUrl(moduleName, WORKFLOW_TRIVY, defaultBranch, "");
    string repoUrl = string `${BALLERINA_ORG_URL}/${moduleName}/actions/workflows/${WORKFLOW_TRIVY}`;
    if openUrlResponse.statusCode == http:STATUS_NOT_FOUND {
        badgeUrl = NABADGE;
    }
    return string `[![Trivy](${badgeUrl})](${repoUrl})`;
}

isolated function getCodecovBadge(string moduleName, string defaultBranch) returns string {
    string badgeUrl = string `${CODECOV_BADGE_URL}/${BALLERINA_ORG_NAME}/${moduleName}/branch/${defaultBranch}/graph/badge.svg`;
    string repoUrl = string `${CODECOV_BADGE_URL}/${BALLERINA_ORG_NAME}/${moduleName}`;
    return string `[![CodeCov](${badgeUrl})](${repoUrl})`;
}

isolated function getBugsBadge(string moduleName) returns string|error {
    string query = check getBugQuery(moduleName);
    string shortName = getModuleShortName(moduleName);
    string issueFilter = string `is:open label:module/${shortName} label:Type/Bug`;
    string encodedQueryParameter = check url:encode(issueFilter, ENCODING);

    string badgeUrl = string `${GITHUB_BADGE_URL}/issues-search/${BALLERINA_ORG_NAME}/${BALLERINA_STANDARD_LIBRARY}?query=${query}`;
    string repoUrl = string `${BALLERINA_ORG_URL}/${BALLERINA_STANDARD_LIBRARY}/issues?q=${encodedQueryParameter}`;

    return string `[![Bugs](${badgeUrl})](${repoUrl})`;
}

isolated function getBugQuery(string moduleName) returns string|error {
    string shortName = getModuleShortName(moduleName);
    string labelColour = "";
    int issuesCount = -1;
    string query = string `state=open&labels=Type/Bug,module/${shortName}`;
    string url = string `/${BALLERINA_ORG_NAME}/${BALLERINA_STANDARD_LIBRARY}/issues?${query}`;
    http:Response openUrlResponse = check openUrl(GITHUB_API_LINK, url).ensureType();
    json urlResult = check openUrlResponse.getJsonPayload();
    if urlResult is json[] {
        issuesCount = urlResult.length();
    }

    if issuesCount == 0 {
        labelColour = BADGE_COLOR_GREEN;
    }
    else {
        labelColour = BADGE_COLOR_YELLOW;
    }
    string issueFilter = string `is:open label:module/${shortName} label:Type/Bug`;
    string encodedFilter = check url:encode(issueFilter, ENCODING);

    return string `${encodedFilter}&label=&color=${labelColour}`;
}

isolated function getPullRequestsBadge(string moduleName) returns string {
    string badgeUrl = string `${GITHUB_BADGE_URL}/issues-pr-raw/${BALLERINA_ORG_NAME}/${moduleName}.svg?label=`;
    string repoUrl = string `${BALLERINA_ORG_URL}/${moduleName}/pulls`;

    return string `[![GitHub Pull Requests](${badgeUrl})](${repoUrl})`;
}

isolated function getLoadTestsBadge(string moduleName, string defaultBranch) returns string|error {
    string badgeUrl = getGithubBadgeUrl(moduleName, WORKFLOW_PROCESS_LOAD_TESTS, defaultBranch, "");
    string repoUrl = string `${BALLERINA_ORG_URL}/${moduleName}/actions/workflows/${WORKFLOW_PROCESS_LOAD_TESTS}`;
    string workflowFileUrl = string `/${BALLERINA_ORG_NAME}/${moduleName}/master/.github/workflows/${WORKFLOW_PROCESS_LOAD_TESTS}`;
    http:Response openUrlResult = check openUrl(GITHUB_RAW_LINK, workflowFileUrl).ensureType();
    string urlResult = check openUrlResult.getTextPayload();
    if urlResult == "404: Not Found" {
        badgeUrl = NABADGE;
    }
    return string `[![Load Tests](${badgeUrl})](${repoUrl})`;
}

isolated function getBalTestNativeBadge(string moduleName, string defaultBranch) returns string|error {
    string badgeUrl = getGithubBadgeUrl(moduleName, WORKFLOW_BAL_TEST_NATIVE, defaultBranch, "");
    string repoUrl = string `${BALLERINA_ORG_URL}/${moduleName}/actions/workflows/${WORKFLOW_BAL_TEST_NATIVE}`;
    string workflowFileUrl = string `/${BALLERINA_ORG_NAME}/${moduleName}/master/.github/workflows/${WORKFLOW_BAL_TEST_NATIVE}`;
    http:Response openUrlResult = check openUrl(GITHUB_RAW_LINK, workflowFileUrl).ensureType();
    string urlResult = check openUrlResult.getTextPayload();
    if urlResult == "404: Not Found" {
        badgeUrl = NABADGE;
    }
    return string `[![GraalVM Check](${badgeUrl})](${repoUrl})`;
}

isolated function getModuleShortName(string moduleName) returns string {
    string[] nameSplit = re `-`.split(moduleName);
    if nameSplit.length() == 3 {
        string shortName = nameSplit[2];
        if shortName == "jballerina.java.arrays" {
            return "java.arrays";
        }
        return shortName;
    }
    return moduleName; // Tools
}

// string formating
isolated function capitalize(string str) returns string {
    return str[0].toUpperAscii() + str.substring(1, str.length());
}

isolated function getGithubBadgeUrl(string moduleName, string workflowFile, string defaultBranch, string? label = ()) returns string {
    string labelParameter = "";
    if label is string {
        labelParameter = "&label=" + label;
    }
    return string `${GITHUB_BADGE_URL}/actions/workflow/status/${BALLERINA_ORG_NAME}/${moduleName}/${workflowFile}?branch=${defaultBranch}${labelParameter}`;
}
