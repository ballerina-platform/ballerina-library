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

import ballerina/os;
import ballerinax/github;
import ballerina/http;

public string defaultBranch = "";

http:Client git = check new(GITHUB_RAW_LINK, config = {
                            auth: {
                                token: os:getEnv(GITHUB_TOKEN)
                            },
                            retryConfig: {
                                count: HTTP_REQUEST_RETRIES,
                                interval: <decimal> HTTP_REQUEST_DELAY_IN_SECONDS,
                                backOffFactor: <float> HTTP_REQUEST_DELAY_MULTIPLIER
                                }
                            });

github:ConnectionConfig config = {
    auth: {
            token: os:getEnv(GITHUB_TOKEN)
    },
    retryConfig: {
        count: HTTP_REQUEST_RETRIES,
        interval: <decimal> HTTP_REQUEST_DELAY_IN_SECONDS,
        backOffFactor: <float> HTTP_REQUEST_DELAY_MULTIPLIER
        }
    };

github:Client githubClient = check new(config);

function getDefaultBranch(string moduleName) returns string|error{
    stream<github:Branch, github:Error?> branches = check githubClient->getBranches(BALLERINA_ORG_NAME, 
                                                            moduleName);
    _ = check branches.forEach(filterBranch);
    return defaultBranch;
}

function filterBranch(github:Branch branch){
    if branch.name == "main"{defaultBranch = "main";}
    else if branch.name == "master" {defaultBranch = "master";}
}

function readRemoteFile(string moduleName, string fileName, string branch) returns string|error {

    string url = "/"+BALLERINA_ORG_NAME+"/"+moduleName+"/"+branch+"/"+fileName;
    http:Response response = check git->get(url);
    return response.getTextPayload();
}