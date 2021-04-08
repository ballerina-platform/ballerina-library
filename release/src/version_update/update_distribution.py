import json
import sys
import os
import semver
from github import Github, GithubException, InputGitAuthor

HTTP_REQUEST_RETRIES = 3
HTTP_REQUEST_DELAY_IN_SECONDS = 2
HTTP_REQUEST_DELAY_MULTIPLIER = 2

packageUser =  os.environ["packageUser"]
packagePAT = os.environ["packagePAT"]
packageEmail =  os.environ["packageEmail"]

ORGANIZATION = "ballerina-platform"
STANDARD_LIBRARY = "stdlib"

MASTER_BRANCH = "master"
MAIN_BRANCH = "main"

VERSION_UPDATE_BRANCH_NAME = "automated/stdlib_version_update"
PULL_REQUEST_TITLE = "[Automated] Update Stdlib module versions"
PULL_REQUEST_BODY = "$subject"

PROPERTIES_FILE = "gradle.properties"

javaArraysModuleName = 'stdlibJavaArraysVersion'
OAuth2ModuleName = 'stdlibOAuth2Version'

SKIPPING_MODULES = ["kafka", "nats", "stan", "rabbitmq", "java.jdbc", "mysql", "serdes"]


def main():
    print("Checking Ballerina Distribution for stdlib version updates")
    module_list = get_stdlib_modules()
    repo = fetch_ballerina_distribution_repo()
    properties_file = fetch_properties_file(repo)
    current_versions = get_current_module_versions(properties_file)
    modified_properties_file, commit_flag, updated_modules = update_properties_file(properties_file, module_list, current_versions)
    if commit_flag:
        commit_changes(modified_properties_file, repo, updated_modules)
        create_pull_request(repo)
        print("Updated gradle.properties file in Ballerina Distribution Successfully")
    else:
        print("Stdlib versions in gradle.properties file are up to date")

# Get stdlib module details from stdlib_modules.json file
def get_stdlib_modules():
    try:
        with open('./release/resources/stdlib_modules.json') as f:
            module_list = json.load(f)
    except:
        print('Failed to read stdlib_modules.json')
        sys.exit()

    return module_list['modules']

# Fetch ballerina-distribution repository with GitHub credentials
def fetch_ballerina_distribution_repo():
    github = Github(packagePAT)
    try:
        repo = github.get_repo(ORGANIZATION + "/" + 'ballerina-distribution')
    except:
        print("Error fetching repository ballerina-distribution")

    return repo

# Fetch the gradle.properties file from the ballerina-distribution repo
def fetch_properties_file(repo):
    try:
        source = repo.get_branch(MAIN_BRANCH)
    except GithubException:
        source = repo.get_branch(MASTER_BRANCH)

    try:
        branch = repo.get_branch(branch=VERSION_UPDATE_BRANCH_NAME)
        repo.merge(VERSION_UPDATE_BRANCH_NAME, source.commit.sha, "Sync default branch")
        file = repo.get_contents(PROPERTIES_FILE, ref=VERSION_UPDATE_BRANCH_NAME)
    except GithubException:
        file = repo.get_contents(PROPERTIES_FILE)

    data = file.decoded_content.decode("utf-8")

    return data

# Get current versions of stdlib modules from gradle.properties file
def get_current_module_versions(properties_file):
    current_versions = {}

    for line in properties_file.splitlines():
        if STANDARD_LIBRARY in line and 'Version=' in line:
            module_name = line.split('=')[0]
            version = line.split('=')[1]
            current_versions[module_name] = version

    return current_versions

# Compare latest version with current version
# Return 1 if latest version > current version
# Return 0 if latest version = current version
# Return -1 if latest version < current version
def compare_version(latest_version, current_version):
    if semver.compare(latest_version.split('-')[0], current_version.split('-')[0]) == 1:
        return latest_version
    else:
        return latest_version

