# Ballerina Module Repository Templates

This directory contains the templates used to bootstrap the repositories of the Ballerina library modules and connectors. A template can be applied to a repository either with the [Apply Library Repo Templates and Create PR](../.github/workflows/apply-library-repo-templates.yml) workflow, which opens a PR against the target repository, or manually with the [`apply_template.bal`](scripts/apply_template.bal) script.

All the templates use Gradle 9.5.1, the Ballerina Gradle plugin 4.0.0, and the reusable workflows in this repository.

## Templates

| Template | Package org | Native code | Workflow family | Modeled on |
| --- | --- | --- | --- | --- |
| [`library-template`](library-template) | `ballerina` | No | Library (`*-template.yml`, stdlib release pipeline) | [module-ballerina-math.vector](https://github.com/ballerina-platform/module-ballerina-math.vector) |
| [`library-native-template`](library-native-template) | `ballerina` | Yes | Library (`*-template.yml`, stdlib release pipeline) | [module-ballerina-constraint](https://github.com/ballerina-platform/module-ballerina-constraint) |
| [`connector-template`](connector-template) | `ballerinax` | Yes | Depends on the distribution feature, see below | [module-ballerinax-aws.s3](https://github.com/ballerina-platform/module-ballerinax-aws.s3), [module-ballerinax-kafka](https://github.com/ballerina-platform/module-ballerinax-kafka) |
| [`generated-connector-template`](generated-connector-template) | `ballerinax` | No | Connector (`*-connector-template.yml`) | Connectors generated from OpenAPI specifications |

### Features

Some templates have optional features, which are enabled when generating the repository.

| Feature | Templates | Description |
| --- | --- | --- |
| `compiler-plugin` | `library-native-template`, `connector-template` | Adds the `compiler-plugin` and `compiler-plugin-tests` modules and the `CompilerPlugin.toml`, and wires them into the build, codecov and the GraalVM check. |
| `released-distribution` | `connector-template` | Builds the connector with `connector = true`, i.e. on the Ballerina Docker image of a released distribution, and uses the connector workflow family (`ci.yml`, `pull-request.yml`, `daily-build.yml`, `dev-stg-release.yml`, `release.yml`). The examples are built with `examples/build.sh`. Use this for connectors that are released independently of the distribution, such as `aws.s3`. |
| `timestamped-distribution` | `connector-template` | Builds the connector against the `jballerina-tools` of `ballerinaLangVersion`, which can be a timestamped version from GitHub packages, and uses the library workflow family (`build-timestamped-master.yml`, `pull-request.yml`, `central-publish.yml`, `publish-release.yml`) and the stdlib release pipeline. The examples are built by Gradle with the unpacked distribution. Use this for connectors that are released with the distribution, such as `kafka`. |

The `connector-template` requires exactly one of `released-distribution` and `timestamped-distribution`.

### Placeholders

The following placeholders are replaced in the file contents and the file and directory names.

| Placeholder | Value | Example (`aws.s3`) |
| --- | --- | --- |
| `{{MODULE_NAME_CC}}` | The module name with the first letter in lower case | `aws.s3` |
| `{{MODULE_NAME_PC}}` | The descriptive name if given, otherwise the module name with the first letter in upper case | `AWS S3` |
| `{{MODULE_PATH}}` | `{{MODULE_NAME_CC}}` with `.` replaced by `/`, used for the Java package directories | `aws/s3` |
| `{{MODULE_CLASS_PREFIX}}` | The PascalCase of the dot-separated module name segments, used for the Java class names | `AwsS3` |
| `{{REPO_NAME}}` | The repository name | `module-ballerinax-aws.s3` |
| `{{MODULE_VERSION}}` | The initial module version | `0.1.0` |
| `{{BAL_VERSION}}` | The Ballerina distribution version | `2201.12.0` |
| `{{LICENSE_YEAR}}` | The current year | `2026` |
| `{{CODEOWNERS}}` | The code owners | `@user1 @user2` |

The Java code of the native modules is in the `io.ballerina.lib.{{MODULE_NAME_CC}}` package, for example `native/src/main/java/io/ballerina/lib/aws/s3`.

## Apply a template with the workflow

Run the [Apply Library Repo Templates and Create PR](https://github.com/ballerina-platform/ballerina-library/actions/workflows/apply-library-repo-templates.yml) workflow with the following inputs. The repository must already exist in the `ballerina-platform` organization.

| Input | Description |
| --- | --- |
| `template_type` | The template to apply: `Library Template`, `Library Template (Native)`, `Connector Template`, or `Generated Connector Template (Standard)`. |
| `target_repo` | The name of the target repository, e.g. `module-ballerinax-aws.s3`. |
| `module_name` | The module name as defined in the `Ballerina.toml` file, e.g. `aws.s3`. |
| `ballerina_version` | The Ballerina distribution version, e.g. `2201.12.0`. |
| `module_version` | The initial module version. |
| `target_branch` | The base branch of the PR. |
| `library_name` | The descriptive name used in the documentation. Defaults to the module name. |
| `code_owners` | The code owners of the repository. |
| `distribution` | `Connector Template` only: `Released` enables `released-distribution` and `Timestamped` enables `timestamped-distribution`. |
| `compiler_plugin` | `Library Template (Native)` and `Connector Template` only: enables `compiler-plugin`. |

## Apply a template manually

### Prerequisites

* [Ballerina Swan Lake](https://ballerina.io/downloads/), to run the script.
* JDK 21, to build the generated repository.
* [Docker](https://www.docker.com/get-started), to build a `released-distribution` connector or a generated connector.
* A GitHub personal access token with the read package permissions, exported as `packageUser` and `packagePAT`.

### Generate the repository

Run the script from the root of this repository:

```bash
bal run repo-templates/scripts/apply_template.bal -- <template-dir> <target-dir> <module-name> <repo-name> <module-version> <ballerina-version> [--name=<descriptive-name>] [--codeOwners=<code-owners>] [--features=<comma-separated-features>]
```

The script copies the template files and the enabled feature overlays into a staging directory, replaces the placeholders there, and then copies the result into the target directory. The files already in the target directory, such as `.git`, are kept, and files with the same path are overwritten. The script fails on an unknown feature, a feature combination that the template does not allow, or an unresolved placeholder in a file or a file name.

Examples:

```bash
# Pure Ballerina library
bal run repo-templates/scripts/apply_template.bal -- repo-templates/library-template ../module-ballerina-math.vector math.vector module-ballerina-math.vector 0.1.0 2201.12.0 --name="Math Vector" --codeOwners="@user1"

# Library with native code and a compiler plugin
bal run repo-templates/scripts/apply_template.bal -- repo-templates/library-native-template ../module-ballerina-constraint constraint module-ballerina-constraint 0.1.0 2201.12.0 --codeOwners="@user1" --features=compiler-plugin

# Connector released independently of the distribution
bal run repo-templates/scripts/apply_template.bal -- repo-templates/connector-template ../module-ballerinax-aws.s3 aws.s3 module-ballerinax-aws.s3 0.1.0 2201.12.0 --name="AWS S3" --codeOwners="@user1" --features=released-distribution

# Connector released with the distribution, with a compiler plugin
bal run repo-templates/scripts/apply_template.bal -- repo-templates/connector-template ../module-ballerinax-kafka kafka module-ballerinax-kafka 0.1.0 2201.12.0 --codeOwners="@user1" --features=timestamped-distribution,compiler-plugin
```

Then build the generated repository to verify it:

```bash
cd <target-dir>
./gradlew clean build
```

The build commits the updated `Ballerina.toml` and `Dependencies.toml` files through the `commitTomlFiles` task when the target directory is a Git repository.

## After generating the repository

* Add the keywords and the icon in `build-config/resources/Ballerina.toml` and `ballerina/Ballerina.toml`, and fill the TODOs in the `README.md` and `ballerina/README.md` files, in `docs/spec/spec.md` for the libraries, and in `examples/README.md` for the connectors.
* Replace the sample `greet` function and its test with the actual API of the module.
* Add the Ballerina library dependencies as `ballerinaStdLibs` in the root `build.gradle`, with their versions in `gradle.properties`. The `released-distribution` connectors resolve their dependencies from the Ballerina Central instead.
* For the native modules, add the third-party jars to the `externalJars` configuration in `ballerina/build.gradle`, add them as `platform.java21.dependency` entries in `build-config/resources/Ballerina.toml`, and replace their version placeholders in the `updateTomlFiles` task. Add the Java dependencies of the native code to `native/build.gradle` and `native/src/main/java/module-info.java`.
* For the connectors, add the example packages to the `examples` directory. With `timestamped-distribution`, also add their paths to the `examples` list in `examples/build.gradle`. With `released-distribution`, the examples build is disabled until [ballerina-library#6135](https://github.com/ballerina-platform/ballerina-library/issues/6135) is fixed, as in the generated connector template.
* For the modules using the library workflow family, add the module to the Ballerina library dependency graph so that it is included in the release pipeline.
* Make sure that the repository has the secrets used by the workflows, such as `BALLERINA_BOT_TOKEN`, `BALLERINA_BOT_USERNAME`, `CODECOV_TOKEN` and the Ballerina Central access tokens, and enable the repository in Codecov.
* With `released-distribution` and `compiler-plugin`, keep `observeVersion` and `observeInternalVersion` in `gradle.properties` aligned with the distribution. The compiler plugin tests use them to add the observe packages to the `jballerina-tools` distribution.

## Authoring the templates

Each template directory has the following structure:

```
<template>/
  files/                 # The base files, always applied
  features/<feature>/    # Optional overlays, copied on top of the base files when the feature is enabled
  template.json          # Optional constraints on the features
```

The `exactlyOneOf` entry of `template.json` lists the groups of features of which exactly one must be enabled, such as the distribution features of the `connector-template`.

The content that depends on a feature is written between whole-line markers, which can be placed inside the comments of the file type:

```groovy
// {{#COMPILER_PLUGIN}}
include ':{{MODULE_NAME_CC}}-compiler-plugin'
// {{/COMPILER_PLUGIN}}
```

The marker name is the feature name in upper snake case. The lines between the markers are kept only when the feature is enabled, and the marker lines are always removed. The markers can be nested. The markers of a feature that a template does not have are treated as disabled.

To add a new placeholder, add it to the `placeholders` map in [`apply_template.bal`](scripts/apply_template.bal) and document it above. The script processes only the file types in `TemplateFileType`, and fails on a placeholder in any other file except the binary types in `BINARY_FILE_TYPES`, so add the extension there when adding a new type of text file. Verify the changes by generating a repository for each affected combination of features and building it.
