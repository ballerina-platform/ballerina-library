public type ConnectorMetadata record {
    string connectorName;
    string version;
    string[] examples;
    string clientBalContent;
    string typesBalContent;

};

public type ExampleData record {|
    string exampleName;
    string exampleDirName;
    string[] balFiles;
    string[] balFileContents;
    string mainBalContent;
|};
