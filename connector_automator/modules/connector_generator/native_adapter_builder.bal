import wso2/connector_automator.sdkanalyzer as analyzer;

# Build Java native adaptor source from method mappings.
#
# + mappings - Method mappings between API spec methods and metadata-described native methods, used to generate method bodies that invoke the correct underlying native methods.
# + metadata - Structured native-library metadata, used to get the root client name for native adaptor generation.
# + return - Generated Java source code for the native adaptor class, or an error if invocation synthesis is not available.
public function buildNativeAdaptorJava(MethodMapping[] mappings,
        analyzer:StructuredSDKMetadata metadata) returns string|error {
    return error(string `Native adaptor invocation synthesis is not implemented for '${metadata.rootClient.simpleName}'; ` +
        "connector generation cannot produce a functional adaptor via the static builder path. " +
        "Use the LLM-based generation path instead.");
}

# Build method mappings by matching API spec names to metadata root client methods.
#
# + parsedSpec - Parsed API specification containing the methods to be mapped.
# + metadata - Structured native-library metadata, used to find matching methods.
# + return - Array of method mappings between API spec methods and metadata native methods.
public function buildMethodMappings(ParsedApiSpec parsedSpec,
        analyzer:StructuredSDKMetadata metadata) returns MethodMapping[] {
    MethodMapping[] mappings = [];
    foreach SpecMethodSignature specMethod in parsedSpec.clientMethods {
        analyzer:MethodInfo? javaMethod = findMatchingJavaMethod(specMethod.name, metadata.rootClient.methods);
        mappings.push({
            specMethod: specMethod,
            javaMethod: javaMethod
        });
    }
    return mappings;
}

function findMatchingJavaMethod(string name, analyzer:MethodInfo[] methods) returns analyzer:MethodInfo? {
    foreach analyzer:MethodInfo m in methods {
        if m.name == name {
            return m;
        }
    }
    foreach analyzer:MethodInfo m in methods {
        if m.name.equalsIgnoreCaseAscii(name) {
            return m;
        }
    }
    return ();
}
