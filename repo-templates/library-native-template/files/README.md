# Ballerina {{MODULE_NAME_PC}} Library

[![Build](https://github.com/ballerina-platform/{{REPO_NAME}}/actions/workflows/build-timestamped-master.yml/badge.svg)](https://github.com/ballerina-platform/{{REPO_NAME}}/actions/workflows/build-timestamped-master.yml)
[![codecov](https://codecov.io/gh/ballerina-platform/{{REPO_NAME}}/branch/main/graph/badge.svg)](https://codecov.io/gh/ballerina-platform/{{REPO_NAME}})
[![Trivy](https://github.com/ballerina-platform/{{REPO_NAME}}/actions/workflows/trivy-scan.yml/badge.svg)](https://github.com/ballerina-platform/{{REPO_NAME}}/actions/workflows/trivy-scan.yml)
[![GraalVM Check](https://github.com/ballerina-platform/{{REPO_NAME}}/actions/workflows/build-with-bal-test-graalvm.yml/badge.svg)](https://github.com/ballerina-platform/{{REPO_NAME}}/actions/workflows/build-with-bal-test-graalvm.yml)
[![GitHub Last Commit](https://img.shields.io/github/last-commit/ballerina-platform/{{REPO_NAME}}.svg)](https://github.com/ballerina-platform/{{REPO_NAME}}/commits/main)
[![GitHub Issues](https://img.shields.io/github/issues/ballerina-platform/ballerina-library/module/{{MODULE_NAME_CC}}.svg?label=Open%20Issues)](https://github.com/ballerina-platform/ballerina-library/labels/module%2F{{MODULE_NAME_CC}})

## Overview

[//]: # (TODO: Add an overview of the library.)

## Issues and projects

The **Issues** and **Projects** tabs are disabled for this repository as this is part of the Ballerina library. To report bugs, request new features, start new discussions, view project boards, etc., go to the Ballerina library [parent repository](https://github.com/ballerina-platform/ballerina-library).

This repository contains only the source code of the package.

## Build from the source

### Set up the prerequisites

1. Download and install Java SE Development Kit (JDK) version 21 (from one of the following locations).

    * [Oracle](https://www.oracle.com/java/technologies/downloads/)
    * [OpenJDK](https://adoptium.net/)

   > **Note:** Set the JAVA_HOME environment variable to the path name of the directory into which you installed JDK.

2. Export your GitHub personal access token with the read package permissions as follows.

    ```bash
    export packageUser=<Username>
    export packagePAT=<Personal access token>
    ```

### Build the source

Execute the commands below to build from the source.

1. To build the library:

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

4. To debug the tests:

    ```bash
    ./gradlew clean build -Pdebug=<port>
    ```

5. To debug the package with the Ballerina language:

    ```bash
    ./gradlew clean build -PbalJavaDebug=<port>
    ```

6. To publish the ZIP artifact to the local `.m2` repository:

    ```bash
    ./gradlew clean build publishToMavenLocal
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

All contributors are encouraged to read the [Ballerina Code of Conduct](https://ballerina.io/code-of-conduct).

## Useful links

* For more information go to the [`{{MODULE_NAME_CC}}` library](https://lib.ballerina.io/ballerina/{{MODULE_NAME_CC}}/latest).
* Chat live with us via our [Discord server](https://discord.gg/ballerinalang).
* Post all technical questions on Stack Overflow with the [#ballerina](https://stackoverflow.com/questions/tagged/ballerina) tag.
