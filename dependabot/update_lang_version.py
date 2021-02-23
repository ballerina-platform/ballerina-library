from github import Github, InputGitAuthor, GithubException
import json
import os
from retry import retry
import sys
import time
import urllib.request

HTTP_REQUEST_RETRIES = 3
HTTP_REQUEST_DELAY_IN_SECONDS = 2
HTTP_REQUEST_DELAY_MULTIPLIER = 2

ORGANIZATION = "ballerina-platform"
LANG_VERSION_KEY = "ballerinaLangVersion"
VERSION_KEY = "version="

LANG_VERSION_UPDATE_BRANCH = 'automated/stdlib_version_update'
MASTER_BRANCH = "master"
MAIN_BRANCH = "main"

packageUser = os.environ["packageUser"]
packagePAT = os.environ["packagePAT"]
packageEmail = os.environ["packageEmail"]

ENCODING = "utf-8"

OPEN = "open"
MODULES = "modules"

COMMIT_MESSAGE_PREFIX = "[Automated] Update lang version to "
PULL_REQUEST_BODY_PREFIX = "Update ballerina lang version to `"
PULL_REQUEST_TITLE = "[Automated] Dependency Update"

MODULE_LIST_FILE = "release/resources/module_list.json"
BALLERINA_DISTRIBUTION = "ballerina-distribution"
PROPERTIES_FILE = "gradle.properties"


def main():
    lang_version = get_lang_version()
    module_list_json = get_module_list_json()
    check_and_update_lang_version(module_list_json, lang_version)


def get_lang_version():
    try:
        properties = open_url(
            "https://raw.githubusercontent.com/ballerina-platform/ballerina-lang/master/gradle.properties")
    except Exception as e:
        print('Failed to gradle.properties file in ballerina-lang' + e)
        sys.exit(1)

    for line in properties:
        line = line.decode(ENCODING).strip()
        if line.startswith(VERSION_KEY):
            return line.split("=")[-1]


@retry(
    urllib.error.URLError,
    tries=HTTP_REQUEST_RETRIES,
    delay=HTTP_REQUEST_DELAY_IN_SECONDS,
    backoff=HTTP_REQUEST_DELAY_MULTIPLIER
)
def open_url(url):
    return urllib.request.urlopen(url)


def get_module_list_json():
    try:
        with open(MODULE_LIST_FILE) as f:
            module_list = json.load(f)

    except Exception as e:
        print(e)
        sys.exit(1)

    # Append ballerina distribution to the list to update the lang version
    module_list[MODULES].append(BALLERINA_DISTRIBUTION)
    return module_list


def check_and_update_lang_version(module_list_json, lang_version):
    for module_name in module_list_json[MODULES]:
        update_module(module_name, lang_version)


def update_module(module_name, lang_version):
    github = Github(packagePAT)
    repo = github.get_repo(ORGANIZATION + "/" + module_name)
    try:
        properties_file = repo.get_contents(PROPERTIES_FILE, ref=LANG_VERSION_UPDATE_BRANCH)
    except:
        properties_file = repo.get_contents(PROPERTIES_FILE)

    properties_file = properties_file.decoded_content.decode(ENCODING)
    update, updated_properties_file = get_updated_properties_file(module_name, properties_file, lang_version)
    if update:
        commit_changes(repo, updated_properties_file, lang_version)
        create_pull_request(repo, lang_version)
        time.sleep(30)


def get_updated_properties_file(module_name, properties_file, lang_version):
    updated_properties_file = ""
    update = False

    for line in properties_file.splitlines():
        if line.startswith(LANG_VERSION_KEY):
            current_version = line.split("=")[-1]
            if current_version != lang_version:
                print("[Info] Updating the lang version in module: \"" + module_name + "\"")
                updated_properties_file += LANG_VERSION_KEY + "=" + lang_version + "\n"
                update = True
            else:
                updated_properties_file += line + "\n"
        else:
            updated_properties_file += line + "\n"

    return update, updated_properties_file


def commit_changes(repo, updated_file, lang_version):
    author = InputGitAuthor(packageUser, packageEmail)
    try:
        base = repo.get_branch(MASTER_BRANCH)
    except:
        base = repo.get_branch(MAIN_BRANCH)

    try:
        ref = f"refs/heads/" + LANG_VERSION_UPDATE_BRANCH
        repo.create_git_ref(ref=ref, sha=base.commit.sha)
    except :
        try:
            repo.get_branch(LANG_VERSION_UPDATE_BRANCH)
            repo.merge(LANG_VERSION_UPDATE_BRANCH, base.commit.sha, "Sync default branch")
        except GithubException as e:
            print("Error occurred: " + e)


    current_file = repo.get_contents(PROPERTIES_FILE, ref=LANG_VERSION_UPDATE_BRANCH)
    repo.update_file(
        current_file.path,
        COMMIT_MESSAGE_PREFIX + lang_version,
        updated_file,
        current_file.sha,
        branch=LANG_VERSION_UPDATE_BRANCH,
        author=author
    )


def create_pull_request(repo, lang_version):
    pulls = repo.get_pulls(state=OPEN, head=LANG_VERSION_UPDATE_BRANCH)
    pr_exists = False

    for pull in pulls:
        if PULL_REQUEST_TITLE in pull.title:
            pr_exists = True

    if not pr_exists:
        try:
            repo.create_pull(
                title=PULL_REQUEST_TITLE,
                body=PULL_REQUEST_BODY_PREFIX + lang_version + "`",
                head=LANG_VERSION_UPDATE_BRANCH,
                base=MASTER_BRANCH
            )
        except:
            repo.create_pull(
                title=PULL_REQUEST_TITLE,
                body=PULL_REQUEST_BODY_PREFIX + lang_version + "`",
                head=LANG_VERSION_UPDATE_BRANCH,
                base=MAIN_BRANCH
            )


main()
