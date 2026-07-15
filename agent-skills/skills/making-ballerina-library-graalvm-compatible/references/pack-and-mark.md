# Packing Native-Image Config and Marking the Library Compatible

This covers stage 05 (filter + pack) and stage 06 (mark). It follows the Ballerina GraalVM compatibility guide's "Pack the additional native image configurations" and "Mark the library as GraalVM compatible" sections.

---

## 1. Resolve coordinates

```bash
<PYTHON_CMD> <skill-root>/scripts/detect_package_coordinates.py "<BALLERINA_TOML>"
```

Gives `group_id`, `artifact_id` (from the first `[[platform.javaXX.dependency]]`, falling back to the package org/name), `has_native_dir`, `native_dir`, and the `meta_inf_dir`:

```
<native_dir>/src/main/resources/META-INF/native-image/<groupId>/<artifactId>/
```

---

## 2. Filter tracing output (skip if only using repo-sourced metadata)

```bash
<PYTHON_CMD> <skill-root>/scripts/filter_trace_configs.py \
  --config-dir "<CONFIG_DIR>" --out "<filtered-dir>" \
  --keep-prefixes "<lib.package.>,<dep.package.>"
```

Review the kept/dropped report — this is a judgment call. Class-keyed entries outside the keep-prefixes (JDK, `io.ballerina.`, `org.ballerinalang.`) are dropped. Resource/bundle globs pass through unfiltered — inspect them manually. Prefer conditional (`typeReached`) entries to keep the binary small (see `reachability-metadata.md`).

---

## 3. Ensure a native module exists

**If `has_native_dir` is true**, pack into the existing tree.

**If not**, scaffold a resources-only module:

```bash
<PYTHON_CMD> <skill-root>/scripts/scaffold_native_module.py \
  --native-dir "<native_dir>" --group-id "<g>" --artifact-id "<a>"
```

---

## 4. Pack the config files

Pack both repo-sourced metadata (`REACHABILITY_REPO_HITS` staging dirs) and the filtered tracing output into the module tree, merging same-named files:

```bash
# repo-sourced (per dependency staging dir)
<PYTHON_CMD> <skill-root>/scripts/pack_native_configs.py \
  --filtered-dir "<staging-dir>/<g>__<a>" --native-dir "<native_dir>" \
  --group-id "<g>" --artifact-id "<a>" --merge

# filtered tracing output
<PYTHON_CMD> <skill-root>/scripts/pack_native_configs.py \
  --filtered-dir "<filtered-dir>" --native-dir "<native_dir>" \
  --group-id "<g>" --artifact-id "<a>" --merge
```

---

## 5. Build the native config jar (only if scaffolding a new module)

If the library had no native jar, jar the resources tree (pure `zipfile`, no Java toolchain):

```bash
<PYTHON_CMD> <skill-root>/scripts/build_native_config_jar.py \
  --resources-dir "<native_dir>/src/main/resources" \
  --out "<native_dir>/build/libs/<artifactId>-<version>.jar"
```

Then declare it as a dependency (step 6). If a native jar already exists and is built by the module's own build (e.g. Gradle), rebuild that instead of jarring by hand, and skip the `--add-dependency` below.

---

## 6. Mark the library GraalVM compatible

Set `graalvmCompatible = true` in the correct platform block (`PLATFORM_JAVA_VERSION`, e.g. `java21`), and — only when you created a new native jar — add the dependency:

```bash
# mark compatible
<PYTHON_CMD> <skill-root>/scripts/update_ballerina_toml_graalvm.py \
  --toml "<BALLERINA_TOML>" --java-version "<PLATFORM_JAVA_VERSION>" \
  --graalvm-compatible true

# only if a new native jar was created
<PYTHON_CMD> <skill-root>/scripts/update_ballerina_toml_graalvm.py \
  --toml "<BALLERINA_TOML>" --java-version "<PLATFORM_JAVA_VERSION>" \
  --add-dependency --group-id "<g>" --artifact-id "<a>" \
  --dep-version "<version>" --path "./native/build/libs/<artifactId>-<version>.jar"
```

The resulting block (canonical ordering — table before its dependency array):

```toml
[platform.java21]
graalvmCompatible = true

[[platform.java21.dependency]]
groupId = "<groupId>"
artifactId = "<artifactId>"
version = "<version>"
path = "./native/build/libs/<artifactId>-<version>.jar"
```

> Replace `java21` with the distribution's `PLATFORM_JAVA_VERSION` (java11/java17/java21).

---

## 7. Verify

Do not mark-and-forget. Re-run and confirm the warning is gone:

```bash
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py "bal build --graalvm" "<BALLERINA_DIR>"
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py "bal test --graalvm" "<BALLERINA_DIR>"
```

Both should pass with **no** "Package is not verified with GraalVM" warning. If the build fails, do not leave `graalvmCompatible = true` in place — revert and continue debugging.

## Sources

- Ballerina GraalVM compatibility guide: `docs/graalvm-compatibility-in-ballerina-libraries.md`
