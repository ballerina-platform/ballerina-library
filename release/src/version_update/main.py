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
    print("Checking Ballerina Distribution for stdlib version updates")
    moduleList = getStdlibModules()
    repo = configureGithubRepository()
    propertiesFile = fetchPropertiesFile(repo)
    modifiedPropertiesFile, commitFlag, updatedModules = updatePropertiesFile(propertiesFile, moduleList)
    if commitFlag:
        commitChanges(modifiedPropertiesFile, repo, updatedModules)
        createPullRequest(repo)
        print("Updated gradle.properties file in Ballerina Distribution Successfully")
    else:
        print("Stdlib versions in gradle.properties file is up to date")

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
def configureGithubRepository():
    g = Github(packagePAT)
    try:
        repo = g.get_repo(organization + "/" + 'ballerina-distribution')
    except:
        print("Error fetching repository ballerina-distribution")

    return repo

# Fetch the gradle.properties file from the ballerina-distribution repo
def fetchPropertiesFile(repo):
    try:
        branch = repo.get_branch(branch="automated-stdlib-version-update")
        file = repo.get_contents("gradle.properties", ref="automated-stdlib-version-update")
    except GithubException:
        file = repo.get_contents("gradle.properties")

    data = file.decoded_content.decode("utf-8")

    return data

# Update stdlib module versions in the gradle.properties file with module details fetched from stdlib_modules.json
def updatePropertiesFile(data, modules):
    modifiedData = ''
    updatedModules = []
    pointer = ''
    commitFlag = False

    lineList = data.splitlines()

    for line in lineList:
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

        if line[0:-1] not in lineList:
            updatedModules.append(moduleName)
        modifiedData += line

    for line in lineList[lineList.index(pointer):len(lineList)]:
        pointer = line
        if 'stdlib' not in line.lower() and line != '':
            break

    modifiedData += "\n"

    for line in lineList[lineList.index(pointer):len(lineList)]:
        if 'stdlib' not in line.lower():
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
        source = repo.get_branch(branch="automated-stdlib-version-update")
    except GithubException:
        try:
            source = repo.get_branch("main")
        except GithubException:
            source = repo.get_branch("master")

        repo.create_git_ref(ref=f"refs/heads/automated-stdlib-version-update", sha=source.commit.sha)

    contents = repo.get_contents("gradle.properties", ref="automated-stdlib-version-update")

    if len(updatedModules) > 0:
        commitMessage = "Bump stdlib module - "
        for updatedModule in updatedModules:
            commitMessage += updatedModule
            commitMessage += " "
    else:
        commitMessage = "Update gradle.properties"

    repo.update_file(contents.path, 
                    commitMessage, 
                    data, 
                    contents.sha, 
                    branch="automated-stdlib-version-update", 
                    author=author)

# Create a PR from the branch created
def createPullRequest(repo):
    pulls = repo.get_pulls(state='open', head="automated-stdlib-version-update")

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
                            head="automated-stdlib-version-update", 
                            base="main")
        except GithubException:
            repo.create_pull(title="[Automated] Update Stdlib module versions", 
                            body='$subject', 
                            head="automated-stdlib-version-update", 
                            base="master")

main()