// Copyright (c) 2024, WSO2 LLC. (http://www.wso2.org).
//
// WSO2 LLC. licenses this file to you under the Apache License,
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

isolated function getLibraryDashboardRow(Module module, string level) returns string|error {
    string dashboardLine = check getDashboardRow(module);
    return string `|${level}${dashboardLine}`;
}

isolated function getToolsDashboardRow(Module module) returns string|error {
    string moduleName = module.name;
    RepoBadges repoBadges = check getRepoBadges(module);
    string repoLink = getRepoLink(moduleName);
    string releaseBadge = getBadge(repoBadges.release);
    string buildStatusBadge = getBadge(repoBadges.buildStatus);
    string trivyBadge = getBadge(repoBadges.trivy);
    string codecovBadge = getBadge(repoBadges.codeCov);
    string bugsBadge = getBadge(repoBadges.bugs);
    string pullRequestsBadge = getBadge(repoBadges.pullRequests);
    return string `|${repoLink}|${releaseBadge}|${buildStatusBadge}|${trivyBadge}|${codecovBadge}|${bugsBadge}|${pullRequestsBadge}|`;
}

isolated function getDashboardRow(Module module) returns string|error {
    RepoBadges repoBadges = check getRepoBadges(module);
    string repoLink = getRepoLink(module.name);
    string releaseBadge = getBadge(repoBadges.release);
    string buildStatusBadge = getBadge(repoBadges.buildStatus);
    string trivyBadge = getBadge(repoBadges.trivy);
    string codecovBadge = getBadge(repoBadges.codeCov);
    string bugsBadge = getBadge(repoBadges.bugs);
    string pullRequestsBadge = getBadge(repoBadges.pullRequests);
    string loadTestsBadge = getBadge(repoBadges.loadTests);
    string graalvmCheck = getBadge(repoBadges.graalvmCheck);
    return string `|${repoLink}|${releaseBadge}|${buildStatusBadge}|${trivyBadge}|${codecovBadge}|${bugsBadge}|${pullRequestsBadge}|${loadTestsBadge}|${graalvmCheck}|`;
}


isolated function getRepoLink(string moduleName) returns string {
    string shortName = getModuleShortName(moduleName);
    return string `[${shortName}](${BALLERINA_ORG_URL}/${moduleName})`;
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

isolated function getBadge(WorkflowBadge? badge) returns string {
    if badge is () {
        return string `[![N/A](${NABADGE})]("")`;
    }
    return string `[![${badge.name}](${badge.badgeUrl})](${badge.htmlUrl})`;
}
