import os
import base64
import requests
import json


url = 'https://api.github.com/repos/TharindaDilshan/module-ballerina-io/contents/build.gradle'
req = requests.get(url)
if req.status_code == requests.codes.ok:
    req = req.json()  # the response is a JSON
    # req is now a dict with keys: name, encoding, url, size ...
    # and content. But it is encoded with base64.
    content = base64.b64decode(req['content'].encode('ascii')).decode('ascii')
    print(json.loads(content))
else:
    print('Content was not found.')
