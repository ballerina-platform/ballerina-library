import os
from github import Github

# using username and password
g = Github(os.environ["packageUser"], os.environ["packagePAT"])

for repo in g.get_user().get_repos():
    print(repo.name)
    repo.edit(has_wiki=False)
    # to see all the available attributes and methods
    print(dir(repo))
