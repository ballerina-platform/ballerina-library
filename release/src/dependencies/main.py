import json

with open('./release/resources/stdlib_modules.json') as f:
  	fileContent = json.load(f)
print(fileContent)
