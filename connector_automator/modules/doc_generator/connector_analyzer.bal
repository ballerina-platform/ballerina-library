import ballerina/file;
import ballerina/io;
import ballerina/lang.'string as strings;
import ballerina/lang.regexp;

public function analyzeConnector(string connectorPath) returns ConnectorMetadata|error {
    file:MetaData|error pathMeta = file:getMetaData(connectorPath);
    if pathMeta is error {
        return error("Invalid connector path: " + connectorPath);
    }

    if !pathMeta.dir {
        return error("Connector path must be a directory");
    }

    ConnectorMetadata metadata = {
        connectorName: "",
        version: "1.0.0",
        examples: [],
        clientBalContent: "",
        typesBalContent: ""
    };

    // Analyze Ballerina.toml
    check analyzeBallerinaToml(connectorPath, metadata);

    // Get client.bal and types.bal content
    check analyzeClientAndTypesFiles(connectorPath, metadata);

    // Analyze examples directory
    check analyzeExamples(connectorPath, metadata);

    return metadata;
}

function analyzeClientAndTypesFiles(string connectorPath, ConnectorMetadata metadata) returns error? {
    // Get client.bal content
    string[] possibleClientPaths = [
        connectorPath + "/ballerina/client.bal",
        connectorPath + "/client.bal"
    ];

    foreach string clientPath in possibleClientPaths {
        if check file:test(clientPath, file:EXISTS) {
            metadata.clientBalContent = check io:fileReadString(clientPath);
            break;
        }
    }

    // Get types.bal content
    string[] possibleTypesPaths = [
        connectorPath + "/ballerina/types.bal",
        connectorPath + "/types.bal"
    ];

    foreach string typesPath in possibleTypesPaths {
        if check file:test(typesPath, file:EXISTS) {
            metadata.typesBalContent = check io:fileReadString(typesPath);
            break;
        }
    }
}

function analyzeBallerinaToml(string connectorPath, ConnectorMetadata metadata) returns error? {
    string ballerinaTomlPath = connectorPath + "/Ballerina.toml";

    if !check file:test(ballerinaTomlPath, file:EXISTS) {
        ballerinaTomlPath = connectorPath + "/ballerina/Ballerina.toml";
    }

    if check file:test(ballerinaTomlPath, file:EXISTS) {
        string content = check io:fileReadString(ballerinaTomlPath);

        string[] lines = regexp:split(re `\n`, content);
        foreach string line in lines {
            string trimmedLine = strings:trim(line);
            if strings:startsWith(trimmedLine, "name") {
                string[] parts = regexp:split(re `=`, trimmedLine);
                if parts.length() > 1 {
                    metadata.connectorName = strings:trim(regexp:replaceAll(re `"`, parts[1], ""));
                }
            }
            if strings:startsWith(trimmedLine, "version") {
                string[] parts = regexp:split(re `=`, trimmedLine);
                if parts.length() > 1 {
                    metadata.version = strings:trim(regexp:replaceAll(re `"`, parts[1], ""));
                }
            }

        }
    }
}

function analyzeExamples(string connectorPath, ConnectorMetadata metadata) returns error? {
    string examplesPath = connectorPath + "/examples";

    if check file:test(examplesPath, file:EXISTS) {
        file:MetaData[] examples = check file:readDir(examplesPath);

        foreach file:MetaData example in examples {
            if example.dir {
                string exampleName = example.absPath.substring(examplesPath.length());
                metadata.examples.push(exampleName);
            }
        }
    }
}

public function getConnectorSummary(ConnectorMetadata metadata) returns string {
    string summary = "Connector: " + metadata.connectorName + "\n";
    summary += "Version: " + metadata.version + "\n";
    summary += "Examples: " + strings:'join(", ", ...metadata.examples) + "\n";

    return summary;
}

public function analyzeExampleDirectory(string examplePath, string exampleDirName) returns ExampleData|error {
    ExampleData exampleData = {
        exampleName: formatExampleName(exampleDirName),
        exampleDirName: exampleDirName,
        balFiles: [],
        balFileContents: [],
        mainBalContent: ""
    };

    file:MetaData[] files = check file:readDir(examplePath);

    foreach file:MetaData fileInfo in files {
        if !fileInfo.dir && fileInfo.absPath.endsWith(".bal") {
            // Fix: Get just the filename without the leading slash
            string fileName = fileInfo.absPath.substring(examplePath.length());
            // Remove leading slash if present
            if fileName.startsWith("/") {
                fileName = fileName.substring(1);
            }

            string content = check io:fileReadString(fileInfo.absPath);

            exampleData.balFiles.push(fileName);
            exampleData.balFileContents.push(content);

            // If it's main.bal, store it separately
            if fileName == "main.bal" {
                exampleData.mainBalContent = content;
            }
        }
    }

    return exampleData;
}

public function formatExampleName(string dirName) returns string {
    // Convert "automated-summary-report" to "Automated summary report"
    string[] parts = regexp:split(re `[-_]`, dirName);
    string[] capitalizedParts = [];

    foreach int i in 0 ..< parts.length() {
        string part = parts[i];
        if part.length() > 0 {
            if i == 0 {
                // Capitalize first word completely
                capitalizedParts.push(part.substring(0, 1).toUpperAscii() + part.substring(1).toLowerAscii());
            } else {
                // Keep other words lowercase
                capitalizedParts.push(part.toLowerAscii());
            }
        }
    }

    return strings:'join(" ", ...capitalizedParts);
}
