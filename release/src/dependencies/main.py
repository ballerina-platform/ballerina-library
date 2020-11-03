import os
from github import Github

# using username and password
g = Github(os.environ["packageUser"], os.environ["packagePAT"])

repo = g.get_repo("TharindaDilshan/module-ballerina-io")
contents = repo.get_contents("README.md")
print(contents)
