import urllib.request
import json
import sys
import os
import semver
from retry import retry
from github import Github, GithubException, InputGitAuthor

HTTP_REQUEST_RETRIES = 3
HTTP_REQUEST_DELAY_IN_SECONDS = 2
HTTP_REQUEST_DELAY_MULTIPLIER = 2
packageUser =  os.environ["packageUser"]
packagePAT = os.environ["packagePAT"]
packageEmail =  os.environ["packageEmail"]
organization = 'ballerina-platform'
standardLibrary = 'stdlib'
versionUpdateBranchName = 'automated/stdlib_version_update'
pullRequestTitle = '[Automated] Update Stdlib module versions'

javaArraysModuleName = 'stdlibJavaArraysVersion'
javaJdbcModuleName = 'stdlibJdbcVersion'
OAuth2ModuleName = 'stdlibOAuth2Version'


def main():
    print("Checking Ballerina Distribution for stdlib version updates")
    moduleList = getStdlibModules()
    repo = fetchBallerinaDistributionRepo()
    propertiesFile = fetchPropertiesFile(repo)
    currentVersions = getCurrentModuleVersions(propertiesFile)
    modifiedPropertiesFile, commitFlag, updatedModules = updatePropertiesFile(propertiesFile, moduleList, currentVersions)
    if commitFlag:
        commitChanges(modifiedPropertiesFile, repo, updatedModules)
        createPullRequest(repo)
        print("Updated gradle.properties file in Ballerina Distribution Successfully")
    else:
        print("Stdlib versions in gradle.properties file are up to date")

# Get stdlib module details from stdlib_modules.json file
def getStdlibModules():
    try:
        with open('./release/resources/stdlib_modules.json') as f:
            moduleList = json.load(f)
    except:
        print('Failed to read stdlib_modules.json')
        sys.exit()

    return moduleList['modules']

# Fetch ballerina-distribution repository with GitHub credentials
def fetchBallerinaDistributionRepo():
    github = Github(packagePAT)
    try:
        repo = github.get_repo(organization + "/" + 'ballerina-distribution')
    except:
        print("Error fetching repository ballerina-distribution")

    return repo

# Fetch the gradle.properties file from the ballerina-distribution repo
def fetchPropertiesFile(repo):
    try:
        source = repo.get_branch("main")
    except GithubException:
        source = repo.get_branch("master")

    try:
        branch = repo.get_branch(branch=versionUpdateBranchName)
        repo.merge(versionUpdateBranchName, source.commit.sha, "Sync default branch")
        file = repo.get_contents("gradle.properties", ref=versionUpdateBranchName)
    except GithubException:
        file = repo.get_contents("gradle.properties")

    data = file.decoded_content.decode("utf-8")

    return data

# Get current versions of stdlib modules from gradle.properties file
def getCurrentModuleVersions(propertiesFile):
    currentVersions = {}

    for line in propertiesFile.splitlines():
        if standardLibrary in line and 'Version=' in line:
            moduleName = line.split('=')[0]
            version = line.split('=')[1]
            currentVersions[moduleName] = version

    return currentVersions

# Compare latest version with current version
# Return 1 if latest version > current version
# Return 0 if latest version = current version
# Return -1 if latest version < current version
def compareVersion(latestVersion, currentVersion):
    if semver.compare(latestVersion.split('-')[0], currentVersion.split('-')[0]) == 1:
        return latestVersion
    else:
        return currentVersion

# Update stdlib module versions in the gradle.properties file with module details fetched from stdlib_modules.json
def updatePropertiesFile(data, modules, currentVersions):
    modifiedData = ''
    updatedModules = []
    currentLine = ''
    commitFlag = False

    lineList = data.splitlines()

    for line in lineList:
        if standardLibrary in line.lower():
            currentLine = line
            break 
        line += '\n'
        modifiedData += line
    modifiedData = modifiedData[0:-1]

    level = 1
    for module in modules:
        if module['level'] == level:
            line = "\n# Stdlib Level " + f"{level:02d}" + "\n"
            modifiedData += line
            level += 1

        moduleName = module['name'].split('-')[-1]
        latestVersion = module['version']

        if moduleName == 'java.arrays':
            version = compareVersion(latestVersion, currentVersions[javaArraysModuleName])
            line = javaArraysModuleName + "=" + version + "\n"
        elif moduleName == 'java.jdbc':
            version = compareVersion(latestVersion, currentVersions[javaJdbcModuleName])
            line = javaJdbcModuleName + "=" + version + "\n"
        elif moduleName == 'oauth2':
            version = compareVersion(latestVersion, currentVersions[OAuth2ModuleName])
            line = OAuth2ModuleName + "=" + version + "\n"
        else:
            moduleNameInNamingConvention = standardLibrary + moduleName.capitalize() + 'Version'
            if moduleNameInNamingConvention in currentVersions:
                version = compareVersion(latestVersion, currentVersions[moduleNameInNamingConvention])
            else:
                version = latestVersion
            line = standardLibrary + moduleName.capitalize() + "Version=" + version + "\n"

        if line[0:-1] not in lineList:
            updatedModules.append(moduleName)
        modifiedData += line

    for line in lineList[lineList.index(currentLine):len(lineList)]:
        currentLine = line
        if standardLibrary not in line.lower() and line != '':
            break

    modifiedData += "\n"

    for line in lineList[lineList.index(currentLine):len(lineList)]:
        if standardLibrary not in line.lower():
            line += "\n"
            modifiedData += line

    # modifiedData = modifiedData[0:-1]
    if modifiedData != data:
        commitFlag = True

    return modifiedData, commitFlag, updatedModules

# Commit changes made to the gradle.properties file
def commitChanges(data, repo, updatedModules):
    author = InputGitAuthor(packageUser, packageEmail)

    # If branch already exists checkout and commit else create new branch from master branch and commit
    try:
        source = repo.get_branch("main")
    except GithubException:
        source = repo.get_branch("master")

    try:
        repo.get_branch(branch=versionUpdateBranchName)
        repo.merge(versionUpdateBranchName, source.commit.sha, "Sync default branch")
    except:
        repo.create_git_ref(ref=f"refs/heads/" + versionUpdateBranchName, sha=source.commit.sha)

    contents = repo.get_contents("gradle.properties", ref=versionUpdateBranchName)

    if len(updatedModules) > 0:
        commitMessage = "Bump the version of stdlib module(s) - "
        for updatedModule in updatedModules:
            commitMessage += updatedModule
            commitMessage += " "
    else:
        commitMessage = "Update gradle.properties"

    repo.update_file(contents.path, 
                    commitMessage, 
                    data, 
                    contents.sha, 
                    branch=versionUpdateBranchName, 
                    author=author)

# Create a PR from the branch created
def createPullRequest(repo):
    pulls = repo.get_pulls(state='open', head=versionUpdateBranchName)

    PRExists = 0

    # Check if a PR already exists for the module
    for pull in pulls:
        if pullRequestTitle in pull.title:
            PRExists = pull.number

    # If PR doesn't exists create a new PR
    if PRExists == 0:
        try:
            repo.create_pull(title=pullRequestTitle, 
                            body='$subject', 
                            head=versionUpdateBranchName, 
                            base="main")
        except GithubException:
            repo.create_pull(title=pullRequestTitle, 
                            body='$subject', 
                            head=versionUpdateBranchName, 
                            base="master")

main()
