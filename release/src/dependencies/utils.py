import json
import os
import sys
import urllib.parse
import urllib.request

from retry import retry

import constants
import remote

def get_dashboard_row(module, level):
    module_name = module['name']
    default_branch = module['default_branch']

    repo_link = get_repo_link(module_name)
    release_badge = get_release_badge(module_name)
    build_status_badge = get_build_status_badge(module_name)
    trivy_badge = get_trivy_badge(module_name)
    codecov_badge = get_codecov_badge(module_name, default_branch)
    bugs_badge = get_bugs_badge(module_name)

    return f'|{level}|{repo_link}|{release_badge}|{build_status_badge}|{trivy_badge}|{codecov_badge}|{bugs_badge}|\n'


def get_repo_link(module_name):
    short_name = get_module_short_name(module_name)
    return f'[{short_name}]({constants.BALLERINA_ORG_URL}/{module_name})'


def get_release_badge(module_name):
    badge_url = f'{constants.GITHUB_BADGE_URL}/v/release/{constants.BALLERINA_ORG_NAME}/{module_name}?color={constants.BADGE_COLOR_GREEN}&label='
    repo_url = f'{constants.BALLERINA_ORG_URL}/{module_name}/releases'
    return f'[![GitHub Release]({badge_url})]({repo_url})'


def get_build_status_badge(module_name):
    badge_url = f'{constants.GITHUB_BADGE_URL}/workflow/status/{constants.BALLERINA_ORG_NAME}/{module_name}/Build?label='
    repo_url = f'{constants.BALLERINA_ORG_URL}/{module_name}/actions/workflows/build-timestamped-master.yml'
    return f'[![Build]({badge_url})]({repo_url})'


def get_trivy_badge(module_name):
    badge_url = f'{constants.GITHUB_BADGE_URL}/workflow/status/{constants.BALLERINA_ORG_NAME}/{module_name}/Trivy?label='
    repo_url = f'{constants.BALLERINA_ORG_URL}/{module_name}/actions/workflows/trivy-scan.yml'
    return f'[![Trivy]({badge_url})]({repo_url})'


def get_codecov_badge(module_name, default_branch):
    badge_url = f'{constants.CODECOV_BADGE_URL}/{constants.BALLERINA_ORG_NAME}/{module_name}/branch/{default_branch}/graph/badge.svg'
    repo_url = f'{constants.CODECOV_BADGE_URL}/{constants.BALLERINA_ORG_NAME}/{module_name}'
    return f'[![CodeCov]({badge_url})]({repo_url})'


def get_bugs_badge(module_name):
    query = get_bug_query(module_name)
    short_name = get_module_short_name(module_name)
    issue_filter = f'is:open label:module/{short_name} label:Type/Bug'
    encoded_query_parameter = urllib.parse.quote_plus(issue_filter)

    badge_url = f'{constants.GITHUB_BADGE_URL}/issues-search/{constants.BALLERINA_ORG_NAME}/{constants.BALLERINA_STANDARD_LIBRARY}?query={query}'
    repo_url = f'{constants.BALLERINA_ORG_URL}/{constants.BALLERINA_STANDARD_LIBRARY}/issues?q={encoded_query_parameter}'

    return f'[![Bugs]({badge_url})]({repo_url})'


def get_bug_query(module_name):
    short_name = get_module_short_name(module_name)
    query = f'state=open&labels=Type/Bug,module/{short_name}'
    url = f'{constants.GITHUB_API_LINK}/{constants.BALLERINA_ORG_NAME}/{constants.BALLERINA_STANDARD_LIBRARY}/issues?{query}'
    try:
        data = remote.open_url(url)
        json_data = json.load(data)
        issue_count = len(json_data)
    except Exception as e:
        print('Failed to get issue details for ' + module_name + ": " + str(e))
        issue_count = 1

    if issue_count == 0:
        label_colour = constants.BADGE_COLOR_GREEN
    else:
        label_colour = constants.BADGE_COLOR_YELLOW

    issue_filter = f'is:open label:module/{short_name} label:Type/Bug'
    encoded_filter = urllib.parse.quote_plus(issue_filter)
    return f'{encoded_filter}&label=&color={label_colour}'


def get_module_short_name(module_name):
    short_name = module_name.split("-")[-1]
    if short_name == "jballerina.java.arrays":
        return "java.arrays"
    return short_name


def print_info(message):
    print(f'[Info] {message}')


def print_warn(message):
    print(f'[Warning] {message}')


def print_error(message, e):
    print(f'[Error] {message}. Reason: {str(e)}')
    sys.exit()
