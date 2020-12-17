import urllib.request
import json
import sys
import os
from retry import retry

HTTP_REQUEST_RETRIES = 3
HTTP_REQUEST_DELAY_IN_SECONDS = 2
HTTP_REQUEST_DELAY_MULTIPLIER = 2
packageUser =  os.environ["packageUser"]
packagePAT = os.environ["packagePAT"]
packageEmail =  os.environ["packageEmail"]
organization = 'ballerina-platform'

def main():
    mod = getStdlibModules()
    repo = configureGithubRepository()
    propertiesFile = fetchPropertiesFile(repo)
    modifiedData, commitFlag = updatePropertiesFile(propertiesFile, mod)
    if commitFlag:
        commitChanges(modifiedData, repo)
        createPullRequest(repo)

def getStdlibModules():
    try:
        with open('./stdlib_modules.JSON') as f:
            nameList = json.load(f)
    except:
        print('Failed to read stdlib_modules.json')
        sys.exit()

    return nameList['modules']

def configureGithubRepository():
    g = Github(packagePAT)
    try:
        repo = g.get_repo(organization + "/" + 'ballerina-distribution')
    except:
        print("Error fetching repository ballerina-distribution")

    return repo

def fetchPropertiesFile(repo):
    try:
        branch = repo.get_branch(branch="automated-version-update")
        file = repo.get_contents("gradle.properties", ref="automated-version-update")
    except GithubException:
        file = repo.get_contents("gradle.properties")

    data = file.decoded_content.decode("utf-8")

    return data

def updatePropertiesFile(data, modules):
    modifiedData = ''
    pointer = ''
    commitFlag = False

    splitLine = data.splitlines()
    # print(type(splitLine[5]))

    for line in splitLine:
        if 'stdlib' in line.lower():
            pointer = line
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
        version = module['version']

        if moduleName == 'java.arrays':
            line = "stdlibJarraysVersion=" + version + "\n"
        elif moduleName == 'java.jdbc':
            line = "stdlibJdbcVersion=" + version + "\n"
        else:
            line = "stdlib" + moduleName.capitalize() + "Version=" + version + "\n"

        modifiedData += line

    for line in splitLine[splitLine.index(pointer):len(splitLine)]:
        if 'stdlib' not in line.lower() and line != '':
            pointer = line
            break

    modifiedData += "\n"

    for line in splitLine[splitLine.index(pointer):len(splitLine)]:
        if 'stdlib' not in line.lower():
            line += "\n"
            modifiedData += line

    modifiedData = modifiedData[0:-1]
    if modifiedData != data:
        commitFlag = True

    return modifiedData, commitFlag

def commitChanges(data, repo):
    author = InputGitAuthor(packageUser, packageEmail)

    # If branch already exists checkout and commit else create new branch from master branch and commit
    try:
        source = repo.get_branch(branch="automated-version-update")
    except GithubException:
        try:
            source = repo.get_branch("main")
        except GithubException:
            source = repo.get_branch("master")

        repo.create_git_ref(ref=f"refs/heads/automated-version-update", sha=source.commit.sha)

    contents = repo.get_contents("gradle.properties", ref="automated-version-update")
    repo.update_file(contents.path, 
                    "[Automated] Update Standard Library module versions", 
                    data, 
                    contents.sha, 
                    branch="automated-version-update", 
                    author=author)

# Create a PR from the branch created
def createPullRequest(repo):
    pulls = repo.get_pulls(state='open', head="automated-version-update")

    PRExists = 0

    # Check if a PR already exists for the module
    for pull in pulls:
        if "[Automated] Update Stdlib module versions" in pull.title:
            PRExists = pull.number

    # If PR doesn't exists create a new PR
    if PRExists == 0:
        try:
            repo.create_pull(title="[Automated] Update Stdlib module versions", 
                            body='$subject', 
                            head="automated-version-update", 
                            base="main")
        except GithubException:
            repo.create_pull(title="[Automated] Update Stdlib module versions", 
                            body='$subject', 
                            head="automated-version-update", 
                            base="master")

main()