# Update stdlib module versions in the gradle.properties file with module details fetched from stdlib_modules.json
def update_properties_file(data, modules, current_versions):
    modified_data = ''
    updated_modules = []
    current_line = ''
    commit_flag = False

    line_list = data.splitlines()

    for line in line_list:
        if STANDARD_LIBRARY in line.lower():
            current_line = line
            break 
        line += '\n'
        modified_data += line
    modified_data = modified_data[0:-1]

    level = 1
    for module in modules:
        if module['level'] == level:
            line = "\n# Stdlib Level " + f"{level:02d}" + "\n"
            modified_data += line
            level += 1

        module_name = module['name'].split('-')[-1]
        latest_version = module['version']

        if module_name == 'jballerina.java.arrays':
            version = compare_version(latest_version, current_versions[javaArraysModuleName])
            line = javaArraysModuleName + "=" + version + "\n"
        elif module_name == 'oauth2':
            version = compare_version(latest_version, current_versions[OAuth2ModuleName])
            line = OAuth2ModuleName + "=" + version + "\n"
        elif module_name in SKIPPING_MODULES:
            continue
        else:
            module_name_in_naming_convention = STANDARD_LIBRARY + module_name.capitalize() + 'Version'
            if module_name_in_naming_convention in current_versions:
                version = compare_version(latest_version, current_versions[module_name_in_naming_convention])
            else:
                version = latest_version
            line = STANDARD_LIBRARY + module_name.capitalize() + "Version=" + version + "\n"

        if line[0:-1] not in line_list:
            updated_modules.append(module_name)
        modified_data += line

    for line in line_list[line_list.index(current_line):len(line_list)]:
        current_line = line
        if STANDARD_LIBRARY not in line.lower() and line != '':
            break

    modified_data += "\n"

    for line in line_list[line_list.index(current_line):len(line_list)]:
        if STANDARD_LIBRARY not in line.lower():
            line += "\n"
            modified_data += line

    # modified_data = modified_data[0:-1]
    if modified_data != data:
        commit_flag = True

    return modified_data, commit_flag, updated_modules

# Commit changes made to the gradle.properties file
def commit_changes(data, repo, updated_modules):
    author = InputGitAuthor(packageUser, packageEmail)

    # If branch already exists checkout and commit else create new branch from master branch and commit
    try:
        source = repo.get_branch(MAIN_BRANCH)
    except GithubException:
        source = repo.get_branch(MASTER_BRANCH)

    try:
        repo.get_branch(branch=VERSION_UPDATE_BRANCH_NAME)
        repo.merge(VERSION_UPDATE_BRANCH_NAME, source.commit.sha, "Sync default branch")
    except:
        repo.create_git_ref(ref=f"refs/heads/" + VERSION_UPDATE_BRANCH_NAME, sha=source.commit.sha)

    contents = repo.get_contents(PROPERTIES_FILE, ref=VERSION_UPDATE_BRANCH_NAME)

    if len(updated_modules) > 0:
        commit_message = "Bump the version of stdlib module(s) - "
        for updated_module in updated_modules:
            commit_message += updated_module
            commit_message += " "
    else:
        commit_message = "Update gradle.properties"

    repo.update_file(
        contents.path, 
        commit_message, 
        data, 
        contents.sha, 
        branch=VERSION_UPDATE_BRANCH_NAME, 
        author=author
    )

# Create a PR from the branch created
def create_pull_request(repo):
    pulls = repo.get_pulls(state='open', head=VERSION_UPDATE_BRANCH_NAME)

    pr_exists = 0

    # Check if a PR already exists for the module
    for pull in pulls:
        if PULL_REQUEST_TITLE in pull.title:
            pr_exists = pull.number

    # If PR doesn't exists create a new PR
    if pr_exists == 0:
        try:
            repo.create_pull(
                title=PULL_REQUEST_TITLE, 
                body=PULL_REQUEST_BODY, 
                head=VERSION_UPDATE_BRANCH_NAME, 
                base=MAIN_BRANCH
            )
        except GithubException:
            repo.create_pull(
                title=PULL_REQUEST_TITLE, 
                body=PULL_REQUEST_BODY, 
                head=VERSION_UPDATE_BRANCH_NAME, 
                base=MASTER_BRANCH
            )

main()
