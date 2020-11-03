import urllib.request
import json
import base64

# Get dependencies of each ballerina standard library module
# build.gradle file is accessed through the github search api and decoded to locate the dependencies
# returns: list of dependencies
def getDependencies( bal_module ):
	
	for files in urllib.request.urlopen("https://api.github.com/repos/TharindaDilshan/" + bal_module + '/contents/build.gradle'):

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

# access the stdlib_modules.json file
# returns: a list containing an array of standard library module names and a json string of the file content 
def getModulesFromJSON():

	with open('./release/resources/stdlib_modules.json') as f:
  		fileContent = json.load(f)

	stdlib_modules = []

	for module in fileContent['modules']:
		stdlib_modules.append(module['name'])

	return stdlib_modules, fileContent

# Updates the stdlib_modules.JSON file with dependents of each standard library module
def updateJSONFile(updatedJSON):

	with open('./release/resources/stdlib_modules.json', 'w') as jsonFile:
		jsonFile.seek(0) 
		json.dump(updatedJSON, jsonFile, indent=4)
		jsonFile.truncate()
	print(updatedJSON)

stdlib_modules, JSONContent = getModulesFromJSON()

updatedJSON = JSONContent

for stdlib_module in stdlib_modules:

	dependencies = getDependencies(stdlib_module)
	for dependency in dependencies:
		for module in JSONContent['modules']:
			if module['name'] == dependency:
				updatedJSON['modules'][JSONContent['modules'].index(module)]['dependents'].append(stdlib_module)
				break

updateJSONFile(updatedJSON)
			


