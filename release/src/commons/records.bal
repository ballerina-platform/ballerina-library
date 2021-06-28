public type Module record {|
    string name;
    string 'version;
    int level;
    string default_branch;
    boolean release;
    string[] dependents;
    Module[] dependentModules = [];
    boolean inProgress = false;
    string version_key;
|};

public type WorkflowStatus record {|
    boolean isFailure;
    string[] failedModules;
|};
