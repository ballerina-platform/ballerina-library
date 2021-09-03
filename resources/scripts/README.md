# Standard Library Related Scripts

## Build Script
> File Name: build_standard_library.py

This script can be used to build the Ballerina Standard Library locally. It will build all the modules incrementally. 

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
| Skip Tests | Optional | Skip tests while building | `--skip-tests` |
| Keep Local Changes | Optional | If this is not set, the repo will be hard reset to the origin branch. All the local changes will be overridden. | `--keep-local-changes` |
| Build Specific Module | Optional | If the build needs to be done up to a particular module, this flag can be used. The script will build all the modules up to the specified module. | `--module <module_repo_full_name_as_in_github>` |
| Custom Module List | Optional | If a custom module list needed to be used, the path to the module list can be passed using this flag. If not provided, the default [stdlib_modules.json](https://raw.githubusercontent.com/ballerina-platform/ballerina-standard-library/main/release/resources/stdlib_modules.json) file will be used. | `--module-list /path/to/module/list.json` |

* Note: This script will only work with Python3. Some additional Python libraries may have to be downloaded before 
  running the script. If there are any missing libraries, script will fail and the error will show what libraries 
  are missing.

