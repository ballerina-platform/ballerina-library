import json
import re
import networkx

import constants
import remote
import utils


def main():
    module_name_list = get_sorted_module_name_list()
    module_details_json = initialize_module_details(module_name_list)
    get_immediate_dependents(module_details_json)
    calculate_levels(module_details_json)
    module_details_json[constants.MODULES].sort(
        key=lambda m: m[constants.LEVEL])
    update_modules_json_file(module_details_json)
    update_stdlib_dashboard(module_details_json)


# Sorts the ballerina standard library module list in ascending order
def get_sorted_module_name_list():
    try:
        with open(constants.MODULE_LIST_JSON) as f:
            name_list = json.load(f)
    except Exception as e:
        utils.print_error(
            f'Failed to read the {constants.MODULE_LIST_JSON} file', e)

    name_list[constants.MODULES].sort(
        key=lambda x: x[constants.NAME].split('-')[-1])
    try:
        with open(constants.MODULE_LIST_JSON, 'w') as json_file:
            json_file.seek(0)
            json.dump(name_list, json_file, indent=4)
            json_file.truncate()
    except Exception as e:
        utils.print_error(
            f'Failed to write to the {constants.MODULE_LIST_JSON} file', e)

    return name_list[constants.MODULES]


# Creates a JSON string to store module information
# returns: JSON with module details
def initialize_module_details(module_name_list):
    utils.print_info("Initializing the module information")
    module_details_json = {constants.MODULES: []}

    for module in module_name_list:
        module = initialize_module_info(module)
        module_details_json[constants.MODULES].append(module)

    return module_details_json


def initialize_module_info(module):
    module_name = module[constants.NAME]
    default_branch = remote.get_default_branch(module_name)
    gradle_properties_file = remote.read_remote_file(
        module_name, constants.GRADLE_PROPERTIES, default_branch)
    name_in_version_key = utils.get_module_short_name(module_name).capitalize()
    default_version_key = f'stdlib{name_in_version_key}Version'
    version = get_version(module_name, gradle_properties_file)

    return {
        "name": module_name,
        "version": version,
        "level": 1,
        "default_branch": default_branch,
        "version_key": module.get('version_key', default_version_key),
        "release": True,
        "dependents": []
    }


def get_version(module_name, properties_file):
    version = ''
    for line in properties_file:
        decoded_line = line.decode(constants.ENCODING)
        if re.match('version=', decoded_line):
            version = decoded_line.split('=')[-1][:-1]

    if version == '':
        utils.print_warn(f'Version not found for the module: {module_name}')

    return version


def get_dependencies(module, module_details_json):
    module_name = module[constants.NAME]
    default_branch = module[constants.DEFAULT_BRANCH]
    properties_file = remote.read_remote_file(
        module_name, constants.GRADLE_PROPERTIES, default_branch)
    dependencies = []

    for line in properties_file:
        processed_line = line.decode(constants.ENCODING)
        for module in module_details_json[constants.MODULES]:
            dependent_name = module[constants.NAME]
            if dependent_name == module_name:
                continue
            if module['version_key'] in processed_line:
                dependencies.append(dependent_name)
                break

    return dependencies


def calculate_levels(module_details_json):
    try:
        dependency_graph = networkx.DiGraph()
    except Exception as e:
        utils.print_error(f'Error generating the dependency graph', e)

    # Module names are used to create the nodes and the level attribute of the node is initialized to 1
    for module in module_details_json[constants.MODULES]:
        dependency_graph.add_node(module[constants.NAME], level=1)

    # Edges are created considering the dependents of each module
    for module in module_details_json[constants.MODULES]:
        for dependent in module[constants.DEPENDENTS]:
            dependency_graph.add_edge(module[constants.NAME], dependent)

    processed_list = [node for node in dependency_graph if dependency_graph.in_degree(node) == 0]

    # While the processing list is not empty, successors of each node in the current level are determined
    # For each successor of the node,
    #    - Longest path from node to successor is considered and intermediate nodes are removed from dependent list
    #    - The level is updated and the successor is appended to a temporary array
    # After all nodes are processed in the current level the processing list is updated with the temporary array
    current_level = 2
    while len(processed_list) > 0:
        processing = []
        for node in processed_list:
            process_current_level(dependency_graph, processing, module_details_json, current_level, node)
        processed_list = processing
        current_level = current_level + 1

    for module in module_details_json[constants.MODULES]:
        module[constants.LEVEL] = dependency_graph.nodes[module[constants.NAME]
                                                         ][constants.LEVEL]


def process_current_level(dependency_graph, processing, module_details_json, current_level, node):
    successors = [successor for successor in dependency_graph.successors(node)]
    for successor in successors:
        remove_modules_in_intermediate_paths(
            dependency_graph, node, successor, successors, module_details_json)
        dependency_graph.nodes[successor][constants.LEVEL] = current_level
        if successor not in processing:
            processing.append(successor)


def remove_modules_in_intermediate_paths(dependency_graph, source, destination, successors, module_details_json):
    longest_path = max(networkx.all_simple_paths(
        dependency_graph, source, destination), key=lambda x: len(x))

    for n in longest_path[1:-1]:
        if n in successors:
            for module in module_details_json[constants.MODULES]:
                if module[constants.NAME] == source:
                    if destination in module[constants.DEPENDENTS]:
                        module[constants.DEPENDENTS].remove(destination)
                    break


def update_modules_json_file(updated_json):
    try:
        with open(constants.STDLIB_MODULES_JSON, 'w') as json_file:
            json_file.seek(0)
            json.dump(updated_json, json_file, indent=4)
            json_file.truncate()
    except Exception as e:
        utils.print_error(
            f'Failed to read the {constants.STDLIB_MODULES_JSON} file', e)


# Gets all the dependents of each module to generate the dependency graph
# returns: module details JSON with updated dependent details
def get_immediate_dependents(module_details_json):
    for module in module_details_json[constants.MODULES]:
        utils.print_info(
            f'Finding dependents of module {module[constants.NAME]}')
        dependees = get_dependencies(module, module_details_json)
        for dependee in module_details_json[constants.MODULES]:
            dependee_name = dependee[constants.NAME]
            if dependee_name in dependees:
                dependee[constants.DEPENDENTS].append(module[constants.NAME])


# Updates the stdlib dashboard in README.md
def update_stdlib_dashboard(module_details_json):
    try:
        with open(constants.README_FILE, 'r+') as readme_file:
            updated_readme_file = ""
            for line in readme_file:
                updated_readme_file += line
                if constants.DASHBOARD_TITLE in line:
                    updated_readme_file += "\n"
                    updated_readme_file += constants.README_HEADER
                    updated_readme_file += constants.README_HEADER_SEPARATOR
                    break

            # Modules in levels 0 and 1 are categorized under level 1
            # A single row in the table is created for each module in the module list
            level_column = 1
            current_level = 1
            for module in module_details_json[constants.MODULES]:
                if module[constants.LEVEL] > current_level:
                    level_column = module[constants.LEVEL]
                    current_level = module[constants.LEVEL]

                row = utils.get_dashboard_row(module, str(level_column))
                updated_readme_file += row

                level_column = ''

            try:
                readme_file.seek(0)
                readme_file.write(updated_readme_file)
                readme_file.truncate()
            except Exception as e:
                utils.print_error(
                    f'Failed to write to the {constants.README_FILE}', e)

    except Exception as e:
        utils.print_error(f'Failed to read the {constants.README_FILE}', e)


main()
