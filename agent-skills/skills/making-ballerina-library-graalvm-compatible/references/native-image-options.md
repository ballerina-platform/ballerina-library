# Raw native-image Options (for Ballerina --graalvm-build-options)

> **Adapted from** the Oracle GraalVM community skill `build-native-image.md`
> (see Sources). In a Ballerina library you do **not** invoke `native-image`
> directly — `bal build --graalvm` / `bal test --graalvm` drive it. To pass any
> of the flags below, wrap them in `--graalvm-build-options`:
>
> ```console
> $ bal build --graalvm --graalvm-build-options="<flag> <flag> ..."
> ```
>
> The Oracle `native-build-tools.md` (Maven/Gradle plugins) is intentionally
> **not** adapted — it does not apply to Ballerina.

This is a reference of the raw flags most useful inside `--graalvm-build-options`.
For problem-based routing see `troubleshooting.md`; for metadata JSON see
`reachability-metadata.md`.

## Build-Time Inputs

```
-Dkey=value        # set a system property at build time
-J<flag>           # pass a flag to the JVM running the builder (e.g. -J-Xmx8g)
```

## Class Initialization and Linking

```
--initialize-at-run-time=<class>     # defer initialization to run time
--initialize-at-build-time=<class>   # force initialization at build time
--link-at-build-time                 # type must be fully defined at build time
```

## Performance and Optimization

```
-Ob                    # fastest build (dev iteration)
-O3                    # best runtime performance
-Os                    # optimize for binary size
--gc=epsilon           # no GC (throughput); --gc=serial is the default
-march=native          # target the current machine's CPU features
-march=compatibility   # maximum compatibility across machines
--parallelism=4        # limit build parallelism (also reduces memory)
```

## Network Support

```
--enable-http --enable-https
--enable-url-protocols=http,https
```

## Monitoring and Observability

```
--enable-monitoring=heapdump,jfr,threaddump
```

## Security and Compliance

```
--enable-all-security-services          # all security services incl. TLS/SSL
-H:AdditionalSecurityProviders=<list>   # pre-initialize specific providers
-H:+AddAllCharsets                      # add all charsets (larger binary)
-H:IncludeLocales=fr,de                 # include specific locales
-H:+IncludeAllLocales                   # include all locales (much larger)
```

## Metadata / Diagnostics

```
--exact-reachability-metadata[=<pkg>]        # strict metadata mode
-H:ConfigurationFileDirectories=<config-dir> # consume tracing-agent config (see tracing-agent.md)
-g                                           # debug symbols
--verbose                                    # verbose build
--emit build-report                          # HTML build report
```

## Notes for Ballerina

- Multiple flags go in one quoted string:
  `--graalvm-build-options="-J-Xmx8g --initialize-at-run-time=com.example.Foo"`.
- The tracing-agent output directory is consumed with
  `--graalvm-build-options="-H:ConfigurationFileDirectories=config-dir"` — this is
  how you validate collected metadata before packing it (see `tracing-agent.md`).

## Sources

- Oracle GraalVM community skill (adapted): https://github.com/oracle/graal/tree/master/substratevm/skills/building-native-image
- https://www.graalvm.org/latest/reference-manual/native-image/overview/Options/
- Ballerina GraalVM compatibility guide: `docs/graalvm-compatibility-in-ballerina-libraries.md`
