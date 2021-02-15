import urllib.request
import json
import sys
from retry import retry

HTTP_REQUEST_RETRIES = 3
HTTP_REQUEST_DELAY_IN_SECONDS = 2
HTTP_REQUEST_DELAY_MULTIPLIER = 2

def main():
    moduleList = fetchModuleList()
    print('Module list fetched from Standard Library')
    latestVersions = getLatestVersions(moduleList)
    updateFile(latestVersions)
    print('Updated modules with the latest version')

# Return the content in the given url
# Retry decorator will retry the function 3 times, doubling the backoff delay if URLError is raised 
@retry(
    urllib.error.URLError, 
    tries=HTTP_REQUEST_RETRIES, 
    delay=HTTP_REQUEST_DELAY_IN_SECONDS, 
    backoff=HTTP_REQUEST_DELAY_MULTIPLIER
)
def urlOpenWithRetry(url):
    return urllib.request.urlopen(url)

# Get a list of Ballerina Stdlib modules from the standard library repo
def fetchModuleList():
    try:
        with open('./release/resources/stdlib_modules.json') as f:
            stdlibModuleList = json.load(f)
            modules = stdlibModuleList["modules"]
    except:
        print('Failed to read module_list.json file in ballerina stdlib')
        sys.exit(1)

    return modules

# Get the latest version of a Ballerina Stdlib module from the Ballerina Central
def fetchModuleVersionFromBallerinaCentral(module):
    try:
        data = urlOpenWithRetry("https://api.central.ballerina.io/2.0/modules/info/ballerina/" + module.split('-')[-1])
        dataToString = data.read().decode("utf-8")
        latestVersion = json.loads(dataToString)['module']['version']
    except:
        print('Failed to fetch the version of ' + module + ' from Ballerina Central')
        latestVersion = '0.0.0'

    return latestVersion

# Create a JSON string to store module name along with the latest version
# If latest version is not available in Ballerina Central use latest version from github repo
def getLatestVersions(moduleList):
    latestModuleVersions = {'modules':[]}

    for module in moduleList:
        version = module['version']
        latestModuleVersions['modules'].append({module['name']: version})

    return latestModuleVersions

# Update the stdlib_latest_versions.json file with the latest version of each standard library module
def updateFile(latestVersions):
    try:
        with open('./dependabot/resources/stdlib_latest_versions.json', 'w') as jsonFile:
            jsonFile.seek(0) 
            json.dump(latestVersions, jsonFile, indent=4)
            jsonFile.truncate()
    except:
        print('Failed to write to stdlib_latest_versions.json')
        sys.exit(1)

main()
