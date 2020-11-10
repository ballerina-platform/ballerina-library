import urllib.request
import json
import base64
import networkx as nx

def main():
    moduleNameList = sortModuleNameList()
    moduleDetailsJSON = initializeModuleDetails(moduleNameList)
    moduleDetailsJSON = getImmediateDependents(moduleNameList, moduleDetailsJSON)
    moduleDetailsJSON = calculateLevels(moduleNameList, moduleDetailsJSON)
    updateJSONFile(moduleDetailsJSON)

# Sorts the ballerina standard library module list in ascending order
def sortModuleNameList():
    with open('./release/resources/module_list.json') as f:
          nameList = json.load(f)

    nameList['modules'].sort()
    
    with open('./release/resources/module_list.json', 'w') as jsonFile:
        jsonFile.seek(0) 
        json.dump(nameList, jsonFile, indent=4)
        jsonFile.truncate()
        
    return nameList['modules'] 

# Gets dependencies of ballerina standard library module from build.gradle file in module repository
# returns: list of dependencies
def getDependencies(balModule):
    data = urllib.request.urlopen("https://raw.githubusercontent.com/ballerina-platform/" 
                                  + balModule + "/master/build.gradle")

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

    data = urllib.request.urlopen("https://raw.githubusercontent.com/ballerina-platform/" 
                                  + balModule + "/master/gradle.properties")

    for line in data:
        processedLine = line.decode("utf-8")
        if 'version' in processedLine:
            version = processedLine.split('=')[-1][:-1]

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

    G = nx.DiGraph()

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
    with open('./release/resources/stdlib_modules.json', 'w') as jsonFile:
        jsonFile.seek(0) 
        json.dump(updatedJSON, jsonFile, indent=4)
        jsonFile.truncate()

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
