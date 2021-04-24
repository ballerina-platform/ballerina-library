import urllib.request
import json
import re
import networkx as nx
import sys
import time
from retry import retry

HTTP_REQUEST_RETRIES = 3
HTTP_REQUEST_DELAY_IN_SECONDS = 2
HTTP_REQUEST_DELAY_MULTIPLIER = 2

BALLERINA_ORG_NAME = "ballerina-platform"
BALLERINA_ORG_URL = "https://github.com/ballerina-platform/"
GITHUB_BADGE_URL = "https://img.shields.io/github/"
CODECOV_BADGE_URL = "https://codecov.io/gh/"

def main():
    print('Running main.py')
    module_name_list = sort_module_name_list()
    print('Fetched module name list')
    module_details_json = initialize_module_details(module_name_list)
    print('Initialized module details and fetched latest module versions')
    module_details_json = get_immediate_dependents(module_name_list, module_details_json)
    print('Fetched immediate dependents of each module')
    module_details_json = calculate_levels(module_name_list, module_details_json)
    print('Generated module dependency graph and updated module levels')
    module_details_json['modules'].sort(key=lambda s: s['level'])
    update_json_file(module_details_json)
    print('Updated module details successfully')
    update_stdlib_dashboard(module_details_json)
    print('Updated README file successfully')

# Sorts the ballerina standard library module list in ascending order
def sort_module_name_list():
    try:
        with open('./release/resources/module_list.json') as f:
            name_list = json.load(f)
    except:
        print('Failed to read module_list.json')
        sys.exit()

    name_list['modules'].sort(key=lambda x: x.split('-')[-1])
    
    try:
        with open('./release/resources/module_list.json', 'w') as json_file:
            json_file.seek(0) 
            json.dump(name_list, json_file, indent=4)
            json_file.truncate()
    except:
        print('Failed to write to file module_list.json')
        sys.exit()
        
    return name_list['modules'] 

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

# Gets dependencies of ballerina standard library module from build.gradle file in module repository
# returns: list of dependencies
def get_dependencies(module_name):
    try:
        data = url_open_with_retry("https://raw.githubusercontent.com/ballerina-platform/" 
                                    + module_name + "/master/build.gradle")
    except:
        print('Failed to read build.gradle file of ' + module_name)
        sys.exit()

    dependencies = []

    for line in data:
        processed_line = line.decode("utf-8")
        if 'ballerina-platform/module' in processed_line:
            module = processed_line.split('/')[-1]
            if module[:-2] == module_name:
                continue
            dependencies.append(module[:-2])

    return dependencies

# Gets the version of the ballerina standard library module from gradle.properties file in module repository
# returns: current version of the module
def get_version(module_name):
    try:
        data = url_open_with_retry("https://raw.githubusercontent.com/ballerina-platform/" 
                                    + module_name + "/master/gradle.properties")
    except:
        print('Failed to read gradle.properties file of ' + module_name)
        sys.exit()

    version = ''
    for line in data:
        processed_line = line.decode("utf-8")
        if re.match('version=', processed_line):
            version = processed_line.split('=')[-1][:-1]

    if version == '':
        print('Version not defined for ' + module_name)

    return version 

# Gets the default branch of the standard library repository
# returns: default branch name
def get_default_branch(module_name):
    try:
        data = url_open_with_retry("https://api.github.com/repos/ballerina-platform/" + module_name)
        json_data = json.load(data)
        return json_data['default_branch']
    except Exception as e:
        print('Failed to get repo details for ' + module_name + ": " + str(e))
        return ""

# Calculates the longest path between source and destination modules and replaces dependents that have intermediates
def remove_modules_in_intermediate_paths(G, source, destination, successors, module_details_json):
    longest_path = max(nx.all_simple_paths(G, source, destination), key=lambda x: len(x))

    for n in longest_path[1:-1]:
        if n in successors:
            for module in module_details_json['modules']:
                if module['name'] == source:
                    if destination in module['dependents']:
                        module['dependents'].remove(destination)
                    break

# Generates a directed graph using the dependencies of the modules
# Level of each module is calculated by traversing the graph 
# Returns a json string with updated level of each module
def calculate_levels(module_name_list, module_details_json):
    try:
        G = nx.DiGraph()
    except:
        print('Error generating graph')
        sys.exit()

    # Module names are used to create the nodes and the level attribute of the node is initialized to 0
    for module in module_name_list:
        G.add_node(module, level=1)

    # Edges are created considering the dependents of each module
    for module in module_details_json['modules']:
        for dependent in module['dependents']:
            G.add_edge(module['name'], dependent)

    processing_list = []

    # Nodes with in degrees=0 and out degrees!=0 are marked as level 1 and the node is appended to the processing list
    for root in [node for node in G if G.in_degree(node) == 0 and G.out_degree(node) != 0]:
        processing_list.append(root)

    # While the processing list is not empty, successors of each node in the current level are determined
    # For each successor of the node, 
    #    - Longest path from node to successor is considered and intermediate nodes are removed from dependent list
    #    - The level is updated and the successor is appended to a temporary array
    # After all nodes are processed in the current level the processing list is updated with the temporary array
    level = 2
    while len(processing_list) > 0:
        temp = []
        for node in processing_list:
            successors = []
            for i in G.successors(node):
                successors.append(i)
            for successor in successors:        
                remove_modules_in_intermediate_paths(G, node, successor, successors, module_details_json)
                G.nodes[successor]['level'] = level
                if successor not in temp:
                    temp.append(successor)
        processing_list = temp
        level = level + 1

    for module in module_details_json['modules']:
        module['level'] = G.nodes[module['name']]['level']

    return module_details_json

