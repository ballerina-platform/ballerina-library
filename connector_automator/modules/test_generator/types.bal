public type ConnectorAnalysis record {
    string packageName;
    string mockServerContent;
    string initMethodSignature;
    string referencedTypeDefinitions;
    "resource"|"remote" methodType = "resource";
    string remoteMethodSignatures = "";

};
