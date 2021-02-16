import urllib.request
import json
import sys
from retry import retry

HTTP_REQUEST_RETRIES = 3
HTTP_REQUEST_DELAY_IN_SECONDS = 2
HTTP_REQUEST_DELAY_MULTIPLIER = 2

def main():
    module_list = fetch_module_list()
    print('Module list fetched from Standard Library')
    latest_versions = get_latest_versions(module_list)
    update_file(latest_versions)
    print('Updated modules with the latest version')

# Return the content in the given url
# Retry decorator will retry the function 3 times, doubling the backoff delay if URLError is raised 
@retry(
    urllib.error.URLError, 
    tries=HTTP_REQUEST_RETRIES, 
    delay=HTTP_REQUEST_DELAY_IN_SECONDS, 
    backoff=HTTP_REQUEST_DELAY_MULTIPLIER
)
def url_open_with_retry(url):
    return urllib.request.urlopen(url)

# Get a list of Ballerina Stdlib modules from the standard library repo
def fetch_module_list():
    try:
        with open('./release/resources/stdlib_modules.json') as f:
            stdlib_module_list = json.load(f)
            modules = stdlib_module_list["modules"]
    except:
        print('Failed to read module_list.json file in ballerina stdlib')
        sys.exit(1)

    return modules

# Get the latest version of a Ballerina Stdlib module from the Ballerina Central
def fetch_module_version_from_ballerina_central(module):
    try:
        data = url_open_with_retry("https://api.central.ballerina.io/2.0/modules/info/ballerina/" + module.split('-')[-1])
        data_to_string = data.read().decode("utf-8")
        latest_version = json.loads(data_to_string)['module']['version']
    except:
        print('Failed to fetch the version of ' + module + ' from Ballerina Central')
        latest_version = '0.0.0'

    return latest_version

# Create a JSON string to store module name along with the latest version
# If latest version is not available in Ballerina Central use latest version from github repo
def get_latest_versions(module_list):
    latest_module_versions = {'modules':[]}

    for module in module_list:
        version = module['version']
        latest_module_versions['modules'].append({module['name']: version})

    return latest_module_versions

# Update the stdlib_latest_versions.json file with the latest version of each standard library module
def update_file(latest_versions):
    try:
        with open('./dependabot/resources/stdlib_latest_versions.json', 'w') as json_file:
            json_file.seek(0) 
            json.dump(latest_versions, json_file, indent=4)
            json_file.truncate()
    except:
        print('Failed to write to stdlib_latest_versions.json')
        sys.exit(1)

main()
