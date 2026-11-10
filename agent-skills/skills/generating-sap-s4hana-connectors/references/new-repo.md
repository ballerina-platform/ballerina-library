# Starting a new S/4HANA area repository

Use this only when the API belongs to an area that has no `module-ballerinax-sap.s4hana.<area>`
repo yet. Adding a package to an existing area repo does not need any of it.

## 1. Get the upstream repo

Repos under `ballerina-platform` are created by the platform team on request, not by us. Ask the
user to request `module-ballerinax-sap.s4hana.<area>` (they use the repo request form) and to fork
it once it exists. Until then, work in a local directory and push later.

## 2. Scaffold from the reference repo

Use `module-ballerinax-sap.s4hana.qm` as the reference. It has the current Gradle/plugin
versions, the README template with per-scenario screenshot keys, and the fixed package
`build.gradle`. Export it without its packages, specs, scenario screenshots and examples
(`git archive` avoids deleting anything in place):

```bash
REF=<path to your clone of module-ballerinax-sap.s4hana.qm>
NEW=<path for the new module-ballerinax-sap.s4hana.<area> clone>
mkdir -p "$NEW"
git -C "$REF" archive HEAD -- . \
  ':!ballerina/api_*' ':!docs/spec/*' ':!docs/setup/s4-3-*' ':!docs/setup/s4-4-*' ':!docs/setup/s4-5-*' \
  ':!examples/*/' | tar -x -C "$NEW"
```

Keep `docs/setup/s4-1-communication-system.png` and `s4-2-communication-system-users.png`, which
are scenario independent. Keep `docs/sanitation/*.bal`, `docs/license.txt`,
`ballerina/resources` (mock certs), `ballerina/icon.png`, `build-config/`, `gradle/` and the
wrapper.

## 3. Replace the area tokens

| File | What to change |
|---|---|
| `settings.gradle` | `rootProject.name`, every `qm-` prefix (`qm-sanitation`, `qm-ballerina`, `qm-examples`), drop the old package lines |
| `build.gradle`, `ballerina/build.gradle`, `docs/sanitation/build.gradle`, `examples/build.gradle` | `qm-` prefixes, the description, drop the old `dependsOn(...:commitTomlFiles)` lines |
| `gradle.properties` | drop the old `<pkg>Version=` lines, reset `version=1.0.0-SNAPSHOT` |
| `.github/workflows/*.yml` | `hana-connector-group: <area>`, empty the `options:` lists |
| `.github/CODEOWNERS` | keep as in the reference unless told otherwise |
| `build-config/resources/Ballerina.toml` | `repository` URL and the area keywords (for example `"Finance", "FI"`) |
| `build-config/resources/README.md` | the overview sentence's area, and every `module-ballerinax-sap.s4hana.qm` image URL |
| `README.md` | title, badges, overview, empty package list and build table (packages get added by `register_package.py`) |
| `changelog.md`, `examples/README.md` | rewrite for the new area; no examples until one is written |

`grep -rn "qm\|Quality" --exclude-dir=.git .` afterwards should only hit things you meant to keep.

## 4. Seed the first package

`register_package.py` copies a sibling package's `build.gradle` and needs at least one
registered package, so for the very first package:

1. Copy `ballerina/api_inspectionmethod_srv/build.gradle` from the reference into
   `ballerina/<module>/`, replace the module name and description.
2. Add its `include`/`projectDir` lines, `gradle.properties` version, `ballerina/build.gradle`
   `dependsOn`, workflow option and README rows by hand (same shape as the reference).
3. Every later package can go through `register_package.py`.
