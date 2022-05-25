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

import ballerina/io;
import ballerina/regex;

function getDashboardRow(m module, int level) {
    string moduleName = module.name;
    string defaultBranch = <string>module.default_branch;

    string repoLink = getRepoLink(moduleName);
    string releaseBadge = getReleaseBadge(moduleName);
    string buildStatusBadge = getBuildStatusBadge(moduleName);
    string trivyBadge = getTrivyBadge(moduleName);
    string codecovBadge = getCodecovBadge(moduleName, defaultBranch);
    string pullRequestsBadge = getPullRequestsBadge(moduleName);
    string loadTestsBadge = getLoadTestsBadge(moduleName);
}

function getRepoLink(string moduleName) returns string{
    string shortName = getModuleShortName(moduleName);
    return string `[${shortName}](${BALLERINA_ORG_URL}/${moduleName})`;
}

function getReleaseBadge(string moduleName) returns string{
    string badgeUrl = string `${GITHUB_BADGE_URL}/v/release/${BALLERINA_ORG_NAME}/${moduleName}?sort=semver&color=${BADGE_COLOR_GREEN}&label=`;
    string repoUrl = string `${BALLERINA_ORG_URL}/${moduleName}/releases`;
    return string `[![GitHub Release](${badgeUrl})](${repoUrl})`;
}

function getBuildStatusBadge(string moduleName) returns string{
    string badgeUrl = string `${GITHUB_BADGE_URL}/workflow/status/${BALLERINA_ORG_NAME}/${moduleName}/Build?label=`;
    string repoUrl = string `${BALLERINA_ORG_URL}/${moduleName}/actions/workflows/build-timestamped-master.yml`;
    return string `[![Build](${badgeUrl})](${repoUrl})`;
}

function getTrivyBadge(string moduleName) returns string{
    string badgeUrl = string `${GITHUB_BADGE_URL}/workflow/status/${BALLERINA_ORG_NAME}/${moduleName}/Trivy?label=`;
    string repoUrl = string `${BALLERINA_ORG_URL}/${moduleName}/actions/workflows/trivy-scan.yml`;
    return string `[![Trivy](${badgeUrl})](${repoUrl})`;
}

function getCodecovBadge(string moduleName, string defaultBranch) returns string{
    string badgeUrl = string `${CODECOV_BADGE_URL}/${BALLERINA_ORG_NAME}/${moduleName}/branch/${defaultBranch}/graph/badge.svg`;
    string repoUrl = string `${CODECOV_BADGE_URL}/${BALLERINA_ORG_NAME}/${moduleName}`;
    return string `[![CodeCov](${badgeUrl})](${repoUrl})`;
}

// function getBugsBadge(string moduleName) {
    
// }

// function getBugQuery(string moduleName) {
//     string shortName = getModuleShortName(moduleName);
//     string query = string `state=open&labels=Type/Bug,module/${shortName}`;
//     string url = string `/${BALLERINA_ORG_NAME}/${BALLERINA_STANDARD_LIBRARY}/issues?${query}`;
//     json|error jsonData = openUrl(GITHUB_API_LINK, url);
//     if jsonData is error {
//         io:println("Failed to get issue details for "+ moduleName);
//         int issueCount = 1;
//     }
//     else {
        
//     }
// }

function getPullRequestsBadge(string moduleName) returns string{
    string badgeUrl = string `${GITHUB_BADGE_URL}/issues-pr-raw/${BALLERINA_ORG_NAME}/${moduleName}.svg?label=`;
    string repoUrl = string `${BALLERINA_ORG_URL}/${moduleName}/pulls`;

    return string `[![GitHub Pull Requests](${badgeUrl})](${repoUrl})`;
}

function getLoadTestsBadge(string modName) returns string{
    // websub/websubhub load tests are in websubhub module, hence `websub` load-test badge should be same as `websubhub` load-test badge
    string moduleName = modName;
    if modName == "module-ballerina-websub"{
        moduleName = "module-ballerina-websubhub";
    }
    string badgeUrl = string `${GITHUB_BADGE_URL}/workflow/status/${BALLERINA_ORG_NAME}/${moduleName}/Process%20load%20test%20results?label=`;
    string repoUrl = string `${BALLERINA_ORG_URL}/${moduleName}/actions/workflows/process-load-test-result.yml`;
    string workflowFileUrl = string `/${BALLERINA_ORG_NAME}/${moduleName}/master/.github/workflows/process-load-test-result.yml`;
    string|error? openUrlResult = openUrl(GITHUB_RAW_LINK,workflowFileUrl);
    if openUrlResult == "404: Not Found" {
        badgeUrl = NABADGE;
    }
    return string `[![Load Tests](${badgeUrl})](${repoUrl})`;
}

function getModuleShortName(string moduleName) returns string{
    string shortName = regex:split(moduleName, "-")[2];
    if shortName == "jballerina.java.arrays" {
        return "java.arrays";
        }
    return shortName;
}

function capitalize(string str) returns string { 
    return str[0].toUpperAscii()+str.substring(1,str.length());
}

function printInfo(string message) {
    io:println("[Info] "+ message);
}

function printWarn(string message){
    io:println("[Warning] "+ message);
}