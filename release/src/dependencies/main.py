import os
import base64
import requests
import json
import urllib.request


url = 'https://api.github.com/repos/TharindaDilshan/module-ballerina-io/contents/build.gradle'
# req = requests.get(url)
#if req.status_code == requests.codes.ok:
    # req = req.json()  # the response is a JSON
    # req is now a dict with keys: name, encoding, url, size ...
    # and content. But it is encoded with base64.
    # content = base64.b64decode(req['content'].encode('ascii')).decode('ascii')
    # print(json.loads(content))
#else:
    #print('Content was not found.')
    
file = urllib.request.urlopen(url)

for line in file:
	decoded_line = base64.b64decode(line.encode('ascii')).decode('ascii')
	print(decoded_line)
