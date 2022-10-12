# Standard Library Build and Release Guide

_Authors_: @niveathika  
_Reviewers_: @shafreenAnfar @daneshk  
_Created_: 2022/07/05  
_Updated_: 2022/10/12

## Overview

This guide explains the build and release process of the Standard Libraries. The goal is that everyone in the team should be able to release any Standard Library with the help of this guide.

### Build Process

Ballerina distribution depends on multiple components.

<img src="_resources/BallerinaComponentsDependency.jpg" alt="drawing" width='400'/>

Standard Libraries are built on top of the base Ballerina Language distribution.

The build includes the following tasks,
1. Create an intermediate Ballerina Distribution consisting of Language and any dependent Standard Library.
2. Build and Run unit tests.
3. Create an intermediate distribution, including the module.
4. Run any Integration Tests or Compiler Plugin Tests.
5. Publish the module to GitHub Packages.

The [Gradle Plugin](https://github.com/ballerina-platform/plugin-gradle) executes tasks 1, 2 and 3. This plugin includes all build, test and publish tasks of the Standard Library to Ballerina Central. Publish of Ballerina module or native components depend on GitHub packages.

### Branching Strategy

Branches will depend on the Ballerina Update version the module depends on,

1. 2201.1.x
2. 2201.2.x
3. master

Module owners should create needed branches for Language versions only if the language includes Essential Breaking Changes.

### Handling Essential Breaking Changes

The module, with a dependency on an older Language Distribution, will function on newer versions as long as there are no Essential Breaking Changes from the Language team.

[Build Pipelines Workflow](https://github.com/ballerina-platform/ballerina-release/actions/workflows/daily-full-build-2201.2.x.yml) will build all Standard Libraries using the latest language (for the specific update). It will send a notification if there are any build breaks. Module owners should address any failure notification promptly.

#### Steps to be taken

1. Language Team can include Breaking changes only on Update releases. If module owners identify any breaking changes in a patch versions, they should inform the Language team to revert the changes.
2. Language team needs to defend their decision for any breaking change as essential for the said update. Verify this from the Language team.
3. Migrate to the latest language version using the timestamp version.
4. Cut the branch for lower lang dependency(2201.2.x).
5. Migrate the code to the latest language dependency.
6. Change the distribution in Ballerina.toml.
7. Bump to the next minor version.
8. Let SMs know of the change.They can coordinate with the team. All dependent modules need to follow steps 3-8 recursively.

### Release Process

### Single module release

With the current design of Central, any stand library can be released at any time if the module owner and the lead deem it necessary. Module owners need not wait and synchronize with distribution release dates.

[Publish GitHub Workflow](https://github.com/ballerina-platform/module-ballerina-http/actions/workflows/publish-release.yml) is used to release the module .

Checklist for the release,
1. All unit and integration tests are passing.
2. The module does not include any components with an identified Security Vulnerability.
3. Publish artifact to the [Central Staging Environment](https://github.com/ballerina-platform/module-ballerina-http/actions/workflows/central-publish.yml).
4. Run [workflow](https://github.com/ballerina-platform/ballerina-standard-library/actions/workflows/test_stdlib_releases_with_staging.yml) to verify that the newly published module is working in an integration scenario. (This is to ensure the standard library release will not break the existing users' build)
5. Run the release workflow.
6. Update module version in Ballerina Distribution.

### Multiple module release

The Standard Library Release Manager will use [Stdlib Release Workflow](https://github.com/ballerina-platform/ballerina-standard-library/actions/workflows/release_pipeline.yml) to release multiple modules(Usually during Ballerina Update releases). It will publish all modules in the [list](https://github.com/ballerina-platform/ballerina-standard-library/blob/main/dashboard/resources/stdlib_modules.json#L1). The Release Manager can override it by using the `release` property.

Checklist,
1. Verify if all modules with essential changes have updated language dependency and distribution versions. (All dependent versions)
2. Coordinate among the team to update modules. Module owners should verify the following,
   - The module can be built with the latest Language release.
   - Modules have the latest published/timestamped dependency versions.
   - Ballerina.toml has the correct distribution version.
3. Use the [Extensions - Update Ballerina Version Workflow](https://github.com/ballerina-platform/ballerina-release/actions/workflows/update_dependency_version.yml) to update dependency versions to the latest for consecutive version updates if any (lang RC releases).
   >> If the RM is releasing only a subset of modules, which have the latest Language version, they should update the [extensions.json](https://github.com/ballerina-platform/ballerina-release/blob/master/dependabot/resources/extensions.json) by removing unnecessary modules in a separate branch. They can run the workflow run on said branch
4. Ensure Ballerina Release Manager has released all modules to the Central Staging after each RC vote. The release Manager of the Ballerina Release will publish this. Module owners are responsible for the ballerinax components.
5. Run the [stdlib test workflow](https://github.com/ballerina-platform/ballerina-standard-library/actions/workflows/test_stdlib_releases_with_staging.yml) to verify newly published modules are working in an integration scenario. (This is to ensure no standard library release will break the existing users' build)