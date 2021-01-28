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
organization = 'ballerina-platform'
dependabotBranchName = 'stdlib-dependabot'

def main():
    modulesWithVersionUpdates = preprocessString()
    stdlibModules = getModuleListFromFile()
    updatedModuleDetails = initializeModuleDetails(modulesWithVersionUpdates)
    updatedModuleDetails = getImmediateDependents(stdlibModules, updatedModuleDetails)
    updateFiles(updatedModuleDetails)

# Fetch the updated module versions string from the environment and append it to an array
def preprocessString():
    try:
        # String is in the form -> '"module": "version" "module": "version"'
        updatedModules = os.environ["modules"].split()

        latestVersion = []
        for i in range(0, len(updatedModules)-1, 2):
            latestVersion.append(updatedModules[i][1:-2] + ':' + updatedModules[i+1][1:-1]) 

        # Processed string -> ["module:version", ",module:version"]
        print("Modules with version updates: ", latestVersion)
        return latestVersion
    except:
        print("Failed to update files")
        print("Input String: " + os.environ["modules"])
        sys.exit(1)

# Fetch list of stdlib modules from stdlib_latest_versions.json 
def getModuleListFromFile():
    try:
        with open('./dependabot/resources/stdlib_latest_versions.json') as f:
            moduleList = json.load(f)
    except:
        print('Failed to read stdlib_latest_versions.json')
        sys.exit(1)

    stdlibModules = []
    for module in moduleList['modules']:
        for key in module:
            stdlibModules.append(key)
        
    return stdlibModules

# Initialize a JSON with updated modules, latest version, and its dependents
def initializeModuleDetails(moduleList):
    updatedModuleDetails = {'modules':[]}

    for module in moduleList:						
        updatedModuleDetails['modules'].append({
            'name': module.split(':')[0], 
            'version':module.split(':')[-1],
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
@retry(urllib.error.URLError, tries=HTTP_REQUEST_RETRIES, delay=HTTP_REQUEST_DELAY_IN_SECONDS, 
                                    backoff=HTTP_REQUEST_DELAY_MULTIPLIER)
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
            time.sleep(30)

# Fetch repository of a given stdlib module
def configureGithubRepository(module):
    github = Github(packagePAT)
    try:
        repo = github.get_repo(organization + "/" + module)
    except:
        print("Error fetching repository " + module)

    return repo

# Fetch gradle.properties file from a given repository
def fetchPropertiesFile(repo, module):
    try:
        branch = repo.get_branch(branch=dependabotBranchName)
        file = repo.get_contents("gradle.properties", ref=dependabotBranchName)
    except GithubException:
        file = repo.get_contents("gradle.properties")

    data = file.decoded_content.decode("utf-8")

    return data

# Update the version of a given module in the gradle.properties file
def updatePropertiesFile(data, module, latestVersion):
    modifiedData = ''
    commitFlag = False
    currentVersion = ''

    for line in data.splitlines():
        if 'stdlib' + module.split('-')[-1].capitalize() + 'Version' in line:
            currentVersion = line.split('=')[-1].split('-')[0]
            # update only if the current version < latest version
            if compareVersion(latestVersion, currentVersion) == 1:
                if 'SNAPSHOT' in line:
                    modifiedLine = 'stdlib' + module.split('-')[-1].capitalize() + 'Version=' + latestVersion + "-SNAPSHOT\n"
                else:
                    modifiedLine = 'stdlib' + module.split('-')[-1].capitalize() + 'Version=' + latestVersion + "\n"
                modifiedData += modifiedLine
                commitFlag = True
        elif module.split('-')[-1] == 'oauth2' and 'stdlibOAuth2Version' in line:
            currentVersion = line.split('=')[-1].split('-')[0]
            if compareVersion(latestVersion, currentVersion) == 1:
                if 'SNAPSHOT' in line:
                    modifiedLine = 'stdlibOAuth2Version=' + latestVersion + "-SNAPSHOT\n"
                else:
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
        source = repo.get_branch(branch=dependabotBranchName)
    except GithubException:
        try:
            source = repo.get_branch("main")
        except GithubException:
            source = repo.get_branch("master")

        repo.create_git_ref(ref=f"refs/heads/" + dependabotBranchName, sha=source.commit.sha)

    contents = repo.get_contents("gradle.properties", ref=dependabotBranchName)
    repo.update_file(contents.path, 
                    "[Automated] Bump " + module + " from " + currentVersion + " to " + latestVersion, 
                    data, 
                    contents.sha, 
                    branch=dependabotBranchName, 
                    author=author)

# Create a PR from the branch created
def createPullRequest(repo, currentVersion, module, latestVersion):
    pulls = repo.get_pulls(state='open', head=dependabotBranchName)
    prExists = 0

    # Check if a PR already exists for the module
    for pull in pulls:
        if "Bump stdlib module versions" in pull.title:
            prExists = pull.number

    # Create a new PR if PR doesn't exist
    if prExists == 0:
        try:
            repo.create_pull(title="Bump stdlib module versions", 
                            body='$subject', 
                            head=dependabotBranchName, 
                            base="main")
        except GithubException:
            repo.create_pull(title="Bump stdlib module versions", 
                            body='$subject', 
                            head=dependabotBranchName, 
                            base="master")

main()
