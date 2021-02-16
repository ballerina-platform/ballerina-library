import urllib.request
import json
import sys
from retry import retry
import os
import semver
import time
from github import Github, InputGitAuthor, GithubException

HTTP_REQUEST_RETRIES = 3
HTTP_REQUEST_DELAY_IN_SECONDS = 2
HTTP_REQUEST_DELAY_MULTIPLIER = 2

packageUser =  os.environ["packageUser"]
packagePAT = os.environ["packagePAT"]
packageEmail =  os.environ["packageEmail"]

ORGANIZATION = "ballerina-platform"

MASTER_BRANCH = "master"
MAIN_BRANCH = "main"

DEPENDABOT_BRANCH_NAME = "automated/stdlib_version_update"
PULL_REQUEST_TITLE = "[Automated] Bump stdlib module versions"
PULL_REQUEST_BODY = "$subject"

PROPERTIES_FILE = "gradle.properties"

def main():
    stdlib_module_name_list, latest_versions = get_module_list_from_file()
    updated_module_details = initialize_module_details(latest_versions)
    updated_module_details = get_immediate_dependents(stdlib_module_name_list, updated_module_details)
    update_files(updated_module_details)


# Fetch the updated module versions and module name list from stdlib_latest_versions.json
def get_module_list_from_file():
    try:
        with open('./dependabot/resources/stdlib_latest_versions.json') as f:
            stdlib_module_list = json.load(f)
            modules = stdlib_module_list["modules"]
    except:
        print('Failed to read stdlib_latest_versions.json')
        sys.exit(1)
    
    stdlib_module_name_list = []
    latest_versions = []
    for module in modules:
        latest_versions.append(module)
        for key in module:
            stdlib_module_name_list.append(key)

    return stdlib_module_name_list, latest_versions


# Initialize a JSON with updated modules, latest version, and its dependents
def initialize_module_details(module_list):
    updated_module_details = {'modules':[]}

    for module in module_list:
        for key, value in module.items():
            updated_module_details['modules'].append({
                'name': key,
                'version': value,
                'dependents': [] })

    return updated_module_details


# Fetch all the immediate dependents of modules with version upgrades and update the JSON
def get_immediate_dependents(stdlib_modules, updated_module_details):
    for module_name in stdlib_modules:
        dependencies = get_dependencies(module_name)
        for module in updated_module_details['modules']:
            if module['name'] in dependencies:
                updated_module_details['modules'][updated_module_details['modules'].index(module)]['dependents'].append(module_name)

    return updated_module_details


# Returns the file in the given url
# Retry decorator will retry the function 3 times, doubling the backoff delay if URLError is raised
@retry(
    urllib.error.URLError, 
    tries=HTTP_REQUEST_RETRIES, 
    delay=HTTP_REQUEST_DELAY_IN_SECONDS,
    backoff=HTTP_REQUEST_DELAY_MULTIPLIER
)
def url_open_with_retry(url):
    return urllib.request.urlopen(url)


# Get dependencies of a given ballerina standard library module from build.gradle file in module repository
# returns: list of dependencies
def get_dependencies(module_name):
    try:
        data = url_open_with_retry("https://raw.githubusercontent.com/ballerina-platform/"
                                    + module_name + "/master/build.gradle")
    except:
        print('Failed to read build.gradle file of ' + module_name)
        sys.exit(1)

    dependencies = []

    for line in data:
        processed_line = line.decode("utf-8")
        if 'ballerina-platform/module' in processed_line:
            module = processed_line.split('/')[-1]
            if module[:-2] == module_name:
                continue
            dependencies.append(module[:-2])

    return dependencies


# Update the gradle.properties file of each dependent module stored in the dependents list of modules with version updates
def update_files(modules):
    for module in modules['modules']:
        print("Updating dependents of " + module)
        for dependent in module['dependents']:
            # Fetch repository of the module
            repo = configure_github_repository(dependent)
            # Fetch gradle.properties file
            data = fetch_properties_file(repo, module['name'])
            # Update the gradle.properties file with version updates
            updated_data, current_version, commit_flag = update_properties_file(data, module['name'], module['version'])
            # If gradle.properties file is updated, commit changes and create PR
            if commit_flag:
                try:
                    commit_changes(updated_data, current_version, repo, module['name'], module['version'])
                    create_pull_request(repo, current_version, module['name'], module['version'])
                    print("Bump " + module['name'] + " version from " + current_version + " to " + module['version'])
                except:
                    continue
            else:
                print(module['name'] + " version is already the lastest version " + current_version)
        print("-------------------------------------------------------------------------------------")        
            time.sleep(30)


