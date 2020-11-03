import json

with open('./release/resources/stdlib_modules.JSON') as f:
  	fileContent = json.load(f)
print(fileContent)
