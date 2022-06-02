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

import ballerina/regex;
import ballerina/url;
import ballerina/http;

function getDashboardRow(Module module, string level) returns string|error {
    string moduleName = module.name;

    string defaultBranch = "";
    string? branch = module.default_branch;
    if branch is string {
        defaultBranch = branch;
    }
    string repoLink = getRepoLink(moduleName);
    string releaseBadge = getReleaseBadge(moduleName);
    string buildStatusBadge = getBuildStatusBadge(moduleName);
    string trivyBadge = getTrivyBadge(moduleName);
    string codecovBadge = getCodecovBadge(moduleName, defaultBranch);
    string bugsBadge = check getBugsBadge(moduleName);
    string pullRequestsBadge = getPullRequestsBadge(moduleName);
    string loadTestsBadge = check getLoadTestsBadge(moduleName);
    return string `|${level}|${repoLink}|${releaseBadge}|${buildStatusBadge}|${trivyBadge}|${codecovBadge}|${bugsBadge}|${pullRequestsBadge}|${loadTestsBadge}|`;
}

function getRepoLink(string moduleName) returns string {
    string shortName = getModuleShortName(moduleName);
    return string `[${shortName}](${BALLERINA_ORG_URL}/${moduleName})`;
}

function getReleaseBadge(string moduleName) returns string {
    string badgeUrl = string `${GITHUB_BADGE_URL}/v/release/${BALLERINA_ORG_NAME}/${moduleName}?sort=semver&color=${BADGE_COLOR_GREEN}&label=`;
    string repoUrl = string `${BALLERINA_ORG_URL}/${moduleName}/releases`;
    return string `[![GitHub Release](${badgeUrl})](${repoUrl})`;
}

function getBuildStatusBadge(string moduleName) returns string {
    string badgeUrl = string `${GITHUB_BADGE_URL}/workflow/status/${BALLERINA_ORG_NAME}/${moduleName}/Build?label=`;
    string repoUrl = string `${BALLERINA_ORG_URL}/${moduleName}/actions/workflows/build-timestamped-master.yml`;
    return string `[![Build](${badgeUrl})](${repoUrl})`;
}

function getTrivyBadge(string moduleName) returns string {
    string badgeUrl = string `${GITHUB_BADGE_URL}/workflow/status/${BALLERINA_ORG_NAME}/${moduleName}/Trivy?label=`;
    string repoUrl = string `${BALLERINA_ORG_URL}/${moduleName}/actions/workflows/trivy-scan.yml`;
    return string `[![Trivy](${badgeUrl})](${repoUrl})`;
}

function getCodecovBadge(string moduleName, string defaultBranch) returns string {
    string badgeUrl = string `${CODECOV_BADGE_URL}/${BALLERINA_ORG_NAME}/${moduleName}/branch/${defaultBranch}/graph/badge.svg`;
    string repoUrl = string `${CODECOV_BADGE_URL}/${BALLERINA_ORG_NAME}/${moduleName}`;
    return string `[![CodeCov](${badgeUrl})](${repoUrl})`;
}

function getBugsBadge(string moduleName) returns string|error {
    string query = check getBugQuery(moduleName);
    string shortName = getModuleShortName(moduleName);
    string issueFilter = string `is:open label:module/${shortName} label:Type/Bug`;
    string encodedQueryParameter = check url:encode(issueFilter, ENCODING);

    string badgeUrl = string `${GITHUB_BADGE_URL}/issues-search/${BALLERINA_ORG_NAME}/${BALLERINA_STANDARD_LIBRARY}?query=${query}`;
    string repoUrl = string `${BALLERINA_ORG_URL}/${BALLERINA_STANDARD_LIBRARY}/issues?q=${encodedQueryParameter}`;

    return string `[![Bugs](${badgeUrl})](${repoUrl})`;
}

function getBugQuery(string moduleName) returns string|error {
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

function getPullRequestsBadge(string moduleName) returns string {
    string badgeUrl = string `${GITHUB_BADGE_URL}/issues-pr-raw/${BALLERINA_ORG_NAME}/${moduleName}.svg?label=`;
    string repoUrl = string `${BALLERINA_ORG_URL}/${moduleName}/pulls`;

    return string `[![GitHub Pull Requests](${badgeUrl})](${repoUrl})`;
}

function getLoadTestsBadge(string modName) returns string|error {
    // websub/websubhub load tests are in websubhub module, hence `websub` load-test badge should be same as `websubhub` load-test badge
    string moduleName = modName;
    if modName == "module-ballerina-websub" {
        moduleName = "module-ballerina-websubhub";
    }
    string badgeUrl = string `${GITHUB_BADGE_URL}/workflow/status/${BALLERINA_ORG_NAME}/${moduleName}/Process%20load%20test%20results?label=`;
    string repoUrl = string `${BALLERINA_ORG_URL}/${moduleName}/actions/workflows/process-load-test-result.yml`;
    string workflowFileUrl = string `/${BALLERINA_ORG_NAME}/${moduleName}/master/.github/workflows/process-load-test-result.yml`;
    http:Response openUrlResult = check openUrl(GITHUB_RAW_LINK, workflowFileUrl).ensureType();
    string urlResult = check openUrlResult.getTextPayload();
    if urlResult == "404: Not Found" {
        badgeUrl = NABADGE;
    }
    return string `[![Load Tests](${badgeUrl})](${repoUrl})`;
}

function getModuleShortName(string moduleName) returns string {
    string shortName = regex:split(moduleName, "-")[2];
    if shortName == "jballerina.java.arrays" {
        return "java.arrays";
    }
    return shortName;
}

// string formating
function capitalize(string str) returns string {
    return str[0].toUpperAscii() + str.substring(1, str.length());
}
