// Unified connector analysis record for both OpenAPI and SDK workflows.
public type ConnectorAnalysis record {
    string packageName;
    string mockServerContent = "";
    string initMethodSignature;
    string referencedTypeDefinitions;
    string connectionConfigDefinition = "";
    string enumDefinitions = "";
    "resource"|"remote" methodType = "resource";
    string remoteMethodSignatures = "";
};
