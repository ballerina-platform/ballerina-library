# Stage 02 — Consult the Reachability-Metadata Repository

Look up published, vetted native-image metadata for the library's third-party Java
dependencies in `oracle/graalvm-reachability-metadata` **before** resorting to the
tracing agent. Full background: `references/reachability-metadata-repo.md`.

**Skip this stage** if `THIRD_PARTY_DEPS` is empty.

---

## Step 1: Build the deps file

Write `THIRD_PARTY_DEPS` to a JSON file (list of `{groupId, artifactId, version}`),
e.g. `deps.json` in `<BALLERINA_DIR>`. Use the Write tool.

---

## Step 2: Look up published metadata

```bash
<PYTHON_CMD> <skill-root>/scripts/lookup_reachability_metadata.py --deps-json "<deps.json>"
```

Read the JSON result. For each dependency, note `has_metadata`, `metadata_version`,
and `version_tested`. Present a short table to the user:

```
Dependency                                   Metadata   Version match
io.example:foo-native  1.2.3                 ✓          exact
com.bar:baz            4.5.6                 ✓          latest (4.5.0) — confirm
com.qux:quux           0.1.0                 ✗          (will trace instead)
```

- **Network failure / rate limit** (`error` set, `has_metadata: false`) → note it,
  and treat those deps as misses to be traced. Do not fail the run.
- **`version_tested: false`** → flag the version substitution; ask the user to
  confirm for major-version gaps.

---

## Step 3: Fetch matched metadata

For each dependency with `has_metadata: true`:

```bash
<PYTHON_CMD> <skill-root>/scripts/fetch_reachability_metadata.py \
  --group-id "<g>" --artifact-id "<a>" --metadata-version "<v>" \
  --out "<staging-root>/<g>__<a>"
```

Record each staging dir in `REACHABILITY_REPO_HITS`. These feed the packing in
`stages/05-filter-and-pack.md`.

---

## Step 4: Decide whether tracing is still needed

- If every dependency matched AND stage 01 had no other missing-metadata signals
  (e.g. from the library's own code) → tracing may be unnecessary. You can go
  straight to `stages/05-filter-and-pack.md` to pack the repo-sourced metadata,
  then validate.
- Otherwise → proceed to `stages/03-trace-jar.md` (if `HAS_MAIN`/`HAS_SERVICE`)
  and/or `stages/04-trace-tests.md` (if `HAS_TESTS`) to cover the gaps.

If `INTERACTIVE_MODE`, confirm the coverage decision before proceeding.
