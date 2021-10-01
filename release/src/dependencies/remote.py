import json
import os
import urllib.request

from retry import retry

import constants
import utils

def read_remote_file(module_name, file_name, branch):
    try:
        url = f'{constants.GITHUB_RAW_LINK}/{constants.BALLERINA_ORG_NAME}/{module_name}/{branch}/{file_name}'
        return open_url(url)

    except Exception as e:
        utils.print_error(f'Failed to read the file {file_name} from the module {module_name}', e)


def get_default_branch(module_name):
    try:
        url = f'{constants.GITHUB_API_LINK}/{constants.BALLERINA_ORG_NAME}/{module_name}'
        response = open_url(url)
        repository = json.load(response)
        return repository[constants.DEFAULT_BRANCH]
    except Exception as e:
        print(f'Failed to retrieve the default branch of the repo"{module_name}". {str(e)}')
        return "master"


@retry(
    urllib.error.URLError,
    tries=constants.HTTP_REQUEST_RETRIES,
    delay=constants.HTTP_REQUEST_DELAY_IN_SECONDS,
    backoff=constants.HTTP_REQUEST_DELAY_MULTIPLIER
)
def open_url(url):
    ballerina_bot_token = os.environ[constants.GITHUB_TOKEN]
    request = urllib.request.Request(url)
    request.add_header('Accept', 'application/vnd.github.v3+json')
    request.add_header('Authorization', 'Bearer ' + ballerina_bot_token)

    return urllib.request.urlopen(request)
