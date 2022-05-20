import ballerina/io;
import ballerina/regex;

type list record {|
    m[] modules;
|};

type m record {|
    string name;
    string module_version?;
    int level?;
    string default_branch?;
    string version_key?;
    boolean release?;
    string[] dependents?;
|};

public function main() returns error? {
    list[] moduleNameList = check getSortedModuleNameList();
    list moduleDetailsJsonBalx = check initializeModuleDteails(moduleNameList[0]);
    list moduleDetailsJsonBal = check initializeModuleDteails(moduleNameList[1]);
    // io:println(moduleDetailsJsonBal);
    error? immediateDependencies = getImmediateDependencies(moduleDetailsJsonBal);
}

//  Sorts the ballerina standard library module list in ascending order
function getSortedModuleNameList() returns list[]|error {

    json nameList = check io:fileReadJson(MODULE_LIST_JSON);
    list nameListClone = check nameList.cloneWithType();

    m[] ballerinaxSorted = from var e in nameListClone.modules 
                                where regex:split(e.name, "-")[1] == "ballerinax" 
                                order by regex:split(e.name, "-")[2]
                                ascending select e;
    m[] ballerinaSorted = from var e in nameListClone.modules 
                                where regex:split(e.name, "-")[1] == "ballerina"
                                order by regex:split(e.name, "-")[2]
                                ascending select e;
    list sortedNameListX = {"modules":ballerinaxSorted};
    list sortedNameList = {"modules":ballerinaSorted};

    // _ = check io:fileWriteJson("./resources/myfile.json", sorted_name_list);

    return [sortedNameListX, sortedNameList];
}

function initializeModuleDteails(list moduleNameList) returns list|error  {
    printInfo("Initializing the module information");
    list moduleDetailsJson = {modules: []};

    foreach var module in moduleNameList.modules {
        m initialModule = check initializeModuleInfo(module);
        moduleDetailsJson.modules.push(initialModule);
    }
    return moduleDetailsJson;
}

function initializeModuleInfo(m module) returns m|error {
    string moduleName = module.name;
    string defaultBranch = check getDefaultBranch(moduleName);
    string gradle_properties_file = check readRemoteFile(
        moduleName, GRADLE_PROPERTIES, defaultBranch);
    string nameInVesrsionKey = getModuleShortName(moduleName);
    string defaultVersionKey = "stdlib"+nameInVesrsionKey+"Version";
    if module.version_key is string {
        defaultVersionKey = <string> module.version_key;
    }

    string moduleVersion = check getVersion(moduleName, gradle_properties_file);

    return {
        "name" : moduleName,
        "module_version": moduleVersion,
        "level": 1,
        "default_branch": defaultVersionKey,
        "version_key": defaultVersionKey,
        "release": true,
        "dependents": []
    };
}

function getVersion(string moduleName, string propertiesFile) returns string|error{
    string[] propertiesFileList = regex:split(propertiesFile, "\n");
    string moduleVersion = "";
    foreach var item in propertiesFileList {
        if regex:matches(item, "^.*version.*$") && !regex:matches(item, "^.*versions.*$"){
            moduleVersion = regex:split(item, "=")[1];
        }
    }
    if moduleVersion == "" {
        printWarn("Version not found for the module: "+ moduleName);
    }
    return moduleVersion;
}

function getImmediateDependencies(list moduleDetailsJson) returns error? {
    foreach m module in moduleDetailsJson.modules {
        printInfo("Finding dependents of module "+ module.name);
        string[] dependees = check getDependencies(module, moduleDetailsJson);
    }
}

function getDependencies(m module, list moduleDetailsJson) returns string[]|error {
    string moduleName = module.name;
    string defaultBranch = <string> module.default_branch;
    string propertiesFile = check readRemoteFile(
            moduleName, GRADLE_PROPERTIES, defaultBranch);
    string[] propertiesFileList = regex:split(propertiesFile, "\n");

    string[] dependencies = [];
    io:println(propertiesFile);
    foreach string line in propertiesFileList {
        foreach m item in moduleDetailsJson.modules {
            string dependentName = item.name;
            if dependentName == moduleName {continue;}
            if regex:matches(line, "^.*"+<string>module.version_key+".*$") {
                io:println(<string>module.version_key+" :",line);
                dependencies.push(dependentName);
                break;
            }
        }
    }
    // io:println(dependencies);
    return dependencies;
}