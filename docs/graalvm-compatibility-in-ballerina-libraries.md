# GraalVM Compatibility in Ballerina Libraries

## Overview of GraalVM

GraalVM is a high-performance, cloud-native, and polyglot JDK designed to accelerate the execution of applications. There are four different distributions of GraalVM: GraalVM Community Edition (CE), GraalVM Enterprise Edition (EE), Oracle GraalVM, and Mandrel. You can install any to use the Ballerina GraalVM native functionality.

- **GraalVM CE** is the free version of GraalVM, which is distributed under GPLv2+CE.
- **GraaLVM EE** is the paid version of GraalVM, which comes with a few additional features such as options for GC, debugging, and other optimizations.
- **Oracle GraalVM** is the new distribution from Oracle available under the [GraalVM Free Terms and Conditions license](https://www.oracle.com/downloads/licenses/graal-free-license.html).
- **Mandrel** is a downstream distribution of the Oracle GraalVM CE, which is maintained by Red Hat.

### GraalVM executable Vs Uber JAR

When compiling a Ballerina application using the `bal build` command the output is an uber JAR file. As you already know, running the JAR requires a JVM. JVM uses a Just In Time (JIT) compiler to generate native code during runtime.

On the other hand, when compiling a Ballerina application using `bal build --graalvm`, the output is the GraalVM executable local to the host machine. In order to build the GraalVM executable, GraalVM uses Ahead Of Time compilation (AOT), which requires the generated uber JAR as the input to produce the native executable. Native Image generation performs aggressive optimizations such as unused code elimination in the JDK and its dependencies, heap snapshotting, and static code initializations.

The difference between both approaches results in different pros and cons as depicted in the spider graph below.

<img src="_resources/aot-vs-jit.png" alt="AOT vs JIT" height="520" style="width: auto !important; padding-top: 20px; padding-bottom: 20px">

As depicted in the image, AOT compilation with GraalVM provides the following advantages over the standard JIT compilation making it ideal for container runtimes.

- Use a fraction of the resources required by the JVM.
- Applications start in milliseconds.
- Deliver peak performance immediately with no warmup.
- Can be packaged into lightweight container images for faster and more efficient deployments.
- Reduced attack surface.

One downside is that the GraalVM native image build is a highly complicated process, which may consume a lot of memory and CPU resulting in an extended build time. However, the GraalVM community is continuously working on improving its performance. In addition, the GraalVM native image assumes a closed-world assumption, where it should know all the classes and resources at compile time. Due to this limitation, Java dynamic features such as reflection are not directly supported. But we can configure the properties related to these dynamic features at compile time to make them work. For more information, see [Native Image Compatibility Guide](https://www.graalvm.org/jdk17/reference-manual/native-image/metadata/Compatibility/).

### Ballerina GraalVM executable

From Ballerina 2201.7.0 (SwanLake) onwards, Ballerina supports GraalVM AOT compilation to generate standalone executables by passing the `graalvm` flag in the build command: `bal build --graalvm`. The generated executable contains the modules in the current package, their dependencies, Ballerina runtime, and statically linked native code from the JDK.

Ballerina runtime, [standard libraries](https://ballerina.io/learn/ballerina-specifications/#standard-library-specifications), and the Ballerina extended modules are GraalVM-compatible. Therefore, packages developed only using these libraries are also GraalVM-compatible. Furthermore, Ballerina reports warnings when the GraalVM build is executed for a project with GraalVM-incompatible packages.

```console
**********************************************************************************
* WARNING: Package is not verified with GraalVM.                                 *
**********************************************************************************

The GraalVM compatibility property has not been defined for the package
'<package-name>. This could potentially lead to compatibility issues with GraalVM.

To resolve this warning, please ensure that all Java dependencies of this
package are compatible with GraalVM. Subsequently, update the Ballerina.toml
file under the section '[platform.<java*>]' with the attribute
'graalvmCompatible = true'.

**********************************************************************************
```

### Analyzing the code base for Java dynamic features

Since the native-image tool assumes the closed-world assumption, the following [dynamic features](https://www.graalvm.org/jdk17/reference-manual/native-image/dynamic-features/) of Java should be handled explicitly through configuration files.

- [Accessing Resources](https://www.graalvm.org/jdk17/reference-manual/native-image/dynamic-features/Resources/)
- [Certificate Management](https://www.graalvm.org/jdk17/reference-manual/native-image/dynamic-features/CertificateManagement/)
- [Dynamic Proxy](https://www.graalvm.org/jdk17/reference-manual/native-image/dynamic-features/DynamicProxy/)
- [Java Native Interface (JNI)](https://www.graalvm.org/jdk17/reference-manual/native-image/dynamic-features/JNI/)
- [JCA Security Services](https://www.graalvm.org/jdk17/reference-manual/native-image/dynamic-features/JCASecurityServices/)
- [Reflection](https://www.graalvm.org/jdk17/reference-manual/native-image/dynamic-features/Reflection/)
- [URL Protocols](https://www.graalvm.org/jdk17/reference-manual/native-image/dynamic-features/URLProtocols/)

The analysis should be also done on the third-party libraries used in the module. Some third-party libraries might be already GraalVM compatible, this should be verified with the third-party library owners. You can also refer to the configurations for some commonly used libraries in [graalvm-reachability-metadata repository](https://github.com/oracle/graalvm-reachability-metadata/tree/master/metadata).

### Test a sample application with GraalVM

#### Prerequisites

1. Latest [Ballerina Swan Lake](https://ballerina.io/downloads/) distribution
   >**Note:** If you are using macOS with an ARM64 processor, then, install Ballerina using the [ARM64 installer](https://ballerina.io/downloads/).

2. A text editor
   >**Tip:** Preferably, [Visual Studio Code](https://code.visualstudio.com/) with the Ballerina VS Code extension installed. For detailed information of the functionalities of this extension, go to the [Ballerina VS Code extension documentation](https://wso2.com/ballerina/vscode/docs/).

3. GraalVM installed and configured appropriately

#### Configure GraalVM locally

1. Install GraalVM.
   >**Tip:** Use [SDKMAN!](https://sdkman.io/) to install GraalVM.
   >
   >   ```console
   >   $ sdk install java 17.0.7-graalce
   >   ```
   >
   For additional download options, see [Get Started with GraalVM](https://www.graalvm.org/jdk17/docs/getting-started/).
   > **Note:** If you have installed Ballerina Swan Lake Update 7(2201.7.x) or lower, you have to install GraalVM JDK 11. For download options, see [Get Started with GraalVM](https://www.graalvm.org/22.3/docs/getting-started/macos/).

2. Set the `GRAALVM_HOME` environment variable to the GraalVM installation directory. If you have installed using SDKMAN! you can set it to `JAVA_HOME`.

> **Note:**
>
> - On Windows, the native image requires Visual Studio Code and Microsoft Visual C++ (MSVC). For more details, see [Prerequisites for Native Image on Windows](https://www.graalvm.org/latest/docs/getting-started/windows/#prerequisites-for-native-image-on-windows).
> - The GraalVM native-image tool support for Apple M1 (darwin-aarch64) is still experimental. For more updates, see [Support for Apple M1](https://github.com/oracle/graal/issues/2666).

#### Build with GraalVM

1. Run the following command to build a native executable for the sample application

   ```console
   $ bal build --graalvm
   ```

2. Run the executable generated in the `target/bin` directory

   ```console
   $ ./target/bin/sample
   ```

#### Test with GraalVM

1. Add Ballerina test cases for the sample application
  
2. Run the following command to run the tests in a native executable

   ```console
   $ bal test --graalvm
   ```

#### Handle errors

There may be errors when building the native image due to [class initialization](https://www.graalvm.org/jdk17/reference-manual/native-image/optimizations-and-performance/ClassInitialization/). Fix these errors using the error logs and tracing the class initialization. For more information, see [Updates on Class Initialization in GraalVM Native Image Generation](https://medium.com/graalvm/updates-on-class-initialization-in-graalvm-native-image-generation-c61faca461f7).

Even though the build passes, running the executable may end up in unexpected errors. This could happen if you have not added all the necessary configurations related to the Java dynamic features. The necessary configurations needed for this particular sample application can be automatically found by engaging the [tracing agent](https://www.graalvm.org/jdk17/reference-manual/native-image/metadata/AutomaticMetadataCollection/) when running the jar file.

#### The GraalVM Tracing agent

GraalVM provides a Tracing Agent to easily gather metadata and prepare configuration files. The agent tracks all usages of dynamic features during application execution on a regular Java VM.

##### Engage the Tracing agent when running the JAR file

1. Build the JAR file for the application

   ```console
   $ bal build
   ```

2. Run the following Java command with the generated JAR file. In addition, you can replace `config-dir` with a custom path where you want to save the generated configurations

   ```console
   $ $GRAALVM_HOME/bin/java -agentlib:native-image-agent=config-output-dir=config-dir -jar target/bin/sample.jar
   ```

   > **Note:** Make sure you use the `java` command packed with GraalVM distribution.

3. If the application is a service, test the service by making some request

4. If the application is a service, terminate the application after testing

5. The generated configurations can be found in `config-dir`

6. Build the native executable with the generated configuration files. In addition, you can replace `config-dir` with the path where you have generated the configurations

    ```console
    $ bal build --graalvm --graalvm-build-options="-H:ConfigurationFileDirectories=config-dir"
    ```

7. Run the native executable and verify its functionalities

   ```console
   $ ./target/sample
   ```

##### Engage the Tracing agent when running the Ballerina tests

This is not straightforward since Ballerina tests are not executed by a single Uber jar. In order to engage the tracing agent with Ballerina tests, we need to know the classpath, main class, and runtime arguments.

1. Run the tests with GraalVM to obtain classpath

   ```console
   $ bal test --graalvm
   ```

2. The class path can be found in the `target/cache/tests_cache/native-config/native-image-args.txt` file. Execute the following command to extract the classpath

   ```console
   $ echo $(sed -n 's/.*-cp \([^ ]*\).*/\1/p' target/cache/tests_cache/native-config/native-image-args.txt) > class-path.txt
   ```

3. Run the following command to run Ballerina tests with the tracing agent

   For **Ballerina SwanLake Update 10(2201.10.x)** or **higher**:
   ```console
   $ $GRAALVM_HOME/bin/java -agentlib:native-image-agent=config-output-dir=config-dir -cp @class-path.txt "org.ballerinalang.test.runtime.BTestMain" false "target/cache/tests_cache/test_suit.json" "target" "" true false "" "" "" false false false false
   ```

   For other versions:
   ```console
   $ $GRAALVM_HOME/bin/java -agentlib:native-image-agent=config-output-dir=config-dir -cp @class-path.txt "org.ballerinalang.test.runtime.BTestMain" "target" "" true false "" "" "" false false
   ```

4. Run the tests with GraalVM after adding the generated configurations

   ```console
   $ bal test --graalvm --graalvm-build-options="-H:ConfigurationFileDirectories=config-dir"
   ```

### Evaluate the GraalVM compatibility

**Once there are enough tests to ensure the functionalities**, execute the `bal test --graalvm` command to run all the tests with the GraalVM native executable.

- If there are any build-time warnings regarding the GraalVM compatibility, review the modules and if possible update the module versions if there is a GraalVM compatible version.

- If there are any build-time errors, refer to the previous section to resolve the issues.

- If there are any run-time errors, run the tests with the tracing agent as mentioned in the previous section to find all the required configurations.

### Pack the additional native image configurations

If the library requires any additional configurations that are generated by the tracing agent, then review the configurations and filter the required ones. The filtered configurations should be packed with the module to make it GraalVM compatible.

1. If you have a `native` directory that holds the Java native code, then you can pack this configuration files in the `src/main/resources/META-INF/native-image/<group-id>/<artifact-id>/` directory.

2. If you do not have a `native` directory, then you should create one and add the configuration files in the `src/main/resources/META-INF/native-image/<group-id>/<artifact-id>/` directory, build and add the native jar to the library by specifying the dependency in the `Ballerina.toml`.

### Mark the library as GraalVM compatible

If you get GraalVM compatibility warnings when building or packing the library, then that means the library has to be marked as GraalVM compatible after making it GraalVM compatible. This can be achieved by adding the following to the `Ballerina.toml`

```toml
[platform.java17]
graalvmCompatible = true
```
