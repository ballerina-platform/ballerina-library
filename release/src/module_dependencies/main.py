import urllib.request
import json
import base64
import os

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

# Updates the stdlib_modules.JSON file with dependents of each standard library module
def updateJSONFile(updatedJSON):

	with open('./release/resources/stdlib_modules.json', 'w') as jsonFile:
		jsonFile.seek(0) 
		json.dump(updatedJSON, jsonFile, indent=4)
		jsonFile.truncate()


moduleNameList = getModuleNameList()
moduleDetailsJSON = {'modules':[]}

for moduleName in moduleNameList:
	version = getVersion(moduleName)
	moduleDetailsJSON['modules'].append({
		'name': moduleName, 
		'version':version,
		'level': 0,
		'release': True, 
		'dependents': [] })

for moduleName in moduleNameList:
	dependencies = getDependencies(moduleName)
	for dependency in dependencies:
		for module in moduleDetailsJSON['modules']:
			if module['name'] == dependency:
				moduleDetailsJSON['modules'][moduleDetailsJSON['modules'].index(module)]['dependents'].append(moduleName)
				break

print(moduleDetailsJSON)
