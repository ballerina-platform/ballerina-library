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

function getModuleShortName(string moduleName) returns string{
    string shortName = regex:split(moduleName, "-")[2];
    if shortName == "jballerina.java.arrays" {
        return "java.arrays";
        }
    shortName = capitalize(shortName);
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