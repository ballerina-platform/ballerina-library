// Simple types for the fixer module
public type FixResult record {|
    boolean success;
    int errorsFixed;
    int errorsRemaining;
    string[] appliedFixes;
    string[] remainingFixes;
|};

public type CompilationError record {|
    string filePath;
    int line;
    int column;
    string message;
    string severity;
    string code?;
|};

public type FixRequest record {|
    string projectPath;
    string filePath;
    string code;
    CompilationError[] errors;
|};

public type FixResponse record {|
    boolean success;
    string fixedCode;
    string explanation;
|};

// Track fix attempts for a specific file to prevent oscillation
public type FixAttempt record {|
    int iteration;
    string[] errorMessages;        // Errors that were present
    string appliedFix;             // Brief description of what was attempted
|};

// History of fix attempts per file
public type FileFixHistory record {|
    string filePath;
    FixAttempt[] attempts;
|};

public type BallerinaFixerError error;
