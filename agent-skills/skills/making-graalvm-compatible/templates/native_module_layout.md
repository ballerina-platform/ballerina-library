# Native Module Layout (template)

Where a Ballerina library's native-image metadata lives, and how it is packed into a jar declared in `Ballerina.toml`. Created/managed by `scripts/scaffold_native_module.py`, `scripts/pack_native_configs.py`, and `scripts/build_native_config_jar.py`.

## Resources-only layout (scaffolded when no native module exists)

```text
native/
└── src/
    └── main/
        └── resources/
            └── META-INF/
                └── native-image/
                    └── <groupId>/
                        └── <artifactId>/
                            └── reachability-metadata.json   # (or legacy split *-config.json)
```

The config jar is a zip of everything under `native/src/main/resources`, so its archive entries are:

```text
META-INF/native-image/<groupId>/<artifactId>/reachability-metadata.json
```

Built to (by convention):

```text
native/build/libs/<artifactId>-<version>.jar
```

and wired into `Ballerina.toml` (see `ballerina_toml_platform_block.md`).

## Existing native module

If the library already has a `native/` module (Java source + its own build), pack the config files into the same `META-INF/native-image/<groupId>/<artifactId>/` resource path and rebuild the module with its existing build system — do **not** hand-jar or add a duplicate `[[platform.javaXX.dependency]]`.

> `<groupId>`/`<artifactId>` are the coordinates of the native jar declared in `[[platform.javaXX.dependency]]` (falling back to the package org/name if the library has no Java dependency). GraalVM discovers config on the classpath by this exact `META-INF/native-image/<groupId>/<artifactId>/` convention.
