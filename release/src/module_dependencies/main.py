import urllib.request
import json
import base64
import os
import networkx as nx

# Gets dependencies of ballerina standard library module
# build.gradle file is accessed through the github search api and decoded to locate the dependencies
# returns: list of dependencies
def getDependencies( bal_module ):
	
	for files in urllib.request.urlopen(urllib.request.Request("https://api.github.com/repos/ballerina-platform/" + bal_module + "/contents/build.gradle", headers={'Authorization': 'token ' + os.environ['packagePAT']})):

		content = json.loads(files.decode('utf-8'))['content']
		lines = base64.b64decode(content.encode('ascii')).decode('ascii').split('\n')

		dependencies = []

		for line in lines:
			if 'ballerina-platform/module' in line:
				module = line.split('/')[-1]
				if module[:-1] == bal_module:
					continue
				dependencies.append(module[:-1])

		return dependencies

# Gets the version of the ballerina standard library module
# gradle.properties file is accessed through the github search api and decoded to find the version
# returns: current version of the module
def getVersion(bal_module):
	for files in urllib.request.urlopen(urllib.request.Request("https://api.github.com/repos/ballerina-platform/" + bal_module + "/contents/gradle.properties", headers={'Authorization': 'token ' + os.environ['packagePAT']})):

		content = json.loads(files.decode('utf-8'))['content']
		lines = base64.b64decode(content.encode('ascii')).decode('ascii').split('\n')

		for line in lines:
			if 'version' in line:
				version = line.split('=')[-1]

		return version 

# access the module_list.json file
# returns: a list containing an array of standard library module names
def getModuleNameList():

	with open('./release/resources/module_list.json') as f:
  		fileContent = json.load(f)

	return fileContent['modules']

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

	# Nodes with no in degrees = 0 and out degrees != 0 are marked as level 1 and the node is appended to the processing list
	for root in [node for node in G if G.in_degree(node) == 0 and G.out_degree(node) != 0]:
		G.nodes[root]['level'] = 1
		processingList.append(root)

	# While the processing list is not empty, successors of each node in the current level are determined
	# For each successor of the node, 
	# 			longest path from node to successor is considered and intermediate nodes are removed from dependent list
	# 			the level is updated and the successor is appended to a temporary array
	# After all nodes are processed in the current level the processing list is updated with the temporary array
	level = 2
	while len(processingList) > 0:
		temp = []
		for node in processingList:
			successors = []
			for i in G.successors(node):
				successors.append(i)

			for successor in successors:
				
				longestPath = max(nx.all_simple_paths(G, node, successor), key=lambda x: len(x))
				for n in longestPath[1:-1]:
					if n in successors:
						for module in moduleDetailsJSON['modules']:
							if module['name'] == node:
								if successor in module['dependents']:
									module['dependents'].remove(successor)
								break

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


moduleNameList = getModuleNameList()
moduleDetailsJSON = initializeModuleDetails(moduleNameList)

for moduleName in moduleNameList:
	
	dependencies = getDependencies(moduleName)

	for dependency in dependencies:
		for module in moduleDetailsJSON['modules']:
			if module['name'] == dependency:
				moduleDetailsJSON['modules'][moduleDetailsJSON['modules'].index(module)]['dependents'].append(moduleName)
				break

moduleDetailsJSON = calculateLevels(moduleNameList, moduleDetailsJSON)
updateJSONFile(moduleDetailsJSON)
