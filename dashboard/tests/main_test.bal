import ballerina/io;
import ballerina/test;

final readonly & string[] centralOnlyModules = check getCentralOnlyModules();

isolated function getCentralOnlyModules() returns readonly & string[]|error {
    ModuleNameList moduleNameList = check (check io:fileReadJson("../release/resources/module_list.json")).fromJsonWithType();
    return moduleNameList.central_only_modules.cloneReadOnly();
}

@test:Config
isolated function partitionByDistributionPackagingTest() {
    LibraryModulesByPackaging partitionedModules =
        partitionByDistributionPackaging(list.library_modules, centralOnlyModules);

    string[] packagedModuleNames = from Module module in partitionedModules.packaged select module.name;
    string[] centralOnlyModuleNames = from Module module in partitionedModules.centralOnly select module.name;

    foreach string moduleName in centralOnlyModules {
        test:assertTrue(centralOnlyModuleNames.indexOf(moduleName) is int,
                string `${moduleName} should be classified as Central-only`);
        test:assertFalse(packagedModuleNames.indexOf(moduleName) is int,
                string `${moduleName} should not be classified as packed with the distribution`);
    }
    test:assertTrue(packagedModuleNames.indexOf(IO_MODULE) is int,
            string `${IO_MODULE} should be classified as packed with the distribution`);
    test:assertEquals(partitionedModules.packaged.length() + partitionedModules.centralOnly.length(),
            list.library_modules.length());
}
