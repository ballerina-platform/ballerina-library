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
    stdlibModuleNameList, latestVersions = getModuleListFromFile()
    updatedModuleDetails = initializeModuleDetails(latestVersions)
    updatedModuleDetails = getImmediateDependents(stdlibModuleNameList, updatedModuleDetails)
    updateFiles(updatedModuleDetails)


# Fetch the updated module versions and module name list from stdlib_latest_versions.json
def getModuleListFromFile():
    try:
        with open('./dependabot/resources/stdlib_latest_versions.json') as f:
            stdlibModuleList = json.load(f)
            modules = stdlibModuleList["modules"]
    except:
        print('Failed to read stdlib_latest_versions.json')
        sys.exit(1)
    
    stdlibModuleNameList = []
    latestVersions = []
    for module in modules:
        latestVersions.append(module)
        for key in module:
            stdlibModuleNameList.append(key)

    return stdlibModuleNameList, latestVersions


# Initialize a JSON with updated modules, latest version, and its dependents
def initializeModuleDetails(moduleList):
    updatedModuleDetails = {'modules':[]}

    for module in moduleList:
        for key, value in module.items():
            updatedModuleDetails['modules'].append({
                'name': key,
                'version': value,
                'dependents': [] })

    return updatedModuleDetails


# Fetch all the immediate dependents of modules with version upgrades and update the JSON
def getImmediateDependents(stdlibModules, updatedModuleDetails):
    for moduleName in stdlibModules:
        dependencies = getDependencies(moduleName)
        for module in updatedModuleDetails['modules']:
            if module['name'] in dependencies:
                updatedModuleDetails['modules'][updatedModuleDetails['modules'].index(module)]['dependents'].append(moduleName)

    return updatedModuleDetails


# Returns the file in the given url
# Retry decorator will retry the function 3 times, doubling the backoff delay if URLError is raised
@retry(
    urllib.error.URLError, 
    tries=HTTP_REQUEST_RETRIES, 
    delay=HTTP_REQUEST_DELAY_IN_SECONDS,
    backoff=HTTP_REQUEST_DELAY_MULTIPLIER
)
def urlOpenWithRetry(url):
    return urllib.request.urlopen(url)


# Get dependencies of a given ballerina standard library module from build.gradle file in module repository
# returns: list of dependencies
def getDependencies(balModule):
    try:
        data = urlOpenWithRetry("https://raw.githubusercontent.com/ballerina-platform/"
                                    + balModule + "/master/build.gradle")
    except:
        print('Failed to read build.gradle file of ' + balModule)
        sys.exit(1)

    dependencies = []

    for line in data:
        processedLine = line.decode("utf-8")
        if 'ballerina-platform/module' in processedLine:
            module = processedLine.split('/')[-1]
            if module[:-2] == balModule:
                continue
            dependencies.append(module[:-2])

    return dependencies


# Update the gradle.properties file of each dependent module stored in the dependents list of modules with version updates
def updateFiles(modules):
    for module in modules['modules']:
        for dependent in module['dependents']:
            print("Updating " + module['name'] + " version in " + dependent)
            # Fetch repository of the module
            repo = configureGithubRepository(dependent)
            # Fetch gradle.properties file
            data = fetchPropertiesFile(repo, module['name'])
            # Update the gradle.properties file with version updates
            updatedData, currentVersion, commitFlag = updatePropertiesFile(data, module['name'], module['version'])
            # If gradle.properties file is updated, commit changes and create PR
            if commitFlag:
                commitChanges(updatedData, currentVersion, repo, module['name'], module['version'])
                createPullRequest(repo, currentVersion, module['name'], module['version'])
                print("Bump " + module['name'] + " version from " + currentVersion + " to " + module['version'])
            else:
                print(module['name'] + " version is already the lastest version " + currentVersion)
                
            time.sleep(30)


# Fetch repository of a given stdlib module
def configureGithubRepository(module):
    github = Github(packagePAT)
    try:
        repo = github.get_repo(ORGANIZATION + "/" + module)
        return repo
    except:
        print("Error fetching repository " + module)
        sys.exit(1)


# Fetch gradle.properties file from a given repository
def fetchPropertiesFile(repo, module):
    try:
        branch = repo.get_branch(branch=DEPENDABOT_BRANCH_NAME)
        file = repo.get_contents(PROPERTIES_FILE, ref=DEPENDABOT_BRANCH_NAME)
    except GithubException:
        file = repo.get_contents(PROPERTIES_FILE)

    data = file.decoded_content.decode("utf-8")

    return data


# Update the version of a given module in the gradle.properties file
def updatePropertiesFile(data, module, latestVersion):
    modifiedData = ''
    commitFlag = False
    currentVersion = ''

    for line in data.splitlines():
        if 'stdlib' + module.split('-')[-1].capitalize() + 'Version' in line:
            currentVersion = line.split('=')[-1]
            # update only if the current version < latest version
            # TODO: RRemoving comparison temporarily
            # if compareVersion(latestVersion, currentVersion) == 1:
            modifiedLine = 'stdlib' + module.split('-')[-1].capitalize() + 'Version=' + latestVersion + "\n"
            modifiedData += modifiedLine
            commitFlag = True
        elif module.split('-')[-1] == 'oauth2' and 'stdlibOAuth2Version' in line:
            currentVersion = line.split('=')[-1]
            if compareVersion(latestVersion, currentVersion) == 1:
                modifiedLine = 'stdlibOAuth2Version=' + latestVersion + "\n"
                modifiedData += modifiedLine
                commitFlag = True
        else:
            modifiedLine = line + '\n'
            modifiedData += modifiedLine

    if currentVersion == '':
        print("Inconsistent module name: ", module)

    return modifiedData, currentVersion, commitFlag


# Compare latest version with current version
# Return 1 if latest version > current version
# Return 0 if latest version = current version
# Return -1 if latest version < current version
def compareVersion(latestVersion, currentVersion):
    return semver.compare(latestVersion, currentVersion)


# Checkout branch and commit changes
def commitChanges(data, currentVersion, repo, module, latestVersion):
    author = InputGitAuthor(packageUser, packageEmail)

    # If branch already exists checkout and commit else create new branch from master branch and commit
    try:
        source = repo.get_branch(MAIN_BRANCH)
    except GithubException:
        source = repo.get_branch(MASTER_BRANCH)

    try:
        repo.get_branch(branch=DEPENDABOT_BRANCH_NAME)
        repo.merge(DEPENDABOT_BRANCH_NAME, source.commit.sha, "Sync default branch")
    except:
        repo.create_git_ref(ref=f"refs/heads/" + DEPENDABOT_BRANCH_NAME, sha=source.commit.sha)

    contents = repo.get_contents(PROPERTIES_FILE, ref=DEPENDABOT_BRANCH_NAME)
    repo.update_file(
        contents.path,
        "[Automated] Bump " + module + " from " + currentVersion + " to " + latestVersion,
        data,
        contents.sha,
        branch=DEPENDABOT_BRANCH_NAME,
        author=author
    )


# Create a PR from the branch created
def createPullRequest(repo, currentVersion, module, latestVersion):
    pulls = repo.get_pulls(state='open', head=DEPENDABOT_BRANCH_NAME)
    prExists = 0

    # Check if a PR already exists for the module
    for pull in pulls:
        if PULL_REQUEST_TITLE in pull.title:
            prExists = pull.number

    # Create a new PR if PR doesn't exist
    if prExists == 0:
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
