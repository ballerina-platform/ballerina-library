import ballerina/test;

const IO_MODULE = "module-ballerina-io";
const JAVA_ARRAYS_MODULE = "module-ballerina-jballerina.java.arrays";

@test:Config
try {
     function getRepoLinkTest() {
    test:assertEquals(getRepoLink(IO_MODULE), "[io](https://github.com/ballerina-platform/module-ballerina-io)");
}
} catch (Exception e) {
    return "An error occurred: " + e.getMessage();
}



@test:Config
function getReleaseBadgeTest() {
    test:assertEquals(getReleaseBadge(IO_MODULE), "[![GitHub Release](https://img.shields.io/github/v/release/ballerina-platform/module-ballerina-io?sort=semver&color=30c955&label=)](https://github.com/ballerina-platform/module-ballerina-io/releases)");
}

@test:Config
function getBuildStatusBadgeTest() {
    test:assertEquals(getBuildStatusBadge(IO_MODULE, "master"), "[![Build](https://img.shields.io/github/actions/workflow/status/ballerina-platform/module-ballerina-io/build-timestamped-master.yml?branch=master&label=)](https://github.com/ballerina-platform/module-ballerina-io/actions/workflows/build-timestamped-master.yml)");
}

@test:Config
function getTrivyBadgeTest() {
    test:assertEquals(getTrivyBadge(IO_MODULE, "master"), "[![Trivy](https://img.shields.io/github/actions/workflow/status/ballerina-platform/module-ballerina-io/trivy-scan.yml?branch=master&label=)](https://github.com/ballerina-platform/module-ballerina-io/actions/workflows/trivy-scan.yml)");
}

@test:Config
function getCodecovBadgeTest() {
    test:assertEquals(getCodecovBadge(IO_MODULE, "master"), "[![CodeCov](https://codecov.io/gh/ballerina-platform/module-ballerina-io/branch/master/graph/badge.svg)](https://codecov.io/gh/ballerina-platform/module-ballerina-io)");
}

@test:Config
function getPullRequestsBadgeTest() {
    test:assertEquals(getPullRequestsBadge(IO_MODULE), "[![GitHub Pull Requests](https://img.shields.io/github/issues-pr-raw/ballerina-platform/module-ballerina-io.svg?label=)](https://github.com/ballerina-platform/module-ballerina-io/pulls)");
}

@test:Config {
    enable: false
}
function getLoadTestsBadgeTest() {
    test:assertEquals(getLoadTestsBadge(IO_MODULE, "master"), "[![Load Tests](https://img.shields.io/github/actions/workflow/status/ballerina-platform/module-ballerina-io/process-load-test-result.yml?branch=master&label=)](https://github.com/ballerina-platform/module-ballerina-io/actions/workflows/process-load-test-result.yml)");
    test:assertEquals(getLoadTestsBadge(JAVA_ARRAYS_MODULE, "master"), "[![Load Tests](https://img.shields.io/badge/-N%2FA-yellow)](https://github.com/ballerina-platform/module-ballerina-jballerina.java.arrays/actions/workflows/process-load-test-result.yml)");
}

@test:Config {
    enable: false
}
function getBugsBadgeTest() {
    test:assertEquals(getBugsBadge(JAVA_ARRAYS_MODULE), "[![Bugs](https://img.shields.io/github/issues-search/ballerina-platform/ballerina-standard-library?query=is%3Aopen%20label%3Amodule%2Fjava.arrays%20label%3AType%2FBug&label=&color=30c955)](https://github.com/ballerina-platform/ballerina-standard-library/issues?q=is%3Aopen%20label%3Amodule%2Fjava.arrays%20label%3AType%2FBug)");
}
