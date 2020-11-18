import urllib.request
import json
import base64
import networkx as nx
import sys
from retry import retry

HTTP_REQUEST_RETRIES = 3
HTTP_REQUEST_DELAY_IN_SECONDS = 2
HTTP_REQUEST_DELAY_MULTIPLIER = 2

def main():
    print('Running main.py')
    moduleNameList = sortModuleNameList()
    print('Fetched module name list')
    moduleDetailsJSON = initializeModuleDetails(moduleNameList)
    print('Initialized module details and fetched latest module versions')
    moduleDetailsJSON = getImmediateDependents(moduleNameList, moduleDetailsJSON)
    print('Fetched immediate dependents of each module')
    moduleDetailsJSON = calculateLevels(moduleNameList, moduleDetailsJSON)
    print('Generated module dependency graph and updated module levels')
    updateJSONFile(moduleDetailsJSON)
    print('Updated module details successfully')

# Sorts the ballerina standard library module list in ascending order
def sortModuleNameList():
    try:
        with open('./release/resources/module_list.json') as f:
            nameList = json.load(f)
    except:
        print('Failed to read module_list.json')
        sys.exit()

    nameList['modules'].sort()
    
    try:
        with open('./release/resources/module_list.json', 'w') as jsonFile:
            jsonFile.seek(0) 
            json.dump(nameList, jsonFile, indent=4)
            jsonFile.truncate()
    except:
        print('Failed to write to file module_list.json')
        sys.exit()
        
    return nameList['modules'] 

# Returns the file in the given url
# Retry decorator will retry the function 3 times, doubling the backoff delay if URLError is raised 
@retry(urllib.error.URLError, tries=HTTP_REQUEST_RETRIES, delay=HTTP_REQUEST_DELAY_IN_SECONDS, 
                                    backoff=HTTP_REQUEST_DELAY_MULTIPLIER)
def urlOpenWithRetry(url):
    return urllib.request.urlopen(url)

# Gets dependencies of ballerina standard library module from build.gradle file in module repository
# returns: list of dependencies
def getDependencies(balModule):
    try:
        data = urlOpenWithRetry("https://raw.githubusercontent.com/ballerina-platform/" 
                                    + balModule + "/master/build.gradle")
    except:
        print('Failed to read build.gradle file of ' + balModule)
        sys.exit()

    dependencies = []

    for line in data:
        processedLine = line.decode("utf-8")
        if 'ballerina-platform/module' in processedLine:
            module = processedLine.split('/')[-1]
            if module[:-2] == balModule:
                continue
            dependencies.append(module[:-2])

    return dependencies

# Gets the version of the ballerina standard library module from gradle.properties file in module repository
# returns: current version of the module
def getVersion(balModule):
    try:
        data = urlOpenWithRetry("https://raw.githubusercontent.com/ballerina-platform/" 
                                    + balModule + "/master/gradle.properties")
    except:
        print('Failed to read gradle.properties file of ' + balModule)
        sys.exit()

    version = ''
    for line in data:
        processedLine = line.decode("utf-8")
        if 'version' in processedLine:
            version = processedLine.split('=')[-1][:-1]

    if version == '':
        print('Version not defined for ' + balModule)

    return version 

# Calculates the longest path between source and destination modules and replaces dependents that have intermediates
def removeModulesInIntermediatePaths(G, source, destination, successors, moduleDetailsJSON):
    longestPath = max(nx.all_simple_paths(G, source, destination), key=lambda x: len(x))

    for n in longestPath[1:-1]:
        if n in successors:
            for module in moduleDetailsJSON['modules']:
                if module['name'] == source:
                    if destination in module['dependents']:
                        module['dependents'].remove(destination)
                    break

# Generates a directed graph using the dependencies of the modules
# Level of each module is calculated by traversing the graph 
# Returns a json string with updated level of each module
def calculateLevels(moduleNameList, moduleDetailsJSON):
    try:
        G = nx.DiGraph()
    except:
        print('Error generating graph')
        sys.exit()

    # Module names are used to create the nodes and the level attribute of the node is initialized to 0
    for module in moduleNameList:
        G.add_node(module, level=0)

    # Edges are created considering the dependents of each module
    for module in moduleDetailsJSON['modules']:
        for dependent in module['dependents']:
            G.add_edge(module['name'], dependent)

    processingList = []

    # Nodes with in degrees=0 and out degrees!=0 are marked as level 1 and the node is appended to the processing list
    for root in [node for node in G if G.in_degree(node) == 0 and G.out_degree(node) != 0]:
        G.nodes[root]['level'] = 1
        processingList.append(root)

    # While the processing list is not empty, successors of each node in the current level are determined
    # For each successor of the node, 
    #    - Longest path from node to successor is considered and intermediate nodes are removed from dependent list
    #    - The level is updated and the successor is appended to a temporary array
    # After all nodes are processed in the current level the processing list is updated with the temporary array
    level = 2
    while len(processingList) > 0:
        temp = []
        for node in processingList:
            successors = []
            for i in G.successors(node):
                successors.append(i)
            for successor in successors:        
                removeModulesInIntermediatePaths(G, node, successor, successors, moduleDetailsJSON)
                G.nodes[successor]['level'] = level
                if successor not in temp:
                    temp.append(successor)
        processingList = temp
        level = level + 1

    for module in moduleDetailsJSON['modules']:
        module['level'] = G.nodes[module['name']]['level']

    return moduleDetailsJSON

# Updates the stdlib_modules.JSON file with dependents of each standard library module
def updateJSONFile(updatedJSON):
    updatedJSON['modules'].sort(key=lambda s: s['level'])

    try:
        with open('./release/resources/stdlib_modules.json', 'w') as jsonFile:
            jsonFile.seek(0) 
            json.dump(updatedJSON, jsonFile, indent=4)
            jsonFile.truncate()
    except:
        print('Failed to write to stdlib_modules.json')
        sys.exit()

# Creates a JSON string to store module information
# returns: JSON with module details
def initializeModuleDetails(moduleNameList):
    moduleDetailsJSON = {'modules':[]}

    for moduleName in moduleNameList:
        version = getVersion(moduleName)						
        moduleDetailsJSON['modules'].append({
            'name': moduleName, 
            'version':version,
            'level': 0,
            'release': True, 
            'dependents': [] })

    return moduleDetailsJSON

# Gets all the dependents of each module to generate the dependency graph
# returns: module details JSON with updated dependent details
def getImmediateDependents(moduleNameList, moduleDetailsJSON):
    for moduleName in moduleNameList:
        dependencies = getDependencies(moduleName)
        for module in moduleDetailsJSON['modules']:
            if module['name'] in dependencies:
                moduleDetailsJSON['modules'][moduleDetailsJSON['modules'].index(module)]['dependents'].append(moduleName)
                    
    return moduleDetailsJSON

main()