# Fetch repository of a given stdlib module
def configure_github_repository(module):
    github = Github(packagePAT)
    try:
        repo = github.get_repo(ORGANIZATION + "/" + module)
        return repo
    except:
        print("Error fetching repository " + module)
        sys.exit(1)


# Fetch gradle.properties file from a given repository
def fetch_properties_file(repo, module):
    try:
        branch = repo.get_branch(branch=DEPENDABOT_BRANCH_NAME)
        file = repo.get_contents(PROPERTIES_FILE, ref=DEPENDABOT_BRANCH_NAME)
    except GithubException:
        file = repo.get_contents(PROPERTIES_FILE)

    data = file.decoded_content.decode("utf-8")

    return data


# Update the version of a given module in the gradle.properties file
def update_properties_file(data, module, latest_version):
    modified_data = ''
    commit_flag = False
    current_version = ''

    for line in data.splitlines():
        if 'stdlib' + module.split('-')[-1].capitalize() + 'Version' in line:
            current_version = line.split('=')[-1]
            # update only if the current version < latest version
            # TODO: RRemoving comparison temporarily
            # if compare_version(latest_version, current_version) == 1:
            if latest_version != current_version:
                modified_line = 'stdlib' + module.split('-')[-1].capitalize() + 'Version=' + latest_version + "\n"
                modified_data += modified_line
                commit_flag = True
        elif module.split('-')[-1] == 'oauth2' and 'stdlibOAuth2Version' in line:
            current_version = line.split('=')[-1]
            # if compare_version(latest_version, current_version) == 1:
            if latest_version != current_version:
                modified_line = 'stdlibOAuth2Version=' + latest_version + "\n"
                modified_data += modified_line
                commit_flag = True
        else:
            modified_line = line + '\n'
            modified_data += modified_line

    if current_version == '':
        print("Inconsistent module name: ", module)

    return modified_data, current_version, commit_flag


# Compare latest version with current version
# Return 1 if latest version > current version
# Return 0 if latest version = current version
# Return -1 if latest version < current version
def compare_version(latest_version, current_version):
    return semver.compare(latest_version, current_version)


# Checkout branch and commit changes
def commit_changes(data, current_version, repo, module, latest_version):
    author = InputGitAuthor(packageUser, packageEmail)

    # If branch already exists checkout and commit else create new branch from master branch and commit
    try:
        source = repo.get_branch(MAIN_BRANCH)
    except GithubException:
        source = repo.get_branch(MASTER_BRANCH)

    try:
        repo.get_branch(branch=DEPENDABOT_BRANCH_NAME)
        try:
            repo.merge(DEPENDABOT_BRANCH_NAME, source.commit.sha, "Sync default branch")
        except Exception as e:
            print(e)
    except:
        repo.create_git_ref(ref=f"refs/heads/" + DEPENDABOT_BRANCH_NAME, sha=source.commit.sha)

    contents = repo.get_contents(PROPERTIES_FILE, ref=DEPENDABOT_BRANCH_NAME)
    repo.update_file(
        contents.path,
        "[Automated] Bump " + module + " from " + current_version + " to " + latest_version,
        data,
        contents.sha,
        branch=DEPENDABOT_BRANCH_NAME,
        author=author
    )


# Create a PR from the branch created
def create_pull_request(repo, current_version, module, latest_version):
    pulls = repo.get_pulls(state='open', head=DEPENDABOT_BRANCH_NAME)
    pr_exists = 0

    # Check if a PR already exists for the module
    for pull in pulls:
        if PULL_REQUEST_TITLE in pull.title:
            pr_exists = pull.number

    # Create a new PR if PR doesn't exist
    if pr_exists == 0:
        try:
            repo.create_pull(
                title=PULL_REQUEST_TITLE,
                body=PULL_REQUEST_BODY,
                head=DEPENDABOT_BRANCH_NAME,
                base=MAIN_BRANCH
            )
        except GithubException:
            repo.create_pull(
                title=PULL_REQUEST_TITLE,
                body=PULL_REQUEST_BODY,
                head=DEPENDABOT_BRANCH_NAME,
                base=MASTER_BRANCH
            )


main()
