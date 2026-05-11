// Simple types for the fixer module
public type FixResult record {|
    boolean success;
    int errorsFixed;
    int errorsRemaining;
    int ballerinaErrorsFixed = 0;
    int javaErrorsFixed = 0;
    int ballerinaErrorsRemaining = 0;
    int javaErrorsRemaining = 0;
    string[] appliedFixes;
    string[] remainingFixes;
|};

public type CompilationError record {|
    string filePath;
    int line;
    int column;
    string message;
    string severity;
    string language = "ballerina";
    string sourceTool = "bal";
    string code?;
|};

public type FixRequest record {|
    string projectPath;
    string filePath;
    string code;
    CompilationError[] errors;
    string language = "ballerina";
|};

public type FixResponse record {|
    boolean success;
    string fixedCode;
    string explanation;
|};

public type BallerinaFixerError error;

type JavaEditOperation record {|
    int startLine;
    int endLine;
    string[] replacement;
|};
