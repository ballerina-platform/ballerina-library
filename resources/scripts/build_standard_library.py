import argparse
import json
import os
import re
import subprocess
import sys
import urllib.request

from pathlib import Path

MODULE_LIST = "https://raw.githubusercontent.com/ballerina-platform/ballerina-standard-library/main/release/resources/stdlib_modules.json"

# Module Fields
FIELD_BRANCH = "branch"
FIELD_DEFAULT_BRANCH = "default_branch"
FIELD_NAME = "name"
FIELD_KEEP_LOCAL_CHANGES = "keep_local_changes"

# File Names
TEMP_PROPERTIES = "temp.properties"
GRADLE_PROPERTIES = "gradle.properties"

# Argument Parser
parser = argparse.ArgumentParser(description='Incrementally Build the Ballerina Standard Library')

# Mandatory Arguments
parser.add_argument('path', help='Path to the directory where the standard library modules are (need to be) cloned')

# Optional arguments
parser.add_argument('--lang-version', help='Ballerina language version to use for the builds')
parser.add_argument('--branch', help='Branch to build. (Build will fail if the branch not found')
parser.add_argument('--snapshots-build', action="store_true", help="Replace all the standard library dependent versions with 'SNAPSHOT' versions. This is helpfull to incrementally build libraries on top of a local change")
parser.add_argument('--publish-to-local-central', action="store_true", help="Publish all the modules to the local ballerina central repository")
parser.add_argument('--skip-tests', action="store_true", help="Skip tests in the builds")
parser.add_argument('--keep-local-changes', action="store_true", help="Stop updating the repos from the origin. Keep the local changes")
parser.add_argument('--module', help="Build up to the specified module")
parser.add_argument('--module-list', help="Path to the module list JSON file. If not provided, the existing 'stdlib_modules.json' from the GitHub will be used")


def main():
    global MODULE_LIST

    args = parser.parse_args()

    commands = ["./gradlew", "clean", "build"]
    lang_version = None
    branch = None
    use_snapshots = False
    keep_local_changes = False
    required_module = None

    print_block()
    print_info("Building Standard Library Modules")

    if not os.path.isdir(args.path):
        print_info("Provided standard library module root directory does not exist. Creating the directory and cloning the repositories")
        create_directory(args.path)

    os.chdir(args.path)

    if args.lang_version:
        print_info("Using ballerina lang version: " + args.lang_version)
        lang_version = args.lang_version

    if args.branch:
        print_info("Building the branch: " + args.branch)
        branch = args.branch
    else:
        print_info("Using default branchs of the repos")

    if args.snapshots_build:
        print_info("Using local SNAPSHOT builds for upper level dependencies")
        commands.append("publishToMavenLocal")
        use_snapshots = True
    else:
        print_info("Using existing timestamp versions for the builds")

    if args.publish_to_local_central:
        print_info("Pushing all the modules to local ballerina central repository")
        commands.append("-PpublishToLocalCentral=true")

    if args.skip_tests:
        print_info("Skipping tests")
        commands.append("-x")
        commands.append("test")

    if args.keep_local_changes:
        print_info("Not updating the local repos.")
        keep_local_changes = True
    else:
        print_info("Updating all the repos. Any local change will be overridden")

    if args.module_list:
        if os.path.isfile(args.module_list):
            print_info("Using provided custom module list JSON file")
            MODULE_LIST = args.module_list
        else:
            print_error("Invalid module list file provided")
    else:
        print_info("Using default module list JSON file from: " + MODULE_LIST)

    module_list = get_stdlib_module_list()

    if args.module:
        required_module = get_required_module(args.module, module_list)

    for module in module_list:
        module[FIELD_BRANCH] = branch if branch else module[FIELD_DEFAULT_BRANCH]
        module[FIELD_KEEP_LOCAL_CHANGES] = keep_local_changes
        process_module(module, commands, lang_version, use_snapshots)
        if module[FIELD_NAME] == required_module:
            exit(0)


def process_module(module, commands, lang_version, use_snapshots):
    print_block()
    print_info("Building: " + module[FIELD_NAME])
    print_info("Branch: " + module[FIELD_BRANCH])
    print_block()

    if not os.path.exists(module[FIELD_NAME]):
        clone_module(module[FIELD_NAME])

    os.chdir(module[FIELD_NAME])

    if not module[FIELD_KEEP_LOCAL_CHANGES]:
        checkout_branch(module[FIELD_BRANCH], module[FIELD_DEFAULT_BRANCH])

    if lang_version:
        replace_lang_version(lang_version)

    if use_snapshots:
        replace_stdlibs_version()

    subprocess.run(commands)

    os.chdir("..")


def replace_lang_version(version):
    with open(TEMP_PROPERTIES, "w+") as temp, open(GRADLE_PROPERTIES) as properties:
        for line in properties:
            if "ballerinaLangVersion" in line:
                line = "ballerinaLangVersion="+version+"\n"
            temp.write(line)

    os.replace(TEMP_PROPERTIES, GRADLE_PROPERTIES)


def replace_stdlibs_version():
    with open(TEMP_PROPERTIES, "w+") as temp, open(GRADLE_PROPERTIES) as properties:
        for line in properties:
            if re.match("^stdlib.*Version=", line):
                version_string = line.split("=")[0]
                version_number = line.split("=")[1].split("-")[0]
                line = version_string + "=" + version_number + "-SNAPSHOT" + "\n"
            temp.write(line)

    os.replace(TEMP_PROPERTIES, GRADLE_PROPERTIES)


def clone_module(module_link):
    print_info("Cloning Module: " + module_link)
    repo_path = "https://www.github.com/ballerina-platform/" + module_link + ".git"
    subprocess.run(["git", "clone", repo_path])


def get_required_module(module_name, module_list):
    module_names = [module[FIELD_NAME] for module in module_list]
    if module_name in module_names:
        print_info("Building up to the module: " + module_name)
        return module_name
    else:
        print_error("Module not found in the list: " + module_name)


def checkout_branch(branch, keep_local_changes):
    try:
        subprocess.run(["git", "checkout", branch])
        if not keep_local_changes:
            subprocess.run(["git", "reset", "--hard", "origin/" + branch])
        subprocess.run(["git", "pull", "origin", branch])

    except Exception as e:
        print("Failed to Sync the Default Branch: " + str(e))


def create_directory(directory_name):
    Path(directory_name).mkdir(parents=True, exist_ok=True)


def get_stdlib_module_list():
    try:
        data = open_file_from_url(MODULE_LIST)
        module_list = json.load(data)

        return module_list["modules"]
    except Exception as e:
        print("Failed to read the module list JSON file: " + str(e))
        sys.exit()


def open_file_from_url(url):
    return urllib.request.urlopen(url)


def print_info(message):
    print("[INFO] " + message)


def print_error(message):
    print("[ERROR] " + message)
    sys.exit(1)


def print_block():
    print()
    print("##############################################")
    print()

main()