# Updates the stdlib_modules.JSON file with dependents of each standard library module
def update_json_file(updated_json):
    try:
        with open('./release/resources/stdlib_modules.json', 'w') as json_file:
            json_file.seek(0) 
            json.dump(updated_json, json_file, indent=4)
            json_file.truncate()
    except:
        print('Failed to write to stdlib_modules.json')
        sys.exit()

# Creates a JSON string to store module information
# returns: JSON with module details
def initialize_module_details(module_name_list):
    module_details_json = {'modules':[]}

    for module_name in module_name_list:
        version = get_version(module_name)		
        default_branch = get_default_branch(module_name)			
        module_details_json['modules'].append({
            'name': module_name, 
            'version':version,
            'level': 0,
            'default_branch': default_branch,
            'release': True, 
            'dependents': [] })
        
        time.sleep(10)

    return module_details_json

# Gets all the dependents of each module to generate the dependency graph
# returns: module details JSON with updated dependent details
def get_immediate_dependents(module_name_list, module_details_json):
    for module_name in module_name_list:
        dependencies = get_dependencies(module_name)
        for module in module_details_json['modules']:
            if module['name'] in dependencies:
                module_details_json['modules'][module_details_json['modules'].index(module)]['dependents'].append(module_name)
                    
    return module_details_json

# Updates the stdlib dashboard in README.md
def update_stdlib_dashboard(module_details_json):
    try:
        readme_file = url_open_with_retry("https://raw.githubusercontent.com/ballerina-platform/ballerina-standard-library/main/README.md")
    except:
        print('Failed to read README.md file')
        sys.exit()

    updated_readme_file = ''

    for line in readme_file:
        processed_line = line.decode("utf-8")
        updated_readme_file += processed_line
        if "## Status Dashboard" in processed_line:
            updated_readme_file += "\n"
            updated_readme_file += "|Level| Modules | Latest Version | Build | Code Coverage | Bugs | Open Pull Requests |\n"
            updated_readme_file += "|:---:|:---:|:---:|:---:|:---:|:---:|:---:|\n"
            break

    # Modules in levels 0 and 1 are categorized under level 1
    # A single row in the table is created for each module in the module list    
    level_column = 1
    current_level = 1
    for module in module_details_json['modules']:
        if module['level'] > current_level:
            level_column = module['level']
            current_level = module['level']

        row = ("|" + str(level_column) + "|" + 
        "[" + module['name'].split('-')[-1] + "](" + BALLERINA_ORG_URL + module['name'] + ")| " + 

        "[![GitHub Release](" + GITHUB_BADGE_URL + "release/" + BALLERINA_ORG_NAME + "/" + module['name'] + ".svg?label=)]" + 
        "(" + BALLERINA_ORG_URL + module['name'] + "/releases)| " + 

        "[![Build](" + BALLERINA_ORG_URL + module['name'] + "/actions/workflows/build-timestamped-master.yml/badge.svg)]" + 
        "(" + BALLERINA_ORG_URL + module['name'] + "/actions/workflows/build-timestamped-master.yml)| " + 

        "[![CodeCov](" + CODECOV_BADGE_URL + BALLERINA_ORG_NAME + "/" + module['name'] + "/branch/" + module['default_branch'] + "/graph/badge.svg)]" +
        "(" + CODECOV_BADGE_URL + BALLERINA_ORG_NAME + "/" + module['name'] + ")| " + 
        
        "[![Bugs](" + GITHUB_BADGE_URL + "issues-search/" + BALLERINA_ORG_NAME + "/ballerina-standard-library?"
               + get_bug_query(module) + ")](" + get_bugs_link(module) + ")| " +

        "[![GitHub pull-requests](" + GITHUB_BADGE_URL + "issues-pr" + "/" + BALLERINA_ORG_NAME + "/" + module['name'] + ".svg?label=)]" + 
        "(" + BALLERINA_ORG_URL + module['name'] + "/pulls)|\n")
        
        updated_readme_file += row

        level_column = ''

    try:
        with open('./README.md', 'w') as README:
            README.seek(0) 
            README.write(updated_readme_file)
            README.truncate()
    except:
        print('Failed to write to README.md')
        sys.exit()


def get_bug_query(module):
    module_name = module['name']
    return "query=is%3Aopen+label%3AType%2FBug+label%3Amodule%2F" + get_module_short_name(module_name) + "&label=&color=yellow&logo=github"


def get_bugs_link(module):
    return BALLERINA_ORG_URL + "/ballerina-standard-library/issues?q=is%3Aopen+label%3AType%2FBug+label%3Amodule%2F" + get_module_short_name(module['name'])


def get_module_short_name(module_name):
    return module_name.split("-")[-1]


main()
