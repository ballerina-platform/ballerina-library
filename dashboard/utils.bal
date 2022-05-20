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