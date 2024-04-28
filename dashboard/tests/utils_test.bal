import ballerina/test;
import ballerina/io;

const IO_MODULE = "module-ballerina-io";
const JAVA_ARRAYS_MODULE = "module-ballerina-jballerina.java.arrays";
const TWILIO_MODULE = "module-ballerinax-twilio";

final readonly & List list = check (check io:fileReadJson("../release/resources/stdlib_modules.json")).fromJsonWithType();
final readonly & Module ioModule = check getIoModule();
final readonly & Module twilioModule = check getTwilioModule();

isolated function getTwilioModule() returns readonly & Module|error {
    foreach Module module in list.connectors {
        if module.name == "module-ballerinax-twilio" {
            return module;
        }
    }
    return error("Twilio module not found");
}

isolated function getIoModule() returns readonly & Module|error {
    foreach Module module in list.modules {
        if module.name == "module-ballerina-io" {
            return module;
        }
    }
    return error("IO module not found");
}

@test:Config
isolated function getRepoLinkTest() {
    test:assertEquals(getRepoLink(IO_MODULE), "[io](https://github.com/ballerina-platform/module-ballerina-io)");
}

@test:Config {
    enable: false
}
function getBuildStatusBadgeTest() returns error? {
    RepoBadges repoBadgesIo = check getRepoBadges(ioModule);
    RepoBadges repoBadgesTwilio = check getRepoBadges(twilioModule);
    test:assertEquals(getBadge(repoBadgesIo.buildStatus), "[![Build](https://img.shields.io/github/actions/workflow/status/ballerina-platform/module-ballerina-io/build-timestamped-master.yml?branch=master&label=)](https://github.com/ballerina-platform/module-ballerina-io/actions/workflows/build-timestamped-master.yml)");
    test:assertEquals(getBadge(repoBadgesTwilio.buildStatus), "[![Build](https://img.shields.io/github/actions/workflow/status/ballerina-platform/module-ballerinax-twilio/ci.yml?branch=master&label=)](https://github.com/ballerina-platform/module-ballerinax-twilio/actions/workflows/ci.yml)");
}

@test:Config {
    enable: false
}
function getTrivyBadgeTest() returns error? {
    RepoBadges repoBadgesIo = check getRepoBadges(ioModule);
    RepoBadges repoBadgesTwilio = check getRepoBadges(twilioModule);
    test:assertEquals(getBadge(repoBadgesIo.trivy), "[![Trivy](https://img.shields.io/github/actions/workflow/status/ballerina-platform/module-ballerina-io/trivy-scan.yml?branch=master&label=)](https://github.com/ballerina-platform/module-ballerina-io/actions/workflows/trivy-scan.yml)");
    test:assertEquals(getBadge(repoBadgesTwilio.trivy), "[![Trivy](https://img.shields.io/badge/-N%2FA-yellow)](https://github.com/ballerina-platform/module-ballerinax-twilio/actions/workflows/trivy-scan.yml)");
}

@test:Config
function getCodecovBadgeTest() returns error? {
    RepoBadges repoBadgesIo = check getRepoBadges(ioModule);
    RepoBadges repoBadgesTwilio = check getRepoBadges(twilioModule);
    test:assertEquals(getBadge(repoBadgesIo.codeCov), "[![CodeCov](https://codecov.io/gh/ballerina-platform/module-ballerina-io/branch/master/graph/badge.svg)](https://codecov.io/gh/ballerina-platform/module-ballerina-io)");
    test:assertEquals(getBadge(repoBadgesTwilio.codeCov), "[![CodeCov](https://img.shields.io/badge/-N%2FA-yellow)]()");
}

@test:Config
function getPullRequestsBadgeTest() returns error? {
    RepoBadges repoBadgesIo = check getRepoBadges(ioModule);
    test:assertEquals(getBadge(repoBadgesIo.pullRequests), "[![Pull Requests](https://img.shields.io/github/issues-pr-raw/ballerina-platform/module-ballerina-io.svg?label=)](https://github.com/ballerina-platform/module-ballerina-io/pulls)");
}

@test:Config {
    enable: false
}
function getLoadTestsBadgeTest() returns error? {
    RepoBadges repoBadgesIo = check getRepoBadges(ioModule);
    RepoBadges repoBadgesTwilio = check getRepoBadges(twilioModule);
    test:assertEquals(getBadge(repoBadgesIo.loadTests), "[![Load Tests](https://img.shields.io/github/actions/workflow/status/ballerina-platform/module-ballerina-io/process-load-test-result.yml?branch=master&label=)](https://github.com/ballerina-platform/module-ballerina-io/actions/workflows/process-load-test-result.yml)");
    test:assertEquals(getBadge(repoBadgesTwilio.loadTests), "[![Load Tests](https://img.shields.io/badge/-N%2FA-yellow)](https://github.com/ballerina-platform/module-ballerinax-twilio/actions/workflows/process-load-test-result.yml)");
}

@test:Config {
    enable: false
}
function getBugsBadgeTest() returns error? {
    RepoBadges repoBadgesIo = check getRepoBadges(ioModule);
    test:assertEquals(repoBadgesIo.bugs, "[![Bugs](https://img.shields.io/github/issues-search/ballerina-platform/ballerina-library?query=is%3Aopen%20label%3Amodule%2Fjava.arrays%20label%3AType%2FBug&label=&color=30c955)](https://github.com/ballerina-platform/ballerina-library/issues?q=is%3Aopen%20label%3Amodule%2Fjava.arrays%20label%3AType%2FBug)");
}
