public type Module record {|
    string name;
    string 'version;
    int level;
    boolean release;
    string[] dependents;
    Module[] dependentModules = [];
    boolean inProgress = false;
|};
