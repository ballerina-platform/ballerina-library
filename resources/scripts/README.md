# Standard Library Related Scripts

## Build Script
> File Name: build_standard_library.py

This script can be used to build the Ballerina Standard Library locally. It will build all the modules incrementally.

If you already have cloned the standard library repos, you can provide the root directory of all the standard library
repos to the script, so it will use the cloned repos. If any of the required repository is not found, script will clone them
automatically to the provided location. This is a one time thing.

### Usage

#### Sample Usage
```shell
python build_standard_library.py /Users/ballerina/standard-library --branch automated/dependency_version_update --skip-tests --module module-ballerina-http
```

#### Flags

| Parameter | Type | Functionality | Sample Usage |
| :---: | :---: | :---: | :---: |
| Path | Mandatory | Provide the path to build the standard library modules. This will be the root directory, and if it is not found, it will be auto-created.| `python build_standard_library.py /path/to/stdlib/root/directory` |
| Lang Version | Optional | Provide a specific lang version to use in builds | `--lang-version <version>` |
| Branch | Optional | Provide a specific branch to build. This will try to build the specified branch in all the module repos. If not provided, the default branch will be used| `--branch <branch_name>` |
| Snapshot Build | Optional | To build and publish all the modules as SNAPSHOT versions locally. Then each depending module will use these SNAPSHOT versions as their dependencies. | `--snapshots-build` |
| Publish to local central | Optional | To publish all the modules to the local Ballerina central repo | `--publish-to-local-central` |
| Skip Tests | Optional | Skip tests while building | `--skip-tests` |
| Keep Local Changes | Optional | If this is not set, the repo will be hard reset to the origin branch. All the local changes will be overridden. | `--keep-local-changes` |
| Build up to a Specific Module | Optional | If the build needs to be done up to a particular module, this flag can be used. The script will build all the modules up to the specified module. | `--module <module_repo_full_name_as_in_github>` |
| Custom Module List | Optional | If a custom module list needed to be used, the path to the module list can be passed using this flag. If not provided, the default [stdlib_modules.json](https://raw.githubusercontent.com/ballerina-platform/ballerina-standard-library/main/release/resources/stdlib_modules.json) file will be used. | `--module-list /path/to/module/list.json` |
| Build the distribution | Optional | If provided, the ballerina-distribution repo will also be cloned and built. This is useful when a local lang change is needed and we need to check the distribution with it. Better to use this with `--snapshots-build` flag. | `--build-distribution` |
| Using custom commands | Optional | The script uses `./gradlew clean build` as the default command (with skip tests, and publish flags when required). If a custom command is needed to be executed inside each repo, it can be provided using this flag | `--commands "./gradlew clean"` |
| Skip Modules | Optional | To skip modules from building. The argument should be a comma separated list or a common word for the modules. Eg.: "nats, stan" or "ballerinax" | `--skip-modules <comma separated list of modules or a common string>` |

> Note: This script will only work with Python3. Some additional Python libraries may have to be downloaded before
  running the script. If there are any missing libraries, script will fail and the error will show what libraries
  are missing.


#### To Test the Affect of a Local Lang Change
* Do the lang change and build it, and publish it to the local maven repository. Executing the following command 
  inside the `ballerina-lang` clone will publish the `SNAPSHOT` version of the language to the local maven repository.
  ```shell
  ./gradlew build publishToMavenLocal
  ```

* Then run the script with the `--lang-version <lang-snapshot-version>` flag. This will replace the
  `ballerinaLangVersion` entry in every `gradle.properties` file of the standard library module when building them. 
  For example, the following command will build the standard library repos using the `2.0.0-SNAPSHOT` version of the 
  lang.
    ```shell
    python build_standard_library.py /Users/ballerina/standard-library --lang-version 2.0.0-SNAPSHOT
    ```

* When building the distribution, the ballerinax modules may not be needed to be built. They can be skipped using
  the `--skip-modules` flag.
  ```shell
    python build_standard_library.py /Users/ballerina/standard-library --skip-modules "ballerinax"
    ```
  Alternatively, a set of modules can be skipped by providing the list of names:
    ```shell
    python build_standard_library.py /Users/ballerina/standard-library --skip-modules "nats, stan, kafka, rabbitmq"
    ```

* If you want to use the `SNAPSHOT` versions of the standard library modules to be used in the upper level modules, use
  `--snapshots-build` flag. This will publish all the standard library modules to the local maven repository, and
  replace the timestamp versions of the standard library module versions to SNAPSHOT versions in the `gradle.properties`
  files.
    ```shell
    python build_standard_library.py /Users/ballerina/standard-library --snapshots-build
    ```

* If you want to build a distribution pack on top of these changes, use `--build-distribution` flag. Example:
  ```shell
  python build_standard_library.py /Users/ballerina/standard-library --build-distribution
  ```

* A complete example could be as follows:
    ```shell
    python build_standard_library.py /Users/ballerina/standard-library --snapshots-build --build-distribution --lang-version 2.0.0-SNAPSHOT --skip-modules "ballerinax" --publish-to-local-central
    ```
