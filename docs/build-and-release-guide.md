# Standard Library Build and Release Guide

_Authors_: @niveathika  
_Reviewers_: @shafreenAnfar @daneshk  
_Created_: 2022/07/05  
_Updated_: 2021/07/05

## Overview

This guide explains the build and the release process of the Standard Libraries. The goal is that everyone in the team should be able to release any Standard Library with the help of the guide.

### Build Process

Ballerina distribution depends on multiple components.

<img src="_resources/BallerinaComponentsDependency.jpg" alt="drawing" width='400'/>

Standard Libraries are build on top of the base Ballerina Language distribution. 

The build includes following tasks,
1. Create an intermediate ballerina distribution consisting of Language and any dependant Standard Library.
2. Build and Run unit tests.
3. Create an intermediate distribution including the Library.
4. Run any Integration Tests, Compiler Plugin Development and Tests.
5. Publish Library to Github Packages.

Task 1, 2 and 3 are executed through a [Gradle Plugin](https://github.com/ballerina-platform/plugin-gradle). This plugin includes all build, test and publish tasks of the Library.

### Branching Strategy

Branches will depend on the update version of the ballerina language, stdlib will depend on.

1. 2201.1.x
2. 2201.2.x
3. master

Branches needs to be created seperatly for Language versions, only if the language includes Essential Breaking Changes.

### Handling Essential Breaking Changes

The Standard Library dependent on an older Language Distribution will function on newer versions as long as there are no Essential Breaking Changes from the Language team. 

All Standard Libraries will be built with the latest language (for the specific update) using [Build Pipelines Workflow](https://github.com/ballerina-platform/ballerina-release/actions/workflows/daily-full-build-2201.2.x.yml). This will send notification if there are any build breaks. These should be addressed in a timely manner.

#### Steps to be taken

1. Breaking changes from Language Team can only be sent on Update releases. If it is identified for any patch versions, inform from the language team to revert the said changes.
2. Language team needs to defend their decision for any breaking change as essential for the said update. Verify this from the lang team. 
3. Migrate to the latest language version using the timestamp version,
4. Cut branch for lower lang dependency(2201.2.x)
5. Migrate code to the latest language dependency.
6. Change the distribution in Ballerina.toml
7. Bump to the next minor version.
8. Let SMs know of the change so that this can be coordinated with the team. All dependent modules need to follow step 3-8 recursively.

### Release Process

### Single module release

With the current design of Central, any stand library can be released at any time if the module owner and the lead deems it necessary. Module owner need not wait and synchronize with distribution release dates.

The release of each modules are done through [Publish Github Workflow](https://github.com/ballerina-platform/module-ballerina-http/actions/workflows/publish-release.yml).

Checklist for the release,
1. All unit test, integration tests are passing
2. The module does NOT include any components with an identified Security Vulnerability.
3. Publish artifact to the Central Staging Environment
4. Run workflow to verify newly published module is working properly in an integrartion scenario. (This is to ensure any stadard library release will not break the existing users build)
5. Run the release workflow 
6. Update module version in Ballerina Distribution

### Multiple module release

With the Essential Changes from the Language Team. Many of the libraries may need to be released along with Ballerina Swan Lake Update releases. 

The release of multiple modules can be done through [Stdlib Release Workflow](https://github.com/ballerina-platform/ballerina-standard-library/actions/workflows/release_pipeline.yml). This will release modules from the [list](https://github.com/ballerina-platform/ballerina-standard-library/blob/main/dashboard/resources/stdlib_modules.json#L1). This can be ovveridden by using release property.

Checklist,
1. Verify if all modules with essential changes have updated language dependency and distribution version.(All dependant version)
2. Coordinate among team to update to latest timestamped version of the dependants
3. Ensure the standard libraries are released to Central Staging after each RC vote. Release Manager of the Ballerina Release will publish this. Module owners is responsible for the ballerinax components.
4. Run workflow to verify newly published module is working properly in an integrartion scenario. (This is to ensure any stadard library release will not break the existing users build)
