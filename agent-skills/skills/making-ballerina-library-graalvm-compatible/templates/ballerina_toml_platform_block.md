# Ballerina.toml Platform Block (template)

Replace `java21` with the distribution's `PLATFORM_JAVA_VERSION` (`java11` / `java17` / `java21`). Place the `[platform.<javaXX>]` table **before** its `[[platform.<javaXX>.dependency]]` array (canonical, unambiguous ordering).

## Mark compatible (minimum)

```toml
[platform.java21]
graalvmCompatible = true
```

## Mark compatible + native config jar dependency

Used when the library packs its native-image metadata into a new resources jar:

```toml
[platform.java21]
graalvmCompatible = true

[[platform.java21.dependency]]
groupId = "<group-id>"
artifactId = "<artifact-id>"
version = "<version>"
path = "./native/build/libs/<artifact-id>-<version>.jar"
```

> `<group-id>` / `<artifact-id>` are the coordinates under which the native-image config is packed: `native/src/main/resources/META-INF/native-image/<group-id>/<artifact-id>/`. These edits are made by `scripts/update_ballerina_toml_graalvm.py`, which preserves surrounding formatting and comments.
