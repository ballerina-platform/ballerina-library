# Stage 05 — Filter and Pack Native-Image Config

Merge repo-sourced metadata (stage 02) with filtered tracing output (stages 03/04) and pack it into the module so it ships with the library. Full procedure: `references/pack-and-mark.md`.

**Skip this stage** if stages 02/03/04 produced nothing worth keeping.

---

## Step 1: Confirm coordinates and native module

You have `GROUP_ID`, `ARTIFACT_ID`, `HAS_NATIVE_MODULE`, `NATIVE_DIR`, `META_INF_DIR` from setup. If they are stale, re-run `detect_package_coordinates.py`.

If `HAS_NATIVE_MODULE` is false, scaffold a resources-only module:

```bash
<PYTHON_CMD> <skill-root>/scripts/scaffold_native_module.py \
  --native-dir "<NATIVE_DIR>" --group-id "<GROUP_ID>" --artifact-id "<ARTIFACT_ID>"
```

---

## Step 2: Filter tracing output (skip if only repo-sourced metadata)

Decide `KEEP_PACKAGE_PREFIXES` — the library's own Java package(s) plus the third-party dependency packages that need metadata (judgment call). Then:

```bash
<PYTHON_CMD> <skill-root>/scripts/filter_trace_configs.py \
  --config-dir "<CONFIG_DIR>" --out "<filtered-dir>" \
  --keep-prefixes "<KEEP_PACKAGE_PREFIXES>"
```

Review the kept/dropped report with the user. Over-packing bloats the binary; under-packing reintroduces runtime errors. Resource/bundle globs pass through unfiltered — inspect them. Prefer conditional (`typeReached`) entries (`references/reachability-metadata.md`).

---

## Step 3: Pack

Pack repo-sourced metadata (each `REACHABILITY_REPO_HITS` staging dir) and the filtered tracing output, merging same-named files:

```bash
# per repo hit
<PYTHON_CMD> <skill-root>/scripts/pack_native_configs.py \
  --filtered-dir "<staging-dir>" --native-dir "<NATIVE_DIR>" \
  --group-id "<GROUP_ID>" --artifact-id "<ARTIFACT_ID>" --merge

# filtered tracing output
<PYTHON_CMD> <skill-root>/scripts/pack_native_configs.py \
  --filtered-dir "<filtered-dir>" --native-dir "<NATIVE_DIR>" \
  --group-id "<GROUP_ID>" --artifact-id "<ARTIFACT_ID>" --merge
```

Files land under `META-INF/native-image/<GROUP_ID>/<ARTIFACT_ID>/`.

---

## Step 4: Build the native config jar (only if a new module was scaffolded)

```bash
<PYTHON_CMD> <skill-root>/scripts/build_native_config_jar.py \
  --resources-dir "<NATIVE_DIR>/src/main/resources" \
  --out "<NATIVE_DIR>/build/libs/<ARTIFACT_ID>-<BAL_PACKAGE_version>.jar"
```

Note this jar path for the dependency wiring in stage 06. If the library already has a native module built by its own build system, rebuild that instead and do not create a hand-made jar.

---

## Step 5: Proceed

Continue to `stages/06-mark-compatible.md`.

If `INTERACTIVE_MODE`, show the packed file list and confirm before proceeding.
