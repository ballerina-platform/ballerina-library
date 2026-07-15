# GraalVM Native Image Reachability Metadata (Ballerina)

> **Adapted from** the Oracle GraalVM community skill
> `reachability-metadata.md` (see the Sources section). Content trimmed and
> annotated for the Ballerina library workflow — in particular, where metadata
> is packed and how raw `native-image` flags reach the build through
> `bal build --graalvm --graalvm-build-options="..."`.

This is the terminal reference for hand-writing or reviewing native-image config.
For where these files come from (the reachability-metadata repo or the tracing
agent) and how they get packed, see `reachability-metadata-repo.md` and
`pack-and-mark.md`.

## Table of Contents

1. [Diagnosing the Error Type](#1-diagnosing-the-error-type)
2. [Where Ballerina Puts Metadata Files](#2-where-ballerina-puts-metadata-files)
3. [Reflection Metadata](#3-reflection-metadata)
4. [JNI Metadata](#4-jni-metadata)
5. [Resource Metadata](#5-resource-metadata)
6. [Serialization Metadata](#6-serialization-metadata)
7. [Conditional Metadata Entries](#7-conditional-metadata-entries)
8. [Full Sample reachability-metadata.json](#8-full-sample-reachability-metadatajson)


## 1. Diagnosing the Error Type

Match the runtime error to the metadata section you need to fix (these appear
when running the native executable produced by `bal build --graalvm`, or during
`bal test --graalvm`):

| Runtime Error | Root Cause | Fix In Section |
|---|---|---|
| `NoClassDefFoundError` | Class not included in binary | [Reflection Metadata](#3-reflection-metadata) — register the type |
| `MissingReflectionRegistrationError` | Reflective access to unregistered class/method/field | [Reflection Metadata](#3-reflection-metadata) |
| `NoSuchMethodException` | Method not registered for reflective invocation | [Reflection Metadata](#3-reflection-metadata) |
| `NoSuchFieldException` | Field not registered for reflective access | [Reflection Metadata](#3-reflection-metadata) |
| `MissingJNIRegistrationError` | JNI lookup of unregistered type/member | [JNI Metadata](#4-jni-metadata) |
| `MissingResourceException` | Resource bundle not included | [Resource Metadata](#5-resource-metadata) |

**Quick diagnostic** — pass these through `--graalvm-build-options` to surface
missing registrations as warnings instead of hard failures while iterating:

```console
$ bal build --graalvm --graalvm-build-options="--exact-reachability-metadata"
```

(The `-XX:MissingRegistrationReportingMode=Warn|Exit` runtime flags from the
upstream doc apply when you run a raw `java`/executable directly, e.g. under the
tracing agent — see `tracing-agent.md`.)

---

## 2. Where Ballerina Puts Metadata Files

Unlike a Maven/Gradle app, a Ballerina library ships its native-image metadata
inside its **native module's resource tree**, which is then jarred and declared
as a `[[platform.javaXX.dependency]]`. All metadata lives in a single JSON file:

```
native/
└── src/main/resources/
    └── META-INF/
        └── native-image/
            └── <groupId>/
                └── <artifactId>/
                    └── reachability-metadata.json
```

`<groupId>`/`<artifactId>` are the coordinates of the library's native jar (see
`detect_package_coordinates.py`). The file is a top-level object with one key per
metadata type:

```json
{
  "reflection": [],
  "resources": []
}
```

> Older GraalVM versions use split files (`reflect-config.json`,
> `resource-config.json`, `jni-config.json`, `proxy-config.json`,
> `serialization-config.json`) in the same directory. The scripts handle both;
> prefer the unified `reachability-metadata.json` on current distributions.

See `pack-and-mark.md` for the full packing + jar + `Ballerina.toml` wiring.

---

## 3. Reflection Metadata

### Register a Type (fixes `NoClassDefFoundError`, `MissingReflectionRegistrationError`)

```json
{
  "reflection": [
    { "type": "com.example.MyClass" }
  ]
}
```

This allows `Class.forName("com.example.MyClass")` and reflective lookups to find the type.

### Methods

Fixes `NoSuchMethodError` and `MissingReflectionRegistrationError` on `Method.invoke()` or `Constructor.newInstance()`.

**Register specific methods:**
```json
{
  "type": "com.example.MyClass",
  "methods": [
    { "name": "myMethod", "parameterTypes": ["java.lang.String", "int"] },
    { "name": "<init>", "parameterTypes": [] }
  ]
}
```
> Use `"<init>"` for constructors.

**Register all methods (less precise, larger binary):**
```json
{
  "type": "com.example.MyClass",
  "allDeclaredMethods": true,
  "allPublicMethods": true,
  "allDeclaredConstructors": true,
  "allPublicConstructors": true
}
```
- `allDeclared*` — methods/constructors declared directly on this type
- `allPublic*` — all public methods/constructors including those inherited from supertypes

### Fields

Fixes `NoSuchFieldException` and `MissingReflectionRegistrationError` on `Field.get()` / `Field.set()`.

```json
{
  "type": "com.example.MyClass",
  "fields": [
    { "name": "myField" },
    { "name": "anotherField" }
  ]
}
```

Register all fields with `"allDeclaredFields": true` / `"allPublicFields": true`.

### Dynamic Proxies

For classes obtained via `Proxy.newProxyInstance(...)` — the type is the proxy's interface list:
```json
{
  "type": { "proxy": ["com.example.IFoo", "com.example.IBar"] }
}
```
> The interface order matters — it must match the order passed to `Proxy.newProxyInstance`.

### Unsafe Allocation

For `Unsafe.allocateInstance(MyClass.class)`:
```json
{ "type": "com.example.MyClass", "unsafeAllocated": true }
```

---

## 4. JNI Metadata

Used when native C/C++ code calls back into Java via JNI. Fixes `MissingJNIRegistrationError`.
Ballerina libraries with a `native` directory holding C/JNI code frequently need this.

```json
{
  "reflection": [
    {
      "type": "com.example.MyClass",
      "jniAccessible": true,
      "fields": [{ "name": "value" }],
      "methods": [{ "name": "callback", "parameterTypes": ["int"] }],
      "allDeclaredConstructors": true
    }
  ]
}
```

JNI metadata follows the same `allDeclared*` / `allPublic*` convenience flags as reflection.

---

## 5. Resource Metadata

Resources are specified using glob patterns in the `resources` array:

```json
{
  "resources": [
    { "glob": "config/app.properties" },
    { "glob": "templates/**" }
  ]
}
```

**Glob rules:** `*` matches one path level; `**` matches across levels; no trailing slash, no `***`.

> `Class.getResourceAsStream("plan.txt")` with class + string literals is auto-detected — no JSON needed.

### Resource Bundles

Fixes `MissingResourceException` from `ResourceBundle.getBundle(...)`:
```json
{ "resources": [ { "bundle": "com.example.Messages" } ] }
```

Control locales by passing flags through `--graalvm-build-options`:
```console
$ bal build --graalvm --graalvm-build-options="-H:IncludeLocales=fr,de"
```

---

## 6. Serialization Metadata

Fixes `InvalidClassException` / `ClassNotFoundException` during `ObjectInputStream.readObject()`:

```json
{
  "reflection": [
    { "type": "com.example.MySerializableClass", "serializable": true }
  ]
}
```

`ObjectInputFilter.Config.createFilter("com.example.MyClass;!*;")` with a constant pattern is auto-detected.

---

## 7. Conditional Metadata Entries

Use conditions to avoid bloating the binary with metadata for code paths that may never run:

```json
{
  "condition": { "typeReached": "com.example.FeatureModule" },
  "type": "com.example.OptionalClass",
  "allDeclaredMethods": true
}
```

The metadata is active at runtime only once `FeatureModule` is reached.
> Use conditions liberally on third-party library metadata to keep binary size reasonable.

---

## 8. Full Sample reachability-metadata.json

```json
{
  "reflection": [
    {
      "condition": { "typeReached": "com.example.App" },
      "type": "com.example.MyClass",
      "fields": [{ "name": "myField" }],
      "methods": [
        { "name": "myMethod", "parameterTypes": ["java.lang.String"] },
        { "name": "<init>", "parameterTypes": [] }
      ],
      "allDeclaredConstructors": true,
      "allDeclaredMethods": true,
      "unsafeAllocated": true,
      "serializable": true
    },
    { "type": { "proxy": ["com.example.IFoo", "com.example.IBar"] } },
    {
      "type": "com.example.JniClass",
      "jniAccessible": true,
      "fields": [{ "name": "nativeHandle" }],
      "allDeclaredMethods": true
    }
  ],
  "resources": [
    { "glob": "config/**" },
    { "bundle": "com.example.Messages" }
  ]
}
```

## Sources

- Oracle GraalVM community skill (adapted): https://github.com/oracle/graal/blob/master/substratevm/skills/building-native-image/references/reachability-metadata.md
- https://www.graalvm.org/latest/reference-manual/native-image/metadata/
- Ballerina GraalVM compatibility guide: `docs/graalvm-compatibility-in-ballerina-libraries.md`
