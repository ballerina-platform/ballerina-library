# result of executing a `bal` command
public type CommandResult record {|
    # The command that was executed
    string command;
    # Whether the command executed successfully
    boolean success;
    # Exit code returned by the command
    int exitCode;
    # Standard output from the command
    string stdout;
    # Standard error output from the command
    string stderr;
    # Parsed compilation errors from the output
    CmdCompilationError[] compilationErrors;
    # Execution time 
    decimal executionTime;
|};

# Compilation error from a `bal build` output

public type CmdCompilationError record {|
    # name of the file where error occured
    string fileName;
    # Line number of the error
    int line;
    # Column number of the error
    int column;
    # Error message description
    string message;
    # Type of error (ERROR, WARNING)
    string errorType;
    # file path
    string filePath?;
|};

public type CommandExecutorError distinct error;

