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

The module, with a dependency on an older Language Distribution, will function on newer versions as long as there are no Essential Breaking Changes from the Language team for the upcoming Ballerina Update release.
> Essential Changes cannot be added in Patch Releases.

Compiler Team will handle all Essential Changes proactively. We have added a Pull Request check to all `ballerina-lang` Pull Requests. It is to validate that no downstream Standard Library modules are impacted.

[Build Pipelines Workflow](https://github.com/ballerina-platform/ballerina-release/actions/workflows/daily-full-build-master.yml) will build all Standard Libraries using the latest Language  version(for the specific update). It will send a notification if there are any build breaks. Module owners should address any failure notification promptly. Since Compiler Team handles the Essential Changes proactively, the builds should not fail for more than a day.

#### Steps to merge Essential Changes

1. Language Team developer will work on the feature in an upstream branch.
2. Run Full Build Pipeline Workflow to identify impacted modules.
3. Open an issue in `ballerina-standard-library` containing the details of the changes and the impacted modules list.
3. Module owners will migrate to the provided version in an upstream feature branch,
    - Cut the branch for lower lang dependency(2201.2.x).
    - Migrate the code to the latest language dependency.
    - Change the distribution in Ballerina.toml.
    - Bump to the next minor version (Skip this step if the development version is the next minor version to the last release)
4. Developer opens a `ballerina-lang` PR and merges the change.
      > The developer should provide the Language timestamped version to module owners to merge the changes to default branch 

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

The Standard Library Release Manager will use [Stdlib Release Workflow](https://github.com/ballerina-platform/ballerina-standard-library/actions/workflows/release_pipeline.yml) to release multiple modules(Usually during Ballerina Update releases). It will publish all modules in the [list](https://github.com/ballerina-platform/ballerina-standard-library/blob/main/release/resources/module_list.json). The Release Manager can override it by using the `release` property.

Checklist,
1. Verify if all modules with essential changes have updated language dependency and distribution versions. (All dependent versions)
2. Coordinate among the team to update modules. Module owners should verify the following,
   - The module can be built with the latest Language release.
   - Modules have the latest published/timestamped dependency versions.
   - Ballerina.toml has the correct distribution version.
3. Use the [Extensions - Update Ballerina Version Workflow](https://github.com/ballerina-platform/ballerina-release/actions/workflows/update_dependency_version.yml) to update dependency versions to the latest for consecutive version updates if any (lang RC releases).
   > If the RM is releasing only a subset of modules, which have the latest Language version, they should update the [extensions.json](https://github.com/ballerina-platform/ballerina-release/blob/master/dependabot/resources/extensions.json) by removing unnecessary modules in a separate branch. They can run the workflow run on said branch
   > Do not remove `ballerina-distribution` from the [extensions.json](https://github.com/ballerina-platform/ballerina-release/blob/master/dependabot/resources/extensions.json). If removed, the workflow will not update latest stdlib versions in `ballerina-distribution` in master branch
4. Ensure Ballerina Release Manager has released all modules to the Central Staging after each RC vote. The release Manager of the Ballerina Release will publish this. Module owners are responsible for the ballerinax components.
5. Run the [stdlib test workflow](https://github.com/ballerina-platform/ballerina-standard-library/actions/workflows/test_stdlib_releases_with_staging.yml) to verify newly published modules are working in an integration scenario. (This is to ensure no standard library release will break the existing users' build)
