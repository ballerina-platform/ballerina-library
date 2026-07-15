# Troubleshooting GraalVM Native Image (Ballerina)

> **Adapted from** the Oracle GraalVM community skill `troubleshooting.md` (see Sources). The Maven and Gradle Native Build Tools sections have been removed — Ballerina does not use those plugins. Raw `native-image` flags shown here are passed to a Ballerina build through `bal build --graalvm --graalvm-build-options="<flags>"` (or `bal test --graalvm --graalvm-build-options="<flags>"`), not to `native-image` directly.

Route Native Image build and runtime failures to the smallest relevant fix. For missing reflection / JNI / proxy / resource / bundle / serialization metadata, use `reachability-metadata.md`.

## Missing Reachability Metadata

Runtime errors involving reflection, JNI, resources, serialization, or dynamic proxies → consult `reachability-metadata.md`. Applies to:

- `NoClassDefFoundError` or `MissingReflectionRegistrationError`
- `MissingJNIRegistrationError`
- `MissingResourceException` from a missing resource bundle

Surface all missing registrations without crashing (strict metadata mode):

```console
$ bal build --graalvm --graalvm-build-options="--exact-reachability-metadata"
```

For GraalVM versions prior to JDK 23, use the build-time options `-H:ThrowMissingRegistrationErrors=` and `-H:MissingRegistrationReportingMode=Warn`.

> It is not always necessary to add every reported element to the metadata. **The element causing the program failure is usually among the last listed.** Prefer repo-sourced metadata (`reachability-metadata-repo.md`) and the tracing agent (`tracing-agent.md`) over hand-writing.

## Class Initialization and Linking

Build-time errors are frequently class-initialization problems. See `class-init-fix-procedure.md` for the full loop. The relevant flags (passed via `--graalvm-build-options`):

```
--initialize-at-run-time=com.example.LazyClass     # must NOT initialize at build time
--initialize-at-build-time=com.example.EagerClass  # must initialize at build time
--link-at-build-time                               # type must be fully defined at build time
```

Example:

```console
$ bal build --graalvm --graalvm-build-options="--initialize-at-run-time=com.example.LazyClass"
```

## Builder Memory

If the native build runs out of memory (`OutOfMemoryError`, `Java heap space`):

```console
$ bal build --graalvm --graalvm-build-options="-J-Xmx8g"
```

`-J<flag>` passes a flag to the JVM running the image builder; `-Dkey=value` sets a build-time system property.

## Diagnostics

Pass through `--graalvm-build-options`:

```
-g                                          # debug symbols in the binary
--verbose                                   # verbose build output
--diagnostics-mode                          # inspect class initialization and substitutions
--emit build-report                         # detailed HTML build report
--trace-object-instantiation=com.example.X  # trace instantiation of a class
--native-image-info                         # native toolchain and build settings
```

## Additional Run-Time Checks

- Sometimes upgrading to the latest GraalVM/Ballerina version resolves a run-time issue.
- If code uses `System.getProperty("java.home")`, it returns `null` in a native executable unless set explicitly at run time (`./myapp -Djava.home=<path>`).
- Charset-sensitive behavior: add `-H:+AddAllCharsets` (increases binary size).
- Security providers (TLS/SSL, JCA): pre-initialize with `-H:AdditionalSecurityProviders=<list>`, or `--enable-all-security-services`.
- For URL protocols and HTTP/HTTPS, see `native-image-options.md`.
- Native shared libraries: diagnose with `-R:MissingRegistrationReportingMode=Exit`.

## Ballerina-Specific Notes

- Watch for the build-time warning **"Package is not verified with GraalVM"** — it is not an error, but signals the package (or a Java dependency) is not yet marked compatible. Resolve it per `pack-and-mark.md`.
- On **macOS ARM64 (darwin-aarch64)** GraalVM native-image is experimental; a failure there may be a platform limitation, not a library bug.
- Native builds/tests are slow and memory-hungry — expect multi-minute runs.

## Sources

- Oracle GraalVM community skills (adapted): https://github.com/oracle/graal/tree/master/substratevm/skills/building-native-image
- https://www.graalvm.org/jdk25/reference-manual/native-image/guides/troubleshoot-run-time-errors/
- Ballerina GraalVM compatibility guide: `docs/graalvm-compatibility-in-ballerina-libraries.md`
