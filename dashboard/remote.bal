import ballerina/os;
import ballerinax/github;
import ballerina/http;

public string defaultBranch = "";

function getDefaultBranch(string moduleName) returns string|error{
    github:Client githubClient = check connectGithub();
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
    string url = "/"+BALLERINA_ORG_NAME+"/"+moduleName+"/"+branch+"/"+fileName;
    http:Response response = check git->get(url);
    return response.getTextPayload();
}

// TODO: Has to be implemented in singleton
function connectGithub() returns github:Client|error {
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
    return  githubClient;
}