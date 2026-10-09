# Ballerina {{MODULE_NAME_PC}} Connector

<!-- {{#RELEASED_DISTRIBUTION}} -->
[![Build](https://github.com/ballerina-platform/{{REPO_NAME}}/actions/workflows/ci.yml/badge.svg)](https://github.com/ballerina-platform/{{REPO_NAME}}/actions/workflows/ci.yml)
<!-- {{/RELEASED_DISTRIBUTION}} -->
<!-- {{#TIMESTAMPED_DISTRIBUTION}} -->
[![Build](https://github.com/ballerina-platform/{{REPO_NAME}}/actions/workflows/build-timestamped-master.yml/badge.svg)](https://github.com/ballerina-platform/{{REPO_NAME}}/actions/workflows/build-timestamped-master.yml)
<!-- {{/TIMESTAMPED_DISTRIBUTION}} -->
[![codecov](https://codecov.io/gh/ballerina-platform/{{REPO_NAME}}/branch/main/graph/badge.svg)](https://codecov.io/gh/ballerina-platform/{{REPO_NAME}})
[![Security Scan](https://github.com/ballerina-platform/{{REPO_NAME}}/actions/workflows/security-scan.yml/badge.svg)](https://github.com/ballerina-platform/{{REPO_NAME}}/actions/workflows/security-scan.yml)
[![GraalVM Check](https://github.com/ballerina-platform/{{REPO_NAME}}/actions/workflows/build-with-bal-test-graalvm.yml/badge.svg)](https://github.com/ballerina-platform/{{REPO_NAME}}/actions/workflows/build-with-bal-test-graalvm.yml)
[![GitHub Last Commit](https://img.shields.io/github/last-commit/ballerina-platform/{{REPO_NAME}}.svg)](https://github.com/ballerina-platform/{{REPO_NAME}}/commits/main)
[![GitHub Issues](https://img.shields.io/github/issues/ballerina-platform/ballerina-library/module/{{MODULE_NAME_CC}}.svg?label=Open%20Issues)](https://github.com/ballerina-platform/ballerina-library/labels/module%2F{{MODULE_NAME_CC}})

## Overview

[//]: # (TODO: Add an overview mentioning the purpose of the connector, the supported versions of the external system, and other high-level details.)

## Setup guide

[//]: # (TODO: Add detailed steps to obtain credentials and configure the connector.)

## Quickstart

[//]: # (TODO: Add a quickstart guide to demonstrate the basic functionality of the connector, including sample code snippets.)

## Examples

The `{{MODULE_NAME_CC}}` connector provides practical examples illustrating usage in various scenarios. Explore these [examples](https://github.com/ballerina-platform/{{REPO_NAME}}/tree/main/examples/), covering the following use cases:

[//]: # (TODO: Add examples)

## Issues and projects

The **Issues** and **Projects** tabs are disabled for this repository as this is part of the Ballerina library. To report bugs, request new features, start new discussions, view project boards, etc., go to the Ballerina library [parent repository](https://github.com/ballerina-platform/ballerina-library).

This repository contains only the source code of the package.

## Build from the source

### Set up the prerequisites

1. Download and install Java SE Development Kit (JDK) version 21. You can download it from either of the following sources:

    * [Oracle JDK](https://www.oracle.com/java/technologies/downloads/)
    * [OpenJDK](https://adoptium.net/)

   > **Note:** After installation, remember to set the `JAVA_HOME` environment variable to the directory where JDK was installed.

<!-- {{#RELEASED_DISTRIBUTION}} -->
2. Download and install [Ballerina Swan Lake](https://ballerina.io/).

3. Download and install [Docker](https://www.docker.com/get-started).

   > **Note**: Ensure that the Docker daemon is running before executing any builds or tests, since the package is built and tested inside the Ballerina Docker image.

4. Export your GitHub personal access token with the read package permissions as follows.
<!-- {{/RELEASED_DISTRIBUTION}} -->
<!-- {{#TIMESTAMPED_DISTRIBUTION}} -->
2. Export your GitHub personal access token with the read package permissions as follows.
<!-- {{/TIMESTAMPED_DISTRIBUTION}} -->

    ```bash
    export packageUser=<Username>
    export packagePAT=<Personal access token>
    ```

### Build options

Execute the commands below to build from the source.

1. To build the package:

    ```bash
    ./gradlew clean build
    ```

2. To run the tests:

    ```bash
    ./gradlew clean test
    ```

3. To build the package without the tests:

    ```bash
    ./gradlew clean build -x test
    ```

4. To run the tests of specific groups:

    ```bash
    ./gradlew clean test -Pgroups=<Comma separated groups/test cases>
    ```

5. To debug the package with a remote debugger:

    ```bash
    ./gradlew clean build -Pdebug=<port>
    ```

6. To debug with the Ballerina language:

    ```bash
    ./gradlew clean build -PbalJavaDebug=<port>
    ```

7. To publish the generated artifacts to the local Ballerina Central repository:

    ```bash
    ./gradlew clean build -PpublishToLocalCentral=true
    ```

8. To publish the generated artifacts to the Ballerina Central repository:

    ```bash
    ./gradlew clean build -PpublishToCentral=true
    ```

## Contribute to Ballerina

As an open-source project, Ballerina welcomes contributions from the community.

For more information, go to the [contribution guidelines](https://github.com/ballerina-platform/ballerina-lang/blob/master/CONTRIBUTING.md).

## Code of conduct

All the contributors are encouraged to read the [Ballerina Code of Conduct](https://ballerina.io/code-of-conduct).

## Useful links

* For more information go to the [`{{MODULE_NAME_CC}}` package](https://central.ballerina.io/ballerinax/{{MODULE_NAME_CC}}/latest).
* For example demonstrations of the usage, go to [Ballerina By Examples](https://ballerina.io/learn/by-example/).
* Chat live with us via our [Discord server](https://discord.gg/ballerinalang).
* Post all technical questions on Stack Overflow with the [#ballerina](https://stackoverflow.com/questions/tagged/ballerina) tag.
