# GraalVM Compatibility in Ballerina Libraries

## Overview of GraalVM
GraalVM is a high-performance, cloud-native, and polyglot JDK designed to accelerate the execution of applications. There are four different distributions of GraalVM: GraalVM Community Edition (CE), GraalVM Enterprise Edition (EE), Oracle GraalVM and Mandrel. You can install any to use the Ballerina GraalVM native functionality.

- **GraalVM CE** is the free version of GraalVM, which is distributed under GPLv2+CE.
- **GraaLVM EE** is the paid version of GraalVM, which comes with a few additional features such as options for GC, debugging, and other optimizations.
- **Oracle GraalVM** is the new distribution from Oracle available under the [GraalVM Free Terms and Conditions license](https://www.oracle.com/downloads/licenses/graal-free-license.html).
- **Mandrel** is a downstream distribution of the Oracle GraalVM CE, which is maintained by Red Hat.

### GraalVM executable Vs Uber JAR
When compiling a  Ballerina application using the `bal build` command the output is an uber JAR file. As you already know, running the JAR requires a JVM. JVM uses a Just In Time (JIT) compiler to generate native code during runtime.

On the other hand, when compiling a Ballerina application using `bal build --graalvm`, the output is the GraalVM executable local to the host machine. In order to build the GraalVM executable, GraalVM uses Ahead Of Time compilation (AOT), which requires the generated uber JAR as the input to produce the native executable. Native Image generation performs aggressive optimizations such as unused code elimination in the JDK and its dependencies, heap snapshotting, and static code initializations.

The difference between both approaches results in different pros and cons as depicted in the spider graph below.

<img src="_resources/aot-vs-jit.png" alt="AOT vs JIT" height="520" style="width: auto !important; padding-top: 20px; padding-bottom: 20px">

As depicted in the image, AOT compilation with GraalVM provides the following advantages over the standard JIT compilation making it ideal for container runtimes.
- Use a fraction of the resources required by the JVM.
- Applications start in milliseconds.
- Deliver peak performance immediately with no warmup.
- Can be packaged into lightweight container images for faster and more efficient deployments.
- Reduced attack surface.

The only downside is that the GraalVM native image build is a highly complicated process, which may consume a lot of memory and CPU resulting in an extended build time. However, the GraalVM community is continuously working on improving its performance.

### Ballerina GraalVM executable
From Ballerina 2201.7.0 (SwanLake) onwards, Ballerina supports GraalVM AOT compilation to generate standalone executables by passing the `graalvm` flag in the build command: `bal build --graalvm`. The generated executable contains the modules in the current package, their dependencies, Ballerina runtime, and statically linked native code from the JDK.

Ballerina runtime, [standard libraries](/learn/ballerina-specifications/#standard-library-specifications), and the Ballerina extended modules are GraalVM-compatible. Therefore packages developed only using these libraries are also GraalVM-compatible. Furthermore, Ballerina reports warnings when the GraalVM build is executed for a project with GraalVM-incompatible packages.

### Testing a Ballerina sample with GraalVM
#### Prerequisites
1. Latest [Ballerina Swan Lake](/downloads) distribution

2. A text editor
   >**Tip:** Preferably, <a href="https://code.visualstudio.com/" target="_blank">Visual Studio Code</a> with the  <a href="https://wso2.com/ballerina/vscode/docs/" target="_blank">Ballerina extension</a> installed.

3. GraalVM installed and configured appropriately
   
#### Configure GraalVM locally
1. Install GraalVM using [SDKMAN!](https://sdkman.io/). 
   >**Tip:** For additional download options, see [Get Started with GraalVM](https://www.graalvm.org/jdk17/docs/getting-started/).

      ```
      $ sdk install java 17.0.7-graalce
      ```
      > **Note:** If you have installed Ballerina Swan Lake Update 7(2201.7.x) or lower, you have to install GraalVM JDK 11. For download options, see [Get Started with GraalVM](https://www.graalvm.org/22.3/docs/getting-started/macos/).
      
2. Set the `GRAALVM_HOME` environment variable to the GraalVM installation directory. If you have installed using SDKMAN! you can set it to `JAVA_HOME`.

> **Note:** 
> - On Windows, the native image requires Visual Studio Code and Microsoft Visual C++ (MSVC). For more details, see [Prerequisites for Native Image on Windows](https://www.graalvm.org/latest/docs/getting-started/windows/#prerequisites-for-native-image-on-windows).
> - The GraalVM native-image tool support for Apple M1 (darwin-aarch64) is still experimental. For more updates, see [Support for Apple M1](https://github.com/oracle/graal/issues/2666).

#### Build with GraalVM

1. Run the following command to build a native exectable for the sample application
   ```
   $ bal build --graalvm
   ```
   
2. Run the executable generated in the `target/bin` directory
   ```
   $ ./target/bin/sample
   ```

#### Test with GraalVM

1. Add Ballerina test cases for the sample application
  
2. Run the following command to run the tests in a native executable
   ```
   $ bal test --graalvm
   ```
