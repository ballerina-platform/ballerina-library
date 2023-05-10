# Adding a new Ballerina Module

Authors: @ThisaruGuruge  
Reviewers: @NipunaRanasinghe  
Created: 2023/05/09  
Updated: 2023/05/10

This is a step-by-step guide on creating a new Ballerina module. This will guide you through how to setup build and workflow scripts, setting up the environment, and how to add a new module to the Ballerina daily build and release pipelines.

## Table of Contents

1. [Introduction](#introduction)
2. [Prerequisites](#prerequisites)
3. [Repository Naming](#repository-naming)
4. [Setting Up the Environment](#setting-up-the-environment)
5. [Initializing the Repository](#initializing-the-repository)
6. [Directory Structure](#directory-structure)
    * 6.1 [The `.github` directory](#the-github-directory-required)
        * 6.1.1 [The `workflows` directory](#the-workflows-directory-required)
    * 6.2 [The `ballerina` directory](#the-ballerina-directory-gradle-submodulerequired)
    * 6.3 [The `build-config` directory](#the-build-config-directory-required)
        * 6.3.1 [The `checkstyle` directory](#the-checkstyle-directory-optional)
        * 6.3.2 [The `resources` directory](#the-resources-directory-required)
    * 6.4 [The `ballerina-tests` directory](#the-ballerina-tests-directory-gradle-submoduleoptional)
    * 6.5 [The `compiler-plugin` directory](#the-compiler-plugin-directory-gradle-submoduleoptional)
    * 6.6 [The `compiler-plugin-tests` directory](#the-compiler-plugin-tests-directory-gradle-submoduleoptional)
    * 6.7 [The `docs` directory](#the-docs-directory-optional)
    * 6.8 [The `examples` directory](#the-examples-directory-gradle-submoduleoptional)
    * 6.9 [The `load-tests` directory](#the-load-tests-directory-optional)
        * 6.9.1 [The `deployment` directory](#the-deployment-directory-required)
        * 6.9.2 [The `results` directory](#the-results-directory-required)
        * 6.9.3 [The `scripts` directory](#the-scripts-directory-required)
        * 6.9.4 [The `src` directory](#the-src-directory-required)
    * 6.10 [The `native` directory](#the-native-directory-gradle-submoduleoptional)
    * 6.11 [Other Build Files](#other-build-files)
        * 6.11.1 [The `LICENSE` file](#the-license-file-required)
        * 6.11.2 [The `README.md` file](#the-readmemd-file-required)
        * 6.11.3 [The `build.gradle` file](#the-buildgradle-file-required)
        * 6.11.4 [The `changelog.md` file](#the-changelogmd-file-required)
        * 6.11.5 [The `codecov.yml` file](#the-codecovyml-file-required)
        * 6.11.6 [The `gradle.properties` file](#the-gradleproperties-file-required)
        * 6.11.7 [The `gradlew` and `gradlew.bat` files](#the-gradlew-and-gradlewbat-files-required)
        * 6.11.8 [The `settings.gradle` file](#the-settingsgradle-file-required)
        * 6.11.9 [The `spotbugs-exclude.xml` file](#the-spotbugs-excludexml-file-optional)
7. [Adding a New Module](#adding-a-new-module)
    * 7.1 [Adding the Module to the Ballerina Standard Library](#adding-the-module-to-the-ballerina-standard-library-optional)
    * 7.2 [Adding the Module to Ballerina Daily Full Build Pipeline](#adding-the-module-to-ballerina-daily-full-build-pipeline-required)
    * 7.3 [Adding the Module to Ballerina Distribution](#adding-the-module-to-ballerina-distribution-optional)

## Introduction

This guide helps to understand the file structure, build scripts, and workflow scripts of a Ballerina module. It also explains how to add a new module to the Ballerina daily build and release pipelines. Each directory/file has tags defined inside `[]` to indicate whether it is required or optional and relation to `ballerina` and `ballerinax` module.

Examples for the directory structure and common files can be found in the existing Ballerina Standard Library module repositories. The links to these repositories can be found in the [Ballerina Standard Library Dashboard](https://github.com/ballerina-platform/ballerina-standard-library#status-dashboard).

The [Ballerina GraphQL Module](https://github.com/ballerina-platform/module-ballerina-graphql) would be a reference.

## Prerequisites

- [Ballerina](https://ballerina.io/downloads)
- [Gradle](https://gradle.org/releases/) - Version 7.1 preferred in Ballerina Standard Libraries
- [A GitHub access token](https://docs.github.com/en/enterprise-server@3.4/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token)

## Repository Naming

The repository name should start with `module-` prefix. Then the org name, either `ballerina-` or `ballerinax-`. Then the module name.

Example Names:

- module-ballerina-http
- module-ballerinax-kafka
- module-ballerina-jballerina.java.arrays

## Setting Up the Environment

Download and install the prerequisites. Then, set up the following environment variables.

- `packageUser` - Your GitHub username
- `packagePAT` - Your GitHub access token

## Initializing the Repository

First, create a new repository in the [Ballerina GitHub organization](https://github.com/ballerina-platform).

Then, clone the repository and initialize it with the following commands.

```shell
gradle init
```

This will open an interactive gradle CLI to initialize the repository. Use the default options to generate the Gradle scripts.

Example output of the `gradle init` command:

```
Select type of project to generate:
  1: basic
  2: application
  3: library
  4: Gradle plugin
Enter selection (default: basic) [1..4] -> Select Option 1 (Hit Enter)

Select build script DSL:
  1: Groovy
  2: Kotlin
Enter selection (default: Groovy) [1..2] -> Select Option 1 (Hit Enter)

Project name (default: module-ballerina-sample): -> Select the repository name (Hit Enter)

Generate build using new APIs and behavior (some features may change in the next minor release)? (default: no) [yes, no] -> Select no (Hit Enter)
```

Then create a new directory named `ballerina` inside the repository. This directory will contain the Ballerina module source code.

```shell
mkdir ballerina
```

Move to the `ballerina` directory and initialize it as a Ballerina module.

```shell
cd ballerina
bal init <module_name>
```

Then follow the instructions in the following [Directory Structure](#directory-structure) section to add/update the files.

## Directory Structure

A Ballerina module source code has the following structure.

```shell
.
├── .github
├── ballerina
├── ballerina-tests
├── build-config
├── compiler-plugin
├── compiler-plugin-tests
├── docs
├── examples
├── load-tests
└── native
```

### The `.github` directory [Required]

This directory contains the GitHub workflow scripts and other configurations required for the module. The following structure should be maintained in this directory.

```shell
.github
├── CODEOWNERS
├── pull_request_template.md
└── workflows
    ├── build-timestamped-master.yml
    ├── build-with-bal-test-native.yml
    ├── central-publish.yml
    ├── process-load-test-result.yml
    ├── publish-release.yml
    ├── pull-request.yml
    ├── stale_check.yml
    ├── trigger-load-tests.yml
    ├── trivy-scan.yml
    └── update-spec.yml
```

- CODEOWNERS: This file contains the GitHub usernames of the module owners. This is used to notify the module owners on pull requests.
- pull_request_template.md: This file contains the template for the pull request description.

#### The `workflows` directory [Required]

This directory contains the GitHub workflow scripts. The following workflow scripts are required for a Ballerina module.

##### The `build-timestamped-master.yml` workflow script [Required]

This workflow script is used to build the module. This will run automatically on every push to the master branch. This will build the module and publish the artifacts to the GitHub packages as a timestamped version, which can be used in the daily builds. It can be run manually as well. The status of this workflow is displayed on the Standard Library dashboard under the `Build` column.

##### The `build-with-bal-test-native.yml` workflow script [Required]

This workflow script is used to run the tests using the native runtime. This will run automatically on a schedule and on pull requests. It can be run manually as well. The status of this workflow is displayed on the Standard Library dashboard under the `GraalVM Check` column. To avoid running this workflow on pull requests, add the `Skip GraalVM Check` label to the pull request.

>**Note:** It is recommended to disable the GraalVM check on the pull requests until it is ready to be merged.

##### The `central-publish.yml` workflow script [Required]

This workflow script is used to publish the module to the central repository including the STAGE and DEV environments. This workflow can be triggered manually on demand.

##### The `process-load-test-result.yml` workflow script [Optional]

This workflow script is used to process the load test results of a module. It is needed only if the module has load tests. The status of this workflow is displayed on the Standard Library dashboard under the `Load Test Results` column.

>**Note:** In case of a failure of this workflow due to non-persistent issue, close the failed pull request, delete the branch that sent the pull request and re-run the failed workflow.

##### The `publish-release.yml` workflow script [Required]

This workflow script is used to release the module. It will create a new git tag, create a GitHub release, publish the artifacts to GitHub packages, publish the module to the Ballerina central, and finally sends a post-release sync pull request.

##### The `pull-request.yml` workflow script [Required]

This workflow script is used to build and run tests on pull requests. It has two main jobs, `Build on Ubuntu` and `Build on Windows`, which are required checks for a pull request. This workflow script is triggered automatically when a pull request is created or updated. It also uploads a code coverage report per each pull request, which is also a required check on all the Standard Library modules. Code coverage check is considered passed if the coverage is above 80%.

To reduce failures in the code coverage check, the `CODECOV_TOKEN` should be added to the repository as a secret.

>**Note:** The above mentioned checks (`Build on Ubuntu`, `Build on Windows`, and `codecov/project`) should be marked as required when creating the repo.

##### The `stale_check.yml` workflow script [Required]

This workflow script is used to check the stale pull requests. It will add a label to the pull request if it is stale. This workflow script is triggered automatically on a schedule.

##### The `trigger-load-tests.yml` workflow script [Optional]

This workflow script is used to trigger the load tests of a module. It is needed only if the module has load tests. This workflow script is triggered automatically on a schedule and can be triggered manually as well.

##### The `trivy-scan.yml` workflow script [Required]

This workflow script is used to scan the module for vulnerabilities using Trivy. This workflow script is triggered automatically on a schedule and can be triggered manually as well. The status of this workflow is displayed on the Standard Library dashboard under the `Security Check` column.

##### The `update-spec.yml` workflow script [Optional]

This workflow script is used to update the module specification in the Ballerina website. It is needed only if the module has a specification listed in the Ballerina website. This workflow script is triggered automatically when the `docs/spec` directory is updated.

### The `ballerina` directory [Gradle Submodule][Required]

This directory contains the Ballerina module source code, including the `Ballerina.toml`, `Module.md`, and `Package.md` files and the tests.

It also includes a `build.gradle` file which is used to build the Ballerina submodule. It uses the [Ballerina Gradle Plugin](https://github.com/ballerina-platform/plugin-gradle) to build the Ballerina module. The Ballerina Gradle plugin will add automated commits during the build to update the `Ballerina.toml`, `Dependencies.toml`, and `CompilerPlugin.toml` files.

### The `build-config` directory [Required]

This directory contains the build configurations for the module. The following structure should be maintained in this directory.

```shell
build-config
├── checkstyle
└── resources
```

#### The `checkstyle` directory [Optional]

This directory contains the checkstyle configurations for the module. This is required only if a module has Java (native) code. It includes a `build.gradle` file.

#### The `resources` directory [Required]

This directory contains the resources required for the Ballerina module, including the `Ballerina.toml`, `BallerinaTest.toml`, and `CompilerPlugin.toml` files.

Each of these files have placeholders to replace the values during the build. The Ballerina Gradle plugin will update these files during the build and commit them as automated commits.

>**Note:** The `CompilerPlugin.toml` file is required only if the module has a compiler plugin. The `BallerinaTest.toml` file is required only if the repository has `ballerina-tests` gradle submodule.

### The `ballerina-tests` directory [Gradle Submodule][Optional]

This directory contains the Ballerina tests that cannot be included in the `ballerina` directory. This includes the tests that are required to be run with the compiler plugin. It also includes a `build.gradle` file which is used to build and run the ballerina-tests submodule.

`ballerina/http` and `ballerina/graphql` are example modules that have tests in the `ballerina-tests` directory.

### The `compiler-plugin` directory [Gradle Submodule][Optional]

This directory contains the compiler plugin source code. It also includes a `build.gradle` file which is used to build the compiler plugin submodule.

### The `compiler-plugin-tests` directory [Gradle Submodule][Optional]

This directory contains the compiler plugin tests written using [TestNG](https://testng.org/doc/). It also includes a `build.gradle` file which is used to build and run the compiler-plugin-tests submodule. This is required only if the module has a compiler plugin.

### The `docs` directory [Optional]

This directory contains the module specifications. It includes a `proposals` directory to add the implemented proposals and the `spec.md` file that defines the module specification.

### The `examples` directory [Gradle Submodule][Optional]

This directory contains the examples for the module. It includes a `build.gradle` file which is used to build the examples submodule.

### The `load-tests` directory [Optional]

This directory is used to add load tests for the module. The `trigger-load-tests` workflow script will trigger the load tests in this directory.

Each load test should be added as a separate directory. The following structure should be maintained in each load test directory.

```
├── deployment
├── results
├── scripts
└── src
```

#### The `deployment` directory [Required]

This directory contains the deployment configurations for the load test including the `ingress.yaml` and `kustomization.yaml` files.

#### The `results` directory [Required]

This directory contains the results of the load test. The `trigger-load-tests` workflow script will upload the results to the `results` directory.

#### The `scripts` directory [Required]

This directory contains the scripts required for the load test. This includes the `run.sh` script which is used to run the load test.

#### The `src` directory [Required]

This directory contains the Ballerina source code of the load test.

### The `native` directory [Gradle Submodule][Optional]

This directory contains the Java native code of the module. This is required only if the module has native code. It also includes a `build.gradle` file which is used to build the native submodule.

### Other Build Files

Apart from the above-mentioned directories, there are other files that are required for the build. These files are required to be added to the root directory of the module.

Following are the files that are required for the build.

```
.
├── LICENSE
├── README.md
├── build.gradle
├── changelog.md
├── codecov.yml
├── gradle.properties
├── gradlew
├── gradlew.bat
├── settings.gradle
├── spotbugs-exclude.xml
```

### The `LICENSE` file [Required]

This file contains the license of the module. All the Ballerina Standard Library modules use `Apache-2` license.

### The `README.md` file [Required]

This file contains the description and the build steps of the module. Usually the content of this file is similar to `Module.md` and `Package.md` files of the Ballerina module.

It also includes the status badges for the module including the `Build`, `CodeCoverage`, `Trivy`, `GraalVM`, `last commit`, and the `Open Issues` badges.

### The `build.gradle` file [Required]

This file contains the build configurations of the module. It includes the configurations for adding other Ballerina module dependencies.

### The `changelog.md` file [Required]

This file contains the changelog of the module. The changelog should be updated with the changes of each feature/fix. Updating the changelog is added as a check in the pull request template to make sure each pull request has an entry in the changelog.

### The `codecov.yml` file [Required]

This file contains the Codecov configurations for the module. It is required to upload the Code coverage report for each pull request.

### The `gradle.properties` file [Required]

This file contains the dependency versions of the module. For Ballerina module dependencies, the naming convention of the version key is `ballerinaStdlib<moduleName>`. This convention should be followed strictly to make sure the automated dependency update workflows to work properly.

### The `gradlew` and `gradlew.bat` files [Required]

These files are auto-generated using the `gradle wrapper` command. These files are required to build the module using the Gradle wrapper.

### The `settings.gradle` file [Required]

This file contains the Gradle settings of the module. It includes the Gradle submodules of the module. The above mentioned directories related to `Gradle Submodule` should be added to this file using the following convention.

```
ballerina -> <module_name>-ballerina
ballerina-tests -> <module_name>-ballerina-tests
compiler-plugin -> <module_name>-compiler-plugin
compiler-plugin-tests -> <module_name>-compiler-plugin-tests
examples -> <module_name>-examples
native -> <module_name>-native
```

This file also includes the Gradle plugins that are used to build the module.

### The `spotbugs-exclude.xml` file [Optional]

This file is used to skip specific spotbugs warnings/errors. This is required only if the module has Java (native) code and needs to skip specific spotbugs warnings/errors.

## Adding a New Module

After creating the module repository with the above structure, the following steps should be followed.

### Adding the Module to the Ballerina Standard Library [Optional]

This step is only required if the module is a part of the Ballerina Standard Library and it should be added to the Ballerina Standard Library dashboard and release process.

To add a module to the Ballerina Standard Library, add an entry in the [`module_list.json`](https://github.com/ballerina-platform/ballerina-standard-library/blob/main/release/resources/module_list.json) file in the [Ballerina Standard Library](https://github.com/ballerina-platform/ballerina-standrad-library) Repository.

>**Note:** Do not edit the `stdlid_modules.json` file manually. It will be auto-generated once the `module_list.json` file is updated.

The JSON entry has two fields.

#### The `name` Field

This field defines the name of the module. This should be the name of the repository. (Eg.: module-ballerina-io)

#### The `version_key` Field

The version key of the module. This is related to the version prefix mentioned in the [`gradle.properties`](#the-gradleproperties-file-required) file. (Eg.: ballerinaStdlibIo). It is used to add the module as a dependency to another repository including the [ballerina-distribution](https://github.com/ballerina-platform/ballerina-distribution).

This field is optional. It is only required if the version key cannot be inferred from the module name. (Eg.: `module-ballerina-jballerina.java.arrays` -> `stdlibJavaArraysVersion`, `module-ballerina-oauth2` -> `stdlibOAuth2Version`)

>**Note:** The version key is case-sensitive and should be in the camel case format.

Once the `module_list.json` file is updated, the [`Update Stdlib Dependency Graph`](https://github.com/ballerina-platform/ballerina-standard-library/actions/workflows/update_dependencies.yml) workflow will run automatically to update the Standard Library dashboard.

Once updated this file, the module is ready to be released with the Ballerina Standard Library.

### Adding the Module to Ballerina Daily Full Build Pipeline [Required]

This step is required to add a module to the Ballerina daily build process.

To add a module to the Ballerina daily build process, add an entry in the [`module_list.json`](https://github.com/ballerina-platform/ballerina-release/blob/master/dependabot/resources/module_list.json) in the [Ballerina Release](https://github.com/ballerina-platform/ballerina-release) repository.

This Json file has two main fields.

- `standard_library` - This field contains an array of modules that are part of the Ballerina distribution. Add the module to this list if the module is released along with the Ballerina distribution.
- `extended_library` - This field contains an array of modules that are not part of the Ballerina distribution. Add the module to this list if the module is an extended Ballerina module which is not released along with the Ballerina distribution.

Each entry in the above-mentioned arrays has the following fields.

#### The `name` Field

This field defines the name of the module. This should be the name of the repository. (Eg.: module-ballerina-io)

#### The `version_key` Field

The version key of the module. This is related to the version prefix mentioned in the [`gradle.properties`](#the-gradleproperties-file-required) file. (Eg.: ballerinaStdlibIo). It is used to add the module as a dependency to another repository including the [ballerina-distribution](https://github.com/ballerina-platform/ballerina-distribution) repository.

#### The `level` Field

This field denotes the level of the module in the dependency graph. This will be updated automatically. Do not update this field manually.

#### The `group_id` Field

This field defines the maven artifact group id of the module. The default value is `io.ballerina.stdlib`. If the group ID of the module is different, it should be updated in this field.

#### The `artifact_id` Field

This field defines the maven artifact id of the module. The default value is `<module_name>-ballerina`. If the artifact ID of the module is different, it should be updated in this field.

#### The `default_branch` Field

This field defines the default branch of the module. This field will be updated automatically. Do not update this field manually.

#### The `auto_merge` Field

This field defines whether to auto-merge the dependency update pull requests or not. Default value is `true`. Set this to `false` to stop auto-merging dependency update PRs (not recommended).

#### The `push_to_central` Field

This field is used to define whether the module is being pushed to the Ballerina central or not. Default value is `true`. Set this to `false` for non-central repositories such as Ballerina tools repositories (Eg.: `ballerina-openapi-tools`, `ballerina-graphql-tools`).

#### The `is_extended_library` Field

This field is used to define whether the module is an extended library or not. Default value is `true`. Set this to `false` for repositories that are released along with the [ballerina-distribution](https://github.com/ballerina-platform/ballerina-distribution).

#### The `build_action_file` Field

This field is to define the default build action file of the module. This field will be updated automatically. Do not update this field manually.

#### The `send_notification` Field

This field is used to define whether to send a notification to the chat on build failures. Default value is `true`. Set this to `false` to stop sending notifications on build failures (not recommended).

#### The `dependents` Field

This field is used to add the dependents of the module. This field will be updated automatically. Do not update this field manually.

Once the `module_list.json` is updated, the [Update Dependency Graph](https://github.com/ballerina-platform/ballerina-release/actions/workflows/update_dependency_graph.yml) workflow will run automatically to update the dependency graph.

### Adding the Module to Ballerina Distribution [Optional]

This is required only if the module is released with the [ballerina-distribution](https://github.com/ballerina-platform/ballerina-distribution).

To add the module to the Ballerina distribution, follow the below steps.

#### Update the `gradle.properties` File [Required]

The module version should be added to the [`gradle.properties`](https://github.com/ballerina-platform/ballerina-distribution/blob/master/gradle.properties) file in the [ballerina-distribution](https://github.com/ballerina-platform/ballerina-distribution).

When adding the version, the `version_key` mentioned in the above sections should be used. If the module is not yet released, use a timestamp version of the module as the version.

>**Note:** The timestamp version can be found in the module repository under the `packages` section.

#### Update the `build.gradle` File [Required]

The module should be added as a configuration in the [`build.gradle`](https://github.com/ballerina-platform/ballerina-distribution/blob/master/build.gradle) file in the [ballerina-distribution](https://github.com/ballerina-platform/ballerina-distribution).

>**Note:** The module should be added under the `ballerinaStdlibs` configuration.

That's it. The module is now added to the Ballerina daily builds and release processes.
